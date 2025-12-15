import SwiftUI

struct ThinkFirstSettingsView: View {
    @AppStorage("stickyNoteInactiveBackgroundOpacity") private var inactiveBackgroundOpacity: Double = 0.14
    @AppStorage("stickyNoteInactiveBlurStrength") private var inactiveBlurStrength: Double = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sticky Note")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Background blur: \(Int((inactiveBlurStrength * 100).rounded()))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Slider(value: $inactiveBlurStrength, in: 0...1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Background opacity: \(Int((inactiveBackgroundOpacity * 100).rounded()))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Slider(value: $inactiveBackgroundOpacity, in: 0...1)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
