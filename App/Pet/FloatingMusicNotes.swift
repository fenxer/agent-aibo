import SwiftUI

/// One rising note driven by a single SwiftUI animation (no display-linked TimelineView).
struct FloatingMusicNote: Identifiable {
    let id = UUID()
    let systemName: String
    let xJitter: CGFloat
    let fontSize: CGFloat
    let flightSeconds: Double
    let riseDistanceFactor: CGFloat
    let sway: CGFloat
}

enum MusicNoteMotion {
    static let pulseInterval: Duration = .seconds(4)
    static let flight: Duration = .milliseconds(1600)
    static let stagger: Duration = .milliseconds(220)
    private static let symbols = [
        "music.note",
        "music.note",
        "music.quarternote.3",
    ]

    static func makeNote() -> FloatingMusicNote {
        FloatingMusicNote(
            systemName: symbols.randomElement() ?? "music.note",
            xJitter: CGFloat.random(in: -14 ... 20),
            fontSize: CGFloat.random(in: 12 ... 17),
            flightSeconds: Double.random(in: 1.15 ... 1.55),
            riseDistanceFactor: CGFloat.random(in: 0.55 ... 0.85),
            sway: CGFloat.random(in: -10 ... 14)
        )
    }

    /// Random 1…3 notes, staggered so they ease out of phase.
    @MainActor
    static func spawnBurst(into notes: Binding<[FloatingMusicNote]>) async {
        let count = Int.random(in: 1 ... 3)
        for index in 0..<count {
            guard !Task.isCancelled else { return }
            if index > 0 {
                try? await Task.sleep(for: stagger)
            }
            guard !Task.isCancelled else { return }
            let note = makeNote()
            notes.wrappedValue.append(note)
            let noteID = note.id
            Task { @MainActor in
                try? await Task.sleep(for: flight)
                notes.wrappedValue.removeAll { $0.id == noteID }
            }
        }
    }
}

struct FloatingMusicNoteView: View {
    let note: FloatingMusicNote
    let color: Color
    let petSize: CGFloat
    @State private var progress: CGFloat = 0

    var body: some View {
        Image(systemName: note.systemName)
            .font(.system(size: note.fontSize, weight: .semibold))
            .foregroundStyle(color.opacity(0.85 + Double(1 - progress) * 0.15))
            .offset(
                x: petSize * 0.28 + note.xJitter + note.sway * progress,
                y: -petSize * 0.15 - progress * (petSize * note.riseDistanceFactor)
            )
            .opacity(Double(1 - progress))
            .scaleEffect(0.92 + 0.12 * (1 - progress))
            .onAppear {
                withAnimation(.easeOut(duration: note.flightSeconds)) {
                    progress = 1
                }
            }
    }
}
