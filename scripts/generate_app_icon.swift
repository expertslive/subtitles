import AppKit
import Foundation

enum IconError: Error {
    case missingOutputPath
    case drawingFailed
    case invalidFourCC(String)
}

guard CommandLine.arguments.count >= 2 else {
    throw IconError.missingOutputPath
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fileManager = FileManager.default
try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let representations: [(type: String, pixels: Int)] = [
    ("icp4", 16),
    ("icp5", 32),
    ("icp6", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1024)
]

let iconEntries = try representations.map { representation in
    (type: representation.type, data: try renderIconPNG(pixels: representation.pixels))
}

let totalLength = 8 + iconEntries.reduce(0) { total, entry in
    total + 8 + entry.data.count
}

var iconData = Data()
try appendFourCC("icns", to: &iconData)
appendUInt32BE(UInt32(totalLength), to: &iconData)

for entry in iconEntries {
    try appendFourCC(entry.type, to: &iconData)
    appendUInt32BE(UInt32(entry.data.count + 8), to: &iconData)
    iconData.append(entry.data)
}

try iconData.write(to: outputURL, options: .atomic)

private func appendFourCC(_ value: String, to data: inout Data) throws {
    guard let encoded = value.data(using: .ascii), encoded.count == 4 else {
        throw IconError.invalidFourCC(value)
    }
    data.append(encoded)
}

private func appendUInt32BE(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { buffer in
        data.append(contentsOf: buffer)
    }
}

private func renderIconPNG(pixels: Int) throws -> Data {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphicsContext = NSGraphicsContext(bitmapImageRep: representation) else {
        throw IconError.drawingFailed
    }

    representation.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext

    let scale = CGFloat(pixels) / 1024
    let canvas = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    let outer = canvas.insetBy(dx: 54 * scale, dy: 54 * scale)
    let screen = CGRect(x: 166 * scale, y: 218 * scale, width: 692 * scale, height: 554 * scale)

    NSColor.clear.setFill()
    canvas.fill()

    NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.075, alpha: 1).setFill()
    NSBezierPath(roundedRect: outer, xRadius: 208 * scale, yRadius: 208 * scale).fill()

    NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.24, alpha: 1).setFill()
    NSBezierPath(
        roundedRect: outer.insetBy(dx: 54 * scale, dy: 54 * scale),
        xRadius: 156 * scale,
        yRadius: 156 * scale
    ).fill()

    NSColor(calibratedRed: 0.06, green: 0.86, blue: 0.18, alpha: 1).setFill()
    NSBezierPath(roundedRect: screen, xRadius: 72 * scale, yRadius: 72 * scale).fill()

    NSColor(calibratedRed: 0.03, green: 0.55, blue: 0.13, alpha: 1).setStroke()
    let screenStroke = NSBezierPath(roundedRect: screen, xRadius: 72 * scale, yRadius: 72 * scale)
    screenStroke.lineWidth = 10 * scale
    screenStroke.stroke()

    drawWaveform(in: screen, scale: scale)
    drawSubtitleBars(in: screen, scale: scale)

    NSGraphicsContext.restoreGraphicsState()

    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw IconError.drawingFailed
    }
    return data
}

private func drawWaveform(in rect: CGRect, scale: CGFloat) {
    let path = NSBezierPath()
    let centerY = rect.maxY - 138 * scale
    let left = rect.minX + 112 * scale
    let step = 58 * scale
    let amplitudes: [CGFloat] = [28, 78, 44, 108, 58, 88, 32, 70]

    for (index, amplitude) in amplitudes.enumerated() {
        let x = left + CGFloat(index) * step
        path.move(to: CGPoint(x: x, y: centerY - amplitude * scale))
        path.line(to: CGPoint(x: x, y: centerY + amplitude * scale))
    }

    NSColor(calibratedRed: 0.82, green: 0.95, blue: 1.0, alpha: 1).setStroke()
    path.lineWidth = 24 * scale
    path.lineCapStyle = .round
    path.stroke()
}

private func drawSubtitleBars(in rect: CGRect, scale: CGFloat) {
    let bars = [
        CGRect(x: rect.minX + 132 * scale, y: rect.minY + 188 * scale, width: 428 * scale, height: 48 * scale),
        CGRect(x: rect.minX + 132 * scale, y: rect.minY + 112 * scale, width: 304 * scale, height: 48 * scale)
    ]

    NSColor.white.setFill()
    for bar in bars {
        NSBezierPath(roundedRect: bar, xRadius: 24 * scale, yRadius: 24 * scale).fill()
    }
}
