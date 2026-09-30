import Foundation
import AppKit
import IOKit
import IOKit.ps

// MARK: - Modelos

enum MemoryPressure {
    case normal, warning, critical

    var label: String {
        switch self {
        case .normal: return "Presión de memoria normal"
        case .warning: return "Presión de memoria alta"
        case .critical: return "Presión de memoria crítica"
        }
    }
}

struct BatteryInfo {
    var percent: Int
    var charging: Bool
    var onAC: Bool
    var cycles: Int?
    var temperature: Double?
}

struct MemoryInfo {
    var used: UInt64
    var free: UInt64
    var total: UInt64
}

struct DiskInfo {
    var free: Int64
    var total: Int64
}

// MARK: - Lecturas del sistema (API públicas de macOS)

enum SystemStats {
    private static let host = mach_host_self()

    /// Memoria usada como la calcula el Monitor de Actividad:
    /// memoria de apps + memoria fija (wired) + comprimida.
    static func memory() -> MemoryInfo? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(host, HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(getpagesize())
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let appPages = internalPages > purgeable ? internalPages - purgeable : 0
        let used = (appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        let free = UInt64(stats.free_count) * page
        return MemoryInfo(used: used, free: free, total: ProcessInfo.processInfo.physicalMemory)
    }

    static func memoryPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }

    static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    /// Espacio libre como lo muestra Finder (incluye lo que macOS puede purgar solo).
    static func disk() -> DiskInfo? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? home.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskInfo(free: free, total: Int64(total))
    }

    static func battery() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let onAC = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            var info = BatteryInfo(percent: percent, charging: charging, onAC: onAC, cycles: nil, temperature: nil)

            // Ciclos y temperatura de la batería (registro de IOKit).
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if service != 0 {
                if let cycles = registryInt(service, key: "CycleCount") {
                    info.cycles = cycles
                }
                if let raw = registryInt(service, key: "Temperature"), raw > 0 {
                    info.temperature = Double(raw) / 100.0
                }
                IOObjectRelease(service)
            }
            return info
        }
        return nil
    }

    private static func registryInt(_ service: io_service_t, key: String) -> Int? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return unmanaged.takeRetainedValue() as? Int
    }
}

// MARK: - Uso de CPU

final class CPUSampler {
    private let host = mach_host_self()
    private var previous: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    /// Porcentaje de uso (0…1) desde la lectura anterior.
    func usage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(host, HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let ticks = info.cpu_ticks
        let now = (user: ticks.0, system: ticks.1, idle: ticks.2, nice: ticks.3)
        defer { previous = now }
        guard let before = previous else { return nil }

        let user = Double(now.user &- before.user)
        let system = Double(now.system &- before.system)
        let idle = Double(now.idle &- before.idle)
        let nice = Double(now.nice &- before.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return (user + system + nice) / total
    }
}

// MARK: - Temperatura del chip

/// Lee los sensores de temperatura del chip Apple con una API interna de IOKit
/// (la misma que usan apps como "Stats"). Si macOS no la permite, devuelve nil
/// y la isla muestra la temperatura de la batería.
final class TemperatureReader {
    private typealias ClientCreateFn = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    private typealias SetMatchingFn = @convention(c) (UnsafeMutableRawPointer?, CFDictionary?) -> Int32
    private typealias CopyServicesFn = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    private typealias CopyPropertyFn = @convention(c) (UnsafeRawPointer?, CFString?) -> UnsafeMutableRawPointer?
    private typealias CopyEventFn = @convention(c) (UnsafeRawPointer?, Int64, Int32, Int64) -> UnsafeMutableRawPointer?
    private typealias GetFloatFn = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> Double

    private var client: UnsafeMutableRawPointer?
    private var copyServices: CopyServicesFn?
    private var copyProperty: CopyPropertyFn?
    private var copyEvent: CopyEventFn?
    private var getFloat: GetFloatFn?

    private static let temperatureEventType: Int64 = 15
    private static let temperatureField: UInt32 = 15 << 16

    init() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let createSymbol = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let matchingSymbol = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
              let servicesSymbol = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let propertySymbol = dlsym(handle, "IOHIDServiceClientCopyProperty"),
              let eventSymbol = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let floatSymbol = dlsym(handle, "IOHIDEventGetFloatValue") else { return }

