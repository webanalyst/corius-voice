import Cocoa
import Foundation

// MARK: - Configuration
let socketPath = "/tmp/corius-fnkey.sock"

// MARK: - Socket Server
class SocketServer {
    private var serverSocket: Int32 = -1
    private var clientSockets: [Int32] = []
    private let queue = DispatchQueue(label: "socket.server", qos: .userInteractive)

    func start() -> Bool {
        // Remove existing socket file
        unlink(socketPath)

        // Create socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            log("Failed to create socket: \(errno)")
            return false
        }

        // Configure socket address
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        // Copy path to sun_path
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            pathBytes.withUnsafeBufferPointer { buffer in
                raw.copyMemory(from: buffer.baseAddress!, byteCount: min(buffer.count, 104))
            }
        }

        // Bind socket
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            log("Failed to bind socket: \(errno)")
            close(serverSocket)
            return false
        }

        // Listen for connections
        guard listen(serverSocket, 5) == 0 else {
            log("Failed to listen: \(errno)")
            close(serverSocket)
            return false
        }

        // Set socket permissions
        chmod(socketPath, 0o777)

        log("Socket server listening on \(socketPath)")

        // Accept connections in background
        queue.async { [weak self] in
            self?.acceptLoop()
        }

        return true
    }

    private func acceptLoop() {
        while serverSocket >= 0 {
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    accept(serverSocket, sockaddrPtr, &clientAddrLen)
                }
            }

            if clientSocket >= 0 {
                log("Client connected: \(clientSocket)")
                clientSockets.append(clientSocket)

                // Send initial connection message
                send(event: "connected")
            }
        }
    }

    func send(event: String, data: [String: Any]? = nil) {
        var message: [String: Any] = ["event": event]
        if let data = data {
            message["data"] = data
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              var jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        jsonString += "\n"

        // Send to all connected clients
        let invalidSockets = clientSockets.filter { socket in
            let bytes = Array(jsonString.utf8)
            let sent = Darwin.send(socket, bytes, bytes.count, 0)
            return sent <= 0
        }

        // Remove disconnected clients
        clientSockets.removeAll { invalidSockets.contains($0) }
    }

    func stop() {
        for socket in clientSockets {
            close(socket)
        }
        clientSockets.removeAll()

        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }

        unlink(socketPath)
    }
}

// MARK: - FN Key Monitor
class FnKeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isFnPressed = false
    private let socketServer: SocketServer

    init(socketServer: SocketServer) {
        self.socketServer = socketServer
    }

    func start() -> Bool {
        // Check accessibility permissions
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        if !accessEnabled {
            log("WARNING: Accessibility access not granted. Please enable in System Preferences.")
            log("System Preferences → Privacy & Security → Accessibility")
            // Continue anyway - some events might still work
        }

        // Monitor flags changed events (modifier keys including FN)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Also add local monitor for when app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        guard globalMonitor != nil else {
            log("Failed to create global event monitor")
            log("Make sure Input Monitoring is enabled in System Preferences")
            return false
        }

        log("FN key monitor started successfully")
        return true
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let fnPressed = event.modifierFlags.contains(.function)

        if fnPressed && !isFnPressed {
            // FN key pressed
            isFnPressed = true
            log("FN key DOWN")
            socketServer.send(event: "fn-down", data: ["timestamp": Date().timeIntervalSince1970])
        } else if !fnPressed && isFnPressed {
            // FN key released
            isFnPressed = false
            log("FN key UP")
            socketServer.send(event: "fn-up", data: ["timestamp": Date().timeIntervalSince1970])
        }
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
    }
}

// MARK: - Logging
func log(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] \(message)"
    FileHandle.standardError.write(Data((logMessage + "\n").utf8))
}

// MARK: - Global State for Cleanup
private var globalSocketServer: SocketServer?
private var globalFnMonitor: FnKeyMonitor?

// MARK: - Signal Handling
func setupSignalHandlers() {
    signal(SIGINT) { _ in
        performCleanup()
        exit(0)
    }

    signal(SIGTERM) { _ in
        performCleanup()
        exit(0)
    }
}

func performCleanup() {
    log("Cleaning up...")
    globalFnMonitor?.stop()
    globalSocketServer?.stop()
}

// MARK: - Main
func main() {
    log("FnKeyHelper starting...")
    log("macOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)")

    // Parse arguments
    let args = CommandLine.arguments
    if args.contains("--help") || args.contains("-h") {
        print("""
        FnKeyHelper - Monitors FN key events and broadcasts via Unix socket

        Usage: FnKeyHelper [options]

        Options:
          --help, -h    Show this help message
          --version     Show version

        The helper listens on: \(socketPath)

        Events sent (JSON format):
          {"event": "fn-down", "data": {"timestamp": 1234567890.123}}
          {"event": "fn-up", "data": {"timestamp": 1234567890.456}}

        Requirements:
          - Accessibility access (System Preferences → Privacy & Security → Accessibility)
          - Input Monitoring (System Preferences → Privacy & Security → Input Monitoring)
        """)
        exit(0)
    }

    if args.contains("--version") {
        print("FnKeyHelper 1.0.0")
        exit(0)
    }

    // Start socket server
    let socketServer = SocketServer()
    globalSocketServer = socketServer
    guard socketServer.start() else {
        log("Failed to start socket server")
        exit(1)
    }

    // Start FN key monitor
    let fnMonitor = FnKeyMonitor(socketServer: socketServer)
    globalFnMonitor = fnMonitor
    guard fnMonitor.start() else {
        log("Failed to start FN key monitor")
        socketServer.stop()
        exit(1)
    }

    // Setup signal handlers for cleanup
    setupSignalHandlers()

    log("FnKeyHelper ready - waiting for FN key events...")
    socketServer.send(event: "ready")

    // Run the main loop
    RunLoop.main.run()
}

main()
