import Foundation
import IOKit

/// SMC command selectors
private enum SMCSelector: UInt8 {
    case readKey = 5
    case writeKey = 6
    case getKeyInfo = 9
}

/// SMC service for reading/writing fan and thermal data
final class SMCWriteService {
    static let shared = SMCWriteService()

    private var connection: io_connect_t = 0
    private let queue = DispatchQueue(label: "com.macaroni.smc", qos: .userInteractive)

    // SMC Keys for fan control
    private enum FanKeys {
        static let fanCount = "FNum"
        static let forcedMask = "FS! "      // Force fan bits - Intel/older Macs

        // Per-fan keys (replace 0 with fan index)
        static func actualRPM(_ index: Int) -> String { "F\(index)Ac" }
        static func minRPM(_ index: Int) -> String { "F\(index)Mn" }
        static func maxRPM(_ index: Int) -> String { "F\(index)Mx" }
        static func targetRPM(_ index: Int) -> String { "F\(index)Tg" }
        static func fanMode(_ index: Int) -> String { "F\(index)Md" }  // Fan mode (Apple Silicon)
    }

    private init() {
        connect()
    }

    deinit {
        disconnect()
    }

    // MARK: - Connection Management

    @discardableResult
    private func connect() -> Bool {
        guard connection == 0 else { return true }

        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )

