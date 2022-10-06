import Foundation
import AppKit

// Defined in host.h
extension Appearance {
    init(withNSAppearance ns: NSAppearance?) {
        let name = ns?.bestMatch(from: [ NSAppearance.Name.aqua, NSAppearance.Name.darkAqua ])
        self = .light
        if let n = name {
            switch n {
                case .aqua: self = .light
                case .darkAqua: self = .dark
                default: return
            }
        }
    }
}

final class AppearanceObserver: NSObject {
    @objc var application: NSApplication
    var callback: OpaquePointer
    var observation: NSKeyValueObservation?
    init(_ callback: OpaquePointer, _ triggerInitially: Bool) {
        self.application = NSApplication.shared
        self.callback = callback
        super.init()

        if triggerInitially {
            let appearance = Appearance(withNSAppearance: self.application.effectiveAppearance)
                call_boxed_callback(callback, appearance)
        }

        self.observation = observe(
            \.application.effectiveAppearance,
            options: [.old, .new]
        ) { object, change in
            let appearance = Appearance(withNSAppearance: change.newValue)
            call_boxed_callback(callback, appearance)
        }
    }

    func run() -> Void {
        self.application.setActivationPolicy(.prohibited)
        self.application.run()
    }
}

@_cdecl("observer_new")
public func observer_new(_ callback: OpaquePointer, triggerInitially: Bool) -> OpaquePointer {
    let observer = AppearanceObserver(callback, triggerInitially)
    let retained = Unmanaged.passRetained(observer).toOpaque()
    return OpaquePointer(retained)
}

@_cdecl("observer_run")
public func observer_run(_ observer: OpaquePointer) -> Void {
    let observer = Unmanaged<AppearanceObserver>
        .fromOpaque(UnsafeRawPointer(observer))
        // consumes observer
        .takeRetainedValue()
    observer.run()
}

@_cdecl("observer_get_callback")
public func observer_get_callback(_ observer: OpaquePointer) -> OpaquePointer {
    let observer = Unmanaged<AppearanceObserver>
        .fromOpaque(UnsafeRawPointer(observer))
        // "borrowed"
        .takeUnretainedValue()
    return observer.callback
}

// Funny, because the idea is that this thing is never freed. Anyway, good practice.
@_cdecl("observer_free")
public func observer_free(_ observer: OpaquePointer) -> Void {
    let _ = Unmanaged<AppearanceObserver>
        .fromOpaque(UnsafeRawPointer(observer))
        // consumes observer
        .takeRetainedValue()
}

