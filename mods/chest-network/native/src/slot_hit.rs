//! Observe the stock GUI's live inventory slot addresses during one click.
use std::{
    ffi::{c_char, c_void, CStr},
    ptr,
    sync::{
        atomic::{AtomicBool, AtomicUsize, Ordering},
        Mutex,
    },
};

type Handle = *mut c_void;
type Script =
    unsafe extern "system" fn(Handle, Handle, *mut Value, i32, *const *const Value) -> *mut Value;

#[repr(C)]
struct Value {
    data: u64,
    flags: u32,
    kind: u32,
}

impl Value {
    fn number(&self) -> Option<f64> {
        match self.kind & 0xff_ffff {
            0 | 13 => Some(f64::from_bits(self.data)),
            7 => Some((self.data as i32) as f64),
            10 => Some((self.data as i64) as f64),
            _ => None,
        }
    }

    fn container_id(&self) -> Option<u32> {
        if self.kind & 0xff_ffff == 15 {
            return Some(self.data as u32);
        }
        let value = self.number()?;
        ((0.0..=f64::from(u32::MAX)).contains(&value) && value.fract() == 0.0)
            .then_some(value as u32)
    }
}

#[link(name = "kernel32")]
extern "system" {
    fn IsProcessorFeaturePresent(feature: u32) -> i32;
    fn VirtualAlloc(address: Handle, size: usize, allocation: u32, protection: u32) -> Handle;
    fn VirtualFree(address: Handle, size: usize, free_type: u32) -> i32;
    fn VirtualProtect(address: Handle, size: usize, protection: u32, old: *mut u32) -> i32;
    fn FlushInstructionCache(process: Handle, address: *const c_void, size: usize) -> i32;
    fn GetModuleHandleExW(flags: u32, address: *const u16, module: *mut Handle) -> i32;
}

const SLOT_RVA: usize = 0x13664a0;
// Four complete, position-independent stores after `mov rax, rsp`.
const STOCK_PREFIX: [u8; 19] = [
    0x48, 0x8b, 0xc4, 0x48, 0x89, 0x58, 0x20, 0x4c, 0x89, 0x40, 0x18, 0x48, 0x89, 0x50, 0x10, 0x48,
    0x89, 0x48, 0x08,
];
const STRIDE: u32 = 256;
static TRAMPOLINE: AtomicUsize = AtomicUsize::new(0);
static INSTALLED: AtomicBool = AtomicBool::new(false);
static ARMED: AtomicBool = AtomicBool::new(false);
static CAPTURE: Mutex<Option<Capture>> = Mutex::new(None);

struct Capture {
    container: u32,
    x: f64,
    y: f64,
    half: f64,
    slot: u32,
    ambiguous: bool,
}

impl Capture {
    fn add(&mut self, x: f64, y: f64, column: f64, row: f64) -> bool {
        if (self.x - x).abs() > self.half
            || (self.y - y).abs() > self.half
            || ![column, row]
                .iter()
                .all(|n| (0.0..f64::from(STRIDE)).contains(n) && n.fract() == 0.0)
            || !x.is_finite()
            || !y.is_finite()
        {
            return false;
        }
        let slot = 1 + column as u32 + row as u32 * STRIDE;
        if self.slot == 0 || self.slot == slot {
            self.slot = slot;
        } else {
            self.ambiguous = true;
        }
        true
    }
}

unsafe fn observe(argc: i32, args: *const *const Value) -> bool {
    if argc != 14 || args.is_null() {
        return false;
    }
    let Ok(mut lock) = CAPTURE.try_lock() else {
        return false;
    };
    let Some(capture) = lock.as_mut() else {
        return false;
    };
    let get = |index| (*args.add(index)).as_ref();
    if get(0).and_then(Value::container_id) != Some(capture.container) {
        return false;
    }
    // The ninth stock argument disables hit-testing for this slot.
    if get(8).and_then(Value::number).is_some_and(|n| n != 0.0) {
        return false;
    }
    if let [Some(column), Some(row), Some(x), Some(y)] =
        [1, 2, 4, 5].map(|i| get(i).and_then(Value::number))
    {
        return capture.add(x, y, column, row);
    }
    false
}

unsafe extern "system" fn slot(
    self_: Handle,
    other: Handle,
    result: *mut Value,
    argc: i32,
    args: *const *const Value,
) -> *mut Value {
    let stock: Script = std::mem::transmute(TRAMPOLINE.load(Ordering::Acquire));
    if ARMED.load(Ordering::Relaxed)
        && super::THREAD.load(Ordering::Relaxed) == super::GetCurrentThreadId()
        && observe(argc, args)
    {
        // This exact Shift gesture belongs to the network. Suppress the stock
        // interaction with the selected inventory slot and keep stock drawing.
        let mut slot_args = [ptr::null(); 14];
        ptr::copy_nonoverlapping(args, slot_args.as_mut_ptr(), slot_args.len());
        let mut blocked = Value {
            data: 1.0f64.to_bits(),
            flags: 0,
            kind: 13,
        };
        slot_args[8] = &mut blocked;
        return stock(self_, other, result, argc, slot_args.as_ptr());
    }
    stock(self_, other, result, argc, args)
}

fn jump(destination: usize) -> [u8; 16] {
    let mut bytes = [0x90; 16];
    bytes[..6].copy_from_slice(&[0xff, 0x25, 0, 0, 0, 0]);
    bytes[6..14].copy_from_slice(&destination.to_le_bytes());
    bytes
}

