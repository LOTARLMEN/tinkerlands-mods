//! Incremental migration: remainder selection and transfer guards live here.
//! The ModExt adapter only observes the engine and invokes its stock move.
#![allow(non_snake_case)]
mod input_trace;
mod slot_hit;
use serde::Deserialize;
use std::{ffi::{c_char,c_void,CStr},ptr,sync::{Mutex,atomic::{AtomicU32,Ordering}}};

#[link(name="kernel32")]
extern "system" {
    fn GetModuleFileNameW(module:*mut c_void,out:*mut u16,size:u32)->u32;
    fn GetCurrentThreadId()->u32;
    fn GetModuleHandleW(name:*const u16)->*mut c_void;
    fn DisableThreadLibraryCalls(module:*mut c_void)->i32;
}
static THREAD:AtomicU32=AtomicU32::new(0);
static CORE:Mutex<Core>=Mutex::new(Core::new());
include!(env!("TINKER_STORAGE_PINS"));
static IMAGE_ALLOWED:AtomicU32=AtomicU32::new(0);

#[derive(Clone,Debug,Deserialize)]
#[serde(deny_unknown_fields)]
struct Slot {
    container:String,
    #[serde(deserialize_with="whole")] x:i32,
    #[serde(deserialize_with="whole")] y:i32,
    item:String,
    #[serde(deserialize_with="whole")] qty:i64,
    #[serde(deserialize_with="whole")] id:i64,
    #[serde(deserialize_with="binary")] favorite:bool,
}
// GameMaker JSON writes integral reals as 7.0. Accept these without truncating
// fractional, nonfinite or inexact large quantities at the language boundary.
fn whole<'de,D:serde::Deserializer<'de>,T:TryFrom<i64>>(d:D)->Result<T,D::Error> {
    let n=f64::deserialize(d)?;
    if !n.is_finite() || n.fract()!=0.0 || n.abs()>9_007_199_254_740_991.0 {
        return Err(serde::de::Error::custom("expected exact integer"));
    }
    T::try_from(n as i64).map_err(|_|serde::de::Error::custom("integer out of range"))
}
// The VM serializes computed logical expressions as 0.0/1.0, even when
// literal true/false serialize as JSON booleans. Reject all other values.
fn binary<'de,D:serde::Deserializer<'de>>(d:D)->Result<bool,D::Error> {
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum Binary {Bool(bool),Number(f64)}
    match Binary::deserialize(d)? {
        Binary::Bool(b)=>Ok(b),
        Binary::Number(0.0)=>Ok(false),
        Binary::Number(1.0)=>Ok(true),
        _=>Err(serde::de::Error::custom("expected boolean or binary real")),
    }
}
impl Slot {
    fn same_address(&self,b:&Self)->bool {self.container==b.container && self.x==b.x && self.y==b.y}
    fn same_item(&self,b:&Self)->bool {self.same_address(b) && self.item==b.item && self.id==b.id}
}
#[derive(Deserialize)]
#[serde(tag="op",rename_all="snake_case",deny_unknown_fields)]
enum Command {
    Capture {slots:Vec<Slot>},
    Select {#[serde(deserialize_with="whole")] token:u32,hover:String,live:Vec<Slot>},
    CheckMove {source:Slot,expected:Slot,destination:String,
        #[serde(deserialize_with="whole")] width:i32,
        #[serde(deserialize_with="whole")] height:i32,
        source_exists:bool,destination_exists:bool},
    Verify {
        #[serde(deserialize_with="whole")] quantity:i64,
        #[serde(deserialize_with="whole")] source_before:i64,
        #[serde(deserialize_with="whole")] source_after:i64,
        #[serde(deserialize_with="whole")] destination_before:i64,
        #[serde(deserialize_with="whole")] destination_after:i64,
    },
    VisibleEmptySlots {
        #[serde(deserialize_with="whole")] occupied: u32,
        #[serde(deserialize_with="whole")] available: u32,
    },
    Reset,
}
struct Core {serial:u32,captured:Option<(u32,Vec<Slot>)>}

// Linked only into the offline test executable, never an exported DLL API.
#[cfg(feature="test-harness")]
pub fn replay(text:&str)->Vec<f64> {
    let mut core=Core::new();
    text.lines().map(|line|match serde_json::from_str(line) {
        Ok(c)=>core.execute(c).unwrap_or(-5.0),
        Err(_)=>{core.captured=None;-4.0},
    }).collect()
}
impl Core {
    const fn new()->Self {Self{serial:0,captured:None}}
    fn execute(&mut self,c:Command)->Result<f64,&'static str> {
        match c {
            Command::Capture{slots}=>{
                self.captured=None;
                if slots.len()>4096 || slots.iter().any(|s|s.qty<0 || s.x<0 || s.y<0) {return Err("invalid_snapshot");}
                self.serial=self.serial.checked_add(1).filter(|n|*n<=0x7fff_ffff).ok_or("token_exhausted")?;
                self.captured=Some((self.serial,slots));Ok(self.serial as f64)
            },
            Command::Select{token,hover,live}=>{
                // Consume before checking: even a rejected or malformed live
                // observation can never reuse an old click.
                let (saved,before)=self.captured.take().ok_or("missing_snapshot")?;
                if token!=saved || live.len()!=before.len() {return Err("stale_snapshot");}
                let mut found=None;
                for (i,(old,now)) in before.iter().zip(live.iter()).enumerate() {
                    if old.item!=hover || old.qty<=0 {continue;}
                    if found.is_some() {return Err("ambiguous_hover");}
                    if !old.same_item(now) || old.favorite || now.favorite || now.qty<=0 || now.qty>old.qty {return Ok(0.0);}
                    found=Some(i);
                }
                Ok(found.map_or(0.0,|i|(i+1) as f64))
            },
            Command::CheckMove{source,expected,destination,width,height,source_exists,destination_exists}=>{
                if !source_exists || !destination_exists {return Ok(-10.0);}
                if source.container==destination {return Ok(-11.0);}
                if source.x<0 || source.y<0 || source.x>=width || source.y>=height {return Ok(-12.0);}
                if !source.same_item(&expected) || source.qty<=0 || source.qty!=expected.qty {return Ok(-13.0);}
                Ok(1.0)
            },
            Command::Verify{quantity,source_before,source_after,destination_before,destination_after}=>{
                if quantity<=0 || [source_before,source_after,destination_before,destination_after].iter().any(|n|*n<0) {return Err("invalid_quantity");}
                let moved=source_before.checked_sub(source_after).ok_or("quantity_overflow")?;
                let received=destination_after.checked_sub(destination_before).ok_or("quantity_overflow")?;
                if moved<0 || moved>quantity || moved!=received {return Err("conservation_failure");}
                Ok(moved as f64)
            },
            Command::VisibleEmptySlots { occupied, available } => {
                // The native grid is five columns wide with six visible rows.
                // A complete final row still needs a place to drop an item.
                let padding = if occupied < 30 { 30 - occupied } else { 5 - occupied % 5 };
                Ok(f64::from(available.min(padding)))
            },
            Command::Reset=>{self.captured=None;Ok(1.0)},
        }
    }
}

