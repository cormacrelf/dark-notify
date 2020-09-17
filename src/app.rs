use cocoa::appkit::{NSApp, NSApplication};
use cocoa::base::{id, nil};
use cocoa::foundation::{NSArray, NSAutoreleasePool, NSDictionary, NSString, NSUInteger};
use objc::declare::ClassDecl;
use objc::rc::autoreleasepool;
use objc::rc::{StrongPtr, WeakPtr};
use objc::runtime::{Class, Object, Sel};

use std::{mem, ops::Deref, raw};

bitflags::bitflags! {
    struct NSKeyValueObservingOptions: NSUInteger {
        const NEW = 0x01;
        const OLD = 0x02;
        const INITIAL = 0x04;
        const PRIOR = 0x08;
    }
}

use anyhow::Error;

fn get_callback(self_obj: &Object) -> *mut dyn Fn(id) {
    unsafe {
        let data: *mut libc::c_void = *self_obj.get_ivar("_data");
        let vtable: *mut libc::c_void = *self_obj.get_ivar("_vtable");
        let trait_obj = raw::TraitObject {
            data: data.cast::<()>(),
            vtable: vtable.cast::<()>(),
        };
        let callback: &mut dyn Fn(id) = mem::transmute(trait_obj);
        callback as *mut dyn Fn(id)
    }
}

lazy_static::lazy_static! {
    static ref RUST_KVO_HELPER: &'static Class = {
        let superclass = class!(NSObject);
        let mut decl = ClassDecl::new("RustKVOHelper", superclass).unwrap();

        // Stores a Box<dyn Fn(id)> -> raw::TraitObject.
        decl.add_ivar::<*mut libc::c_void>("_data");
        decl.add_ivar::<*mut libc::c_void>("_vtable");

        // type NSKeyValueChangeKey = id /* NSString */;
        fn emit(callback: &dyn Fn(id), changes: impl NSDictionary) {
            let new_value = unsafe {
                let new_key = StrongPtr::new(NSString::alloc(nil).init_str("new"));
                changes.valueForKey_(*new_key.deref())
            };

            callback(new_value);
        }

        // Add an ObjC method for getting the number
        extern fn observe(
            self_obj: &Object,
            _self_selector: Sel,
            _key_path: id /* NSString */,
            _of_object: id,
            changes: id, /* NSDictionary<NSKeyValueChangeKey, id> */
            _context: *mut libc::c_void,
        ) {
            unsafe {
                let callback = get_callback(self_obj);
                emit(&*callback, changes)
            }
        }
        unsafe {
            decl.add_method(
                sel!(observeValueForKeyPath:ofObject:change:context:),
                observe as extern fn(&Object, Sel, id, id, id, *mut libc::c_void)
            );
        }

        decl.register();
        class!(RustKVOHelper)
    };
}

struct KeyValueObserver {
    observer: StrongPtr,
    observed_object: WeakPtr,
    // NSString
    key_path: id,
}

impl KeyValueObserver {
    fn observe(
        object: id,
        key_path: id, /* NSString */
        options: NSKeyValueObservingOptions,
        closure: impl Fn(id) + 'static,
    ) -> Result<Self, Error> {
        if object == nil {
            return Err(anyhow::anyhow!(
                "KeyValueObserver cannot observe on a nil object"
            ));
        }
        unsafe {
            let boxed = Box::new(closure);
            let callback: *const dyn Fn(*mut Object) = Box::into_raw(boxed);
            let trait_obj: raw::TraitObject = mem::transmute(callback);
            let observer: id = msg_send![*RUST_KVO_HELPER, new];
            (*observer).set_ivar("_data", trait_obj.data.cast::<libc::c_void>());
            (*observer).set_ivar("_vtable", trait_obj.vtable.cast::<libc::c_void>());
            let _: libc::c_void = msg_send![object,
                addObserver: observer
                 forKeyPath: key_path
                    options: options
                    context: nil
            ];
            let observed_object = WeakPtr::new(object);
            Ok(KeyValueObserver {
                observer: StrongPtr::new(observer),
                observed_object,
                key_path,
            })
        }
    }
}

impl Drop for KeyValueObserver {
    fn drop(&mut self) {
        unsafe {
            let observed = self.observed_object.load();
            if observed.is_null() {
                return;
            }
            let observed = *observed.deref();
            let observer = *self.observer.deref();
            let _: libc::c_void =
                msg_send![observed, removeObserver: observer forKeyPath: self.key_path];
            let callback = get_callback(&*observer);
            drop(Box::from_raw(callback));
        }
    }
}

#[link(name = "AppKit", kind = "framework")]
extern "C" {
    static NSAppearanceNameAqua: id;
    static NSAppearanceNameDarkAqua: id;
}

fn is_dark_mode(names: id, appearance: id) -> Appearance {
    unsafe {
        let best_match: id = msg_send![appearance, bestMatchFromAppearancesWithNames: names];
        if best_match == NSAppearanceNameDarkAqua {
            Appearance::Dark
        } else {
            Appearance::Light
        }
    }
}

#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash)]
pub enum Appearance {
    Light,
    Dark,
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

pub fn run(
    trigger_initially: bool,
    switch_callback: impl Fn(Appearance) + 'static,
) -> Result<(), Error> {
    autoreleasepool(|| unsafe {
        let app = NSApp();
        app.setActivationPolicy_(
            cocoa::appkit::NSApplicationActivationPolicy::NSApplicationActivationPolicyProhibited,
        );
        let effectiveAppearance = NSString::alloc(nil).init_str("effectiveAppearance");
        let options = NSKeyValueObservingOptions::NEW;
        let names =
            NSArray::arrayWithObjects(nil, &[NSAppearanceNameAqua, NSAppearanceNameDarkAqua])
                .autorelease();
        let on_change = move |appearance: id| {
            if appearance.is_null() {
                return;
            }
            switch_callback(is_dark_mode(names, appearance))
        };
        if trigger_initially {
            let appearance: id = msg_send![app, effectiveAppearance];
            on_change(appearance);
        }
        let _observer = KeyValueObserver::observe(app, effectiveAppearance, options, on_change)?;
        app.run();
        Ok(())
    })
}
