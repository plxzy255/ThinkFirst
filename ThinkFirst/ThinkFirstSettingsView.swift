import CoreLocation
import SwiftUI

struct ThinkFirstSettingsView: View {
    @AppStorage("stickyNoteInactiveBackgroundOpacity") private var inactiveBackgroundOpacity: Double = 0.3
    @AppStorage("prayerEnabled") private var prayerEnabled: Bool = false
    @Environment(\.controlActiveState) private var controlActiveState
    @ObservedObject private var prayerLocationManager = PrayerLocationManager.shared

    private let cornerRadius: CGFloat = 16
    private var isWindowActive: Bool { controlActiveState == .key }

    var body: some View {
        ZStack {
            // Keep the Settings window background native so the titlebar/traffic lights look correct.
            Rectangle().fill(.windowBackground)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "note.text")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.secondary.opacity(0.10))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sticky Note")
                            .font(.headline)
                    }

                    Spacer()
                }

                Divider().opacity(0.6)

                // Content
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Background opacity") {
                            Text("\(Int((inactiveBackgroundOpacity * 100).rounded()))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $inactiveBackgroundOpacity, in: 0...1)
                            .frame(maxWidth: 220)
                    }

                    Divider().opacity(0.6)

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Prayer", isOn: $prayerEnabled)
                            .onChange(of: prayerEnabled) { _, enabled in
                                if enabled {
                                    prayerLocationManager.requestAccessAndLocation()
                                }
                            }

                        if prayerEnabled {
                            Group {
                                switch prayerLocationManager.authorizationStatus {
                                case .authorized, .authorizedAlways:
                                    if prayerLocationManager.lastKnownCoordinate != nil {
                                        Text("Using your current location to calculate prayer times.")
                                    } else {
                                        Text("Getting location…")
                                    }
                                case .notDetermined:
                                    Text("Allow location access to calculate prayer times.")
                                case .restricted, .denied:
                                    Text("Location access is off. Enable it in System Settings to show prayer times.")
                                @unknown default:
                                    Text("Location status unknown.")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(18)
            .frame(width: 420)
            .background {
                ZStack {
                    if #available(macOS 26.0, *) {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.clear)
                            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.ultraThinMaterial)
                    }

                    // Subtle border + depth
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                        .blendMode(.plusLighter)

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.black.opacity(0.25), lineWidth: 1)
                        .blendMode(.multiply)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(radius: 14)
            .padding(16)
        }
        .onAppear {
            if prayerEnabled {
                prayerLocationManager.requestAccessAndLocation()
            }
        }
    }
}
