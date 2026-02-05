import Foundation
import AppKit
import CoreGraphics
import Carbon

class HotkeyService {
    static let shared = HotkeyService()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var flagsMonitor: Any?

    private var isFnKeyPressed = false
    private var fnKeyCheckTimer: Timer?

    // Track state to avoid duplicates
    private var lastFnState = false
    private var fnPressTime: Date?

    // Debouncing
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.15 // 150ms debounce

    private init() {}

    var isRunning: Bool {
        return globalMonitor != nil || localMonitor != nil || fnKeyCheckTimer != nil
    }

    func start() {
        print("[HotkeyService] 🚀 Starting Globe/Fn key detection...")

        // Check accessibility permissions
        let hasPermissions = AXIsProcessTrusted()

        if hasPermissions {
            print("[HotkeyService] ✅ Accessibility permissions granted")
            setupNSEventMonitors()
        } else {
            print("[HotkeyService] ℹ️ No accessibility permissions - using polling")
            // Only use polling if no accessibility permissions
            startFnKeyPolling()
        }

        print("[HotkeyService] ✅ Started successfully")
        print("[HotkeyService] 📝 Press and hold Globe/Fn key to record")
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }

        fnKeyCheckTimer?.invalidate()
        fnKeyCheckTimer = nil

        debounceTimer?.invalidate()
        debounceTimer = nil

