import Testing
@testable import StashCore

struct DiskSpaceTests {
    @Test func `low space warns and recovers with a margin`() {
        var monitor = DiskSpaceMonitor()
        var changed = monitor.update(available: 10_000_000_000)
        #expect(!changed)
        changed = monitor.update(available: 1_000_000_000)
        #expect(changed && monitor.isLow)
        changed = monitor.update(available: 3_000_000_000)
        #expect(!changed && monitor.isLow)
        changed = monitor.update(available: 6_000_000_000)
        #expect(changed && !monitor.isLow)
    }
}
