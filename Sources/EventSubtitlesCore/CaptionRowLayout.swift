public enum CaptionRowLayout {
    public static func rows(
        for lines: [String],
        maxLines: Int,
        reserveEmptyRows: Bool
    ) -> [String] {
        let rowCount = max(0, maxLines)
        guard rowCount > 0 else {
            return []
        }

        let visible = Array(lines.suffix(rowCount))
        guard reserveEmptyRows, visible.count < rowCount else {
            return visible
        }

        return Array(repeating: "", count: rowCount - visible.count) + visible
    }
}
