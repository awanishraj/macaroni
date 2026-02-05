import SwiftUI

struct CameraMenuView: View {
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var preferences: Preferences
    @ObservedObject private var extensionManager = SystemExtensionManager.shared
    @State private var isHoveringPreview = false
    @State private var needsRestart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Show restart prompt if extension was updated
            if needsRestart {
                restartRequiredSection
            }
            // Authorization check
            else if cameraManager.authorizationStatus != .authorized {
                authorizationSection
            } else {
                // Preview on top
                previewSection

                // Camera selector
                if cameraManager.cameras.count > 1 {
                    cameraSelector
                }

                // Transform Controls
                transformSection

                // Virtual Camera Section - only show if not activated
                if extensionManager.cameraExtensionStatus != .activated {
                    virtualCameraSection
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .onReceive(NotificationCenter.default.publisher(for: .cameraExtensionNeedsRestart)) { _ in
            needsRestart = true
        }
        // NOTE: Camera only starts when user clicks power button
        // Don't stop capture on disappear - keep sending frames to virtual camera
    }

    // MARK: - Restart Required Section

    private var restartRequiredSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            Text("Restart Required")
                .font(.system(size: 13, weight: .semibold))

            Text("Camera extension updated.\nPlease restart Macaroni to apply changes.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Restart Now") {
                restartApp()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func restartApp() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundlePath]
        task.launch()
        NSApp.terminate(nil)
    }

    // MARK: - Preview Section - Shows Macaroni Camera output

    private var previewSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)
                .frame(height: 160)

            if cameraManager.isCapturing {
                VirtualCameraPreviewView()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("Click power button to start")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            // Power button overlay
            // Show when: hovering (if camera on) OR camera is off (always)
            if isHoveringPreview || !cameraManager.isCapturing {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            cameraManager.toggleCapture()
                        } label: {
                            Image(systemName: cameraManager.isCapturing ? "power.circle.fill" : "power.circle")
                                .font(.system(size: 20))
                                .foregroundColor(cameraManager.isCapturing ? .green : .white)
                                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                    Spacer()
                }
            }
        }
        .onHover { hovering in
            isHoveringPreview = hovering
        }
    }

    // MARK: - Transform Section

    private var transformSection: some View {
        HStack {
            Text("Transform")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)

            Spacer()

            HStack(spacing: 4) {
                // Anti-clockwise rotation
                Button {
                    preferences.cameraRotation = preferences.cameraRotation.previous
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 20)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Rotate Counter-clockwise")

                // Clockwise rotation
                Button {
                    preferences.cameraRotation = preferences.cameraRotation.next
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 20)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Rotate Clockwise")

                // Horizontal flip
                Button {
                    preferences.horizontalFlip.toggle()
                } label: {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 20)
                        .background(
                            preferences.horizontalFlip
                                ? Color.accentColor
                                : Color.secondary.opacity(0.15)
                        )
                        .foregroundColor(
                            preferences.horizontalFlip
                                ? .white
                                : .primary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Horizontal Flip")
            }
        }
    }

    // MARK: - Virtual Camera Section (only shown when not activated)

    private var virtualCameraSection: some View {
        HStack {
            Text("Virtual Camera")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            if extensionManager.cameraExtensionStatus == .activating {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
                Text("Activating...")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else if extensionManager.cameraExtensionStatus == .needsUpdate {
                Button {
                    extensionManager.activateCameraExtension()
                } label: {
                    Text("Update")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            } else if extensionManager.cameraExtensionStatus == .needsApproval {
                VStack(alignment: .trailing, spacing: 2) {
                    Button {
                        extensionManager.activateCameraExtension()
                    } label: {
                        Text("Activate")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)

                    Text("Check System Settings > Privacy")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                }
            } else if case .failed(let error) = extensionManager.cameraExtensionStatus {
                VStack(alignment: .trailing, spacing: 2) {
                    Button {
                        extensionManager.activateCameraExtension()
                    } label: {
                        Text("Retry")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)

                    Text(error)
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
            } else {
                // Not installed or unknown
                Button {
                    extensionManager.activateCameraExtension()
                } label: {
                    Text("Activate")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
    }


    // MARK: - Camera Selector (dropdown, not segmented)

    private var cameraSelector: some View {
        HStack {
            Text("Camera")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)

            Spacer()

            Picker("", selection: Binding(
                get: { cameraManager.selectedCamera?.id ?? "" },
                set: { id in
                    if let camera = cameraManager.cameras.first(where: { $0.id == id }) {
                        cameraManager.selectCamera(camera)
                    }
                }
            )) {
                ForEach(cameraManager.cameras) { camera in
                    Text(camera.name)
                        .tag(camera.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 160)
        }
    }

    // MARK: - Authorization Section

    private var authorizationSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("Camera Access Required")
                .font(.system(size: 12, weight: .medium))

            Button("Grant Access") {
                cameraManager.requestAuthorization()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

}

// MARK: - Virtual Camera Preview View

struct VirtualCameraPreviewView: NSViewRepresentable {
    @ObservedObject private var virtualPreview = VirtualCameraPreview.shared

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor

        // Start capturing from Macaroni Camera
        virtualPreview.startCapture()

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let previewLayer = virtualPreview.previewLayer {
            previewLayer.frame = nsView.bounds

            if previewLayer.superlayer == nil {
                nsView.layer?.addSublayer(previewLayer)
            }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        VirtualCameraPreview.shared.stopCapture()
    }
}

#Preview {
    CameraMenuView()
        .environmentObject(CameraManager())
        .environmentObject(Preferences.shared)
        .frame(width: 300)
}
