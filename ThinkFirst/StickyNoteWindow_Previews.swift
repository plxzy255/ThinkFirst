import SwiftUI

private enum PreviewStorage {
    static let defaults: UserDefaults = {
        let defaults = UserDefaults(suiteName: "ThinkFirst.StickyNote.Previews")!
        defaults.set(
            "Buy milk Call dentist Ship package test ",
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

private struct EmojiSpec: Identifiable {
    let id = UUID()
    let emoji: String
    let size: CGFloat
    let x: CGFloat
    let y: CGFloat
}

private struct PlaygroundBackdropSpec {
    let colorA: Color
    let colorB: Color
    let emojis: [EmojiSpec]

    static func random(width: CGFloat, height: CGFloat, count: Int = 12) -> PlaygroundBackdropSpec {
        func randColor() -> Color {
            Color(
                red: .random(in: 0...1),
                green: .random(in: 0...1),
                blue: .random(in: 0...1)
            )
        }

        let e1 = "😀"
        let e2 = "🟣"
        let e3 = "🟢"
        let e4 = "🔵"
        let e5 = "🟡"
        let e6 = "⭐️"
        let e7 = "🍕"
        let e8 = "🚀"
        let e9 = "🌈"
        let e10 = "🧠"
        let e11 = "🔥"
        let e12 = "👀"
        let emojiPool: [String] = [e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11, e12]
        let emojis: [EmojiSpec] = (0..<count).map { _ in
            EmojiSpec(
                emoji: emojiPool.randomElement()!,
                size: .random(in: 18...42),
                x: .random(in: 0...width),
                y: .random(in: 0...height)
            )
        }

        return PlaygroundBackdropSpec(
            colorA: randColor(),
            colorB: randColor(),
            emojis: emojis
        )
    }
}

private struct PlaygroundBackdrop: View {
    let spec: PlaygroundBackdropSpec

    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [spec.colorA, spec.colorB],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ForEach(spec.emojis) { e in
                Text(e.emoji)
                    .font(.system(size: e.size))
                    .opacity(0.35)
                    .position(x: e.x, y: e.y)
            }
        }
    }
}

private struct StickyNoteDoneButtonPlayground: View {
    @State private var doneStyle: DoneButtonStyle = .glassProminent
    private let backdrop = PlaygroundBackdropSpec.random(width: 260, height: 180)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Done style", selection: $doneStyle) {
                ForEach(DoneButtonStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }

            ZStack {
                PlaygroundBackdrop(spec: backdrop)

                #if DEBUG
                StickyNoteView(previewIsEditing: true)
                #else
                StickyNoteView()
                #endif
            }
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
