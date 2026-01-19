import SwiftUI

struct CameraMenuView: View {
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var preferences: Preferences

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
