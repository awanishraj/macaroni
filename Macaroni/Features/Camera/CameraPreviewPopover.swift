import SwiftUI
import AVFoundation

/// Popover view for camera preview
struct CameraPreviewPopover: View {
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var preferences: Preferences

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            // Preview area
            previewArea

            Divider()

            // Quick controls
            controlsBar
        }
        .frame(width: 320, height: 280)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Preview Area

    private var previewArea: some View {
        ZStack {
            // Background
            Color.black

            // Camera preview
            if let frame = cameraManager.processedFrame {
                Image(nsImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if cameraManager.isCapturing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
            } else {
                // Not capturing
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.largeTitle)
                        .foregroundColor(.gray)

                    if cameraManager.authorizationStatus == .denied {
                        Text("Camera access denied")
                            .font(.caption)
                            .foregroundColor(.red)

                        Button("Open Settings") {
                            openSystemSettings()
                        }
                        .font(.caption)
                    } else {
                        Text("Click to start preview")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }

            // Hover overlay with rotation indicator
            if isHovering && cameraManager.isCapturing {
                VStack {
                    HStack {
                        Spacer()
                        rotationBadge
                            .padding(8)
                    }
                    Spacer()
                }
            }
        }
        .frame(height: 200)
        .contentShape(Rectangle())
        .onTapGesture {
            cameraManager.toggleCapture()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }

    private var rotationBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "rotate.right")
                .font(.caption2)

            Text(preferences.cameraRotation.displayName)
                .font(.caption2)

            if preferences.horizontalFlip {
                Image(systemName: "arrow.left.and.right")
                    .font(.caption2)
            }

            if preferences.verticalFlip {
                Image(systemName: "arrow.up.and.down")
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.6))
        .cornerRadius(4)
        .foregroundColor(.white)
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack(spacing: 16) {
            // Rotation control
            Menu {
                ForEach(CameraRotation.allCases, id: \.self) { rotation in
                    Button(action: { preferences.cameraRotation = rotation }) {
                        HStack {
                            Text(rotation.displayName)
                            if preferences.cameraRotation == rotation {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(preferences.cameraRotation.displayName, systemImage: "rotate.right")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 70)

            Divider()
                .frame(height: 20)

            // Flip controls
            Toggle(isOn: $preferences.horizontalFlip) {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Horizontal Flip")

            Toggle(isOn: $preferences.verticalFlip) {
                Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Vertical Flip")

            Divider()
                .frame(height: 20)

            // Frame style
            Menu {
                ForEach(FrameStyle.allCases, id: \.self) { style in
                    Button(action: { preferences.frameStyle = style }) {
                        HStack {
                            Text(style.displayName)
                            if preferences.frameStyle == style {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Frame", systemImage: "square.on.square")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 80)

            Spacer()

            // Start/Stop button
            Button(action: { cameraManager.toggleCapture() }) {
                Image(systemName: cameraManager.isCapturing ? "stop.circle.fill" : "play.circle.fill")
                    .foregroundColor(cameraManager.isCapturing ? .red : .green)
            }
            .buttonStyle(.plain)
            .font(.title2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Preview Thumbnail

struct CameraPreviewThumbnail: View {
    @EnvironmentObject var cameraManager: CameraManager

    var body: some View {
        ZStack {
            Color.black

            if let frame = cameraManager.processedFrame {
                Image(nsImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "camera.fill")
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 60, height: 45)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    CameraPreviewPopover()
        .environmentObject(CameraManager())
        .environmentObject(Preferences.shared)
}
