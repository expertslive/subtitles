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
        // True TV-style roll-up: each logical line from the line builder gets
        // its own `Text` so its wrap never changes when other lines arrive or
        // leave. We pick the newest logical lines whose combined visual line
        // count fits in `maxLines`, drop the rest from the top. Old lines keep
        // their original word breaks; new lines appear at the bottom.
        let textWidth = max(availableWidth - 2 * state.safeMargin, 100)
        let visibleLogical = pickVisibleLogicalLines(
            candidates: state.captionLayout.lines,
            availableWidth: textWidth,
            maxVisualLines: state.maxLines
        )

        return VStack(spacing: state.lineSpacing) {
            ForEach(Array(visibleLogical.enumerated()), id: \.offset) { _, line in
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
    }

    /// Walks logical lines newest-to-oldest, accumulating their visual line
    /// counts. Includes a line if adding it stays within `maxVisualLines`. A
    /// single logical line longer than the budget is included anyway (better
    /// than showing nothing) but no older lines are added on top of it.
    private func pickVisibleLogicalLines(
        candidates: [String],
        availableWidth: CGFloat,
        maxVisualLines: Int
    ) -> [String] {
        guard !candidates.isEmpty, maxVisualLines > 0 else { return [] }

        let baseFont = NSFont(name: state.fontName, size: CGFloat(state.fontSize))
            ?? NSFont.systemFont(ofSize: CGFloat(state.fontSize))
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.bold)
        let font = NSFont(descriptor: descriptor, size: CGFloat(state.fontSize)) ?? baseFont

        var totalVisualLines = 0
        var picked: [String] = []
        for line in candidates.reversed() {
            let visualCount = measureVisualLineCount(
                line: line,
                availableWidth: availableWidth,
                font: font
            )
            if !picked.isEmpty && totalVisualLines + visualCount > maxVisualLines {
                break
            }
            picked.append(line)
            totalVisualLines += visualCount
            if totalVisualLines >= maxVisualLines {
                break
            }
        }
        return picked.reversed()
    }

    /// Counts how many visual lines `line` would take when greedy-wrapped at
    /// the operator's bold font in `availableWidth` pixels. Mirrors SwiftUI
    /// Text's default word-wrap behavior closely enough for line budgeting.
    private func measureVisualLineCount(
        line: String,
        availableWidth: CGFloat,
        font: NSFont
    ) -> Int {
        let words = line
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !words.isEmpty else { return 0 }

        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        var lines = 1
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            let width = (candidate as NSString).size(withAttributes: attrs).width
            if width <= availableWidth || current.isEmpty {
                current = candidate
            } else {
                lines += 1
                current = word
            }
        }
        return lines
    }
}
