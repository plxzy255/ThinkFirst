import SwiftUI

struct ThinkFirstSettingsView: View {
    @AppStorage("stickyNoteInactiveBackgroundOpacity") private var inactiveBackgroundOpacity: Double = 0.3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sticky Note")
                .font(.headline)

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
