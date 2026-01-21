import { EventEmitter } from 'events'
import { spawn, ChildProcess } from 'child_process'
import * as net from 'net'
import * as path from 'path'
import * as fs from 'fs'
import { app } from 'electron'

const SOCKET_PATH = '/tmp/corius-fnkey.sock'
const RECONNECT_DELAY = 1000
const MAX_RECONNECT_ATTEMPTS = 5

interface FnKeyEvent {
  event: string
  data?: {
    timestamp: number
  }
}

type FnKeyEventType = 'fn-down' | 'fn-up' | 'ready' | 'connected' | 'error' | 'helper-error' | 'helper-exit' | 'permission-required'

class FnKeyService extends EventEmitter {
  private helperProcess: ChildProcess | null = null
  private socket: net.Socket | null = null
  private isConnected = false
  private isRunning = false
  private reconnectAttempts = 0
  private reconnectTimer: NodeJS.Timeout | null = null
  private buffer = ''

  /**
   * Get the path to the FnKeyHelper binary
   */
  private getHelperPath(): string {
    // In development, use the resources/bin directory
    // In production, use the app's resources directory
    const isDev = !app.isPackaged

    if (isDev) {
      return path.join(app.getAppPath(), 'resources', 'bin', 'FnKeyHelper')
    }

    // In production, the binary is in the app's Resources folder
    return path.join(process.resourcesPath, 'bin', 'FnKeyHelper')
  }

  /**
   * Check if the helper binary exists and is executable
   */
  private helperExists(): boolean {
    const helperPath = this.getHelperPath()
    try {
      fs.accessSync(helperPath, fs.constants.X_OK)
      return true
    } catch {
      return false
    }
  }

  /**
   * Start the FN key monitoring service
   */
  async start(): Promise<boolean> {
    if (this.isRunning) {
      console.log('[FnKeyService] Already running')
      return true
    }

    const helperPath = this.getHelperPath()
    console.log('[FnKeyService] Starting with helper:', helperPath)

    if (!this.helperExists()) {
      console.error('[FnKeyService] Helper binary not found:', helperPath)
      this.emit('error', new Error(`Helper binary not found: ${helperPath}`))
      return false
    }

    // Clean up any existing socket file
    try {
      if (fs.existsSync(SOCKET_PATH)) {
        fs.unlinkSync(SOCKET_PATH)
      }
    } catch (err) {
      console.warn('[FnKeyService] Could not clean up old socket:', err)
    }

    // Start the helper process
    try {
      this.helperProcess = spawn(helperPath, [], {
        stdio: ['ignore', 'pipe', 'pipe'],
        detached: false
      })

      this.isRunning = true

      // Handle helper stdout (not used, but good to capture)
      this.helperProcess.stdout?.on('data', (data: Buffer) => {
        console.log('[FnKeyHelper]', data.toString().trim())
      })

      // Handle helper stderr (log messages)
      this.helperProcess.stderr?.on('data', (data: Buffer) => {
        const message = data.toString().trim()
        console.log('[FnKeyHelper]', message)

        // Check for permission issues
        if (message.includes('Accessibility access not granted')) {
          this.emit('permission-required', 'accessibility')
        }
        if (message.includes('Input Monitoring')) {
          this.emit('permission-required', 'input-monitoring')
        }
      })

      // Handle helper exit
      this.helperProcess.on('exit', (code, signal) => {
        console.log(`[FnKeyService] Helper exited with code ${code}, signal ${signal}`)
        this.isRunning = false
        this.helperProcess = null
        this.emit('helper-exit', { code, signal })

        // Attempt to restart if unexpected exit
        if (code !== 0 && code !== null) {
          this.scheduleReconnect()
        }
      })

      this.helperProcess.on('error', (err) => {
        console.error('[FnKeyService] Helper process error:', err)
        this.emit('helper-error', err)
      })

      // Wait for socket to be created and connect
      await this.waitForSocket()
      return this.connectToSocket()
    } catch (err) {
      console.error('[FnKeyService] Failed to start helper:', err)
      this.isRunning = false
      this.emit('error', err)
      return false
    }
  }

