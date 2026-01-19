import Foundation

/// Protocol for XPC communication between main app and privileged helper
@objc public protocol FanHelperProtocol {
    /// Get current fan speed and limits
    /// - Parameter reply: Callback with (currentRPM as NSNumber?, minRPM, maxRPM)
    func getFanSpeed(reply: @escaping (NSNumber?, Int, Int) -> Void)

    /// Set target fan speed in RPM
    /// - Parameters:
    ///   - rpm: Target RPM value
    ///   - reply: Success callback
    func setFanSpeed(_ rpm: Int, reply: @escaping (Bool) -> Void)

    /// Enable forced/manual fan control mode
    /// - Parameter reply: Success callback
    func enableForcedMode(reply: @escaping (Bool) -> Void)

    /// Disable forced mode and return to automatic control
    /// - Parameter reply: Success callback
    func disableForcedMode(reply: @escaping (Bool) -> Void)

    /// Get all available fan information
    /// - Parameter reply: Callback with array of fan info dictionaries
    func getAllFanInfo(reply: @escaping ([[String: Any]]) -> Void)

    /// Check if helper is running with required privileges
    /// - Parameter reply: Callback with authorization status
    func checkAuthorization(reply: @escaping (Bool) -> Void)
}

/// Keys used in fan info dictionaries
public enum FanInfoKey: String {
    case index = "index"
    case name = "name"
    case currentRPM = "currentRPM"
    case minRPM = "minRPM"
    case maxRPM = "maxRPM"
    case targetRPM = "targetRPM"
    case isForced = "isForced"
}
