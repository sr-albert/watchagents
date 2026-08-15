import SwiftUI

enum AnimalOverlay {
    static func badge(for state: SessionState) -> String? {
        switch state {
        case .idle: return nil
        case .active: return "🏃"
        case .overloaded: return "🔥"
        case .frozen: return "💤"
        }
    }

    static func tint(for state: SessionState) -> Color {
        switch state {
        case .idle: return .clear
        case .active: return .green.opacity(0.2)
        case .overloaded: return .red.opacity(0.15)
        case .frozen: return .blue.opacity(0.12)
        }
    }
}

/// The visual transform applied to one animal at one instant.
struct AnimalMotion: Equatable {
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var scale: CGFloat = 1
    var rotation: Double = 0
}

/// Motion is a pure function of (state, clock, per-animal phase) rather than a
/// `repeatForever` animation. A repeating animation has to be torn down and re-armed
/// whenever the state changes — which is what the earlier `.id(state)` remount did, and
/// it made every animal visibly snap back to rest on each transition. Sampling a
/// continuous function has no such seam: a state change simply picks a different curve
/// from the next frame onward. It is also directly unit-testable, unlike an `Animation`.
enum AnimalMotionModel {
    /// Each state gets a qualitatively different motion, not the same bob at a
    /// different speed — at a glance you should be able to tell breathing from
    /// hopping from juddering without reading the badge.
    static func motion(for state: SessionState, time: Double, phase: Double) -> AnimalMotion {
        switch state {
        case .idle:
            // Slow breathing: scale only, no travel. Calm enough to ignore.
            let breath = sin(time * 2 * .pi / 3.0 + phase)
            return AnimalMotion(scale: 1 + 0.035 * breath)

        case .active:
            // Hopping: abs() gives the bounce a floor to land on, instead of the
            // symmetric sine that made "active" read as a slow float.
            let hop = abs(sin(time * 2 * .pi / 0.7 + phase))
            return AnimalMotion(offsetY: -9 * hop, scale: 1 + 0.05 * hop)

        case .overloaded:
            // Fast lateral judder plus a rotational wobble — a real shake, where the
            // previous version just oscillated vertically like a faster bob.
            let shake = sin(time * 2 * .pi / 0.09 + phase)
            let wobble = sin(time * 2 * .pi / 0.13 + phase)
            return AnimalMotion(offsetX: 2.5 * shake, rotation: 4 * wobble)

        case .frozen:
            return AnimalMotion()
        }
    }

    /// Spreads animals out of lockstep so a pen doesn't pulse as one block.
    /// Derived from the pid so an animal's phase is stable across frames.
    static func phase(forPID pid: Int) -> Double {
        Double(pid % 1000) / 1000 * 2 * .pi
    }
}

struct AnimalView: View {
    let species: AnimalSpecies
    let state: SessionState
    let pid: Int
    let time: Double

    var body: some View {
        let motion = AnimalMotionModel.motion(
            for: state,
            time: time,
            phase: AnimalMotionModel.phase(forPID: pid)
        )

        return ZStack(alignment: .topTrailing) {
            Text(species.rawValue)
                .font(.system(size: 40))
                .grayscale(state == .frozen ? 0.7 : 0)
                .opacity(state == .frozen ? 0.65 : 1)
                .scaleEffect(motion.scale)
                .rotationEffect(.degrees(motion.rotation))
                .offset(x: motion.offsetX, y: motion.offsetY)
            if let badge = AnimalOverlay.badge(for: state) {
                Text(badge)
                    .font(.system(size: 16))
                    .offset(x: 4, y: -4)
            }
        }
        .padding(10)
        .background(Circle().fill(AnimalOverlay.tint(for: state)))
    }
}

struct PenView: View {
    let pen: FarmPen
    let time: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pen.label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(spacing: 10) {
                ForEach(pen.processes, id: \.pid) { process in
                    AnimalView(
                        species: pen.species,
                        state: process.state,
                        pid: process.pid,
                        time: time
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.green.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .foregroundStyle(Color.brown.opacity(0.5))
        )
    }
}

struct FarmView: View {
    @ObservedObject var viewModel: MonitorViewModel

    var body: some View {
        // One clock for the whole farm, sampled per frame and handed down, rather than
        // a timer per animal. Animals stay out of lockstep via their pid-derived phase.
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                    ForEach(FarmGrouping.pens(from: viewModel.snapshot.processes), id: \.cwd) { pen in
                        PenView(pen: pen, time: time)
                    }
                }
                .padding()
            }
        }
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.15), Color.green.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(minWidth: 420, minHeight: 320)
    }
}
