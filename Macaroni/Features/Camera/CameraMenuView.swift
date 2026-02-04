import SwiftUI

struct CameraMenuView: View {
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var preferences: Preferences
    @ObservedObject private var extensionManager = SystemExtensionManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Authorization check
            if cameraManager.authorizationStatus != .authorized {
                authorizationSection
            } else {
                // Preview first (like Hand Mirror)
                previewSection

                // Transform Controls
                transformSection

                // Virtual Camera Section
                virtualCameraSection

                // Camera selector at bottom
                if cameraManager.cameras.count > 1 {
                    cameraSelector
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            // Auto-start preview like Hand Mirror
            if cameraManager.authorizationStatus == .authorized && !cameraManager.isCapturing {
                cameraManager.startCapture()
            }
        }
        .onDisappear {
            // Stop camera when leaving the tab
            if cameraManager.isCapturing {
                cameraManager.stopCapture()
            }
        }
    }

    // MARK: - Preview Section (First, like Hand Mirror)

    private var previewSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)
                .frame(height: 160)

            if cameraManager.isCapturing {
                CameraPreviewView()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("Preview Off")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Transform Section

    private var transformSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Rotation - compact inline
            HStack {
                Text("Rotate")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    ForEach(CameraRotation.allCases, id: \.self) { rotation in
                        Button {
                            preferences.cameraRotation = rotation
                        } label: {
                            Text(rotation.displayName)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    preferences.cameraRotation == rotation
                                        ? Color.accentColor
                                        : Color.secondary.opacity(0.15)
                                )
                                .foregroundColor(
                                    preferences.cameraRotation == rotation
                                        ? .white
                                        : .primary
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Flip - compact inline
            HStack {
                Text("Flip")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    Button {
                        preferences.horizontalFlip.toggle()
                    } label: {
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
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

                    Button {
                        preferences.verticalFlip.toggle()
                    } label: {
                        Image(systemName: "arrow.up.and.down")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                preferences.verticalFlip
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.15)
                            )
                            .foregroundColor(
                                preferences.verticalFlip
                                    ? .white
                                    : .primary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Vertical Flip")
                }
            }
        }
    }

    // MARK: - Virtual Camera Section

    private var virtualCameraSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Virtual Camera")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(extensionStatusColor)
                        .frame(width: 6, height: 6)
                    Text(extensionStatusText)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button {
                    extensionManager.activateCameraExtension()
                } label: {
                    Text(extensionManager.cameraExtensionStatus == .activated ? "Activated" : "Activate")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(extensionManager.cameraExtensionStatus == .activated ? Color.green.opacity(0.2) : Color.accentColor)
                        .foregroundColor(extensionManager.cameraExtensionStatus == .activated ? .green : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .disabled(extensionManager.cameraExtensionStatus == .activating || extensionManager.cameraExtensionStatus == .activated)

                if extensionManager.cameraExtensionStatus == .activated {
                    Text("Available as \"Macaroni Camera\"")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            if case .failed(let error) = extensionManager.cameraExtensionStatus {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
                    .lineLimit(2)
            }

            if extensionManager.cameraExtensionStatus == .needsApproval {
                Text("Go to System Settings > Privacy & Security to approve")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            }
        }
    }

    private var extensionStatusText: String {
        switch extensionManager.cameraExtensionStatus {
        case .unknown: return "Not Installed"
        case .notInstalled: return "Not Installed"
        case .activating: return "Activating..."
        case .activated: return "Active"
        case .needsApproval: return "Needs Approval"
        case .failed: return "Failed"
        }
    }

    private var extensionStatusColor: Color {
        switch extensionManager.cameraExtensionStatus {
        case .activated: return .green
        case .activating: return .yellow
        case .needsApproval: return .orange
        case .failed: return .red
        default: return .gray
        }
    }


    // MARK: - Camera Selector (dropdown, not segmented)

    private var cameraSelector: some View {
        HStack {
            Text("Camera")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

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

    // MARK: - Helpers

    private func openCameraSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: NSViewRepresentable {
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var preferences: Preferences

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let previewLayer = cameraManager.previewLayer {
            previewLayer.frame = nsView.bounds

            if previewLayer.superlayer == nil {
                nsView.layer?.addSublayer(previewLayer)
            }

            // Apply transforms
            var transform = CATransform3DIdentity

            // Apply rotation
            let rotation = CGFloat(preferences.cameraRotation.rawValue) * .pi / 180
            transform = CATransform3DRotate(transform, rotation, 0, 0, 1)

            // Apply flips
            if preferences.horizontalFlip {
                transform = CATransform3DScale(transform, -1, 1, 1)
            }
            if preferences.verticalFlip {
                transform = CATransform3DScale(transform, 1, -1, 1)
            }

            previewLayer.transform = transform
        }
    }
}

#Preview {
    CameraMenuView()
        .environmentObject(CameraManager())
        .environmentObject(Preferences.shared)
        .frame(width: 300)
}
