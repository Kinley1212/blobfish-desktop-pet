import Darwin
import Foundation

struct PerformanceSample: Equatable {
    let systemCPUPercent: Double
    let systemRAMPercent: Double
    let appCPUPercent: Double
    let appRAMPercent: Double
    let appMemoryMB: Double

    static let zero = PerformanceSample(
        systemCPUPercent: 0,
        systemRAMPercent: 0,
        appCPUPercent: 0,
        appRAMPercent: 0,
        appMemoryMB: 0
    )
}

enum PerformanceMath {
    static func processCPUPercent(
        cpuTimeDelta: TimeInterval,
        elapsed: TimeInterval,
        logicalProcessorCount: Int
    ) -> Double {
        guard cpuTimeDelta.isFinite, cpuTimeDelta >= 0, elapsed.isFinite, elapsed > 0 else { return 0 }
        let capacity = elapsed * Double(max(1, logicalProcessorCount))
        return min(100, max(0, cpuTimeDelta / capacity * 100))
    }

    static func systemRAMPercent(
        activePages: UInt64,
        inactivePages: UInt64,
        wiredPages: UInt64,
        compressedPages: UInt64,
        fileBackedPages: UInt64,
        purgeablePages: UInt64,
        pageSize: UInt64,
        physicalMemory: UInt64
    ) -> Double {
        guard pageSize > 0, physicalMemory > 0 else { return 0 }
        let residentPages = activePages + inactivePages + wiredPages + compressedPages
        let reclaimablePages = min(residentPages, fileBackedPages + purgeablePages)
        let usedBytes = Double(residentPages - reclaimablePages) * Double(pageSize)
        return min(100, max(0, usedBytes / Double(physicalMemory) * 100))
    }

    static func appRAMPercent(appMemoryMB: Double, physicalMemory: UInt64) -> Double {
        guard appMemoryMB.isFinite, appMemoryMB >= 0, physicalMemory > 0 else { return 0 }
        return min(100, max(0, appMemoryMB * 1_048_576 / Double(physicalMemory) * 100))
    }
}

enum PerformanceMonitoringPolicy: Equatable {
    case disabled
    case memoryOnly
    case full

    static func resolve(panelEnabled: Bool, autoQuitEnabled: Bool) -> Self {
        if panelEnabled { return .full }
        if autoQuitEnabled { return .memoryOnly }
        return .disabled
    }

    var schedulesTimer: Bool { self != .disabled }
    var collectsSystemMetrics: Bool { self == .full }
}

final class PerformanceMonitor {
    var onSample: ((PerformanceSample) -> Void)?
    var onSustainedMemoryLimit: (() -> Void)?
    var memoryLimitMB = 1024.0
    var autoQuitEnabled = false {
        didSet {
            if !autoQuitEnabled { memoryExceededAt = nil }
        }
    }
    var policy = PerformanceMonitoringPolicy.disabled {
        didSet {
            guard oldValue != policy else { return }
            timer?.invalidate()
            timer = nil
            resetCPUBaseline()
            if policy == .disabled { memoryExceededAt = nil }
            syncTimer()
        }
    }

    private var timer: Timer?
    private var isRunning = false
    private var previousCPU: (idle: UInt64, total: UInt64)?
    private var previousProcessCPU: TimeInterval?
    private var previousDate: Date?
    private var memoryExceededAt: Date?

    deinit {
        timer?.invalidate()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        resetCPUBaseline()
        syncTimer()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        resetCPUBaseline()
        memoryExceededAt = nil
    }

    private func syncTimer() {
        guard isRunning else { return }
        guard policy.schedulesTimer else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        sample()
        guard isRunning, policy.schedulesTimer, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.sample()
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func resetCPUBaseline() {
        previousCPU = nil
        previousProcessCPU = nil
        previousDate = nil
    }

    private func sample() {
        guard policy.schedulesTimer else { return }
        let now = Date()
        let appMemory = readAppMemoryMB()
        if policy.collectsSystemMetrics {
            let cpu = readSystemCPU()
            let processCPUTime = readProcessCPUTime()
            let processCPU: Double
            if let prior = previousProcessCPU, let priorDate = previousDate {
                processCPU = PerformanceMath.processCPUPercent(
                    cpuTimeDelta: processCPUTime - prior,
                    elapsed: now.timeIntervalSince(priorDate),
                    logicalProcessorCount: ProcessInfo.processInfo.activeProcessorCount
                )
            } else { processCPU = 0 }
            previousProcessCPU = processCPUTime; previousDate = now
            let memory = readSystemMemoryPercent()
            let value = PerformanceSample(
                systemCPUPercent: cpu,
                systemRAMPercent: memory,
                appCPUPercent: processCPU,
                appRAMPercent: PerformanceMath.appRAMPercent(
                    appMemoryMB: appMemory,
                    physicalMemory: ProcessInfo.processInfo.physicalMemory
                ),
                appMemoryMB: appMemory
            )
            onSample?(value)
        }

        if autoQuitEnabled, appMemory >= memoryLimitMB {
            if memoryExceededAt == nil { memoryExceededAt = now }
            if let start = memoryExceededAt, now.timeIntervalSince(start) >= 180 {
                memoryExceededAt = nil
                onSustainedMemoryLimit?()
            }
        } else { memoryExceededAt = nil }
    }

    private func readSystemCPU() -> Double {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3].map(UInt64.init)
        let idle = ticks[Int(CPU_STATE_IDLE)], total = ticks.reduce(0, +)
        defer { previousCPU = (idle, total) }
        guard let previousCPU, total > previousCPU.total else { return 0 }
        let totalDelta = total - previousCPU.total
        return Double(totalDelta - min(totalDelta, idle - min(idle, previousCPU.idle))) / Double(totalDelta) * 100
    }

    private func readSystemMemoryPercent() -> Double {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return PerformanceMath.systemRAMPercent(
            activePages: UInt64(info.active_count),
            inactivePages: UInt64(info.inactive_count),
            wiredPages: UInt64(info.wire_count),
            compressedPages: UInt64(info.compressor_page_count),
            fileBackedPages: UInt64(info.external_page_count),
            purgeablePages: UInt64(info.purgeable_count),
            pageSize: UInt64(pageSize),
            physicalMemory: ProcessInfo.processInfo.physicalMemory
        )
    }

    private func readAppMemoryMB() -> Double {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }

    private func readProcessCPUTime() -> TimeInterval {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return TimeInterval(usage.ru_utime.tv_sec) + TimeInterval(usage.ru_utime.tv_usec) / 1_000_000
            + TimeInterval(usage.ru_stime.tv_sec) + TimeInterval(usage.ru_stime.tv_usec) / 1_000_000
    }
}
