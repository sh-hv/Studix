import SwiftUI
import PDFKit
import ZIPFoundation

enum ItemKind: String, Codable, CaseIterable, Identifiable {
    case document, recording, note

    var id: String { rawValue }
    var title: String {
        switch self {
        case .document: return Lang.tr("المستندات")
        case .recording: return Lang.tr("التسجيلات")
        case .note: return Lang.tr("الملاحظات")
        }
    }
    var icon: String {
        switch self {
        case .document: return "doc.text.fill"
        case .recording: return "waveform"
        case .note: return "pencil.and.scribble"
        }
    }
}

struct Subject: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var colorIndex: Int
    var theory: Grade?
    var practical: Grade?
}

struct Grade: Codable, Hashable {
    var max: Double
    var score: Double?

    static func fmt(_ value: Double) -> String {
        guard value.isFinite, abs(value) < 1e12 else { return "–" }
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%d", locale: Lang.locale, Int(value))
            : String(format: "%.1f", locale: Lang.locale, value)
    }

    var text: String {
        let got = score.map(Grade.fmt) ?? "–"
        return got + "/" + Grade.fmt(max)
    }
}

extension Subject {
    var gradeSummary: String? {
        var parts: [String] = []
        if let theory { parts.append(Lang.tr("نظري") + " " + theory.text) }
        if let practical { parts.append(Lang.tr("عملي") + " " + practical.text) }
        if let theory, let practical, let a = theory.score, let b = practical.score {
            parts.append(Lang.tr("المجموع") + " " + Grade.fmt(a + b) + "/" + Grade.fmt(theory.max + practical.max))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct Item: Identifiable, Codable, Hashable {
    var id = UUID()
    var subjectID: UUID?
    var kind: ItemKind
    var title: String
    var file: String
    var date = Date()
    var marks: [Double]?
    var template: String?
    var text: String?
    var progress: Double?
    var favorite: Bool?
}

/// Decodes one array element without failing the whole array when that element is unreadable
/// (for example an item kind written by a newer version of the app).
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

struct Library: Codable {
    var version = 1
    var subjects: [Subject] = []
    var items: [Item] = []
    var deadlines: [Deadline]? = []
    var todos: [TodoItem]? = []

    private enum CodingKeys: String, CodingKey { case version, subjects, items, deadlines, todos }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        subjects = (try values.decodeIfPresent([Lossy<Subject>].self, forKey: .subjects) ?? []).compactMap(\.value)
        items = (try values.decodeIfPresent([Lossy<Item>].self, forKey: .items) ?? []).compactMap(\.value)
        deadlines = (try values.decodeIfPresent([Lossy<Deadline>].self, forKey: .deadlines) ?? []).compactMap(\.value)
        todos = (try values.decodeIfPresent([Lossy<TodoItem>].self, forKey: .todos) ?? []).compactMap(\.value)
    }
}

enum BackupError: LocalizedError {
    case invalid
    case persistence
    case missingFile(String)
    case rollback(String)

    var errorDescription: String? {
        switch self {
        case .invalid: return Lang.tr("الملف ليس نسخة احتياطية صالحة")
        case .persistence: return Lang.tr("تعذر حفظ البيانات قبل إنشاء النسخة الاحتياطية")
        case .missingFile(let name): return Lang.tr("النسخة الاحتياطية تفتقد الملف: %@", name)
        case .rollback(let path): return Lang.tr("تعذر إكمال الاستعادة. احتفظنا ببياناتك السابقة في %@", path)
        }
    }
}

enum Lang {
    static var code: String { UserDefaults.standard.string(forKey: "appLanguage") ?? "system" }

    static var resolved: String {
        if code != "system" { return code }
        return Locale.preferredLanguages.first?.hasPrefix("en") == true ? "en" : "ar"
    }

    /// System-owned UI (Edit button, search field, keyboard menus) follows the app's
    /// AppleLanguages preference, which iOS reads at launch. Keep it in sync with the chosen language.
    static func applySystemLanguage() {
        let defaults = UserDefaults.standard
        if code == "system" {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([code], forKey: "AppleLanguages")
        }
    }

    static var locale: Locale { Locale(identifier: resolved) }
    static var direction: LayoutDirection { resolved == "ar" ? .rightToLeft : .leftToRight }

    static var bundle: Bundle {
        Bundle.main.path(forResource: resolved, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let template = resolved == "ar" ? key : bundle.localizedString(forKey: key, value: key, table: nil)
        return args.isEmpty ? template : String(format: template, locale: locale, arguments: args)
    }
}

private var languageBundleKey: UInt8 = 0

final class LanguageBundle: Bundle {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &languageBundleKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    static func setLanguage(_ code: String) {
        object_setClass(Bundle.main, LanguageBundle.self)
        let path = Bundle.main.path(forResource: code, ofType: "lproj")
        objc_setAssociatedObject(Bundle.main, &languageBundleKey, path.flatMap(Bundle.init(path:)), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

extension Date {
    func styled(_ date: Date.FormatStyle.DateStyle, _ time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time).locale(Lang.locale))
    }
}

func dateStamp() -> String {
    Date().formatted(.dateTime.day().month().hour().minute().locale(Lang.locale))
}

func defaultTitle(_ prefix: String) -> String {
    Lang.tr(prefix) + " " + dateStamp()
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var library = Library()
    @Published private(set) var persistenceError: String?

    static let root = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Data", isDirectory: true)

    private var indexURL: URL { Self.root.appendingPathComponent("index.json") }

    init() {
        do {
            try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
        } catch {
            persistenceError = error.localizedDescription
        }
        cleanShareFolders()
        load()
    }

    private var backupIndexURL: URL { Self.root.appendingPathComponent("index.previous.json") }

    func load() {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            library = Library()
            return
        }
        do {
            let data = try Data(contentsOf: indexURL)
            library = try JSONDecoder().decode(Library.self, from: data)
            persistenceError = nil
        } catch {
            // Keep the unreadable file so a failed decode never silently destroys user data.
            let preserved = Self.root.appendingPathComponent("index-corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: indexURL, to: preserved)
            if let previousData = try? Data(contentsOf: backupIndexURL),
               let previous = try? JSONDecoder().decode(Library.self, from: previousData) {
                library = previous
                persistenceError = Lang.tr("تعذر قراءة بياناتك فاستعدنا آخر نسخة سليمة. قد تفقد آخر تعديلات فقط.")
            } else {
                library = Library()
                persistenceError = Lang.tr("تعذر قراءة بياناتك. احتفظنا بالملف الأصلي في %@", preserved.lastPathComponent)
            }
        }
        migrateInlineText()
        syncReminders()
    }

    /// Older versions stored OCR text inside index.json. Move it to its own files so the index stays small.
    private func migrateInlineText() {
        var changed = false
        for index in library.items.indices {
            guard let text = library.items[index].text else { continue }
            if !text.isEmpty { setText(text, for: library.items[index].id) }
            library.items[index].text = nil
            changed = true
        }
        if changed { save() }
    }

    func dismissPersistenceError() {
        persistenceError = nil
    }

    func reportError(_ message: String) {
        persistenceError = message
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(library)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                try? FileManager.default.removeItem(at: backupIndexURL)
                try? FileManager.default.copyItem(at: indexURL, to: backupIndexURL)
            }
            try data.write(to: indexURL, options: .atomic)
            persistenceError = nil
            return true
        } catch {
            persistenceError = error.localizedDescription
            return false
        }
    }

    func url(for item: Item) -> URL { Self.root.appendingPathComponent(item.file) }

    /// Copies an item's file to a temporary folder under a readable name (the item title),
    /// so sharing shows "Physics Notes.pdf" instead of the internal UUID file name.
    func exportCopy(of item: Item) -> URL? {
        let fm = FileManager.default
        let source = url(for: item)
        guard fm.fileExists(atPath: source.path) else { return nil }
        let folder = fm.temporaryDirectory.appendingPathComponent("Share-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder
                .appendingPathComponent(Self.readableFileName(item.title))
                .appendingPathExtension(source.pathExtension)
            try fm.copyItem(at: source, to: target)
            return target
        } catch {
            return nil
        }
    }

    private static func readableFileName(_ title: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters)
        let cleaned = title
            .components(separatedBy: illegal)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Studix" : String(cleaned.prefix(80))
    }

    private func cleanShareFolders() {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory
        let names = (try? fm.contentsOfDirectory(atPath: temp.path)) ?? []
        for name in names where name.hasPrefix("Share-") || (name.hasPrefix("Studix-") && name.hasSuffix(".zip")) {
            try? fm.removeItem(at: temp.appendingPathComponent(name))
        }
    }

    func newFile(ext: String) -> String { "\(UUID().uuidString).\(ext)" }
    func subject(_ id: UUID?) -> Subject? { library.subjects.first { $0.id == id } }

    func items(_ kind: ItemKind, subject: UUID? = nil) -> [Item] {
        library.items
            .filter { $0.kind == kind && (subject == nil || $0.subjectID == subject) }
            .sorted { first, second in
                let a = first.favorite ?? false
                let b = second.favorite ?? false
                return a != b ? a : first.date > second.date
            }
    }

    func add(_ item: Item) {
        library.items.append(item)
        save()
    }

    func update(_ item: Item) {
        guard let index = library.items.firstIndex(where: { $0.id == item.id }) else { return }
        library.items[index] = item
        save()
    }

    func delete(_ item: Item) {
        if item.kind == .note,
           let data = try? Data(contentsOf: url(for: item)),
           let note = try? JSONDecoder().decode(NoteContent.self, from: data) {
            for file in note.blocks.compactMap(\.file) {
                try? FileManager.default.removeItem(at: Self.root.appendingPathComponent(file))
            }
        }
        try? FileManager.default.removeItem(at: url(for: item))
        try? FileManager.default.removeItem(at: textURL(item.id))
        textCache[item.id] = nil
        library.items.removeAll { $0.id == item.id }
        save()
    }

    func addSubject(name: String, colorIndex: Int) {
        library.subjects.append(Subject(name: name, colorIndex: colorIndex))
        save()
    }

    var todos: [TodoItem] { library.todos ?? [] }

    func addTodo(_ todo: TodoItem) {
        library.todos = (library.todos ?? []) + [todo]
        save()
        syncReminders()
    }

    func toggleTodo(_ todo: TodoItem) {
        guard let index = library.todos?.firstIndex(where: { $0.id == todo.id }) else { return }
        library.todos?[index].done.toggle()
        save()
        syncReminders()
    }

    func deleteTodo(_ todo: TodoItem) {
        library.todos?.removeAll { $0.id == todo.id }
        save()
        syncReminders()
    }

    func toggleFavorite(_ item: Item) {
        guard let index = library.items.firstIndex(where: { $0.id == item.id }) else { return }
        library.items[index].favorite = !(library.items[index].favorite ?? false)
        save()
    }

    func addSubject(_ subject: Subject) {
        library.subjects.append(subject)
        save()
    }

    func updateSubject(_ subject: Subject) {
        guard let index = library.subjects.firstIndex(where: { $0.id == subject.id }) else { return }
        library.subjects[index] = subject
        save()
    }

    func setProgress(_ value: Double, for id: UUID) {
        guard let index = library.items.firstIndex(where: { $0.id == id }) else { return }
        library.items[index].progress = value
        save()
    }

    func deleteSubject(_ subject: Subject) {
        library.subjects.removeAll { $0.id == subject.id }
        for index in library.items.indices where library.items[index].subjectID == subject.id {
            library.items[index].subjectID = nil
        }
        for index in (library.deadlines ?? []).indices where library.deadlines?[index].subjectID == subject.id {
            library.deadlines?[index].subjectID = nil
        }
        for index in (library.todos ?? []).indices where library.todos?[index].subjectID == subject.id {
            library.todos?[index].subjectID = nil
        }
        save()
    }

    var deadlines: [Deadline] {
        (library.deadlines ?? []).sorted { $0.due < $1.due }
    }

    /// Adds a deadline, or replaces the one with the same id.
    func saveDeadline(_ deadline: Deadline) {
        var list = library.deadlines ?? []
        if let index = list.firstIndex(where: { $0.id == deadline.id }) {
            list[index] = deadline
        } else {
            list.append(deadline)
        }
        library.deadlines = list
        save()
        syncReminders()
    }

    func deleteDeadline(_ deadline: Deadline) {
        library.deadlines?.removeAll { $0.id == deadline.id }
        save()
        syncReminders()
    }

    func syncReminders() {
        Reminders.rescheduleAll(deadlines: deadlines, todos: todos)
    }

    // MARK: Search text (OCR and note text) lives in its own files, outside index.json.

    private var textCache: [UUID: String] = [:]
    private var textDirectory: URL { Self.root.appendingPathComponent("Text", isDirectory: true) }
    private func textURL(_ id: UUID) -> URL { textDirectory.appendingPathComponent("\(id.uuidString).txt") }

    func hasIndexedText(_ id: UUID) -> Bool {
        textCache[id] != nil || FileManager.default.fileExists(atPath: textURL(id).path)
    }

    func searchText(for id: UUID) -> String {
        if let cached = textCache[id] { return cached }
        // Missing files are not cached, so "not indexed yet" stays distinguishable from "no text".
        guard let text = try? String(contentsOf: textURL(id), encoding: .utf8) else { return "" }
        textCache[id] = text
        return text
    }

    func setText(_ text: String, for id: UUID) {
        guard library.items.contains(where: { $0.id == id }) else { return }
        textCache[id] = text
        // The search index can always be rebuilt, so a failed write is not worth alarming the user.
        try? FileManager.default.createDirectory(at: textDirectory, withIntermediateDirectories: true)
        try? text.write(to: textURL(id), atomically: true, encoding: .utf8)
    }

    /// Indexes notes and documents that were created before search text had its own storage,
    /// or whose indexing was interrupted (for example, the app was closed during OCR).
    func indexPending() async {
        for item in library.items where item.kind == .note && !hasIndexedText(item.id) {
            if let data = try? Data(contentsOf: url(for: item)),
               let note = try? JSONDecoder().decode(NoteContent.self, from: data) {
                setText(note.plainText, for: item.id)
            }
        }
        for item in library.items where item.kind == .document && !hasIndexedText(item.id) {
            guard let document = PDFDocument(url: url(for: item)) else { continue }
            let text = await OCR.text(from: document)
            setText(text, for: item.id)
        }
    }

    /// Removes a freshly created note if the user left without writing anything.
    func pruneIfEmpty(_ item: Item) {
        guard item.kind == .note, library.items.contains(where: { $0.id == item.id }) else { return }
        if let data = try? Data(contentsOf: url(for: item)) {
            guard let note = try? JSONDecoder().decode(NoteContent.self, from: data), note.isEmpty else { return }
        }
        delete(item)
    }

    func backup() async throws -> URL {
        guard save() else { throw BackupError.persistence }
        let stamp = Date().formatted(.iso8601.year().month().day())
        let root = Self.root
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Studix-\(stamp)-\(UUID().uuidString.prefix(8)).zip")
        // Zipping can take a while with long recordings, so keep it off the main thread.
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.zipItem(at: root, to: destination, shouldKeepParent: false)
        }.value
        return destination
    }

