import { BrowserWindow, screen } from 'electron'
import { join } from 'path'
import { is } from '@electron-toolkit/utils'

let flowBarWindow: BrowserWindow | null = null

export async function createFlowBar(): Promise<BrowserWindow> {
  const primaryDisplay = screen.getPrimaryDisplay()
  const { width: screenWidth, height: screenHeight } = primaryDisplay.workAreaSize

  const barWidth = 400
  const barHeight = 80

  flowBarWindow = new BrowserWindow({
    width: barWidth,
    height: barHeight,
    x: Math.round((screenWidth - barWidth) / 2),
    y: screenHeight - barHeight - 100,
    frame: false,
    transparent: true,
    alwaysOnTop: true,
    skipTaskbar: true,
    resizable: false,
    movable: true,
    hasShadow: true,
    show: false,
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      sandbox: false,
      contextIsolation: true,
      nodeIntegration: false
    }
  })

  // Make window visible on all workspaces
  flowBarWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })

  // Prevent window from being focused
  flowBarWindow.setAlwaysOnTop(true, 'floating')

  // Load the flow bar renderer
  if (is.dev && process.env['ELECTRON_RENDERER_URL']) {
    flowBarWindow.loadURL(`${process.env['ELECTRON_RENDERER_URL']}/flowBar.html`)
  } else {
    flowBarWindow.loadFile(join(__dirname, '../renderer/flowBar.html'))
  }

  return flowBarWindow
}

export function showFlowBar(window: BrowserWindow): void {
  if (window && !window.isDestroyed()) {
    window.show()
    window.setAlwaysOnTop(true, 'floating')
  }
}

export function hideFlowBar(window: BrowserWindow): void {
  if (window && !window.isDestroyed()) {
    window.hide()
  }
}

export function getFlowBar(): BrowserWindow | null {
  return flowBarWindow
}