        guard service != 0 else { return false }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)

        return result == KERN_SUCCESS
    }

    private func disconnect() {
        guard connection != 0 else { return }
        IOServiceClose(connection)
        connection = 0
    }

    // MARK: - Public API

    /// Get number of fans in the system
    func getFanCount() -> Int {
        guard let data = readKey(FanKeys.fanCount), !data.isEmpty else { return 0 }
        return Int(data[0])
    }

    /// Get current actual fan RPM
    func getActualRPM(fanIndex: Int) -> Int? {
        return readFanRPM(FanKeys.actualRPM(fanIndex))
    }

    /// Get minimum fan RPM
    func getMinRPM(fanIndex: Int) -> Int? {
        return readFanRPM(FanKeys.minRPM(fanIndex))
    }

    /// Get maximum fan RPM
    func getMaxRPM(fanIndex: Int) -> Int? {
        return readFanRPM(FanKeys.maxRPM(fanIndex))
    }

    /// Get target fan RPM
    func getTargetRPM(fanIndex: Int) -> Int? {
        return readFanRPM(FanKeys.targetRPM(fanIndex))
    }

    /// Set target fan RPM (requires forced mode enabled)
    func setTargetRPM(_ rpm: Int, fanIndex: Int) -> Bool {
        return writeFanRPM(FanKeys.targetRPM(fanIndex), value: rpm)
    }

    /// Enable forced mode for a specific fan
    func enableForcedMode(fanIndex: Int) -> Bool {
        // Try method 1: F0Md (per-fan mode) - used on Apple Silicon Macs
        if let modeData = readKey(FanKeys.fanMode(fanIndex)), modeData.count == 1 {
            if writeKey(FanKeys.fanMode(fanIndex), data: [1]) {
                return true
            }
        }

        // Try method 2: FS! (global forced mask) - used on Intel Macs
        if let currentMask = readKey(FanKeys.forcedMask), currentMask.count >= 2 {
            var mask = UInt16(currentMask[0]) << 8 | UInt16(currentMask[1])
            mask |= UInt16(1 << fanIndex)
            let data: [UInt8] = [UInt8((mask >> 8) & 0xFF), UInt8(mask & 0xFF)]
            if writeKey(FanKeys.forcedMask, data: data) {
                return true
            }
        }

        // Fallback: assume direct RPM control is available
        return true
    }

    /// Disable forced mode for a specific fan
    func disableForcedMode(fanIndex: Int) -> Bool {
        // Try F0Md first (Apple Silicon)
        if let modeData = readKey(FanKeys.fanMode(fanIndex)), modeData.count == 1 {
            if writeKey(FanKeys.fanMode(fanIndex), data: [0]) {
                return true
            }
        }

        // Try FS! (Intel)
        if let currentMask = readKey(FanKeys.forcedMask), currentMask.count >= 2 {
            var mask = UInt16(currentMask[0]) << 8 | UInt16(currentMask[1])
            mask &= ~UInt16(1 << fanIndex)
            let data: [UInt8] = [UInt8((mask >> 8) & 0xFF), UInt8(mask & 0xFF)]
            return writeKey(FanKeys.forcedMask, data: data)
        }

        return writeKey(FanKeys.forcedMask, data: [0, 0])
    }

    /// Check if a fan is in forced mode
    func isForcedMode(fanIndex: Int) -> Bool {
        if let modeData = readKey(FanKeys.fanMode(fanIndex)), !modeData.isEmpty {
            return modeData[0] != 0
        }
        guard let data = readKey(FanKeys.forcedMask), data.count >= 2 else { return false }
        let mask = UInt16(data[0]) << 8 | UInt16(data[1])
        return (mask & UInt16(1 << fanIndex)) != 0
    }

    // MARK: - Low-Level SMC Access

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

    private func stringToKey(_ key: String) -> UInt32 {
        var result: UInt32 = 0
        for char in key.prefix(4).utf8 {
            result = (result << 8) | UInt32(char)
        }
        return result
    }

    private func readKey(_ key: String) -> [UInt8]? {
        guard connect() else { return nil }

        var inputStruct = SMCKeyData()
        inputStruct.key = stringToKey(key)
        inputStruct.data8 = SMCSelector.getKeyInfo.rawValue

        var outputStruct = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.size

        var result = IOConnectCallStructMethod(
            connection, 2,
            &inputStruct, MemoryLayout<SMCKeyData>.size,
            &outputStruct, &outputSize
        )

        guard result == KERN_SUCCESS else { return nil }

        let dataSize = outputStruct.keyInfo.dataSize
        inputStruct.keyInfo.dataSize = dataSize
        inputStruct.data8 = SMCSelector.readKey.rawValue

        result = IOConnectCallStructMethod(
            connection, 2,
            &inputStruct, MemoryLayout<SMCKeyData>.size,
            &outputStruct, &outputSize
        )

        guard result == KERN_SUCCESS else { return nil }

        // Extract bytes using saved dataSize (outputStruct.keyInfo.dataSize may be cleared)
        let size = Int(dataSize)
        var bytes = [UInt8](repeating: 0, count: size)

        withUnsafePointer(to: &outputStruct.bytes) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 32) { bytePtr in
                for i in 0..<size {
                    bytes[i] = bytePtr[i]
                }
            }
        }

        return bytes
    }

    private func writeKey(_ key: String, data: [UInt8]) -> Bool {
        guard connect() else { return false }

        var inputStruct = SMCKeyData()
        inputStruct.key = stringToKey(key)
        inputStruct.data8 = SMCSelector.getKeyInfo.rawValue

        var outputStruct = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.size

        var result = IOConnectCallStructMethod(
            connection, 2,
            &inputStruct, MemoryLayout<SMCKeyData>.size,
            &outputStruct, &outputSize
        )

        guard result == KERN_SUCCESS else { return false }

        inputStruct.keyInfo.dataSize = outputStruct.keyInfo.dataSize
        inputStruct.data8 = SMCSelector.writeKey.rawValue

        withUnsafeMutablePointer(to: &inputStruct.bytes) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 32) { bytePtr in
                for i in 0..<min(data.count, 32) {
                    bytePtr[i] = data[i]
                }
            }
        }

        result = IOConnectCallStructMethod(
            connection, 2,
            &inputStruct, MemoryLayout<SMCKeyData>.size,
            &outputStruct, &outputSize
        )

        return result == KERN_SUCCESS
    }

    // MARK: - Fan RPM Format Helpers

    private func readFanRPM(_ key: String) -> Int? {
        guard let data = readKey(key) else { return nil }

        if data.count == 4 {
            // Float32 format (Apple Silicon)
            let floatValue = data.withUnsafeBytes { $0.load(as: Float.self) }
            return Int(floatValue)
        } else if data.count >= 2 {
            // FPE2 format (Intel): 14 bits integer, 2 bits fraction
            let value = (Int(data[0]) << 8) | Int(data[1])
            return value >> 2
        }

        return nil
    }

    private func writeFanRPM(_ key: String, value: Int) -> Bool {
        guard let existingData = readKey(key) else { return false }

        if existingData.count == 4 {
            // Float32 format (Apple Silicon)
            var floatValue = Float(value)
            let data = withUnsafeBytes(of: &floatValue) { Array($0) }
            return writeKey(key, data: data)
        } else {
            // FPE2 format (Intel)
            let fpe2Value = value << 2
            let data: [UInt8] = [UInt8((fpe2Value >> 8) & 0xFF), UInt8(fpe2Value & 0xFF)]
            return writeKey(key, data: data)
        }
    }
}