fn game_filename(path:&str)->bool {
    path.rsplit(['\\','/']).next().is_some_and(|s|s.eq_ignore_ascii_case("tinkerlands.exe"))
}
unsafe fn allowed()->bool {
    if THREAD.load(Ordering::Acquire)!=GetCurrentThreadId(){return false;}
    match IMAGE_ALLOWED.load(Ordering::Acquire) {1=>return true,2=>return false,_=>{}}
    let mut path=[0u16;1024];let n=GetModuleFileNameW(ptr::null_mut(),path.as_mut_ptr(),1024) as usize;
    let valid=n>0 && n<path.len() && game_filename(&String::from_utf16_lossy(&path[..n])) && image_matches();
    IMAGE_ALLOWED.store(if valid{1}else{2},Ordering::Release);valid
}
unsafe fn image_matches()->bool {
    let base=GetModuleHandleW(ptr::null()) as usize;
    if base==0 || ptr::read_unaligned(base as *const u16)!=0x5a4d{return false;}
    let offset=ptr::read_unaligned((base+0x3c) as *const u32) as usize;
    if !(64..4096).contains(&offset){return false;}
    let pe=base+offset;
    ptr::read_unaligned(pe as *const u32)==0x4550 &&
        ptr::read_unaligned((pe+4) as *const u16)==0x8664 &&
        ptr::read_unaligned((pe+8) as *const u32)==GAME_TIMESTAMP &&
        ptr::read_unaligned((pe+0x50) as *const u32)==GAME_IMAGE_SIZE &&
        GAME_ENTRY_PIN.iter().enumerate().all(|(i,b)|ptr::read((base+GAME_ENTRY_RVA+i) as *const u8)==*b)
}
#[no_mangle]
pub unsafe extern "system" fn DllMain(module:*mut c_void,reason:u32,_:*mut c_void)->i32 {
    if reason==1 {THREAD.store(GetCurrentThreadId(),Ordering::Release);DisableThreadLibraryCalls(module);}1
}
#[no_mangle]
pub extern "C" fn TCS_ABI()->f64 {65536.0}
#[no_mangle]
pub unsafe extern "C" fn TCS_Command(text:*const c_char)->f64 {
    // Refuse external hosts/threads before dereferencing their request pointer.
    if !allowed(){return -1.0;}
    let result=std::panic::catch_unwind(||{
        if text.is_null(){return -2.0;}
        // GameMaker supplies a zero-terminated string with this external ABI.
        let bytes=CStr::from_ptr(text).to_bytes();
        if bytes.len()>2_000_000{return -2.0;}
        let Ok(mut core)=CORE.try_lock() else{return -3.0;};
        let command=match serde_json::from_slice(bytes){Ok(c)=>c,Err(_)=>{core.captured=None;return -4.0;}};
        core.execute(command).unwrap_or(-5.0)
    });
    result.unwrap_or(-100.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn process_name_is_portable_but_exact(){
        assert!(game_filename("D:\\SteamLibrary\\Tinkerlands\\tinkerlands.exe"));
        assert!(game_filename("E:/Games/Tinkerlands/TINKERLANDS.EXE"));
        assert!(!game_filename("E:/Games/not-tinkerlands.exe"));
        assert!(!game_filename("C:/Python/python.exe"));
    }
    fn slot(qty:i64)->Slot {Slot{container:"inventory".into(),x:0,y:0,item:"ds_map(101)".into(),qty,id:3,favorite:false}}
    fn select(old:Slot,now:Slot)->f64 {
        let mut c=Core::new();let token=c.execute(Command::Capture{slots:vec![old]}).unwrap() as u32;
        c.execute(Command::Select{token,hover:"ds_map(101)".into(),live:vec![now]}).unwrap()
    }
    #[test] fn full_and_partial_remainders(){assert_eq!(select(slot(7),slot(7)),1.0);assert_eq!(select(slot(7),slot(3)),1.0);}
    #[test] fn snapshots_are_owned_and_quantity_cannot_alias_engine(){let mut a=slot(7);let before=a.clone();a.qty=3;assert_eq!(select(before,a),1.0);}
    #[test] fn refuses_full_transfer_growth_replacement_and_favorites(){
        for mut s in [slot(0),slot(8),slot(3),slot(3),slot(3)] {
            if s.qty==3 {s.item="ds_map(102)".into();}
            assert_eq!(select(slot(7),s),0.0);
        }
        let mut a=slot(7);a.favorite=true;assert_eq!(select(a,slot(3)),0.0);
        let mut b=slot(3);b.favorite=true;assert_eq!(select(slot(7),b),0.0);
        let mut b=slot(3);b.id=4;assert_eq!(select(slot(7),b),0.0);
    }
    #[test] fn stale_token_and_replay_cannot_select(){
        let mut c=Core::new();let token=c.execute(Command::Capture{slots:vec![slot(7)]}).unwrap() as u32;
        assert!(c.execute(Command::Select{token:token+1,hover:slot(7).item,live:vec![slot(3)]}).is_err());
        assert!(c.execute(Command::Select{token,hover:slot(7).item,live:vec![slot(3)]}).is_err());
    }
    #[test] fn refuse_moved_source_and_ambiguous_hover(){
        let mut b=slot(3);b.y=1;assert_eq!(select(slot(7),b),0.0);
        let mut c=Core::new();let token=c.execute(Command::Capture{slots:vec![slot(7),slot(7)]}).unwrap() as u32;
        assert!(c.execute(Command::Select{token,hover:slot(7).item,live:vec![slot(3),slot(3)]}).is_err());
    }
    #[test] fn conservation_including_full_refusal(){
        for moved in 0..=7 {let mut c=Core::new();assert_eq!(c.execute(Command::Verify{quantity:7,source_before:7,source_after:7-moved,destination_before:995,destination_after:995+moved}),Ok(moved as f64));}
        let mut c=Core::new();assert!(c.execute(Command::Verify{quantity:7,source_before:7,source_after:3,destination_before:995,destination_after:998}).is_err());
    }
    #[test] fn move_guards_reject_new_item_and_stale_quantity(){
        let check=|source:Slot|Core::new().execute(Command::CheckMove{source,expected:slot(7),destination:"chest".into(),width:1,height:1,source_exists:true,destination_exists:true}).unwrap();
        assert_eq!(check(slot(7)),1.0);assert_eq!(check(slot(3)),-13.0);let mut s=slot(7);s.item="replacement".into();assert_eq!(check(s),-13.0);
    }
    #[test] fn gamemaker_real_json_is_accepted_but_fractional_quantities_are_rejected(){
        let s=r#"{"container":"ref ds_map 1","x":0.0,"y":0.0,"item":"ref ds_map 2","qty":7.0,"id":3.0,"favorite":false}"#;
        assert_eq!(serde_json::from_str::<Slot>(s).unwrap().qty,7);
        assert!(serde_json::from_str::<Slot>(&s.replace("7.0","7.5")).is_err());
        assert!(serde_json::from_str::<Slot>(&s.replace("7.0","9007199254740992")).is_err());
    }
    #[test] fn real_gamemaker_capture_accepts_binary_real_favorite_only(){
        let observed=r#"{"op":"capture","slots":[{"id":2.0,"x":0.0,"y":0.0,"favorite":0.0,"item":"ref ds_map 132","container":"ref ds_map 129","qty":7.0}]}"#;
        let mut c=Core::new();
        assert_eq!(c.execute(serde_json::from_str(observed).unwrap()),Ok(1.0));
        for (encoded,expected) in [("0.0",false),("1.0",true),("false",false),("true",true)] {
            let command=serde_json::from_str::<Command>(&observed.replace("\"favorite\":0.0",&format!("\"favorite\":{encoded}"))).unwrap();
            let Command::Capture{slots}=command else {panic!("expected capture")};
            assert_eq!(slots[0].favorite,expected);
        }
        for bad in ["0.5","2.0","-1.0","null","\"0\""] {
            assert!(serde_json::from_str::<Command>(&observed.replace("\"favorite\":0.0",&format!("\"favorite\":{bad}"))).is_err());
        }
    }
}
