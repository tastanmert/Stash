import Foundation
import FoundationModels

/// "Intelligent Shelf Names": asks the on-device model for a short title when the files clearly
/// belong together. Nothing leaves the Mac; without Apple Intelligence the count title stays.
enum TitleGenerator {
    static func suggestTitle(for model: ShelfModel) {
        guard Prefs.bool(Pref.intelligentNames), model.customName == nil, model.items.count > 1, model.folderGroup == nil else {
            model.generatedName = nil
            return
        }
        guard #available(macOS 26.0, *), SystemLanguageModel.default.availability == .available else { return }
        let names = model.items.prefix(20).map(\.displayName)
        let language = Locale.preferredLanguages.first?.hasPrefix("tr") == true ? "Turkish" : "English"
        Task {
            let session = LanguageModelSession(instructions: """
                You name groups of files. Reply with a title of one to three words in \(language), \
                with no quotes or punctuation. If the files do not clearly belong together, reply with NONE.
                """)
            guard let reply = try? await session.respond(to: "Files: " + names.joined(separator: ", ")) else { return }
            let title = reply.content.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard !title.isEmpty, title.uppercased() != "NONE", title.count <= 40,
                  model.items.prefix(20).map(\.displayName) == names else { return }
            model.generatedName = title
        }
    }
}