    /// Restores a backup. Returns how many library entries were skipped because their file was missing from the archive.
    @discardableResult
    func restore(from zip: URL) async throws -> Int {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("Studix-Restore-\(UUID().uuidString)", isDirectory: true)
        let previous = fm.temporaryDirectory.appendingPathComponent("Studix-Previous-\(UUID().uuidString)", isDirectory: true)
        var preservePrevious = false
        defer {
            try? fm.removeItem(at: staging)
            if !preservePrevious { try? fm.removeItem(at: previous) }
        }

        // Unzipping and validation can be slow, so they run off the main thread.
        let prepared = try await Task.detached(priority: .userInitiated) {
            try Self.prepareRestore(zip: zip, staging: staging)
        }.value

        // Swap only after the archive and all referenced files have been validated.
        let hadCurrentData = fm.fileExists(atPath: Self.root.path)
        if hadCurrentData { try fm.moveItem(at: Self.root, to: previous) }
        do {
            try fm.moveItem(at: staging, to: Self.root)
        } catch {
            if hadCurrentData, !fm.fileExists(atPath: Self.root.path) {
                do {
                    try fm.moveItem(at: previous, to: Self.root)
                } catch {
                    preservePrevious = true
                    throw BackupError.rollback(previous.path)
                }
            }
            throw error
        }

        library = prepared.library
        textCache.removeAll()
        persistenceError = nil
        migrateInlineText()
        if prepared.skipped > 0 { save() }
        // Replaces every pending notification, so reminders of the data we just replaced disappear.
        syncReminders()
        return prepared.skipped
    }

