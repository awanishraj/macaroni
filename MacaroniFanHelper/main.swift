import Foundation

/// Privileged helper tool for SMC fan control
/// This runs as a LaunchDaemon with root privileges
class FanHelperService: NSObject, FanHelperProtocol, NSXPCListenerDelegate {

    private let smcService = SMCWriteService.shared
    private let listener: NSXPCListener

    override init() {
        listener = NSXPCListener(machServiceName: "com.macaroni.fanhelper")
        super.init()
        listener.delegate = self
    }

    func run() {
        listener.resume()
        RunLoop.main.run()
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // MARK: - FanHelperProtocol

    func getFanSpeed(reply: @escaping (NSNumber?, Int, Int) -> Void) {
        let fanIndex = 0
        let currentRPM = smcService.getActualRPM(fanIndex: fanIndex)
        let minRPM = smcService.getMinRPM(fanIndex: fanIndex) ?? 1000
        let maxRPM = smcService.getMaxRPM(fanIndex: fanIndex) ?? 6000
        let rpmNumber: NSNumber? = currentRPM != nil ? NSNumber(value: currentRPM!) : nil
        reply(rpmNumber, minRPM, maxRPM)
    }

    func setFanSpeed(_ rpm: Int, reply: @escaping (Bool) -> Void) {
        let fanIndex = 0
        let minRPM = smcService.getMinRPM(fanIndex: fanIndex) ?? 1000
        let maxRPM = smcService.getMaxRPM(fanIndex: fanIndex) ?? 6000
        let clampedRPM = max(minRPM, min(maxRPM, rpm))
        let success = smcService.setTargetRPM(clampedRPM, fanIndex: fanIndex)
        reply(success)
    }

    func enableForcedMode(reply: @escaping (Bool) -> Void) {
        let success = smcService.enableForcedMode(fanIndex: 0)
        reply(success)
    }

    func disableForcedMode(reply: @escaping (Bool) -> Void) {
        let success = smcService.disableForcedMode(fanIndex: 0)
        reply(success)
    }

    func getAllFanInfo(reply: @escaping ([[String: Any]]) -> Void) {
        var fanInfoList: [[String: Any]] = []
        let fanCount = smcService.getFanCount()

        for i in 0..<fanCount {
            var info: [String: Any] = [FanInfoKey.index.rawValue: i]

            if let currentRPM = smcService.getActualRPM(fanIndex: i) {
                info[FanInfoKey.currentRPM.rawValue] = currentRPM
            }
            if let minRPM = smcService.getMinRPM(fanIndex: i) {
                info[FanInfoKey.minRPM.rawValue] = minRPM
            }
            if let maxRPM = smcService.getMaxRPM(fanIndex: i) {
                info[FanInfoKey.maxRPM.rawValue] = maxRPM
            }
            if let targetRPM = smcService.getTargetRPM(fanIndex: i) {
                info[FanInfoKey.targetRPM.rawValue] = targetRPM
            }
            info[FanInfoKey.isForced.rawValue] = smcService.isForcedMode(fanIndex: i)

            fanInfoList.append(info)
        }

        reply(fanInfoList)
    }

    func checkAuthorization(reply: @escaping (Bool) -> Void) {
        reply(geteuid() == 0)
    }
}

// MARK: - Main Entry Point

let service = FanHelperService()
service.run()
