import Foundation
import AppKit
import CoreGraphics
import Carbon
import IOKit.hid

class HotkeyService {
    static let shared = HotkeyService()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hidManager: IOHIDManager?
    
    private var isFnKeyPressed = false
    private var fnKeyCheckTimer: Timer?

    private init() {}

    var isRunning: Bool {
        return eventTap != nil || hidManager != nil
    }

    func start() {
        print("[HotkeyService] 🚀 Starting Fn key detection...")
        
        // Check accessibility permissions
        if !checkAccessibilityPermissions() {
            print("[HotkeyService] ⚠️ Accessibility permissions not granted")
            requestAccessibilityPermissions()
            
            // Show alert to user
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "Corius Voice needs accessibility permissions to detect the Fn key. Please grant permission in System Settings > Privacy & Security > Accessibility."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Cancel")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        
        // Method 1: CGEvent tap for modifier flags
        setupEventTap()
        
        // Method 2: IOKit HID for direct keyboard access
        setupHIDManager()
        
        // Method 3: Polling as last resort
        startFnKeyPolling()
        
        print("[HotkeyService] ✅ Started successfully")
        print("[HotkeyService] 📝 Press and hold Fn key to record")
    }

    func stop() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        
        if let hidManager = hidManager {
            IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        
        fnKeyCheckTimer?.invalidate()
        fnKeyCheckTimer = nil

        eventTap = nil
        runLoopSource = nil
        hidManager = nil

        print("[HotkeyService] Stopped")
    }

    private func checkAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }

    private func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }

    private func setupEventTap() {
        // Listen for flags changed and all key events
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) |
                                     (1 << CGEventType.keyDown.rawValue) |
                                     (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else {
                return Unmanaged.passRetained(event)
            }

            let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
            return service.handleEvent(proxy: proxy, type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: refcon
        ) else {
            print("[HotkeyService] ❌ Failed to create event tap")
            return
        }

        eventTap = tap

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[HotkeyService] ✅ CGEvent tap created")
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if it gets disabled
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            print("[HotkeyService] ⚠️ Event tap disabled, re-enabling...")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        // Handle flags changed (modifier keys)
        if type == .flagsChanged {
            let flags = event.flags
            let fnPressed = flags.contains(.maskSecondaryFn)
            
            // Log all flag changes for debugging
            if fnPressed != isFnKeyPressed {
                print("[HotkeyService] 🔑 Flags: \(flags.rawValue)")
                print("[HotkeyService] 🔑 SecondaryFn flag: \(fnPressed)")
            }

            if fnPressed != isFnKeyPressed {
                isFnKeyPressed = fnPressed
                print("[HotkeyService] 🎤 Fn key \(fnPressed ? "PRESSED ✅" : "RELEASED ⭕️")")
                notifyKeyStateChange(pressed: fnPressed)
            }
        }
        
        // Also check keyDown/keyUp events for Fn key combinations
        if type == .keyDown || type == .keyUp {
            let flags = event.flags
            let fnPressed = flags.contains(.maskSecondaryFn)
            
            if fnPressed != isFnKeyPressed {
                isFnKeyPressed = fnPressed
                print("[HotkeyService] 🎤 Fn key detected via keyEvent: \(fnPressed ? "PRESSED ✅" : "RELEASED ⭕️")")
                notifyKeyStateChange(pressed: fnPressed)
            }
        }

        return Unmanaged.passRetained(event)
    }
    
    private func notifyKeyStateChange(pressed: Bool) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .fnKeyStateChanged,
                object: nil,
                userInfo: ["pressed": pressed]
            )
        }
    }
    
    // MARK: - IOKit HID Manager (Direct keyboard access)
    
    private func setupHIDManager() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        guard let manager = hidManager else {
            print("[HotkeyService] ❌ Failed to create HID manager")
            return
        }
        
        // Match keyboard devices
        let deviceMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]
        
        IOHIDManagerSetDeviceMatching(manager, deviceMatch as CFDictionary)
        
        // Register callbacks
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, sender, value in
            guard let context = context else { return }
            let service = Unmanaged<HotkeyService>.fromOpaque(context).takeUnretainedValue()
            service.handleHIDInput(value: value)
        }, context)
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult == kIOReturnSuccess {
            print("[HotkeyService] ✅ HID manager opened successfully")
        } else {
            print("[HotkeyService] ⚠️ Failed to open HID manager: \(openResult)")
        }
    }
    
    private func handleHIDInput(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)
        
        // Fn key is typically on usage page 0xFF (vendor defined) or 0x07 (keyboard)
        // Usage varies by keyboard manufacturer
        
        // Log all keyboard events for debugging
        if usagePage == 0x07 || usagePage == 0xFF {
            print("[HotkeyService] 🎹 HID: page=\(usagePage), usage=\(usage), value=\(intValue)")
            
            // Common Fn key codes: 0x63 (99), 0xFF, varies by manufacturer
            if usage == 0x63 || usage == 0xFF {
                let pressed = intValue != 0
                if pressed != isFnKeyPressed {
                    isFnKeyPressed = pressed
                    print("[HotkeyService] 🎤 Fn key detected via HID: \(pressed ? "PRESSED ✅" : "RELEASED ⭕️")")
                    notifyKeyStateChange(pressed: pressed)
                }
            }
        }
    }
    
    // MARK: - Polling Method (Last resort)
    
    private func startFnKeyPolling() {
        // Poll every 50ms to check Fn key state
        fnKeyCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkFnKeyState()
        }
        print("[HotkeyService] ✅ Started Fn key polling")
    }
    
    private func checkFnKeyState() {
        // Create a temporary event to check current modifier flags
        guard let event = CGEvent(source: nil) else { return }
        
        let flags = event.flags
        let fnPressed = flags.contains(.maskSecondaryFn)
        
        if fnPressed != isFnKeyPressed {
            isFnKeyPressed = fnPressed
            print("[HotkeyService] 🎤 Fn key detected via polling: \(fnPressed ? "PRESSED ✅" : "RELEASED ⭕️")")
            notifyKeyStateChange(pressed: fnPressed)
        }
    }
}
