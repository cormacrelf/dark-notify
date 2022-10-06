use core::ffi;

#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash)]
#[repr(i32)]
#[allow(dead_code)]
pub enum Appearance {
    Light = 0,
    Dark = 1,
}

use std::fmt;
impl fmt::Display for Appearance {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Appearance::Light => write!(f, "light"),
            Appearance::Dark => write!(f, "dark"),
        }
    }
}

extern "C" {
    fn observer_new(callback: *mut ffi::c_void, trigger_initially: bool) -> *mut ffi::c_void;
    fn observer_run(observer: *mut ffi::c_void);
    fn observer_get_callback(observer: *mut ffi::c_void) -> *mut ffi::c_void;
    fn observer_free(observer: *mut ffi::c_void);
}

struct SwiftObserver {
    obj: *mut ffi::c_void,
}

#[no_mangle]
pub unsafe extern "C" fn call_boxed_callback(ptr: *mut ffi::c_void, appearance: Appearance) {
    let callback = ptr.cast::<Box<dyn Fn(Appearance)>>();
    (*callback)(appearance);
}

impl SwiftObserver {
    fn new(switch_callback: impl Fn(Appearance) + 'static, trigger_initially: bool) -> Self {
        let fat_closure: Box<dyn Fn(Appearance)> = Box::new(switch_callback);
        let boxed = Box::new(fat_closure);
        let callback = Box::into_raw(boxed);
        let observer = unsafe {
            let raw = callback.cast::<ffi::c_void>();
            observer_new(raw, trigger_initially)
        };
        SwiftObserver { obj: observer }
    }

    fn run(mut self) {
        unsafe {
            // pull the callback out so we can drop the boxes
            let cb = observer_get_callback(self.obj);
            // this consumes self.obj and frees it.
            observer_run(self.obj);
            // so we zero it out to mark it as freed
            self.obj = core::ptr::null_mut();
            // now we can free our callback
            let callback = cb.cast::<Box<dyn Fn(Appearance)>>();
            drop(Box::from_raw(callback));
        }
    }
}

impl Drop for SwiftObserver {
    fn drop(&mut self) {
        if !self.obj.is_null() {
            unsafe {
                // pull the callback out so we can drop the boxes
                let cb = observer_get_callback(self.obj);
                observer_free(self.obj);
                self.obj = core::ptr::null_mut();
                // now we can free our callback
                let callback = cb.cast::<Box<dyn Fn(Appearance)>>();
                drop(Box::from_raw(callback));
            }
        }
    }
}

pub fn run(trigger_initially: bool, switch_callback: impl Fn(Appearance) + 'static) {
    let observer = SwiftObserver::new(switch_callback, trigger_initially);
    observer.run();
}
