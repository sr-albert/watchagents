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

struct AnimalView: View {
    let species: AnimalSpecies
    let state: SessionState

    @State private var isAnimating = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(species.rawValue)
                .font(.system(size: 40))
                .grayscale(state == .frozen ? 0.7 : 0)
                .offset(y: bobOffset)
                .animation(stateAnimation, value: isAnimating)
            if let badge = AnimalOverlay.badge(for: state) {
                Text(badge)
                    .font(.system(size: 16))
                    .offset(x: 4, y: -4)
            }
        }
        .padding(10)
        .background(Circle().fill(AnimalOverlay.tint(for: state)))
        .onAppear { isAnimating = true }
        .onChange(of: state) { _ in
            // The repeatForever loop kicked off in .onAppear keeps using the
            // animation config it was given at that moment; `.animation(_, value:)`
            // only reapplies on changes to `isAnimating`, not to `state`. Toggling
            // `isAnimating` off then back on inside `withAnimation` forces a fresh
            // transition using the *new* state's `stateAnimation`/`bobOffset`, so a
            // persisting session's motion actually updates when its state changes.
            isAnimating = false
            withAnimation(stateAnimation) {
                isAnimating = true
            }
        }
    }

    private var bobOffset: CGFloat {
        switch state {
        case .idle: return isAnimating ? -4 : 0
        case .active: return isAnimating ? -8 : 0
        case .overloaded: return isAnimating ? 3 : -3
        case .frozen: return 0
        }
    }

    private var stateAnimation: Animation? {
        switch state {
        case .idle: return .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
        case .active: return .easeInOut(duration: 0.3).repeatForever(autoreverses: true)
        case .overloaded: return .easeInOut(duration: 0.175).repeatForever(autoreverses: true)
        case .frozen: return nil
        }
    }
}

struct PenView: View {
    let pen: FarmPen

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pen.label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(spacing: 10) {
                ForEach(pen.processes, id: \.pid) { process in
                    AnimalView(species: pen.species, state: process.state)
                }
            }
        }
        .padding(12)
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
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 16) {
                ForEach(FarmGrouping.pens(from: viewModel.snapshot.processes), id: \.cwd) { pen in
                    PenView(pen: pen)
                }
            }
            .padding()
        }
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.15), Color.green.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(minWidth: 400, minHeight: 300)
    }
}
