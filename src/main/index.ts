import { app, BrowserWindow, Tray, Menu, nativeImage, ipcMain, shell } from 'electron'
import { electronApp, optimizer } from '@electron-toolkit/utils'
import { join } from 'path'
import { createMainWindow } from './windows/mainWindow'
import { createFlowBar, showFlowBar, hideFlowBar } from './windows/flowBar'
import { setupIpcHandlers } from './ipc'
import { initStore, addTranscription, getSettings } from './services/store.service'
import { ShortcutService } from './services/shortcut.service'
import { DeepgramService } from './services/deepgram.service'
import { AudioService } from './services/audio.service'
import { KeyboardService } from './services/keyboard.service'
import { cleanText } from './utils/textCleanup'
import { IPC_CHANNELS } from '../shared/constants/ipcChannels'

let mainWindow: BrowserWindow | null = null
let flowBar: BrowserWindow | null = null
let tray: Tray | null = null

// Services
let shortcutService: ShortcutService | null = null
let deepgramService: DeepgramService | null = null
let audioService: AudioService | null = null
let keyboardService: KeyboardService | null = null

// Recording state
let isRecording = false
let isQuitting = false
let recordingMode: 'idle' | 'hold' | 'continuous' = 'idle'
let holdTimer: NodeJS.Timeout | null = null
let releaseDelayTimer: NodeJS.Timeout | null = null
let transcriptionText = ''

// Delay before stopping recording after key release (ms)
const RELEASE_DELAY_MS = 800

async function createTray(): Promise<void> {
  const iconPath = join(__dirname, '../../resources/trayTemplate.png')
  const icon = nativeImage.createFromPath(iconPath)
  tray = new Tray(icon.isEmpty() ? nativeImage.createEmpty() : icon)

  const contextMenu = Menu.buildFromTemplate([
    {
      label: 'Show Corius Voice',
      click: () => {
        if (mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.show()
          mainWindow.focus()
        }
      }
    },
    { type: 'separator' },
    {
      label: 'Start Recording',
      accelerator: 'Alt+Space',
      click: () => startRecording()
    },
    { type: 'separator' },
    {
      label: 'Quit',
      click: () => app.quit()
    }
  ])

  tray.setToolTip('Corius Voice')
  tray.setContextMenu(contextMenu)

  tray.on('click', () => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.show()
      mainWindow.focus()
    }
  })
}

function createAppMenu(): void {
  const isMac = process.platform === 'darwin'

  const template: Electron.MenuItemConstructorOptions[] = [
    // App menu (macOS only)
    ...(isMac
      ? [
          {
            label: app.name,
            submenu: [
              { role: 'about' as const },
              { type: 'separator' as const },
              {
                label: 'Settings...',
                accelerator: 'Cmd+,',
                click: () => {
                  if (mainWindow && !mainWindow.isDestroyed()) {
                    mainWindow.show()
                    mainWindow.focus()
                  }
                }
              },
              { type: 'separator' as const },
              { role: 'services' as const },
              { type: 'separator' as const },
              { role: 'hide' as const },
              { role: 'hideOthers' as const },
              { role: 'unhide' as const },
              { type: 'separator' as const },
              { role: 'quit' as const }
            ]
          }
        ]
      : []),
    // Edit menu
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' },
        { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        { role: 'selectAll' }
      ]
    },
    // View menu
    {
      label: 'View',
      submenu: [
        { role: 'reload' },
        { role: 'forceReload' },
        { role: 'toggleDevTools' },
        { type: 'separator' },
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' }
      ]
    },
    // Window menu
    {
      label: 'Window',
      submenu: [
        { role: 'minimize' },
        { role: 'zoom' },
        ...(isMac
          ? [
              { type: 'separator' as const },
              { role: 'front' as const },
              { type: 'separator' as const },
              { role: 'window' as const }
            ]
          : [{ role: 'close' as const }])
      ]
    },
    // Help menu
    {
      role: 'help',
      submenu: [
        {
          label: 'Learn More',
          click: async () => {
            await shell.openExternal('https://github.com/marius/corius-voice')
          }
        }
      ]
    }
  ]

  const menu = Menu.buildFromTemplate(template)
  Menu.setApplicationMenu(menu)
}

async function startRecording(): Promise<void> {
  if (isRecording) return

  recordingMode = 'hold'
  transcriptionText = ''

  // First connect to Deepgram before starting audio capture
  try {
    await deepgramService?.connect()
  } catch (error) {
    console.error('Failed to connect to Deepgram:', error)
    return
  }

  // Now set recording state and notify renderers to start capturing
  isRecording = true

  // Show flow bar (this triggers audio capture in the renderer)
  if (flowBar) {
    showFlowBar(flowBar)
    flowBar.webContents.send(IPC_CHANNELS.RECORDING_STATE_CHANGED, {
      isRecording: true,
      mode: 'hold'
    })
  }

  // Notify main window
  mainWindow?.webContents.send(IPC_CHANNELS.RECORDING_STATE_CHANGED, {
    isRecording: true,
    mode: 'hold'
  })

  // Start audio service (placeholder for main process audio handling)
  audioService?.startCapture((audioData) => {
    deepgramService?.sendAudio(audioData)
    flowBar?.webContents.send(IPC_CHANNELS.AUDIO_DATA, audioData)
  })

  // Start hold timer - if user holds for more than 3 seconds, switch to continuous mode
  holdTimer = setTimeout(() => {
    if (isRecording && recordingMode === 'hold') {
      recordingMode = 'continuous'
      flowBar?.webContents.send(IPC_CHANNELS.RECORDING_STATE_CHANGED, {
        isRecording: true,
        mode: 'continuous'
      })
      mainWindow?.webContents.send(IPC_CHANNELS.RECORDING_STATE_CHANGED, {
        isRecording: true,
        mode: 'continuous'
      })
    }
  }, 3000)
}

