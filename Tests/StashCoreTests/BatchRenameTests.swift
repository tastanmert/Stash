import Foundation
import Testing
@testable import StashCore

struct BatchRenameTests {
    @Test func `replace keeps the extension and can ignore case`() {
        var rule = RenameRule()
        rule.find = "img"
        rule.replacement = "Photo"
        #expect(rule.newName(for: "IMG_01.jpg", index: 0) == "Photo_01.jpg")
        rule.caseSensitive = true
        #expect(rule.newName(for: "IMG_01.jpg", index: 0) == "IMG_01.jpg")
    }

    @Test func `custom format fills in counter, date and original name`() {
        var rule = RenameRule()
        rule.mode = .custom
        rule.format = "#original-#counter-#date"
        rule.counterStart = 5
        let date = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 UTC
        let name = rule.newName(for: "beach.png", index: 1, date: date)
        #expect(name.hasPrefix("beach-6-2023-11-1"))
        #expect(name.hasSuffix(".png"))
    }

    @Test func `invalid input is reported`() {
        var rule = RenameRule()
        #expect(rule.validate() == .missing)
        rule.mode = .custom
        rule.format = "a/b"
        #expect(rule.validate() == .invalidCharacter("/"))
        rule.format = "ok_#counter"
        #expect(rule.validate() == nil)
    }

    @Test func `renames files in place without overwriting`() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "stash-rename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appending(path: "a.txt"), b = dir.appending(path: "b.txt"), taken = dir.appending(path: "new_2.txt")
        for url in [a, b, taken] { try Data("x".utf8).write(to: url) }
        var rule = RenameRule()
        rule.mode = .custom
        rule.format = "new_#counter"
        let renamed = try FileOperations.batchRename([a, b], rule: rule)
        #expect(renamed.map(\.lastPathComponent) == ["new_1.txt", "new_2 2.txt"])
        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(FileManager.default.fileExists(atPath: taken.path))
    }
}
