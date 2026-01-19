import Foundation
import ServiceManagement
import Security

/// Handles installation of the privileged fan control helper
final class FanHelperInstaller {
    static let shared = FanHelperInstaller()

    private let helperBundleID = "com.macaroni.fanhelper"
    private let helperPath = "/Library/PrivilegedHelperTools/com.macaroni.fanhelper"
    private let plistPath = "/Library/LaunchDaemons/com.macaroni.fanhelper.plist"

    private init() {}

    // MARK: - Public API

    /// Check if the helper is installed
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: helperPath)
    }

    /// Check if the helper daemon is running
    var isRunning: Bool {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["list", helperBundleID]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Install the helper using admin privileges
    /// This prompts the user for their password
    func install(completion: @escaping (Bool, String?) -> Void) {
        // Try to find the helper in the app bundle
        var helperSourcePath: String?

        // First try auxiliary executables
        if let path = Bundle.main.path(forAuxiliaryExecutable: "com.macaroni.fanhelper") {
            helperSourcePath = path
        }

        // Then try Resources folder
        if helperSourcePath == nil, let resourcePath = Bundle.main.resourcePath {
            let altPath = (resourcePath as NSString).appendingPathComponent("com.macaroni.fanhelper")
            if FileManager.default.fileExists(atPath: altPath) {
                helperSourcePath = altPath
            }
        }

        // Finally try MacOS folder
        if helperSourcePath == nil, let execPath = Bundle.main.executablePath {
            let macosPath = (execPath as NSString).deletingLastPathComponent
            let altPath = (macosPath as NSString).appendingPathComponent("com.macaroni.fanhelper")
            if FileManager.default.fileExists(atPath: altPath) {
                helperSourcePath = altPath
            }
        }

        guard let sourcePath = helperSourcePath else {
            completion(false, "Helper not found in app bundle")
            return
        }

        installWithAppleScript(helperSource: sourcePath, completion: completion)
    }

    /// Uninstall the helper
    func uninstall(completion: @escaping (Bool, String?) -> Void) {
        let script = """
        do shell script "launchctl unload '\(plistPath)' 2>/dev/null; rm -f '\(helperPath)' '\(plistPath)'" with administrator privileges
        """

        executeAppleScript(script, completion: completion)
    }

    // MARK: - Private Methods

    private func installWithAppleScript(helperSource: String, completion: @escaping (Bool, String?) -> Void) {
        // Get the plist from the helper's directory or bundle
        let plistSource = (helperSource as NSString).deletingLastPathComponent + "/com.macaroni.fanhelper.plist"

        // Build installation commands
        let commands = [
            "mkdir -p /Library/PrivilegedHelperTools",
            "cp '\(helperSource)' '\(helperPath)'",
            "chown root:wheel '\(helperPath)'",
            "chmod 755 '\(helperPath)'",
            "cp '\(plistSource)' '\(plistPath)' 2>/dev/null || true",
            "launchctl unload '\(plistPath)' 2>/dev/null || true",
            "launchctl load '\(plistPath)'"
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
                            completion(false, nil)
                        } else {
                            let message = error["NSAppleScriptErrorMessage"] as? String ?? "Installation failed"
                            completion(false, message)
                        }
                    } else {
                        completion(true, nil)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion(false, "Failed to create installation script")
                }
            }
        }
    }
}
