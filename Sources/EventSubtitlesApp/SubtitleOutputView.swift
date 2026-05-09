import AppKit
import SwiftUI

struct SubtitleOutputView: View {
    @Environment(AppState.self) private var state
    var ignoresSafeArea = true
    var animatesCaptionChanges = true
    /// When true, this view publishes its measured pixel width back to AppState
    /// so all output windows use the audience window as the wrapping source.
    var governsLayout = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background

                if !state.outputBlanked {
                    positionedCaptions(availableWidth: geo.size.width)
                }
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        if ignoresSafeArea {
            state.backgroundColor
                .ignoresSafeArea()
        } else {
            state.backgroundColor
        }
    }

    private func positionedCaptions(availableWidth: CGFloat) -> some View {
        VStack {
            if state.captionPosition != .top {
                Spacer(minLength: state.safeMargin)
            }

            captionLines(availableWidth: availableWidth)

            if state.captionPosition != .bottom {
                Spacer(minLength: state.safeMargin)
            }
        }
        .padding(.horizontal, state.safeMargin)
        .padding(.vertical, state.safeMargin)
        .offset(x: state.captionOffsetX, y: state.captionOffsetY)
        .animation(
            (animatesCaptionChanges && !reduceMotion) ? .smooth(duration: 0.18) : nil,
            value: CaptionAnimationKey(
                text: state.captionLayout.text,
                position: state.captionPosition.rawValue,
                offsetX: state.captionOffsetX,
                offsetY: state.captionOffsetY
            )
        )
    }

    private func captionLines(availableWidth: CGFloat) -> some View {
        VStack(spacing: state.lineSpacing) {
            ForEach(Array(state.visibleCaptionLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.custom(state.fontName, size: state.fontSize).weight(.bold))
                    .foregroundStyle(state.foregroundColor)
                    .multilineTextAlignment(.center)
                    .lineSpacing(state.lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsTightening(false)
                    .shadow(
                        color: state.shadowEnabled ? .black.opacity(0.82) : .clear,
                        radius: state.shadowRadius,
                        x: 0,
                        y: 2
                    )
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if governsLayout { state.applyOutputRenderWidth(availableWidth) }
        }
        .onChange(of: availableWidth) { _, newValue in
            if governsLayout { state.applyOutputRenderWidth(newValue) }
        }
    }
}

private struct CaptionAnimationKey: Equatable {
    let text: String
    let position: String
    let offsetX: Double
    let offsetY: Double
}
