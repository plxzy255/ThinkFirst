import SwiftUI

private enum PreviewStorage {
    static let defaults: UserDefaults = {
        let defaults = UserDefaults(suiteName: "ThinkFirst.StickyNote.Previews")!
        defaults.set(
            "Buy milk\nCall dentist\nShip package",
            forKey: "stickyNoteText"
        )
        return defaults
    }()
}

private struct DoneButtonStyleGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(DoneButtonStyle.allCases) { style in
                doneButton(for: style)
            }
        }
        .controlSize(.small)
        .padding()
        .frame(width: 260)
    }

    @ViewBuilder
    private func doneButton(for style: DoneButtonStyle) -> some View {
        switch style {
        case .automatic:
            Button(style.rawValue) {}.buttonStyle(.automatic)
        case .bordered:
            Button(style.rawValue) {}.buttonStyle(.bordered)
        case .borderedProminent:
            Button(style.rawValue) {}.buttonStyle(.borderedProminent)
        case .glass:
            Button(style.rawValue) {}.buttonStyle(.glass)
        case .glassProminent:
            Button(style.rawValue) {}.buttonStyle(.glassProminent)
        }
    }
}

private struct StickyNoteDoneButtonPlayground: View {
    @State private var doneStyle: DoneButtonStyle = .glassProminent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Done style", selection: $doneStyle) {
                ForEach(DoneButtonStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }

            StickyNoteView(previewIsEditing: true)
                .defaultAppStorage(PreviewStorage.defaults)
                .doneButtonStyle(doneStyle)
                .frame(width: 260, height: 180)
        }
        .padding()
        .frame(width: 320)
    }
}

#Preview("Done Button Styles") {
    DoneButtonStyleGallery()
}

#Preview("Sticky Note Playground") {
    StickyNoteDoneButtonPlayground()
}
