import SwiftUI

struct SubtitleOutputView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            state.backgroundColor
                .ignoresSafeArea()

            positionedCaptions
        }
    }

    private var positionedCaptions: some View {
        VStack {
            if state.captionPosition != .top {
                Spacer(minLength: state.safeMargin)
            }

            captionLines

            if state.captionPosition != .bottom {
                Spacer(minLength: state.safeMargin)
            }
        }
        .padding(.horizontal, state.safeMargin)
        .padding(.vertical, state.safeMargin)
        .animation(.easeOut(duration: 0.18), value: state.captionLayout.text)
        .animation(.easeOut(duration: 0.18), value: state.captionPosition.rawValue)
    }

    private var captionLines: some View {
        VStack(spacing: state.lineSpacing) {
            ForEach(Array(state.captionLayout.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.custom(state.fontName, size: state.fontSize).weight(.bold))
                    .foregroundStyle(state.foregroundColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(false)
                    .shadow(
                        color: state.shadowEnabled ? .black.opacity(0.82) : .clear,
                        radius: state.shadowRadius,
                        x: 0,
                        y: 2
                    )
            }
        }
        .frame(maxWidth: .infinity)
    }
}
