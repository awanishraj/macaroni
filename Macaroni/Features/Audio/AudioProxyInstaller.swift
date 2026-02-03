import Foundation
import os.log

private let logger = Logger(subsystem: "com.macaroni.app", category: "AudioProxyInstaller")

/// Handles installation of the HAL audio proxy driver
final class AudioProxyInstaller {
    static let shared = AudioProxyInstaller()

    private let driverName = "MacaroniAudioProxy.driver"
    private let driverPath = "/Library/Audio/Plug-Ins/HAL/MacaroniAudioProxy.driver"

    private init() {}

    // MARK: - Public API

    /// Check if the driver is installed
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: driverPath)
    }

    /// Install the audio proxy driver using admin privileges
    /// This prompts the user for their password
    func install(completion: @escaping (Bool, String?) -> Void) {
        // Find the driver in the app bundle
        var driverSourcePath: String?

        // Try Resources folder first (embedded bundle)
        if let resourcePath = Bundle.main.resourcePath {
            let path = (resourcePath as NSString).appendingPathComponent(driverName)
            if FileManager.default.fileExists(atPath: path) {
                driverSourcePath = path
            }
        }

        // Try Frameworks folder (embedded dependency)
        if driverSourcePath == nil, let frameworksPath = Bundle.main.privateFrameworksPath {
            let path = (frameworksPath as NSString).appendingPathComponent(driverName)
            if FileManager.default.fileExists(atPath: path) {
                driverSourcePath = path
            }
        }

        // Try PlugIns folder
        if driverSourcePath == nil, let plugInsPath = Bundle.main.builtInPlugInsPath {
            let path = (plugInsPath as NSString).appendingPathComponent(driverName)
            if FileManager.default.fileExists(atPath: path) {
                driverSourcePath = path
            }
        }

        guard let sourcePath = driverSourcePath else {
            logger.error("Audio proxy driver not found in app bundle")
            completion(false, "Audio proxy driver not found in app bundle")
            return
        }

        logger.info("Installing audio proxy driver from: \(sourcePath)")
        installWithAppleScript(driverSource: sourcePath, completion: completion)
    }

    /// Uninstall the audio proxy driver
    func uninstall(completion: @escaping (Bool, String?) -> Void) {
        let script = """
        do shell script "rm -rf '\(driverPath)' && killall coreaudiod 2>/dev/null || true" with administrator privileges
        """

        executeAppleScript(script, completion: completion)
    }

    /// Restart coreaudiod to reload plugins
    func restartCoreAudio(completion: @escaping (Bool, String?) -> Void) {
        // macOS 14.4+ can use killall, earlier versions need launchctl
        let script = """
        do shell script "killall coreaudiod 2>/dev/null || sudo launchctl kickstart -k system/com.apple.audio.coreaudiod" with administrator privileges
        """

        executeAppleScript(script, completion: completion)
    }

    // MARK: - Private Methods

    private func installWithAppleScript(driverSource: String, completion: @escaping (Bool, String?) -> Void) {
        // Build installation commands
        let commands = [
            "mkdir -p '/Library/Audio/Plug-Ins/HAL'",
            "rm -rf '\(driverPath)'",
            "cp -R '\(driverSource)' '\(driverPath)'",
            "chown -R root:wheel '\(driverPath)'",
            "chmod -R 755 '\(driverPath)'",
            "killall coreaudiod 2>/dev/null || true"
        ].joined(separator: " && ")

        let script = """
        do shell script "\(commands)" with administrator privileges
        """

        executeAppleScript(script, completion: completion)
    }

    private func executeAppleScript(_ script: String, completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?

            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)

                DispatchQueue.main.async {
                    if let error = error {
                        let errorNumber = error["NSAppleScriptErrorNumber"] as? Int ?? 0
                        if errorNumber == -128 {
                            // User cancelled
                            logger.info("User cancelled audio proxy installation")
                            completion(false, nil)
                        } else {
                            let message = error["NSAppleScriptErrorMessage"] as? String ?? "Installation failed"
                            logger.error("Audio proxy installation failed: \(message)")
                            completion(false, message)
                        }
                    } else {
                        logger.info("Audio proxy driver installed successfully")
                        completion(true, nil)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    logger.error("Failed to create installation script")
                    completion(false, "Failed to create installation script")
                }
            }
        }
    }
}
