use serde::Serialize;
use std::{
    ffi::c_void,
    fs::{File, OpenOptions},
    io::{self, Write},
    sync::{Mutex, OnceLock},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

#[link(name = "user32")]
extern "system" {
    fn GetForegroundWindow() -> *mut c_void;
    fn GetWindowThreadProcessId(window: *mut c_void, process: *mut u32) -> u32;
    fn GetAsyncKeyState(key: i32) -> i16;
}

#[link(name = "kernel32")]
extern "system" {
    fn GetModuleHandleA(name: *const u8) -> *const u8;
    fn GetProcAddress(module: *const u8, symbol: *const u8) -> *const u8;
}

const SIGNALS: [&str; 17] = [
    "world_gui",
    "steam_overlay",
    "connected",
    "host",
    "gm_rmb",
    "gm_rmb_pressed",
    "gm_rmb_released",
    "alt_use",
    "interact_pressed",
    "menu_rmb_pressed",
    "can_use_actions",
    "storage_search",
    "storage_input_lease",
    "storage_window",
    "can_move",
    "storage_draw_guard",
    "menu_rmb",
];
const SIGNAL_MASK: u32 = (1 << SIGNALS.len()) - 1;
const MAX_RECORDS: u32 = 12_000;
const HEARTBEAT: Duration = Duration::from_secs(2);
const FRAME_GAP: Duration = Duration::from_millis(250);
const STEAM_OVERLAY: u32 = 1 << 1;

// The installed Steamworks extension stores a numeric or bool result in the
// YYC RValue. Its zero-argument getter only dereferences the result parameter.
#[repr(C)]
struct RValue {
    value: f64,
    flags: u32,
    kind: u32,
}

type OverlayGetter = unsafe extern "C" fn(*mut RValue, *mut c_void, *mut c_void, i32, *mut RValue);

struct SteamOverlay {
    getter: OverlayGetter,
    module_base: usize,
}

static OVERLAY: OnceLock<Option<SteamOverlay>> = OnceLock::new();

fn resolve_steam_overlay() -> Option<SteamOverlay> {
    const GETTER_RVA: usize = 0x4cb0;
    const GETTER_CODE: &[u8] = b"\x40\x53\x48\x83\xec\x20\x80\x3d\x07\x65\x07\x00\x00\x48\x8b\xd9\x75\x14\x0f\x57\xc0\xc7\x41\x0c\x00\x00\x00\x00\xf2\x0f\x11\x01\x48\x83\xc4\x20\x5b\xc3\xe8\x75\xfd\xff\xff\xc7\x43\x0c\x0d\x00\x00\x00\x0f\xb6\x40\x40\x66\x0f\x6e\xc0\xf3\x0f\xe6\xc0\xf2\x0f\x11\x03\x48\x83\xc4\x20\x5b\xc3";
    const STATE_CODE: &[u8] =
        b"\x48\x83\xec\x28\x48\x8b\x05\x5d\x67\x07\x00\x48\x85\xc0\x0f\x85\xa8\x00\x00\x00";
    unsafe {
        let module = GetModuleHandleA(c"Steamworks_x64.dll".as_ptr().cast());
        if module.is_null() {
            return None;
        }
        let symbol = c"?steam_is_overlay_activated@@YAXAEAURValue@@PEAVCInstance@@1HPEAU1@@Z";
        let address = GetProcAddress(module, symbol.as_ptr().cast());
        if address as usize != module as usize + GETTER_RVA
            || std::slice::from_raw_parts(address, GETTER_CODE.len()) != GETTER_CODE
            || std::slice::from_raw_parts(module.add(0x4a50), STATE_CODE.len()) != STATE_CODE
        {
            return None;
        }
        Some(SteamOverlay {
            getter: std::mem::transmute::<*const u8, OverlayGetter>(address),
            module_base: module as usize,
        })
    }
}

fn read_steam_overlay() -> Option<bool> {
    let steam = OVERLAY.get_or_init(resolve_steam_overlay).as_ref()?;
    unsafe {
        // The extension lazily allocates its callback registry if null. Wait
        // until the game itself initializes it before calling the getter.
        if (steam.module_base as *const u8).add(0x7b1c4).read() == 0
            || (steam.module_base as *const usize).add(0x7b1b8 / 8).read() == 0
        {
            return None;
        }
        let mut result = RValue {
            value: 0.0,
            flags: 0,
            kind: 5,
        };
        (steam.getter)(
            &mut result,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            0,
            std::ptr::null_mut(),
        );
        match (result.kind, result.value) {
            (0 | 13, 0.0) => Some(false),
            (0 | 13, 1.0) => Some(true),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, PartialEq)]
struct Sample {
    known: u32,
    signals: u32,
    input_mode: Option<i32>,
    player_instances: u32,
    foreground: bool,
    windows_rmb: Option<bool>,
}

impl Sample {
    fn signal(self, index: usize) -> Option<bool> {
        let flag = 1 << index;
        (self.known & flag != 0).then_some(self.signals & flag != 0)
    }
}

#[derive(Serialize)]
struct Record<'a> {
    unix_ms: u128,
    elapsed_ms: u128,
    frame_gap_ms: u128,
    input_mode: Option<i32>,
    player_instances: u32,
    foreground: bool,
    windows_rmb: Option<bool>,
    signals: std::collections::BTreeMap<&'a str, Option<bool>>,
}

struct Trace {
    file: File,
    start: Instant,
    previous: Instant,
    last_write: Instant,
    last_sample: Option<Sample>,
    records: u32,
}

impl Trace {
    fn open(now: Instant) -> io::Result<Self> {
        let local_app_data = std::env::var_os("LOCALAPPDATA")
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "LOCALAPPDATA unavailable"))?;
        let filename = format!(
            "chest-network-input-{}-{}.jsonl",
            std::process::id(),
            unix_ms()
        );
        let path = std::path::PathBuf::from(local_app_data)
            .join("Tinkerlands")
            .join(filename);
        let file = OpenOptions::new().create_new(true).write(true).open(path)?;
        Ok(Self {
            file,
            start: now,
            previous: now,
            last_write: now,
            last_sample: None,
            records: 0,
        })
    }

    fn observe(&mut self, now: Instant, sample: Sample) -> io::Result<()> {
        let gap = now.duration_since(self.previous);
        self.previous = now;
        if self.records >= MAX_RECORDS
            || !should_record(
                self.last_sample,
                sample,
                now.duration_since(self.last_write),
                gap,
            )
        {
            return Ok(());
        }
        let signals = SIGNALS
            .iter()
            .enumerate()
            .map(|(index, name)| (*name, sample.signal(index)))
            .collect();
        let record = Record {
            unix_ms: unix_ms(),
            elapsed_ms: now.duration_since(self.start).as_millis(),
            frame_gap_ms: gap.as_millis(),
            input_mode: sample.input_mode,
            player_instances: sample.player_instances,
            foreground: sample.foreground,
            windows_rmb: sample.windows_rmb,
            signals,
        };
        let mut line = serde_json::to_vec(&record)?;
        line.push(b'\n');
        self.file.write_all(&line)?;
        self.last_sample = Some(sample);
        self.last_write = now;
        self.records += 1;
        Ok(())
    }
}

