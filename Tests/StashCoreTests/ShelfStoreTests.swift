import Foundation
import Testing
@testable import StashCore

struct ShelfStoreTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "stash-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func file(_ name: String) throws -> String {
        let url = dir.appending(path: name)
        try Data("x".utf8).write(to: url)
        return url.path
    }

    @Test func `recent list is newest first and capped`() throws {
        var store = ShelfStore()
        let path = try file("a.txt")
        for _ in 0..<(ShelfStore.maxRecent + 3) { store.addRecent(ShelfRecord(paths: [path])) }
        #expect(store.recent.count == ShelfStore.maxRecent)
        let newest = ShelfRecord(paths: [path])
        store.addRecent(newest)
        #expect(store.recent.first?.id == newest.id)
    }

    @Test func `empty shelves are not remembered`() {
        var store = ShelfStore()
        store.addRecent(ShelfRecord(paths: []))
        #expect(store.recent.isEmpty)
    }

    @Test func `reopen skips shelves whose files are gone`() throws {
        var store = ShelfStore()
        let kept = ShelfRecord(paths: [try file("kept.txt")])
        store.addRecent(kept)
        store.addRecent(ShelfRecord(paths: [dir.appending(path: "missing.txt").path]))
        #expect(store.popLastRestorable()?.id == kept.id)
        #expect(store.recent.isEmpty)
    }

    @Test func `round trips through JSON`() throws {
        var store = ShelfStore()
        store.addRecent(ShelfRecord(name: "Raf", paths: [try file("b.txt")], colorIndex: 2))
        store.setPinned(ShelfRecord(paths: [try file("c.txt")], pinned: true))
        let url = dir.appending(path: "shelves.json")
        try store.save(to: url)
        #expect(ShelfStore.load(from: url) == store)
    }

    @Test func `unique URL numbers duplicates`() throws {
        _ = try file("Note.txt")
        #expect(StashPaths.uniqueURL(in: dir, name: "Note.txt").lastPathComponent == "Note 2.txt")
        #expect(StashPaths.uniqueURL(in: dir, name: "New.txt").lastPathComponent == "New.txt")
    }

    @Test func `titles name a single item or count by kind`() {
        let plural: (Int, ShelfTitle.Kind?) -> String = { n, kind in "\(n) \(kind.map { "\($0)" } ?? "files")" }
        #expect(ShelfTitle.make(names: ["a.png"], kinds: [.image], plural: plural) == "a.png")
        #expect(ShelfTitle.make(names: ["a.png", "b.png"], kinds: [.image, .image], plural: plural) == "2 image")
        #expect(ShelfTitle.make(names: ["a.png", "b.txt"], kinds: [.image, .text], plural: plural) == "2 files")
    }

    @Test func `items from one folder are named after it and their main kind`() {
        let group = ShelfTitle.folderGroup(parents: ["dragtest", "dragtest", "dragtest"], kinds: [.image, .image, .text])
        #expect(group?.folder == "dragtest")
        #expect(group?.kind == .image)
        #expect(ShelfTitle.folderGroup(parents: ["a", "a"], kinds: [.image, .text])?.kind == nil)
        #expect(ShelfTitle.folderGroup(parents: ["a", "b"], kinds: [.image, .image]) == nil)
        #expect(ShelfTitle.folderGroup(parents: ["a"], kinds: [.image]) == nil)
    }
}
