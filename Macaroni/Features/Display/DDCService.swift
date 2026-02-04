import Foundation
import IOKit
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "com.macaroni.app", category: "DDCService")

// MARK: - Private API Declarations (linked from IOMobileFramebuffer)

/// IOAVService is an opaque type
typealias IOAVServiceRef = UnsafeMutableRawPointer

/// Create IOAVService from IORegistry service entry
@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ allocator: CFAllocator!, _ service: io_service_t) -> IOAVServiceRef?

/// Read I2C data from display via IOAVService
@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(_ service: IOAVServiceRef, _ chipAddress: UInt32, _ dataAddress: UInt32, _ outputBuffer: UnsafeMutableRawPointer, _ outputBufferSize: UInt32) -> IOReturn

/// Write I2C data to display via IOAVService
@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ service: IOAVServiceRef, _ chipAddress: UInt32, _ dataAddress: UInt32, _ inputBuffer: UnsafeMutableRawPointer, _ inputBufferSize: UInt32) -> IOReturn

// MARK: - VCP Codes

/// DDC/CI VCP (Virtual Control Panel) codes
enum VCPCode: UInt8 {
    case brightness = 0x10
    case contrast = 0x12
    case volume = 0x62
    case powerMode = 0xD6
}

// MARK: - AV Service Wrapper

/// Wrapper for IOAVService with display matching
private class AVServiceInfo {
    let service: IOAVServiceRef
    let displayID: CGDirectDisplayID?

    init(service: IOAVServiceRef, displayID: CGDirectDisplayID?) {
        self.service = service
        self.displayID = displayID
    }
}

// MARK: - DDC Service

/// DDC/CI service for controlling external displays via I2C
/// Uses IOAVService private APIs for Apple Silicon Macs
final class DDCService {
    static let shared = DDCService()

    private let i2cChipAddress: UInt32 = 0x37  // Standard DDC/CI address (shifted: 0x6E)
    private let i2cDataAddress: UInt32 = 0x51  // Host address
    private let delayBetweenCommands: UInt32 = 50000  // 50ms in microseconds
    private let maxRetries = 3

    // Cache for DDC support and services
    private var ddcSupportCache: [CGDirectDisplayID: Bool] = [:]
    private var serviceCache: [CGDirectDisplayID: AVServiceInfo] = [:]

    private init() {
        logger.info("DDCService initialized")
        discoverServices()
    }

    // MARK: - Service Discovery

    /// Discover all IOAVService instances for external displays
    /// Uses recursive IORegistry traversal like MonitorControl
    /// Searches for both AppleCLCD2 and DCPAVServiceProxy classes
    private func discoverServices() {
        logger.info("Discovering IOAVServices via recursive IORegistry traversal...")

        // Get the root of the IORegistry
        let ioregRoot = IORegistryGetRootEntry(kIOMainPortDefault)
        guard ioregRoot != 0 else {
            logger.error("Failed to get IORegistry root")
            return
        }
        defer { IOObjectRelease(ioregRoot) }

        var iterator: io_iterator_t = 0

        // Create recursive iterator from root
        let result = IORegistryEntryCreateIterator(
            ioregRoot,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        )

        guard result == KERN_SUCCESS else {
            logger.error("Failed to create IORegistry iterator: \(result)")
            return
        }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        var foundCount = 0

        // Classes that can provide IOAVService (MonitorControl checks both)
        let targetClasses = ["DCPAVServiceProxy", "AppleCLCD2"]

        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }

            // Get the class name
            var className = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(entry, &className)
            let classNameStr = String(cString: className)

