import Foundation
import IOKit
import Darwin

/// All probes run on one background queue. No child processes or elevated privileges.
final class SystemSampler: @unchecked Sendable {
    private var previousTicks: (UInt64, UInt64)?
    private var previousProcess: (pid_t, UInt64, TimeInterval)?
    private var previousSelf: (UInt64, TimeInterval)?
    private let host = mach_host_self()
    private var accelerator: io_service_t = 0

    deinit {
        mach_port_deallocate(mach_task_self_, host)
        if accelerator != 0 { IOObjectRelease(accelerator) }
    }

    func sample(pid: pid_t?) -> Metrics {
        var metrics = Metrics()
        metrics.cpu = cpu()
        metrics.memoryUsed = memory()
        metrics.swapUsed = swap()
        metrics.memoryPressure = pressure()
        metrics.gpu = gpu()
        var own = rusage_info_v2()
        let ownResult = withUnsafeMutablePointer(to: &own) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V2, $0)
            }
        }
        if ownResult == 0 {
            let now = ProcessInfo.processInfo.systemUptime
            let ticks = own.ri_user_time + own.ri_system_time
            if let last = previousSelf, ticks >= last.0, now > last.1 {
                metrics.monitorCPU = Double(ticks - last.0) / 1_000_000_000 / (now - last.1) * 100
            }
            previousSelf = (ticks, now)
            metrics.monitorMemory = Double(own.ri_resident_size) / 1_048_576
        }
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: metrics.thermalState = "Nominal"
        case .fair: metrics.thermalState = "Fair"
        case .serious: metrics.thermalState = "Serious"
        case .critical: metrics.thermalState = "Critical"
        @unknown default: metrics.thermalState = "Unknown"
        }
        if let pid {
            var usage = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            if result == 0 {
                let time = ProcessInfo.processInfo.systemUptime
                let ticks = usage.ri_user_time + usage.ri_system_time
                metrics.robloxMemory = Double(usage.ri_resident_size) / 1_073_741_824
                if let last = previousProcess, last.0 == pid, ticks >= last.1, time > last.2 {
                    // 100% = one CPU core, matching Activity Monitor's process convention.
                    metrics.robloxCPU = Double(ticks - last.1) / 1_000_000_000 / (time - last.2) * 100
                }
                previousProcess = (pid, ticks, time)
            } else { previousProcess = nil }
        } else { previousProcess = nil }
        return metrics
    }

    private func cpu() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        let idle = UInt64(ticks.2)
        let total = UInt64(ticks.0) + UInt64(ticks.1) + idle + UInt64(ticks.3)
        defer { previousTicks = (total, idle) }
        guard let last = previousTicks, total > last.0, idle >= last.1 else { return nil }
        return min(100, max(0, (1 - Double(idle - last.1) / Double(total - last.0)) * 100))
    }

    private func memory() -> Double? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // App memory + wired + compressed; subtract purgeable cached app pages.
        let pages = UInt64(info.active_count) + UInt64(info.inactive_count)
            + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        let reclaimable = UInt64(info.purgeable_count) + UInt64(info.external_page_count)
        let used = pages > reclaimable ? pages - reclaimable : 0
        return min(Double(ProcessInfo.processInfo.physicalMemory), Double(used) * Double(vm_kernel_page_size)) / 1_073_741_824
    }

    private func swap() -> Double? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return Double(usage.xsu_used) / 1_073_741_824
    }

    private func pressure() -> String {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 else { return "Unknown" }
        switch value { case 1: return "Normal"; case 2: return "Warning"; case 4: return "Critical"; default: return "Unknown" }
    }

    private func gpu() -> Double? {
        if accelerator == 0 { accelerator = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator")) }
        guard accelerator != 0,
              let properties = IORegistryEntryCreateCFProperty(accelerator, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSDictionary
        else { return nil }
        for key in ["Device Utilization %", "GPU Activity(%)", "GPU Core Utilization", "Renderer Utilization %"] {
            if let number = properties[key] as? NSNumber { return min(100, max(0, number.doubleValue)) }
        }
        return nil
    }
}