    nonisolated private static func prepareRestore(zip: URL, staging: URL) throws -> (library: Library, skipped: Int) {
        let fm = FileManager.default
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let archive: Archive
        do {
            archive = try Archive(url: zip, accessMode: .read)
        } catch {
            throw BackupError.invalid
        }
        var entryCount = 0
        var expandedBytes: UInt64 = 0
        for entry in archive {
            entryCount += 1
            let (newTotal, overflow) = expandedBytes.addingReportingOverflow(entry.uncompressedSize)
            expandedBytes = newTotal
            let components = entry.path.split(separator: "/")
            guard !overflow,
                  entryCount <= 10_000,
                  expandedBytes <= 1_500_000_000,
                  entry.type != .symlink,
                  !entry.path.hasPrefix("/"),
                  !entry.path.contains("\\"),
                  !components.contains(".."),
                  !components.contains(".") else {
                throw BackupError.invalid
            }
        }
        guard entryCount > 0 else { throw BackupError.invalid }
        try fm.unzipItem(at: zip, to: staging)

        let stagedIndex = staging.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: stagedIndex),
              var restored = try? JSONDecoder().decode(Library.self, from: data),
              restored.version <= 1 else {
            throw BackupError.invalid
        }

        // An entry whose file is missing is skipped instead of rejecting the whole backup.
        // Unsafe file names are still rejected outright.
        var kept: [Item] = []
        var skipped = 0
        for item in restored.items {
            guard isSafeFileName(item.file) else { throw BackupError.invalid }
            guard fm.fileExists(atPath: staging.appendingPathComponent(item.file).path) else {
                skipped += 1
                continue
            }
            if item.kind == .note,
               let noteData = try? Data(contentsOf: staging.appendingPathComponent(item.file)),
               let note = try? JSONDecoder().decode(NoteContent.self, from: noteData) {
                for file in note.blocks.compactMap(\.file) where !isSafeFileName(file) {
                    throw BackupError.invalid
                }
            }
            kept.append(item)
        }
        restored.items = kept
        return (restored, skipped)
    }

    nonisolated private static func isSafeFileName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else { return false }
        return URL(fileURLWithPath: name).lastPathComponent == name
    }
}