            // Look for entries that can provide IOAVService
            if targetClasses.contains(classNameStr) {
                // Check if this is an external display
                if let locationRef = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0) {
                    let location = locationRef.takeRetainedValue() as? String

                    logger.info("Found \(classNameStr) with location: \(location ?? "nil")")

                    if location == "External" {
                        logger.info("Creating IOAVService for external display from \(classNameStr)...")

                        // Create IOAVService
                        if let avService = IOAVServiceCreateWithService(kCFAllocatorDefault, entry) {
                            foundCount += 1
                            logger.info("Successfully created IOAVService from \(classNameStr)")

                            // Match to display ID
                            let externalDisplays = getExternalDisplays()
                            logger.info("[discoverServices] External displays found: \(externalDisplays)")

                            if let firstExternal = externalDisplays.first, serviceCache[firstExternal] == nil {
                                serviceCache[firstExternal] = AVServiceInfo(service: avService, displayID: firstExternal)
                                logger.info("Cached IOAVService for display \(firstExternal)")
                            } else if externalDisplays.isEmpty {
                                logger.warning("[discoverServices] No external displays found to cache service!")
                            } else {
                                logger.info("[discoverServices] Service already cached for \(externalDisplays.first!)")
                            }
                        } else {
                            logger.error("IOAVServiceCreateWithService returned nil for \(classNameStr)")
                        }
                    }
                } else {
                    // No Location property
                    logger.debug("Found \(classNameStr) without Location property")
                }
            }
        }

        logger.info("Service discovery complete. Found \(foundCount) external services, cached \(self.serviceCache.count).")
    }

    /// Match an IORegistry entry to a CGDisplayID using EDID
    private func matchServiceToDisplay(entry: io_object_t) -> CGDirectDisplayID? {
        // Try to get display info to match
        let externalDisplays = getExternalDisplays()

        // For now, return the first external display
        // In a full implementation, match using EDID data
        return externalDisplays.first
    }

    /// Get IOAVService for a display
    private func getAVService(for displayID: CGDirectDisplayID) -> IOAVServiceRef? {
        logger.info("[getAVService] Looking for displayID: \(displayID)")
        logger.info("[getAVService] Current cache keys: \(Array(self.serviceCache.keys))")

        // Check cache first
        if let cached = serviceCache[displayID] {
            logger.info("[getAVService] Found in cache for displayID: \(displayID)")
            return cached.service
        }

        logger.info("[getAVService] Not in cache, re-discovering services...")

        // Re-discover services if not found
        discoverServices()

        if let service = serviceCache[displayID]?.service {
            logger.info("[getAVService] Found after re-discovery for displayID: \(displayID)")
            return service
        }

        logger.warning("[getAVService] Still not found after re-discovery for displayID: \(displayID)")
        logger.info("[getAVService] Available display IDs in cache: \(Array(self.serviceCache.keys))")

        return nil
    }

    // MARK: - Public API

    /// Check if a display supports DDC/CI
    func supportsDDC(displayID: CGDirectDisplayID) -> Bool {
        // Check cache first
        if let cached = ddcSupportCache[displayID] {
            return cached
        }

        logger.info("Checking DDC support for display \(displayID)")

        // Try to read brightness - if successful, DDC is supported
        let supported = getBrightness(for: displayID) != nil
        ddcSupportCache[displayID] = supported

        logger.info("DDC support for display \(displayID): \(supported)")
        return supported
    }

    /// Read current brightness value from display
    func getBrightness(for displayID: CGDirectDisplayID) -> Int? {
        return readVCPValue(displayID: displayID, code: .brightness)
    }

    /// Set brightness value on display
    @discardableResult
    func setBrightness(_ brightness: Int, for displayID: CGDirectDisplayID) -> Bool {
        logger.info("[DDC setBrightness] displayID: \(displayID), brightness: \(brightness)")
        logger.info("[DDC setBrightness] serviceCache keys: \(Array(self.serviceCache.keys))")
        logger.info("[DDC setBrightness] ddcSupportCache: \(self.ddcSupportCache)")

        let clampedValue = max(0, min(100, brightness))
        let result = writeVCPValue(displayID: displayID, code: .brightness, value: UInt16(clampedValue))
        logger.info("[DDC setBrightness] writeVCPValue result: \(result)")
        return result
    }

    /// Get maximum brightness value
    func getMaxBrightness(for displayID: CGDirectDisplayID) -> Int? {
        return readVCPMaxValue(displayID: displayID, code: .brightness)
    }

    /// Get list of external displays
    func getExternalDisplays() -> [CGDirectDisplayID] {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0

        guard CGGetActiveDisplayList(16, &displayIDs, &displayCount) == .success else {
            return []
        }

        return Array(displayIDs.prefix(Int(displayCount))).filter { displayID in
            CGDisplayIsBuiltin(displayID) == 0
        }
    }

    /// Get the display ID that has a cached IOAVService (the REAL physical display)
    /// This is useful when virtual displays are present, as only the physical display
    /// will have an IOAVService
    func getPhysicalDisplayWithDDC() -> CGDirectDisplayID? {
        // First ensure we've discovered services
        if serviceCache.isEmpty {
            discoverServices()
        }

        logger.info("[getPhysicalDisplayWithDDC] serviceCache keys: \(Array(self.serviceCache.keys))")

        // Return the first display ID that has a cached service
        return serviceCache.keys.first
    }

    /// Clear caches (call when display configuration changes)
    func clearCaches() {
        logger.info("[clearCaches] Clearing DDC caches...")
        logger.info("[clearCaches] Before clear - serviceCache keys: \(Array(self.serviceCache.keys))")
        ddcSupportCache.removeAll()
        serviceCache.removeAll()
        logger.info("[clearCaches] Cache cleared, re-discovering services...")
        discoverServices()
        logger.info("[clearCaches] After discovery - serviceCache keys: \(Array(self.serviceCache.keys))")
    }

    // MARK: - DDC/CI Protocol Implementation

    /// Read a VCP value from the display
    private func readVCPValue(displayID: CGDirectDisplayID, code: VCPCode) -> Int? {
        guard let service = getAVService(for: displayID) else {
            logger.warning("No IOAVService available for display \(displayID)")
            return nil
        }

        // Build DDC/CI Get VCP Feature command
        // Format: [length | 0x80], 0x01 (Get VCP), VCP code, checksum
        var command: [UInt8] = [0x82, 0x01, code.rawValue]

        // Calculate checksum: XOR of (destination address, source address, and all data bytes)
        var checksum: UInt8 = UInt8(i2cChipAddress << 1) ^ UInt8(i2cDataAddress)
        for byte in command {
            checksum ^= byte
        }
        command.append(checksum)

        // Send command with retries
        for attempt in 1...maxRetries {
            var cmdBuffer = command
            let writeResult = IOAVServiceWriteI2C(service, i2cChipAddress, i2cDataAddress, &cmdBuffer, UInt32(cmdBuffer.count))

            if writeResult != kIOReturnSuccess {
                logger.warning("DDC write failed on attempt \(attempt): 0x\(String(writeResult, radix: 16))")
                usleep(delayBetweenCommands)
                continue
            }

            usleep(delayBetweenCommands)

            // Read response (12 bytes expected for VCP reply)
            // MonitorControl uses offset 0 for reads, not the data address
            var response = [UInt8](repeating: 0, count: 12)
            let readResult = IOAVServiceReadI2C(service, i2cChipAddress, 0, &response, 12)

            if readResult != kIOReturnSuccess {
                logger.warning("DDC read failed on attempt \(attempt): 0x\(String(readResult, radix: 16))")
                usleep(delayBetweenCommands)
                continue
            }

            // Log response for debugging
            logger.debug("DDC response: \(response.map { String(format: "%02X", $0) }.joined(separator: " "))")

            // Parse response - DDC/CI VCP Reply format:
            // Byte 0: Source address (0x6E)
            // Byte 1: Length | 0x80 (typically 0x88 = 8 bytes)
            // Byte 2: VCP Reply opcode (0x02)
            // Byte 3: Result code (0x00 = no error)
            // Byte 4: VCP code
            // Byte 5: Type code
            // Byte 6-7: Maximum value (high, low)
            // Byte 8-9: Current value (high, low)
            // Byte 10: Checksum

            // Check for valid VCP reply
            let resultCode = response[3]
            let vcpCode = response[4]

            if resultCode == 0x00 && vcpCode == code.rawValue {
                let currentValue = (Int(response[8]) << 8) | Int(response[9])
                let maxValue = (Int(response[6]) << 8) | Int(response[7])
                logger.info("Read VCP 0x\(String(code.rawValue, radix: 16)): current=\(currentValue), max=\(maxValue)")
                return currentValue
            } else {
                logger.warning("Unexpected DDC response: opcode=\(String(format: "0x%02X", response[2])), result=\(String(format: "0x%02X", resultCode)), vcpCode=\(String(format: "0x%02X", vcpCode))")
            }

            usleep(delayBetweenCommands)
        }

        return nil
    }

    /// Read max value for a VCP code
    private func readVCPMaxValue(displayID: CGDirectDisplayID, code: VCPCode) -> Int? {
        guard let service = getAVService(for: displayID) else { return nil }

        var command: [UInt8] = [0x82, 0x01, code.rawValue]
        var checksum: UInt8 = UInt8(i2cChipAddress << 1) ^ UInt8(i2cDataAddress)
        for byte in command {
            checksum ^= byte
        }
        command.append(checksum)

        var cmdBuffer = command
        guard IOAVServiceWriteI2C(service, i2cChipAddress, i2cDataAddress, &cmdBuffer, UInt32(cmdBuffer.count)) == kIOReturnSuccess else {
            return nil
        }

        usleep(delayBetweenCommands)

        // Use offset 0 for reads like MonitorControl
        var response = [UInt8](repeating: 0, count: 12)
        guard IOAVServiceReadI2C(service, i2cChipAddress, 0, &response, 12) == kIOReturnSuccess else {
            return nil
        }

        // Parse using correct DDC/CI response format
        let resultCode = response[3]
        let vcpCode = response[4]

        if resultCode == 0x00 && vcpCode == code.rawValue {
            let maxValue = (Int(response[6]) << 8) | Int(response[7])
            return maxValue
        }

        return nil
    }

    /// Write a VCP value to the display
    private func writeVCPValue(displayID: CGDirectDisplayID, code: VCPCode, value: UInt16) -> Bool {
        guard let service = getAVService(for: displayID) else {
            logger.warning("No IOAVService available for display \(displayID)")
            return false
        }

        // Build DDC/CI Set VCP Feature command
        // Format: [length | 0x80], 0x03 (Set VCP), VCP code, value_hi, value_lo, checksum
        let valueHigh = UInt8((value >> 8) & 0xFF)
        let valueLow = UInt8(value & 0xFF)
        var command: [UInt8] = [0x84, 0x03, code.rawValue, valueHigh, valueLow]

        // Calculate checksum
        var checksum: UInt8 = UInt8(i2cChipAddress << 1) ^ UInt8(i2cDataAddress)
        for byte in command {
            checksum ^= byte
        }
        command.append(checksum)

        // Send command with retries
        for attempt in 1...maxRetries {
            var cmdBuffer = command
            let result = IOAVServiceWriteI2C(service, i2cChipAddress, i2cDataAddress, &cmdBuffer, UInt32(cmdBuffer.count))

            if result == kIOReturnSuccess {
                logger.info("Set VCP 0x\(String(code.rawValue, radix: 16)) to \(value) succeeded on attempt \(attempt)")
                return true
            }

            logger.warning("DDC write failed on attempt \(attempt): 0x\(String(result, radix: 16))")
            usleep(delayBetweenCommands * 2)  // Longer delay for write retries
        }

        return false
    }
}
