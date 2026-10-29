import Foundation
import Testing
@testable import StashCore

struct WatchedFolderTests {
    let report = FileFacts(name: "Q3 Report.PDF", fileExtension: "PDF", kind: .pdf, size: 12_000_000)
    let photo = FileFacts(name: "IMG_0042.heic", fileExtension: "heic", kind: .image, size: 2_500_000)

    @Test(arguments: [
        (FolderRule.Field.name, FolderRule.Comparison.contains, "report", true),
        (.name, .doesNotContain, "report", false),
        (.name, .beginsWith, "q3", true),
        (.name, .endsWith, ".pdf", true),
        (.name, .equals, "q3 report.pdf", true),
        (.name, .notEquals, "q3 report.pdf", false),
        (.fileExtension, .equals, ".pdf", true),
        (.kind, .equals, "pdf", true),
        (.kind, .notEquals, "image", true),
        (.size, .greaterThan, "10", true),
        (.size, .lessThan, "10", false),
    ])
    func `rules compare names, extensions, kinds and sizes`(field: FolderRule.Field, comparison: FolderRule.Comparison, value: String, expected: Bool) {
        #expect(FolderRule(field: field, comparison: comparison, value: value).matches(report) == expected)
    }

    @Test func `case sensitivity is honored`() {
        let rule = FolderRule(field: .name, comparison: .contains, value: "report")
        #expect(rule.matches(report, caseSensitive: false))
        #expect(!rule.matches(report, caseSensitive: true))
    }

    @Test func `all or any rules`() {
        var folder = WatchedFolder(path: "/tmp")
        folder.rules = [FolderRule(field: .kind, comparison: .equals, value: "image"),
                        FolderRule(field: .size, comparison: .greaterThan, value: "5")]
        #expect(!folder.accepts(photo))
        folder.matchAll = false
        #expect(folder.accepts(photo))
        folder.rules = []
        #expect(folder.accepts(photo))
    }

    @Test func `subfolders only when enabled`() {
        var folder = WatchedFolder(path: "/Users/me/Downloads")
        let direct = URL(filePath: "/Users/me/Downloads/a.zip")
        let nested = URL(filePath: "/Users/me/Downloads/inner/a.zip")
        let sibling = URL(filePath: "/Users/me/Downloads2/a.zip")
        #expect(folder.covers(direct))
        #expect(!folder.covers(nested))
        folder.includeSubfolders = true
        #expect(folder.covers(nested))
        #expect(!folder.covers(sibling))
    }

    @Test func `hidden files and partial downloads are skipped`() {
        #expect(NewFileFilter.isCandidate(URL(filePath: "/x/report.pdf")))
        #expect(!NewFileFilter.isCandidate(URL(filePath: "/x/.Screenshot 2026.png")))
        #expect(!NewFileFilter.isCandidate(URL(filePath: "/x/movie.mp4.crdownload")))
        #expect(!NewFileFilter.isCandidate(URL(filePath: "/x/movie.download")))
    }

    @Test func `kinds come from content types`() {
        #expect(FolderRule.Kind(type: .pdf) == .pdf)
        #expect(FolderRule.Kind(type: .png) == .image)
        #expect(FolderRule.Kind(type: .mpeg4Movie) == .video)
        #expect(FolderRule.Kind(type: .zip) == .archive)
        #expect(FolderRule.Kind(type: .plainText) == .text)
    }

    @Test func `folders round trip through JSON`() throws {
        var folder = WatchedFolder(path: "/tmp/watch")
        folder.rules = [FolderRule(field: .fileExtension, comparison: .equals, value: "zip")]
        folder.delay = 5
        let url = FileManager.default.temporaryDirectory.appending(path: "folders-\(UUID().uuidString).json")
        try WatchedFolder.save([folder], to: url)
        #expect(WatchedFolder.load(from: url) == [folder])
    }
}
