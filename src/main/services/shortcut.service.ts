import { globalShortcut, BrowserWindow } from 'electron'
import { getSettings } from './store.service'
import { fnKeyService } from './fnkey.service'

type KeyCallback = () => void
type ActivationMode = 'keyboard-shortcut' | 'fn-key'

export class ShortcutService {
  private keyDownCallback: KeyCallback | null = null
  private keyUpCallback: KeyCallback | null = null
  private isStarted = false
  private isKeyDown = false
  private keyUpTimer: NodeJS.Timeout | null = null
  private activationMode: ActivationMode = 'keyboard-shortcut'
  private fnKeyStarted = false
  private lastFnDownTime = 0
  private fnReleaseDebounceTimer: NodeJS.Timeout | null = null

  // Minimum time Fn must be held before release is registered (ms)
  private static readonly FN_MIN_HOLD_TIME = 150
  // Debounce time for Fn release events (ms)
  private static readonly FN_RELEASE_DEBOUNCE = 100

  onKeyDown(callback: KeyCallback): void {
    this.keyDownCallback = callback
  }

  onKeyUp(callback: KeyCallback): void {
    this.keyUpCallback = callback
  }

  async start(): Promise<void> {
    if (this.isStarted) return

    const settings = getSettings()
    const shortcut = settings.shortcuts?.activationKey || 'Alt+Space'

    // Determine activation mode based on settings
    // If shortcut is 'fn' or 'Fn' or 'FN', use FN key mode
    if (shortcut.toLowerCase() === 'fn') {
      this.activationMode = 'fn-key'
      await this.startFnKeyMode()
    } else {
      this.activationMode = 'keyboard-shortcut'
      this.startKeyboardShortcutMode(shortcut)
    }

    this.isStarted = true
  }

  /**
   * Start FN key detection mode using native helper
   */
  private async startFnKeyMode(): Promise<void> {
    console.log('Starting FN key mode...')

    // Set up event listeners with debouncing
    fnKeyService.on('fn-down', () => {
      // Cancel any pending release
      if (this.fnReleaseDebounceTimer) {
        clearTimeout(this.fnReleaseDebounceTimer)
        this.fnReleaseDebounceTimer = null
      }

      if (!this.isKeyDown) {
        this.isKeyDown = true
        this.lastFnDownTime = Date.now()
        console.log('[ShortcutService] FN key pressed')
        this.keyDownCallback?.()
      }
    })

    fnKeyService.on('fn-up', () => {
      if (this.isKeyDown) {
        const holdTime = Date.now() - this.lastFnDownTime

        // Ignore very short presses (likely spurious events)
        if (holdTime < ShortcutService.FN_MIN_HOLD_TIME) {
          console.log(`[ShortcutService] FN release ignored (held only ${holdTime}ms)`)
          return
        }

        // Debounce the release to handle rapid toggles
        if (this.fnReleaseDebounceTimer) {
          clearTimeout(this.fnReleaseDebounceTimer)
        }

        this.fnReleaseDebounceTimer = setTimeout(() => {
          if (this.isKeyDown) {
            this.isKeyDown = false
            console.log('[ShortcutService] FN key released')
            this.keyUpCallback?.()
          }
          this.fnReleaseDebounceTimer = null
        }, ShortcutService.FN_RELEASE_DEBOUNCE)
      }
    })

    fnKeyService.on('error', (err) => {
      console.error('[ShortcutService] FN key service error:', err)
    })

    fnKeyService.on('permission-required', (permission) => {
      console.warn(`[ShortcutService] Permission required: ${permission}`)
      // You could emit an event to show a dialog to the user
    })

    fnKeyService.on('ready', () => {
      console.log('[ShortcutService] FN key service ready')
    })

    // Start the FN key service
    const started = await fnKeyService.start()
    if (started) {
      this.fnKeyStarted = true
      console.log('FN key mode started successfully')
    } else {
      console.error('Failed to start FN key mode, falling back to Alt+Space')
      // Fallback to keyboard shortcut
      this.activationMode = 'keyboard-shortcut'
      this.startKeyboardShortcutMode('Alt+Space')
    }
  }

