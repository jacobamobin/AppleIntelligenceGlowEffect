// Adapted from Nowsee, copyright (c) 2026 Sergey (Sergio-prog), MIT.
// Source and full license: ../../ThirdParty/Nowsee/.
import Foundation

public struct LogFrequencyMap {
    public let rowCount: Int
    public let lowestHz: Double
    public let highestHz: Double

    private let ranges: [Range<Int>]

    public init(
        binCount: Int,
        sampleRate: Double,
        rowCount: Int = 256,
        lowestHz: Double = 30,
        highestHz: Double = 16000
    ) {
        self.rowCount = rowCount
        self.lowestHz = lowestHz
        self.highestHz = min(highestHz, sampleRate / 2)

        let hzPerBin = (sampleRate / 2) / Double(binCount)
        let ratio = self.highestHz / lowestHz

        ranges = (0..<rowCount).map { row in
            let lowHz = lowestHz * pow(ratio, Double(row) / Double(rowCount))
            let highHz = lowestHz * pow(ratio, Double(row + 1) / Double(rowCount))
            let lowBin = max(0, min(binCount - 1, Int(lowHz / hzPerBin)))
            let highBin = max(lowBin + 1, min(binCount, Int((highHz / hzPerBin).rounded(.up))))
            return lowBin..<highBin
        }
    }

    public func apply(_ magnitudes: [Float], into rows: inout [Float]) {
        precondition(rows.count == rowCount)
        for (index, range) in ranges.enumerated() {
            var peak = -Float.greatestFiniteMagnitude
            for bin in range {
                peak = max(peak, magnitudes[bin])
            }
            rows[index] = peak
        }
    }
}
