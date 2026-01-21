import { clipboard, Notification } from 'electron'
import { exec } from 'child_process'
import { promisify } from 'util'

const execAsync = promisify(exec)

export class KeyboardService {
  private canUseAppleScript = true

  constructor() {
    // Test if AppleScript is available (macOS with accessibility permissions)
    this.checkAppleScriptAccess()
  }

  private async checkAppleScriptAccess(): Promise<void> {
    if (process.platform !== 'darwin') {
      this.canUseAppleScript = false
      return
    }

    try {
      // Simple test to check if we have accessibility permissions
      await execAsync('osascript -e "tell application \\"System Events\\" to return name of first process"')
      this.canUseAppleScript = true
    } catch {
      this.canUseAppleScript = false
      console.warn('AppleScript access not available. Auto-paste disabled.')
    }
  }

  async copyAndPaste(text: string): Promise<boolean> {
    // Always copy to clipboard first
    clipboard.writeText(text)
    console.log('Text copied to clipboard')

    // Try to auto-paste on macOS
    if (process.platform === 'darwin' && this.canUseAppleScript) {
      return this.pasteWithAppleScript()
    }

    // Show notification that text is in clipboard
    this.showClipboardNotification()
    return false
  }

  private async pasteWithAppleScript(): Promise<boolean> {
    try {
      // Use AppleScript to simulate Cmd+V
      const script = `
        tell application "System Events"
          keystroke "v" using command down
        end tell
      `
      await execAsync(`osascript -e '${script}'`)
      console.log('Text pasted using AppleScript')
      return true
    } catch (error) {
      console.error('Failed to paste with AppleScript:', error)
      this.showClipboardNotification()
      return false
    }
  }

  private showClipboardNotification(): void {
    const notification = new Notification({
      title: 'Corius Voice',
      body: 'Text copied to clipboard. Press Cmd+V to paste.',
      silent: true
    })
    notification.show()
  }

  async typeText(text: string): Promise<boolean> {
    if (process.platform !== 'darwin' || !this.canUseAppleScript) {
      // Fall back to clipboard
      clipboard.writeText(text)
      this.showClipboardNotification()
      return false
    }

    try {
      // Escape special characters for AppleScript
      const escapedText = text
        .replace(/\\/g, '\\\\')
        .replace(/"/g, '\\"')
        .replace(/\n/g, '\\n')

      const script = `
        tell application "System Events"
          keystroke "${escapedText}"
        end tell
      `
      await execAsync(`osascript -e '${script}'`)
      return true
    } catch (error) {
      console.error('Failed to type text:', error)
      clipboard.writeText(text)
      this.showClipboardNotification()
      return false
    }
  }

  isAutopasteAvailable(): boolean {
    return this.canUseAppleScript
  }
}
