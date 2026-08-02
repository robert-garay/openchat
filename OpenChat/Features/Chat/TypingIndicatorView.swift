import SwiftUI

struct TypingIndicatorView: View {
    @State private var phase = 0

    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(phase == index ? 1 : 0.3)
            }
        }
        .onReceive(timer) { _ in
            withAnimation(Theme.springFast) { phase = (phase + 1) % 3 }
        }
    }
}
