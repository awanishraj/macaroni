import Foundation
import IOKit
import Combine
import os.log

private let logger = Logger(subsystem: "com.macaroni.app", category: "ThermalService")

/// Chip generation for reference
enum AppleSiliconChip: String, CaseIterable {
    case m1 = "M1"
    case m2 = "M2"
    case m3 = "M3"
    case m4 = "M4"
    case unknown = "Unknown"
}

/// Service for reading CPU temperature on Apple Silicon via IOHIDEventSystem
final class ThermalService: ObservableObject {
    @Published private(set) var cpuTemperature: Double?
    @Published private(set) var chipGeneration: AppleSiliconChip = .unknown
    @Published private(set) var isAvailable: Bool = false

    private var updateTimer: Timer?

    // IOHIDEventSystem types and functions (private API)
    private var hidEventSystem: AnyObject?

    init() {
        detectChipGeneration()
        isAvailable = isAppleSilicon()
        if isAvailable {
            setupHIDEventSystem()
            startMonitoring()
        }
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Public API

    func refresh() {
        if isAvailable {
            cpuTemperature = readTemperatureFromHID()
        }
    }

    func startMonitoring() {
        guard isAvailable else { return }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func stopMonitoring() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Chip Detection

    private func detectChipGeneration() {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)

        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)

        let brandString = String(cString: brand).lowercased()

        if brandString.contains("m4") {
            chipGeneration = .m4
        } else if brandString.contains("m3") {
            chipGeneration = .m3
        } else if brandString.contains("m2") {
            chipGeneration = .m2
        } else if brandString.contains("m1") {
            chipGeneration = .m1
        } else {
            chipGeneration = .unknown
        }
    }

    private func isAppleSilicon() -> Bool {
        var sysinfo = utsname()
        uname(&sysinfo)

        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }

        return machine.hasPrefix("arm64")
    }

    // MARK: - IOHIDEventSystem Temperature Reading

    // Function pointer types
    private typealias IOHIDEventSystemClientCreateFunc = @convention(c) (CFAllocator?) -> AnyObject?
    private typealias IOHIDEventSystemClientCopyServicesFunc = @convention(c) (AnyObject) -> CFArray?
    private typealias IOHIDServiceClientCopyPropertyFunc = @convention(c) (AnyObject, CFString) -> AnyObject?
    private typealias IOHIDServiceClientCopyEventFunc = @convention(c) (AnyObject, Int64, Int32, Int64) -> AnyObject?
    private typealias IOHIDEventGetFloatValueFunc = @convention(c) (AnyObject, Int32) -> Double

    private func setupHIDEventSystem() {
        // Get IOHIDEventSystemClient using private API
        guard let sym = dlsym(dlopen(nil, RTLD_LAZY), "IOHIDEventSystemClientCreate") else {
            logger.error("Failed to get IOHIDEventSystemClientCreate")
            return
        }

        let clientCreate = unsafeBitCast(sym, to: IOHIDEventSystemClientCreateFunc.self)
        hidEventSystem = clientCreate(kCFAllocatorDefault)
    }

    private func readTemperatureFromHID() -> Double? {
        guard let hidSystem = hidEventSystem else {
            return readTemperatureFromSMC()
        }

        // IOHIDEventSystemClientCopyServices
        guard let copyServicesSym = dlsym(dlopen(nil, RTLD_LAZY), "IOHIDEventSystemClientCopyServices") else {
            return readTemperatureFromSMC()
        }
        let copyServices = unsafeBitCast(copyServicesSym, to: IOHIDEventSystemClientCopyServicesFunc.self)

        guard let services = copyServices(hidSystem) as? [AnyObject] else {
            return readTemperatureFromSMC()
        }

        // IOHIDServiceClientCopyProperty
        guard let copyPropertySym = dlsym(dlopen(nil, RTLD_LAZY), "IOHIDServiceClientCopyProperty") else {
            return readTemperatureFromSMC()
        }
        let copyProperty = unsafeBitCast(copyPropertySym, to: IOHIDServiceClientCopyPropertyFunc.self)

        // IOHIDServiceClientCopyEvent
        guard let copyEventSym = dlsym(dlopen(nil, RTLD_LAZY), "IOHIDServiceClientCopyEvent") else {
            return readTemperatureFromSMC()
        }
        let copyEvent = unsafeBitCast(copyEventSym, to: IOHIDServiceClientCopyEventFunc.self)

        // IOHIDEventGetFloatValue
        guard let getFloatValueSym = dlsym(dlopen(nil, RTLD_LAZY), "IOHIDEventGetFloatValue") else {
            return readTemperatureFromSMC()
        }
        let getFloatValue = unsafeBitCast(getFloatValueSym, to: IOHIDEventGetFloatValueFunc.self)

        var temperatures: [Double] = []

        for service in services {
            // Check if this is a temperature sensor
            if let product = copyProperty(service, "Product" as CFString) as? String {
                let productLower = product.lowercased()

                // Look for CPU-related temperature sensors
                if productLower.contains("cpu") ||
                   productLower.contains("soc") ||
                   productLower.contains("die") ||
                   productLower.contains("pmgr") {

                    // kIOHIDEventTypeTemperature = 15
                    if let event = copyEvent(service, 15, 0, 0) {
                        // kIOHIDEventFieldTemperatureLevel = 0xF0000
                        let temp = getFloatValue(event, 0xF << 16)
                        if temp > 0 && temp < 150 {
                            temperatures.append(temp)
                        }
                    }
                }
            }
        }

        // Return average CPU temperature, or max if we want worst-case
        if !temperatures.isEmpty {
            return temperatures.max()
        }

        // Fallback to SMC
        return readTemperatureFromSMC()
    }

    // MARK: - SMC Fallback

    private var smcConnection: io_connect_t = 0

    private func readTemperatureFromSMC() -> Double? {
        // Try to connect to SMC if not already
        if smcConnection == 0 {
            let service = IOServiceGetMatchingService(
                kIOMainPortDefault,
                IOServiceMatching("AppleSMC")
            )
            guard service != 0 else { return nil }

            let result = IOServiceOpen(service, mach_task_self_, 0, &smcConnection)
            IOObjectRelease(service)

            if result != KERN_SUCCESS {
                smcConnection = 0
                return nil
            }
        }

        // Try temperature keys
        let keys = ["TC0P", "TC0D", "TC0E", "TC0F", "Tp01", "Tp1h", "Tf04"]
        for key in keys {
            if let temp = readSMCKey(key) {
                return temp
            }
        }

        return nil
    }

    private func readSMCKey(_ key: String) -> Double? {
        guard smcConnection != 0 else { return nil }

        var inputStruct = SMCKeyData()
        var outputStruct = SMCKeyData()

        inputStruct.key = stringToFourCharCode(key)
        inputStruct.data8 = 9 // readKeyInfo

        var outputSize = MemoryLayout<SMCKeyData>.size

        var result = IOConnectCallStructMethod(
            smcConnection,
            2, // handleYPCEvent
            &inputStruct,
            MemoryLayout<SMCKeyData>.size,
            &outputStruct,
            &outputSize
        )

        guard result == KERN_SUCCESS else { return nil }

        inputStruct.keyInfo.dataSize = outputStruct.keyInfo.dataSize
        inputStruct.keyInfo.dataType = outputStruct.keyInfo.dataType
        inputStruct.data8 = 5 // readKey

        result = IOConnectCallStructMethod(
            smcConnection,
            2,
            &inputStruct,
            MemoryLayout<SMCKeyData>.size,
            &outputStruct,
            &outputSize
        )

        guard result == KERN_SUCCESS else { return nil }

        // Parse sp78 format
        if outputStruct.keyInfo.dataType == stringToFourCharCode("sp78") {
            let value = (Int16(outputStruct.bytes.0) << 8) | Int16(outputStruct.bytes.1)
            let temp = Double(value) / 256.0
            if temp > 0 && temp < 150 {
                return temp
            }
        }

        // Parse flt format
        if outputStruct.keyInfo.dataType == stringToFourCharCode("flt ") {
            var floatValue: Float = 0
            withUnsafeMutableBytes(of: &floatValue) { ptr in
                ptr[0] = outputStruct.bytes.0
                ptr[1] = outputStruct.bytes.1
                ptr[2] = outputStruct.bytes.2
                ptr[3] = outputStruct.bytes.3
            }
            let temp = Double(floatValue)
            if temp > 0 && temp < 150 {
                return temp
            }
        }

        return nil
    }

    private func stringToFourCharCode(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for char in string.prefix(4).utf8 {
            result = (result << 8) | UInt32(char)
        }
        let padding = 4 - min(string.count, 4)
        for _ in 0..<padding {
            result = (result << 8) | UInt32(0x20)
        }
        return result
    }
}

// MARK: - SMC Data Structures

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0)
    var pLimitData: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                     UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0,
                                                                                 0, 0, 0, 0, 0, 0, 0, 0)
    var keyInfo: SMCKeyInfoData = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0,
                                                                            0, 0, 0, 0, 0, 0, 0, 0,
                                                                            0, 0, 0, 0, 0, 0, 0, 0,
                                                                            0, 0, 0, 0, 0, 0, 0, 0)
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}
