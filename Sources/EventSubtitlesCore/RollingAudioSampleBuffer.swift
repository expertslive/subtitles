import Foundation

public struct RollingAudioSampleBuffer: Sendable {
    public let maximumRetainedSamples: Int
    public let sampleRate: Int

    private var retainedSamples: [Float] = []
    public private(set) var droppedSampleCount = 0
    public private(set) var totalSampleCount = 0

    public init(maximumRetainedSamples: Int, sampleRate: Int) {
        self.maximumRetainedSamples = max(1, maximumRetainedSamples)
        self.sampleRate = max(1, sampleRate)
    }

    public var samples: [Float] {
        retainedSamples
    }

    public var streamOffsetSeconds: TimeInterval {
        TimeInterval(droppedSampleCount) / TimeInterval(sampleRate)
    }

    public mutating func append(_ newSamples: [Float]) {
        guard !newSamples.isEmpty else {
            return
        }

        retainedSamples.append(contentsOf: newSamples)
        totalSampleCount += newSamples.count

        let overflow = retainedSamples.count - maximumRetainedSamples
        guard overflow > 0 else {
            return
        }

        retainedSamples.removeFirst(overflow)
        droppedSampleCount += overflow
    }

    public mutating func reset() {
        retainedSamples.removeAll(keepingCapacity: true)
        droppedSampleCount = 0
        totalSampleCount = 0
    }
}