fn should_record(last: Option<Sample>, next: Sample, since_write: Duration, gap: Duration) -> bool {
    last != Some(next) || since_write >= HEARTBEAT || gap >= FRAME_GAP
}

fn unix_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}

fn read_windows_input() -> (bool, Option<bool>) {
    let mut foreground_process = 0;
    unsafe {
        let window = GetForegroundWindow();
        if !window.is_null() {
            GetWindowThreadProcessId(window, &mut foreground_process);
        }
        if foreground_process == std::process::id() {
            // The high bit is the current physical right button state (VK_RBUTTON).
            return (true, Some(GetAsyncKeyState(0x02) < 0));
        }
    }
    (false, None)
}

static TRACE: Mutex<Option<Trace>> = Mutex::new(None);

#[no_mangle]
pub extern "C" fn TCS_ObserveInput(
    known: f64,
    signals: f64,
    input_mode: f64,
    player_instances: f64,
) -> f64 {
    if !unsafe { super::allowed() } {
        return -1.0;
    }
    if !(0.0..=f64::from(SIGNAL_MASK)).contains(&known)
        || known.fract() != 0.0
        || !(0.0..=known).contains(&signals)
        || signals.fract() != 0.0
        || signals as u32 & !(known as u32) != 0
        || !(-1000.0..=1000.0).contains(&input_mode)
        || input_mode.fract() != 0.0
        || !(0.0..=10_000.0).contains(&player_instances)
        || player_instances.fract() != 0.0
    {
        return -2.0;
    }
    let Ok(mut trace) = TRACE.try_lock() else {
        return -3.0;
    };
    let now = Instant::now();
    let (foreground, windows_rmb) = read_windows_input();
    let mut sample = Sample {
        known: known as u32,
        signals: signals as u32,
        input_mode: (input_mode != -1000.0).then_some(input_mode as i32),
        player_instances: player_instances as u32,
        foreground,
        windows_rmb,
    };
    if let Some(active) = read_steam_overlay() {
        sample.known |= STEAM_OVERLAY;
        if active {
            sample.signals |= STEAM_OVERLAY;
        }
    }
    let result = (|| {
        if trace.is_none() {
            *trace = Some(Trace::open(now)?);
        }
        trace.as_mut().unwrap().observe(now, sample)
    })();
    if result.is_ok() {
        1.0
    } else {
        -4.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn records_edges_missing_signals_and_frame_gaps_without_idle_spam() {
        let sample = Sample {
            known: 1,
            signals: 0,
            input_mode: None,
            player_instances: 0,
            foreground: true,
            windows_rmb: Some(false),
        };
        let short = Duration::from_millis(16);
        assert!(should_record(None, sample, short, short));
        assert!(!should_record(Some(sample), sample, short, short));
        assert!(should_record(Some(sample), sample, HEARTBEAT, short));
        assert!(should_record(Some(sample), sample, short, FRAME_GAP));
        assert!(should_record(
            Some(sample),
            Sample {
                windows_rmb: Some(true),
                ..sample
            },
            short,
            short
        ));
        assert_eq!(sample.signal(0), Some(false));
        assert_eq!(sample.signal(1), None);
    }
}
