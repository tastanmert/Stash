import Foundation

/// Tracks whether the startup disk is low on space. Once low, it stays low until clearly recovered,
/// so the warning doesn't flicker around the threshold.
public struct DiskSpaceMonitor: Sendable {
    public var lowThreshold: Int64 = 2_000_000_000
    public var recoveryThreshold: Int64 = 5_000_000_000
    public private(set) var isLow = false

    public init() {}

    /// Feeds a new reading of free bytes; returns whether the state changed.
    @discardableResult
    public mutating func update(available: Int64) -> Bool {
        let wasLow = isLow
        if isLow { isLow = available < recoveryThreshold } else { isLow = available < lowThreshold }
        return wasLow != isLow
    }

    /// Free space on the volume holding `url`, as macOS reports it for important data.
    public static func available(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }
}
