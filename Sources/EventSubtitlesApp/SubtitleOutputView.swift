import SwiftUI

struct SubtitleOutputView: View {
    @EnvironmentObject private var state: AppState
    var ignoresSafeArea = true
    var animatesCaptionChanges = true

    var body: some View {
        ZStack {
            background

            if !state.outputBlanked {
                positionedCaptions
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
        .offset(x: state.captionOffsetX, y: state.captionOffsetY)
        .animation(animatesCaptionChanges ? .easeOut(duration: 0.18) : nil, value: state.captionLayout.text)
        .animation(animatesCaptionChanges ? .easeOut(duration: 0.18) : nil, value: state.captionPosition.rawValue)
        .animation(animatesCaptionChanges ? .easeOut(duration: 0.12) : nil, value: state.captionOffsetX)
        .animation(animatesCaptionChanges ? .easeOut(duration: 0.12) : nil, value: state.captionOffsetY)
    }

    private var captionLines: some View {
        // Always render at the operator's selected fontSize. No auto-scaling.
        // Lines are pre-wrapped to fit `targetCharactersPerLine`; if the operator
        // selects a font size whose pixel width overflows the screen, that's their
        // tuning to do. Truncation (tail) handles any residual overflow gracefully
        // without changing the perceived font size.
        Text(state.captionLayout.text)
            .font(.custom(state.fontName, size: state.fontSize).weight(.bold))
            .foregroundStyle(state.foregroundColor)
            .multilineTextAlignment(.center)
            .lineSpacing(state.lineSpacing)
            .lineLimit(state.maxLines)
            .truncationMode(.tail)
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