  /**
   * Wait for the socket file to be created
   */
  private waitForSocket(timeout = 5000): Promise<void> {
    return new Promise((resolve, reject) => {
      const startTime = Date.now()

      const check = () => {
        if (fs.existsSync(SOCKET_PATH)) {
          resolve()
          return
        }

        if (Date.now() - startTime > timeout) {
          reject(new Error('Timeout waiting for socket'))
          return
        }

        setTimeout(check, 100)
      }

      check()
    })
  }

  /**
   * Connect to the helper's Unix socket
   */
  private connectToSocket(): boolean {
    try {
      this.socket = net.createConnection(SOCKET_PATH)

      this.socket.on('connect', () => {
        console.log('[FnKeyService] Connected to helper socket')
        this.isConnected = true
        this.reconnectAttempts = 0
        this.emit('connected')
      })

      this.socket.on('data', (data: Buffer) => {
        this.handleSocketData(data)
      })

      this.socket.on('close', () => {
        console.log('[FnKeyService] Socket closed')
        this.isConnected = false
        this.socket = null

        if (this.isRunning) {
          this.scheduleReconnect()
        }
      })

      this.socket.on('error', (err) => {
        console.error('[FnKeyService] Socket error:', err)
        this.emit('error', err)
      })

      return true
    } catch (err) {
      console.error('[FnKeyService] Failed to connect to socket:', err)
      return false
    }
  }

  /**
   * Handle incoming data from the socket
   */
  private handleSocketData(data: Buffer): void {
    // Append to buffer and process complete lines
    this.buffer += data.toString()

    const lines = this.buffer.split('\n')
    // Keep the last incomplete line in the buffer
    this.buffer = lines.pop() || ''

    for (const line of lines) {
      if (!line.trim()) continue

      try {
        const event: FnKeyEvent = JSON.parse(line)
        this.processEvent(event)
      } catch (err) {
        console.error('[FnKeyService] Failed to parse event:', line, err)
      }
    }
  }

  /**
   * Process a parsed event from the helper
   */
  private processEvent(event: FnKeyEvent): void {
    console.log('[FnKeyService] Event:', event.event)

    switch (event.event) {
      case 'fn-down':
        this.emit('fn-down', event.data)
        break
      case 'fn-up':
        this.emit('fn-up', event.data)
        break
      case 'ready':
        this.emit('ready')
        break
      case 'connected':
        // Internal event, already handled
        break
      default:
        console.log('[FnKeyService] Unknown event:', event.event)
    }
  }

  /**
   * Schedule a reconnection attempt
   */
  private scheduleReconnect(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
    }

    if (this.reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
      console.error('[FnKeyService] Max reconnect attempts reached')
      this.emit('error', new Error('Max reconnect attempts reached'))
      return
    }

    this.reconnectAttempts++
    console.log(`[FnKeyService] Reconnecting in ${RECONNECT_DELAY}ms (attempt ${this.reconnectAttempts})`)

    this.reconnectTimer = setTimeout(() => {
      if (this.isRunning && !this.isConnected) {
        this.connectToSocket()
      }
    }, RECONNECT_DELAY)
  }

  /**
   * Stop the FN key monitoring service
   */
  stop(): void {
    console.log('[FnKeyService] Stopping...')

    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }

    if (this.socket) {
      this.socket.destroy()
      this.socket = null
    }

    if (this.helperProcess) {
      this.helperProcess.kill('SIGTERM')
      this.helperProcess = null
    }

    this.isConnected = false
    this.isRunning = false

    // Clean up socket file
    try {
      if (fs.existsSync(SOCKET_PATH)) {
        fs.unlinkSync(SOCKET_PATH)
      }
    } catch {
      // Ignore cleanup errors
    }

    console.log('[FnKeyService] Stopped')
  }

  /**
   * Check if the service is currently running and connected
   */
  isActive(): boolean {
    return this.isRunning && this.isConnected
  }

  /**
   * Type-safe event emitter methods
   */
  on(event: FnKeyEventType, listener: (...args: unknown[]) => void): this {
    return super.on(event, listener)
  }

  once(event: FnKeyEventType, listener: (...args: unknown[]) => void): this {
    return super.once(event, listener)
  }

  off(event: FnKeyEventType, listener: (...args: unknown[]) => void): this {
    return super.off(event, listener)
  }
}

// Export singleton instance
export const fnKeyService = new FnKeyService()