        print("[HotkeyService] Stopped")
    }

    // MARK: - NSEvent Monitors (Better for Globe key)

    private func setupNSEventMonitors() {
        // Monitor for flagsChanged events globally
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Also monitor locally when app is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        print("[HotkeyService] ✅ NSEvent monitors created")
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags

        // Check for Globe/Fn key - it's the .function flag
        let fnPressed = flags.contains(.function)

        // Check if ANY other modifier is pressed - if so, ignore
        let hasCommand = flags.contains(.command)
        let hasOption = flags.contains(.option)
        let hasControl = flags.contains(.control)
        let hasShift = flags.contains(.shift)
        let hasOtherModifier = hasCommand || hasOption || hasControl || hasShift

        // Check if arrow keys or other keys are pressed
        let keyCode = event.keyCode
        let isArrowOrNavKey = isProblematicKeyCode(keyCode)

        // Also check if any arrow key is currently held down
        let arrowHeld = isAnyArrowKeyPressed()

        // Debug logging - ALWAYS log when fn flag is set
        if fnPressed {
            print("[HotkeyService] 🔑 Flags: fn=\(fnPressed), keyCode=\(keyCode), otherMod=\(hasOtherModifier), isArrowCode=\(isArrowOrNavKey), arrowHeld=\(arrowHeld)")
        }

        // Only trigger if:
        // 1. Fn flag changed state
        // 2. No other modifiers are pressed
        // 3. Not caused by arrow/nav keys (either keyCode or held state)

        let shouldIgnore = hasOtherModifier || isArrowOrNavKey || arrowHeld

        if fnPressed && !isFnKeyPressed && !shouldIgnore {
            // Fn pressed - use debounce to avoid false positives
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
                self?.confirmFnPress()
            }
            fnPressTime = Date()
        } else if !fnPressed && isFnKeyPressed {
            // Fn released - immediate response
            debounceTimer?.invalidate()
            debounceTimer = nil
            setFnState(false)
        } else if shouldIgnore {
            // Another key is involved - cancel any pending press
            debounceTimer?.invalidate()
            debounceTimer = nil
            if isFnKeyPressed {
                print("[HotkeyService] ⚠️ Cancelling due to other key")
                setFnState(false)
            }
        }

        lastFnState = fnPressed
    }

    private func confirmFnPress() {
        // Double-check that Fn is still pressed and nothing else
        guard let event = CGEvent(source: nil) else { return }
        let flags = event.flags

        let fnStillPressed = flags.contains(.maskSecondaryFn)
        let hasCommand = flags.contains(.maskCommand)
        let hasOption = flags.contains(.maskAlternate)
        let hasControl = flags.contains(.maskControl)
        let hasShift = flags.contains(.maskShift)
        let hasOtherModifier = hasCommand || hasOption || hasControl || hasShift

        let arrowPressed = isAnyArrowKeyPressed()

        if fnStillPressed && !hasOtherModifier && !arrowPressed && !isFnKeyPressed {
            setFnState(true)
        }
    }

    private func setFnState(_ pressed: Bool) {
        guard pressed != isFnKeyPressed else { return }

        isFnKeyPressed = pressed
        print("[HotkeyService] 🎤 Globe/Fn key \(pressed ? "PRESSED ✅" : "RELEASED ⭕️")")

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .fnKeyStateChanged,
                object: nil,
                userInfo: ["pressed": pressed]
            )
        }
    }

    private func isProblematicKeyCode(_ keyCode: UInt16) -> Bool {
        // For flagsChanged events:
        // - keyCode 63 is the Fn/Globe key itself
        // - keyCode 0 might mean just modifier change (no specific key)
        // - Any other keyCode means another key was pressed WITH the modifier

        // These are the ONLY acceptable keyCodes for Globe key alone
        let acceptableCodes: Set<UInt16> = [0, 63]

        // If keyCode is acceptable, it's NOT problematic
        if acceptableCodes.contains(keyCode) {
            return false
        }

        // Any other keyCode is problematic (arrow, F-key, letter, etc.)
        return true
    }

    private func isAnyArrowKeyPressed() -> Bool {
        let keysToCheck: [CGKeyCode] = [123, 124, 125, 126, 115, 116, 117, 119, 121]
        for keyCode in keysToCheck {
            if CGEventSource.keyState(.combinedSessionState, key: keyCode) {
                return true
            }
        }
        return false
    }

    private func isGlobeKeyPhysicallyPressed() -> Bool {
        // KeyCode 63 is the Fn/Globe key on most keyboards
        // KeyCode 179 is Globe key on some newer MacBooks
        return CGEventSource.keyState(.combinedSessionState, key: 63) ||
               CGEventSource.keyState(.combinedSessionState, key: 179)
    }

    private func isAnyNonModifierKeyPressed() -> Bool {
        // Check common keys that might trigger the Fn flag
        // Arrow keys
        for keyCode: CGKeyCode in [123, 124, 125, 126] {
            if CGEventSource.keyState(.combinedSessionState, key: keyCode) {
                return true
            }
        }
        // Navigation keys
        for keyCode: CGKeyCode in [115, 116, 117, 119, 121] {
            if CGEventSource.keyState(.combinedSessionState, key: keyCode) {
                return true
            }
        }
        // F-keys
        for keyCode: CGKeyCode in [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111] {
            if CGEventSource.keyState(.combinedSessionState, key: keyCode) {
                return true
            }
        }
        return false
    }

    // MARK: - Polling Method (Backup)

    private var pollDebounceCount = 0
    private var lastPollState = false

    private func startFnKeyPolling() {
        fnKeyCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkFnKeyState()
        }
        print("[HotkeyService] ✅ Started polling (backup)")
    }

    private func checkFnKeyState() {
        guard let event = CGEvent(source: nil) else { return }

        let flags = event.flags
        let fnFlagSet = flags.contains(.maskSecondaryFn)

        // Check for other modifiers
        let hasCommand = flags.contains(.maskCommand)
        let hasOption = flags.contains(.maskAlternate)
        let hasControl = flags.contains(.maskControl)
        let hasShift = flags.contains(.maskShift)
        let hasOtherModifier = hasCommand || hasOption || hasControl || hasShift

        // Check if any non-modifier key is pressed (arrows, F-keys, etc.)
        let anyKeyPressed = isAnyNonModifierKeyPressed()

        // Check if Globe key (keyCode 63 or 179) is physically pressed
        let globeKeyPressed = isGlobeKeyPhysicallyPressed()

        // Release is always immediate - Globe key must be physically released
        if !globeKeyPressed && isFnKeyPressed {
            pollDebounceCount = 0
            setFnState(false)
            return
        }

        // Cancel if we're recording and another key is pressed
        if isFnKeyPressed && anyKeyPressed {
            print("[HotkeyService] ⚠️ Other key pressed while recording, stopping")
            pollDebounceCount = 0
            setFnState(false)
            return
        }

        // Use Globe key physical state - NOT the fn flag (which arrow keys also set)
        let shouldBePressed = globeKeyPressed && !hasOtherModifier && !anyKeyPressed

        // Debug logging
        if fnFlagSet || globeKeyPressed {
            if pollDebounceCount == 0 {
                print("[HotkeyService] 📊 Poll: fnFlag=\(fnFlagSet), globeKey=\(globeKeyPressed), anyKey=\(anyKeyPressed), should=\(shouldBePressed)")
            }
        }

        if shouldBePressed == lastPollState {
            pollDebounceCount += 1
        } else {
            pollDebounceCount = 0
            lastPollState = shouldBePressed
        }

        // Require 4 consistent polls (200ms) for press
        if pollDebounceCount >= 4 && shouldBePressed && !isFnKeyPressed {
            setFnState(true)
        }
    }
}
