import Foundation
import AppKit
import CoreGraphics

class KeyboardService {
    static let shared = KeyboardService()

    private init() {}

    /// Paste text into the active application
    func pasteText(_ text: String) {
        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure clipboard is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.simulatePaste()
        }
    }

    /// Copy text to clipboard without pasting
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Get text from clipboard
    func getClipboardText() -> String? {
        return NSPasteboard.general.string(forType: .string)
    }

    /// Simulate Cmd+V keyboard shortcut
    private func simulatePaste() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("[KeyboardService] Failed to create event source")
            return
        }

        // Virtual key code for 'V'
        let vKeyCode: CGKeyCode = 0x09

        // Create key down event with Command modifier
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
            print("[KeyboardService] Failed to create key down event")
            return
        }
        keyDown.flags = .maskCommand

        // Create key up event
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            print("[KeyboardService] Failed to create key up event")
            return
        }
        keyUp.flags = .maskCommand

        // Post events
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        print("[KeyboardService] Paste simulated")
    }

    /// Type text character by character (slower but more compatible)
    func typeText(_ text: String, interval: TimeInterval = 0.01) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("[KeyboardService] Failed to create event source")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            for char in text {
                let charString = String(char)

                // Create key event for each character
                if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                   let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {

                    // Set the Unicode string for the key event
                    var unicodeChars = Array(charString.utf16)
                    keyDown.keyboardSetUnicodeString(stringLength: unicodeChars.count, unicodeString: &unicodeChars)
                    keyUp.keyboardSetUnicodeString(stringLength: unicodeChars.count, unicodeString: &unicodeChars)

                    keyDown.post(tap: .cghidEventTap)
                    keyUp.post(tap: .cghidEventTap)

                    Thread.sleep(forTimeInterval: interval)
                }
            }
        }
    }

    /// Simulate a specific key press
    func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        if !modifiers.isEmpty {
            keyDown.flags = modifiers
            keyUp.flags = modifiers
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

// Common key codes
extension CGKeyCode {
    static let returnKey: CGKeyCode = 0x24
    static let tabKey: CGKeyCode = 0x30
    static let spaceKey: CGKeyCode = 0x31
    static let deleteKey: CGKeyCode = 0x33
    static let escapeKey: CGKeyCode = 0x35
    static let leftArrowKey: CGKeyCode = 0x7B
    static let rightArrowKey: CGKeyCode = 0x7C
    static let downArrowKey: CGKeyCode = 0x7D
    static let upArrowKey: CGKeyCode = 0x7E
}
