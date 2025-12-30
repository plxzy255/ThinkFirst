import CoreLocation
import SwiftUI

struct TwitterSettingsView: View {
    @ObservedObject private var service = TwitterService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Client ID") {
                TextField("Client ID", text: $service.clientID)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("Client Secret") {
                SecureField("Client Secret", text: $service.clientSecret)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                if service.isAuthenticated {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Authenticated")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Sign Out") {
                        // Reset tokens
                        UserDefaults.standard.removeObject(forKey: "twitterAccessToken")
                        UserDefaults.standard.removeObject(forKey: "twitterRefreshToken")
                        UserDefaults.standard.removeObject(forKey: "twitterTokenExpiry")
                        service.isAuthenticated = false
                    }
                } else {
                    Button("Sign In with X") {
                        service.authorize()
                    }
                    .disabled(service.clientID.isEmpty || service.clientSecret.isEmpty)
                }
            }
            .padding(.top, 4)

            Text("Enter your credentials from the X Developer Portal. Ensure 'thinkfirst://auth' is set as a callback URL.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if service.isAuthenticated {
                Divider()

                HStack {
                    VStack(alignment: .leading) {
                        Text("Bookmarks: \(service.bookmarks.count)")
                            .font(.callout)
                        if service.lastSyncDate > 0 {
                            Text("Last Sync: \(Date(timeIntervalSince1970: service.lastSyncDate).formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        Task {
                            await service.refreshData()
                        }
                    } label: {
                        if service.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(service.isSyncing)
                }
            }
        }
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    private let cornerRadius: CGFloat = 16

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.secondary.opacity(0.10))
                    )

                Text(title)
                    .font(.headline)

                Spacer()
            }

            Divider().opacity(0.6)

            content
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
    }
}

struct ThinkFirstSettingsView: View {
    @AppStorage("stickyNoteInactiveBackgroundOpacity") private var inactiveBackgroundOpacity: Double = 0.3
    @AppStorage(StickyNoteFontSizeOption.storageKey) private var stickyNoteFontSizeOptionRaw: String = StickyNoteFontSizeOption.normal.rawValue
    @AppStorage("prayerEnabled") private var prayerEnabled: Bool = false
    @AppStorage("prayerAlertEnabled") private var prayerAlertEnabled: Bool = false
    @AppStorage("prayerAlertTestNonce") private var prayerAlertTestNonce: Int = 0
    @ObservedObject private var prayerLocationManager = PrayerLocationManager.shared

    var body: some View {
        ZStack {
            // Keep the Settings window background native so the titlebar/traffic lights look correct.
            Rectangle().fill(.windowBackground)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionCard(title: "Sticky Note", systemImage: "note.text") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Font size") {
                            Picker("Font size", selection: $stickyNoteFontSizeOptionRaw) {
                                ForEach(StickyNoteFontSizeOption.allCases) { option in
                                    Text(option.title).tag(option.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 220, alignment: .trailing)
                        }

                        LabeledContent("Background opacity") {
                            Text("\(Int((inactiveBackgroundOpacity * 100).rounded()))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $inactiveBackgroundOpacity, in: 0...1)
                            .frame(maxWidth: 220)
                    }
                }

                SettingsSectionCard(title: "Twitter / X", systemImage: "bird") {
                    TwitterSettingsView()
                }

                SettingsSectionCard(title: "Prayer", systemImage: "hands.sparkles") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Enable Prayer", isOn: $prayerEnabled)
                            .onChange(of: prayerEnabled) { _, enabled in
                                if enabled {
                                    prayerLocationManager.requestAccessAndLocation()
                                }
                            }

                        if prayerEnabled {
                            Toggle("Prayer time alert (yellow tint)", isOn: $prayerAlertEnabled)

                            Button("Test alert") {
                                prayerAlertTestNonce += 1
                            }
                            .disabled(!prayerAlertEnabled)
                            .buttonStyle(.bordered)

                            Group {
                                switch prayerLocationManager.authorizationStatus {
                                case .authorizedAlways, .authorizedWhenInUse:
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
            .padding(16)
        }
        .onAppear {
            if prayerEnabled {
                prayerLocationManager.requestAccessAndLocation()
            }
        }
    }
}
