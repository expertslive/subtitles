import SwiftUI

struct SubtitleOutputView: View {
    @EnvironmentObject private var state: AppState
    var ignoresSafeArea = true
    var animatesCaptionChanges = true
    /// Set to true on the actual output window only. The operator-UI previews
    /// (Live, Style, Output workspaces) leave this false — their narrower frames
    /// must not drive the audience-facing line wrap.
    var governsLayout = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background

                if !state.outputBlanked {
                    positionedCaptions
                }
            }
            .onAppear {
                if governsLayout {
                    state.applyOutputRenderWidth(geo.size.width)
                }
            }
            .onChange(of: geo.size.width) { _, newWidth in
                if governsLayout {
                    state.applyOutputRenderWidth(newWidth)
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
        // No truncation either — every committed word must reach the audience.
        // Lines are pre-wrapped to `targetCharactersPerLine`; if the operator
        // selects a font size whose pixel width forces individual lines to
        // re-wrap, the block grows taller rather than dropping words.
        Text(state.captionLayout.text)
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
