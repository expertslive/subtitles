import AppKit
import SwiftUI

struct SubtitleOutputView: View {
    @EnvironmentObject private var state: AppState
    var ignoresSafeArea = true
    var animatesCaptionChanges = true
    /// Kept for source compatibility with prior versions. The renderer now wraps
    /// per-instance using the view's own pixel width, so this flag has no effect.
    var governsLayout = false

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
        .animation(animatesCaptionChanges ? .easeOut(duration: 0.18) : nil, value: state.captionLayout.text)
        .animation(animatesCaptionChanges ? .easeOut(duration: 0.18) : nil, value: state.captionPosition.rawValue)
        .animation(animatesCaptionChanges ? .easeOut(duration: 0.12) : nil, value: state.captionOffsetX)
        .animation(animatesCaptionChanges ? .easeOut(duration: 0.12) : nil, value: state.captionOffsetY)
    }

    private func captionLines(availableWidth: CGFloat) -> some View {
        // Render exactly `maxLines` visual rows. The line builder's logical
        // lines are joined into a continuous word stream, then re-wrapped here
        // using NSAttributedString pixel measurements at the view's actual
        // width and the operator's chosen font/size. The `last(maxLines)` keeps
        // the most recent words (TV-style scroll: oldest words leave the top).
        let textWidth = max(availableWidth - 2 * state.safeMargin, 100)
        let wrapped = pixelWrappedLines(
            text: state.captionLayout.lines.joined(separator: " "),
            availableWidth: textWidth,
            maxLines: state.maxLines
        )

        return Text(wrapped.joined(separator: "\n"))
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

    /// Greedy word-fill wrap based on actual pixel width at the operator's font.
    /// Returns up to `maxLines` lines, taking the most recent words when the
    /// text doesn't fit (TV-style scroll-up). A single word longer than
    /// `availableWidth` is emitted on its own line rather than dropped.
    private func pixelWrappedLines(
        text: String,
        availableWidth: CGFloat,
        maxLines: Int
    ) -> [String] {
        let words = text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !words.isEmpty, maxLines > 0 else { return [] }

        let baseFont = NSFont(name: state.fontName, size: CGFloat(state.fontSize))
            ?? NSFont.systemFont(ofSize: CGFloat(state.fontSize))
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.bold)
        let font = NSFont(descriptor: descriptor, size: CGFloat(state.fontSize)) ?? baseFont
        let attrs: [NSAttributedString.Key: Any] = [.font: font]

        var lines: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            let width = (candidate as NSString).size(withAttributes: attrs).width
            if width <= availableWidth || current.isEmpty {
                current = candidate
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }

        return Array(lines.suffix(maxLines))
    }
}
