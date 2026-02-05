import Foundation
import QuartzCore

// MARK: - Performance Profiler

/// Servicio para medir y analizar performance
class PerformanceProfiler {
    
    // MARK: - Singleton
    
    static let shared = PerformanceProfiler()
    
    // MARK: - State
    
    private var measurements: [String: [TimeInterval]] = [:]
    private var memorySnapshots: [String: (memoryUsage: UInt64, timestamp: Date)] = [:]
    
    // MARK: - Timing Measurements
    
    func measure<T>(
        operation: String,
        block: () async throws -> T
    ) async throws -> T {
        let startTime = Date()
        let result = try await block()
        let duration = Date().timeIntervalSince(startTime)
        
        recordTiming(operation: operation, duration: duration)
        return result
    }
    
    func measureSync<T>(
        operation: String,
        block: () throws -> T
    ) throws -> T {
        let startTime = Date()
        let result = try block()
        let duration = Date().timeIntervalSince(startTime)
        
        recordTiming(operation: operation, duration: duration)
        return result
    }
    
    private func recordTiming(operation: String, duration: TimeInterval) {
        if measurements[operation] == nil {
            measurements[operation] = []
        }
        measurements[operation]?.append(duration)
        
        // Log si es lento (>100ms)
        if duration > 0.1 {
            print("⚠️ Operación lenta '\(operation)': \(String(format: "%.2f", duration * 1000))ms")
        }
    }
    
    // MARK: - Memory Monitoring
    
    func captureMemory(label: String) {
        let memoryUsage = getMemoryUsage()
        memorySnapshots[label] = (memoryUsage, Date())
        print("💾 Memoria [\(label)]: \(formatBytes(memoryUsage))")
    }
    
    private func getMemoryUsage() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size)/4
        
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        
        guard kerr == KERN_SUCCESS else { return 0 }
        return UInt64(info.phys_footprint)
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .decimal
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // MARK: - Report Generation
    
    func generateReport() -> String {
        var report = "📊 Performance Report\n"
        report += "======================\n\n"
        
        // Timing stats
        report += "⏱️  Timing Statistics:\n"
        for (operation, timings) in measurements.sorted(by: { $0.key < $1.key }) {
            let average = timings.reduce(0, +) / Double(timings.count)
            let min = timings.min() ?? 0
            let max = timings.max() ?? 0
            let count = timings.count
            
            report += "  \(operation): avg=\(String(format: "%.2f", average * 1000))ms, min=\(String(format: "%.2f", min * 1000))ms, max=\(String(format: "%.2f", max * 1000))ms, count=\(count)\n"
        }
        
        // Memory snapshots
        report += "\n💾 Memory Snapshots:\n"
        for (label, snapshot) in memorySnapshots.sorted(by: { $0.key < $1.key }) {
            report += "  \(label): \(formatBytes(snapshot.memoryUsage))\n"
        }
        
        return report
    }
    
    func reset() {
        measurements.removeAll()
        memorySnapshots.removeAll()
    }
}

// MARK: - FPS Monitor

#if canImport(UIKit)
/// Monitor de FPS para detectar stutters (iOS)
final class FPSMonitor: ObservableObject {
    
    static let shared = FPSMonitor()
    
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount = 0
    private var frameTimes: [CFTimeInterval] = []
    
    @Published private(set) var currentFPS: Double = 60.0
    @Published private(set) var droppedFrames = 0
    
    private init() {}
    
    func start() {
        displayLink = CADisplayLink(target: self, selector: #selector(update))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func update(displayLink: CADisplayLink) {
        let deltaTime = displayLink.timestamp - lastTimestamp
        lastTimestamp = displayLink.timestamp
        
        frameTimes.append(deltaTime)
        frameCount += 1
        
        // Calcular FPS cada segundo
        if frameCount >= 60 {
            let averageFrameTime = frameTimes.reduce(0, +) / Double(frameTimes.count)
            let fps = 1.0 / averageFrameTime
            currentFPS = fps
            
            // Detectar dropped frames
            let slowFrames = frameTimes.filter { $0 > (1.0 / 55.0) }.count
            droppedFrames = slowFrames
            
            if slowFrames > 0 {
                print("⚠️  Dropped \(slowFrames) frames in last second (FPS: \(String(format: "%.1f", fps)))")
            }
            
            frameTimes.removeAll()
            frameCount = 0
        }
    }
}
#else
/// Stub para macOS (sin CADisplayLink)
final class FPSMonitor: ObservableObject {
    static let shared = FPSMonitor()
    @Published private(set) var currentFPS: Double = 60.0
    @Published private(set) var droppedFrames = 0
    private init() {}
    func start() {}
    func stop() {}
}
#endif

// MARK: - Mach Time Helper

import Darwin

extension CFTimeInterval {
    var milliseconds: String {
        String(format: "%.2f", self * 1000)
    }
}