async function stopRecording(): Promise<void> {
  if (!isRecording) return

  isRecording = false
  recordingMode = 'idle'

  // Clear timers
  if (holdTimer) {
    clearTimeout(holdTimer)
    holdTimer = null
  }
  if (releaseDelayTimer) {
    clearTimeout(releaseDelayTimer)
    releaseDelayTimer = null
  }

  // Stop audio capture
  audioService?.stopCapture()

  // Disconnect Deepgram
  deepgramService?.disconnect()

  // Hide flow bar
  if (flowBar) {
    hideFlowBar(flowBar)
  }

  // Notify windows
  flowBar?.webContents.send(IPC_CHANNELS.RECORDING_STATE_CHANGED, {
    isRecording: false,
    mode: 'idle'
  })
  mainWindow?.webContents.send(IPC_CHANNELS.RECORDING_STATE_CHANGED, {
    isRecording: false,
    mode: 'idle'
  })

  // Clean and process text
  if (transcriptionText.trim()) {
    const cleanedText = cleanText(transcriptionText)
    const settings = getSettings()

    // Create transcription object
    const transcription = {
      id: `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`,
      text: transcriptionText.trim(),
      cleanedText,
      timestamp: Date.now(),
      language: settings.general.language || 'es',
      duration: 0
    }

    // Save to store
    addTranscription(transcription)
    console.log('[Transcription] Saved:', transcription.cleanedText.slice(0, 50))

    // Copy to clipboard and attempt to paste
    await keyboardService?.copyAndPaste(cleanedText)

    // Send final transcription to main window
    mainWindow?.webContents.send(IPC_CHANNELS.TRANSCRIPTION_FINAL, transcription)
  }
}

function handleKeyRelease(): void {
  // Only stop if in hold mode (< 3 seconds)
  if (isRecording && recordingMode === 'hold') {
    // Add a small delay before stopping to capture any last words
    releaseDelayTimer = setTimeout(() => {
      if (isRecording && recordingMode === 'hold') {
        stopRecording()
      }
      releaseDelayTimer = null
    }, RELEASE_DELAY_MS)
  }
}

function handleKeyPress(): void {
  // Cancel any pending release delay
  if (releaseDelayTimer) {
    clearTimeout(releaseDelayTimer)
    releaseDelayTimer = null
  }

  if (isRecording) {
    // Toggle off - stop recording regardless of mode
    stopRecording()
  } else {
    startRecording()
  }
}

app.whenReady().then(async () => {
  // Set app user model id for windows
  electronApp.setAppUserModelId('com.corius.voice')

  // Set dock icon on macOS
  if (process.platform === 'darwin') {
    const dockIconPath = join(__dirname, '../../resources/icon.png')
    const dockIcon = nativeImage.createFromPath(dockIconPath)
    if (!dockIcon.isEmpty()) {
      app.dock.setIcon(dockIcon)
    }
  }

  // Default open or close DevTools by F12 in development
  app.on('browser-window-created', (_, window) => {
    optimizer.watchWindowShortcuts(window)
  })

  // Initialize store
  initStore()

  // Create windows
  mainWindow = await createMainWindow(() => isQuitting)
  flowBar = await createFlowBar()

  // Create tray
  await createTray()

  // Create application menu
  createAppMenu()

  // Setup IPC handlers
  setupIpcHandlers(mainWindow, flowBar)

  // Initialize services
  keyboardService = new KeyboardService()
  audioService = new AudioService()
  deepgramService = new DeepgramService()

  // Setup Deepgram transcription handlers
  deepgramService.onTranscript((result) => {
    console.log(`[Deepgram] Transcript: "${result.text}" (final: ${result.isFinal})`)
    if (result.isFinal) {
      transcriptionText += result.text + ' '
      mainWindow?.webContents.send(IPC_CHANNELS.TRANSCRIPTION_FINAL, result)
      flowBar?.webContents.send(IPC_CHANNELS.TRANSCRIPTION_FINAL, result)
    } else {
      mainWindow?.webContents.send(IPC_CHANNELS.TRANSCRIPTION_INTERIM, result)
      flowBar?.webContents.send(IPC_CHANNELS.TRANSCRIPTION_INTERIM, result)
    }
  })

  deepgramService.onUtteranceEnd(() => {
    // Auto-stop in continuous mode when silence is detected
    if (isRecording && recordingMode === 'continuous') {
      stopRecording()
    }
  })

  deepgramService.onError((error) => {
    console.error('Deepgram error:', error)
    mainWindow?.webContents.send(IPC_CHANNELS.TRANSCRIPTION_ERROR, error.message)
  })

  // Handle audio data from renderer (flow bar captures audio in WebM/Opus format)
  ipcMain.on('audio:raw-data', (_, data: ArrayBuffer) => {
    if (isRecording && deepgramService) {
      deepgramService.sendAudio(Buffer.from(data))
    }
  })

  // Initialize shortcut service
  shortcutService = new ShortcutService()
  shortcutService.onKeyDown(() => handleKeyPress())
  shortcutService.onKeyUp(() => handleKeyRelease())
  await shortcutService.start()

  app.on('activate', () => {
    // Show window when clicking dock icon
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.show()
      mainWindow.focus()
    } else if (BrowserWindow.getAllWindows().length === 0) {
      createMainWindow(() => isQuitting).then((win) => {
        mainWindow = win
      })
    }
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit()
  }
})

app.on('before-quit', () => {
  isQuitting = true
  shortcutService?.stop()
  audioService?.stopCapture()
  deepgramService?.disconnect()
})