  /**
   * Start traditional keyboard shortcut mode using Electron globalShortcut
   */
  private startKeyboardShortcutMode(shortcut: string): void {
    // Register the shortcut
    const registered = globalShortcut.register(shortcut, () => {
      if (!this.isKeyDown) {
        // Key down event
        this.isKeyDown = true
        this.keyDownCallback?.()

        // Clear any existing timer
        if (this.keyUpTimer) {
          clearTimeout(this.keyUpTimer)
        }
      } else {
        // Second press while recording - trigger stop
        this.isKeyDown = false
        if (this.keyUpTimer) {
          clearTimeout(this.keyUpTimer)
          this.keyUpTimer = null
        }
        this.keyUpCallback?.()
      }
    })

    if (!registered) {
      console.error(`Failed to register shortcut: ${shortcut}`)
      return
    }

    // Since globalShortcut doesn't detect key release, we use a workaround:
    // Monitor for the shortcut NOT being pressed using a polling mechanism
    // This runs only when recording is active
    this.startKeyUpDetection()

    console.log(`Shortcut service started - listening for ${shortcut}`)
  }

  private startKeyUpDetection(): void {
    // Use window blur/focus events as a proxy for key release
    // When the user releases Option, other windows can receive focus
    const windows = BrowserWindow.getAllWindows()

    windows.forEach(window => {
      window.on('blur', () => {
        // If we're in hold mode (less than 3 seconds), treat blur as key release
        if (this.isKeyDown && this.activationMode === 'keyboard-shortcut') {
          // Small delay to allow for focus changes
          this.keyUpTimer = setTimeout(() => {
            if (this.isKeyDown) {
              this.isKeyDown = false
              this.keyUpCallback?.()
            }
          }, 100)
        }
      })
    })
  }

  // Call this when recording mode changes to continuous
  notifyModeChange(mode: 'hold' | 'continuous'): void {
    if (mode === 'continuous' && this.keyUpTimer) {
      // In continuous mode, cancel key-up detection
      clearTimeout(this.keyUpTimer)
      this.keyUpTimer = null
    }
  }

  // Manual trigger for key release (can be called from IPC)
  triggerKeyUp(): void {
    if (this.isKeyDown) {
      this.isKeyDown = false
      this.keyUpCallback?.()
    }
  }

  stop(): void {
    if (!this.isStarted) return

    // Stop keyboard shortcut mode
    globalShortcut.unregisterAll()

    // Stop FN key mode
    if (this.fnKeyStarted) {
      fnKeyService.stop()
      this.fnKeyStarted = false
    }

    if (this.keyUpTimer) {
      clearTimeout(this.keyUpTimer)
      this.keyUpTimer = null
    }

    if (this.fnReleaseDebounceTimer) {
      clearTimeout(this.fnReleaseDebounceTimer)
      this.fnReleaseDebounceTimer = null
    }

    this.isStarted = false
    this.isKeyDown = false
    this.lastFnDownTime = 0
    console.log('Shortcut service stopped')
  }

  isRunning(): boolean {
    return this.isStarted
  }

  isPressed(): boolean {
    return this.isKeyDown
  }

  getActivationMode(): ActivationMode {
    return this.activationMode
  }

  /**
   * Switch activation mode at runtime
   */
  async setActivationMode(mode: ActivationMode | string): Promise<void> {
    // Stop current mode
    this.stop()

    // Reset state
    this.isStarted = false
    this.isKeyDown = false

    if (mode === 'fn-key' || mode.toLowerCase() === 'fn') {
      this.activationMode = 'fn-key'
      await this.startFnKeyMode()
    } else {
      this.activationMode = 'keyboard-shortcut'
      this.startKeyboardShortcutMode(mode === 'keyboard-shortcut' ? 'Alt+Space' : mode)
    }

    this.isStarted = true
  }
}