// Use the same aligned atomic exchange as the engine optimizer. The copied
// instructions run on the original stack and then continue at the stock body.
unsafe fn exchange_code(address: usize, old: [u8; 16], new: [u8; 16]) -> bool {
    let lo = u64::from_le_bytes(old[..8].try_into().unwrap());
    let hi = u64::from_le_bytes(old[8..].try_into().unwrap());
    let new_lo = u64::from_le_bytes(new[..8].try_into().unwrap());
    let new_hi = u64::from_le_bytes(new[8..].try_into().unwrap());
    let ok: u8;
    core::arch::asm!("push rbx", "mov rbx, r9", "lock cmpxchg16b [r8]", "sete r10b", "pop rbx",
        in("r8") address, in("r9") new_lo, in("rcx") new_hi,
        inout("rax") lo => _, inout("rdx") hi => _, lateout("r10b") ok);
    ok != 0
}

unsafe fn install() -> bool {
    let site = super::GetModuleHandleW(ptr::null()) as usize + SLOT_RVA;
    if IsProcessorFeaturePresent(14) == 0
        || std::slice::from_raw_parts(site as *const u8, STOCK_PREFIX.len()) != STOCK_PREFIX
    {
        return false;
    }
    let page = VirtualAlloc(ptr::null_mut(), 4096, 0x3000, 4);
    if page.is_null() {
        return false;
    }
    let tail = jump(site + STOCK_PREFIX.len());
    ptr::copy_nonoverlapping(STOCK_PREFIX.as_ptr(), page.cast::<u8>(), STOCK_PREFIX.len());
    ptr::copy_nonoverlapping(
        tail.as_ptr(),
        page.cast::<u8>().add(STOCK_PREFIX.len()),
        tail.len(),
    );
    let mut old = 0;
    let process = -1isize as Handle;
    let mut module = ptr::null_mut();
    if VirtualProtect(page, 4096, 0x20, &mut old) == 0
        || FlushInstructionCache(process, page, STOCK_PREFIX.len() + tail.len()) == 0
        || GetModuleHandleExW(5, slot as *const () as *const u16, &mut module) == 0
        || VirtualProtect(site as Handle, 16, 0x40, &mut old) == 0
    {
        VirtualFree(page, 0, 0x8000);
        return false;
    }
    TRAMPOLINE.store(page as usize, Ordering::Release);
    let installed = exchange_code(
        site,
        STOCK_PREFIX[..16].try_into().unwrap(),
        jump(slot as *const () as usize),
    );
    let flushed = FlushInstructionCache(process, site as Handle, 16) != 0;
    let mut ignored = 0;
    let protected = VirtualProtect(site as Handle, 16, old, &mut ignored) != 0;
    if installed {
        // The process owns the executable relay and pinned DLL until exit.
        INSTALLED.store(flushed && protected, Ordering::Release);
    } else {
        TRAMPOLINE.store(0, Ordering::Release);
        VirtualFree(page, 0, 0x8000);
    }
    installed && flushed && protected
}

#[no_mangle]
pub unsafe extern "C" fn TCS_InitInventoryHit() -> f64 {
    if !super::allowed() {
        return -1.0;
    }
    if INSTALLED.load(Ordering::Acquire) || install() {
        1.0
    } else {
        -2.0
    }
}

fn container_id(text: &str) -> Option<u32> {
    text.strip_prefix("ref ds_map ")
        .unwrap_or(text)
        .parse()
        .ok()
}

#[no_mangle]
pub unsafe extern "C" fn TCS_ArmInventoryHit(
    container: *const c_char,
    x: f64,
    y: f64,
    scale: f64,
) -> f64 {
    if !super::allowed() {
        return -1.0;
    }
    if !INSTALLED.load(Ordering::Acquire)
        || container.is_null()
        || !x.is_finite()
        || !y.is_finite()
        || !(0.5..=16.0).contains(&scale)
    {
        return -2.0;
    }
    let Some(id) = CStr::from_ptr(container)
        .to_str()
        .ok()
        .and_then(container_id)
    else {
        return -2.0;
    };
    let Ok(mut capture) = CAPTURE.try_lock() else {
        return -3.0;
    };
    // container_slot tests the rectangle centered at its native draw coordinates,
    // using the stock 21-pixel footprint scaled by GUI_SCALE.
    *capture = Some(Capture {
        container: id,
        x,
        y,
        half: 10.5 * scale,
        slot: 0,
        ambiguous: false,
    });
    ARMED.store(true, Ordering::Release);
    1.0
}

#[no_mangle]
pub unsafe extern "C" fn TCS_TakeInventoryHit() -> f64 {
    if !super::allowed() {
        return -1.0;
    }
    ARMED.store(false, Ordering::Release);
    let Ok(mut capture) = CAPTURE.try_lock() else {
        return -3.0;
    };
    capture
        .take()
        .filter(|hit| !hit.ambiguous)
        .map_or(0.0, |hit| f64::from(hit.slot))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn captures_one_physical_address_and_rejects_conflicting_slots() {
        let mut capture = Capture {
            container: 129,
            x: 100.0,
            y: 22.0,
            half: 10.5,
            slot: 0,
            ambiguous: false,
        };
        capture.add(122.0, 22.0, 4.0, 1.0);
        assert_eq!(capture.slot, 0);
        capture.add(100.0, 22.0, 3.0, 1.0);
        capture.add(100.0, 22.0, 3.0, 1.0);
        assert_eq!(capture.slot, 260);
        assert!(!capture.ambiguous);
        capture.add(100.0, 22.0, 3.0, 2.0);
        assert!(capture.ambiguous);
        assert_eq!(container_id("ref ds_map 129"), Some(129));
    }
}