        let create = unsafeBitCast(createSymbol, to: ClientCreateFn.self)
        let setMatching = unsafeBitCast(matchingSymbol, to: SetMatchingFn.self)
        guard let newClient = create(kCFAllocatorDefault) else { return }

        // Página de uso 0xFF00 / uso 5 = sensores de temperatura.
        let matching = ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 5] as CFDictionary
        _ = setMatching(newClient, matching)

        client = newClient
        copyServices = unsafeBitCast(servicesSymbol, to: CopyServicesFn.self)
        copyProperty = unsafeBitCast(propertySymbol, to: CopyPropertyFn.self)
        copyEvent = unsafeBitCast(eventSymbol, to: CopyEventFn.self)
        getFloat = unsafeBitCast(floatSymbol, to: GetFloatFn.self)
    }

    /// Promedio de los sensores del chip en °C, o nil si no hay lectura.
    func chipTemperature() -> Double? {
        guard let client = client,
              let copyServices = copyServices,
              let copyProperty = copyProperty,
              let copyEvent = copyEvent,
              let getFloat = getFloat,
              let servicesPointer = copyServices(client) else { return nil }

        let services = Unmanaged<CFArray>.fromOpaque(servicesPointer).takeRetainedValue()
        var chip: [Double] = []
        var others: [Double] = []

        for index in 0..<CFArrayGetCount(services) {
            guard let service = CFArrayGetValueAtIndex(services, index) else { continue }

            var name = ""
            if let namePointer = copyProperty(service, "Product" as CFString) {
                let value = Unmanaged<AnyObject>.fromOpaque(namePointer).takeRetainedValue()
                name = (value as? String) ?? ""
            }

            guard let eventPointer = copyEvent(service, TemperatureReader.temperatureEventType, 0, 0) else { continue }
            let celsius = getFloat(eventPointer, TemperatureReader.temperatureField)
            Unmanaged<AnyObject>.fromOpaque(eventPointer).release()

            guard celsius > 5, celsius < 130 else { continue }
            let lower = name.lowercased()
            if lower.contains("battery") || lower.contains("gas gauge") || lower.contains("nand") { continue }
            if lower.contains("tdie") || lower.contains("mtr") || lower.contains("cpu") || lower.contains("soc") {
                chip.append(celsius)
            } else {
                others.append(celsius)
            }
        }

        let pool = chip.isEmpty ? others : chip
        guard !pool.isEmpty else { return nil }
        return pool.reduce(0, +) / Double(pool.count)
    }
}

// MARK: - Memoria por app

struct AppCandidate {
    let pid: pid_t
    let name: String
    let bundlePath: String
}

struct AppMemoryTotal {
    let pid: pid_t
    let name: String
    let bytes: UInt64
}

enum ProcessMemory {
    /// Suma la memoria de cada app incluyendo sus procesos auxiliares
    /// (Chrome, Slack, VS Code, etc. reparten su memoria en varios procesos).
    static func totals(for apps: [AppCandidate]) -> [AppMemoryTotal] {
        let prefixes = apps.map { $0.bundlePath.hasSuffix("/") ? $0.bundlePath : $0.bundlePath + "/" }
        var sums = [UInt64](repeating: 0, count: apps.count)

        for pid in allPIDs() {
            guard let path = executablePath(of: pid),
                  let index = prefixes.firstIndex(where: { path.hasPrefix($0) }) else { continue }
            sums[index] += footprint(of: pid)
        }

        var result: [AppMemoryTotal] = []
        for (index, app) in apps.enumerated() {
            result.append(AppMemoryTotal(pid: app.pid, name: app.name, bytes: sums[index]))
        }
        return result.sorted { $0.bytes > $1.bytes }
    }

    private static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { buffer -> Int32 in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count))).filter { $0 > 0 }
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// "Memoria" tal como la muestra el Monitor de Actividad.
    private static func footprint(of pid: pid_t) -> UInt64 {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }
        return result == 0 ? info.ri_phys_footprint : 0
    }
}
