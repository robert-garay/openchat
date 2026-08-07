import SwiftUI

/// ChatGPT-style effort lever: a horizontal segmented slider with a large knob
/// and a centered label showing the selected level. Three stops map to Low, Medium, High.
struct EffortLevelPicker: View {
    let level: EffortLevel
    let onChange: (EffortLevel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int
    @GestureState private var dragOffset: CGFloat = 0

    private let stopCount = EffortLevel.ordered.count
    private let trackHeight: CGFloat = 52
    private let knobDiameter: CGFloat = 44
    private let spring = Theme.springFast

    init(level: EffortLevel, onChange: @escaping (EffortLevel) -> Void) {
        self.level = level
        self.onChange = onChange
        self._selectedIndex = State(initialValue: level.index)
    }

    var body: some View {
        VStack(spacing: 24) {
            Text(selectedLevel.displayName)
                .font(.title2.weight(.semibold))
                .contentTransition(.numericText())
                .animation(spring, value: selectedIndex)

            GeometryReader { geometry in
                let trackWidth = geometry.size.width
                let trackRange = trackWidth - knobDiameter
                let stopSpacing = stopCount > 1 ? trackRange / CGFloat(stopCount - 1) : 0
                let centerX = knobRadius + stopSpacing * CGFloat(selectedIndex) + dragOffset

                ZStack(alignment: .leading) {
                    // Background track with filled portion.
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: trackHeight)

                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(0, centerX + knobRadius), height: trackHeight)
                    }

                    // Stop tick dots.
                    HStack(spacing: 0) {
                        ForEach(0..<stopCount, id: \.self) { index in
                            Circle()
                                .fill(index <= selectedIndex ? Color.white.opacity(0.55) : Color(.tertiaryLabel).opacity(0.5))
                                .frame(width: 8, height: 8)
                                .offset(x: knobRadius + stopSpacing * CGFloat(index) - 4)
                            if index < stopCount - 1 {
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 0)

                    // Knob.
                    Circle()
                        .fill(.white)
                        .frame(width: knobDiameter, height: knobDiameter)
                        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                        .offset(x: centerX - knobRadius)
                }
                .frame(height: trackHeight)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .updating($dragOffset) { value, state, _ in
                            state = value.translation.width
                        }
                        .onEnded { value in
                            let currentX = knobRadius + stopSpacing * CGFloat(selectedIndex)
                            let finalX = max(0, min(trackWidth, currentX + value.translation.width))
                            let nearestIndex = Int((finalX - knobRadius) / stopSpacing + 0.5)
                            let clamped = max(0, min(stopCount - 1, nearestIndex))
                            withAnimation(spring) {
                                selectedIndex = clamped
                            }
                            if let level = EffortLevel(index: clamped) {
                                Haptics.light()
                                onChange(level)
                                dismiss()
                            }
                        }
                )
            }
            .frame(height: trackHeight)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var selectedLevel: EffortLevel {
        EffortLevel(index: selectedIndex) ?? .default
    }

    private var knobRadius: CGFloat { knobDiameter / 2 }
}
