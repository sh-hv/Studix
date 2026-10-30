import SwiftUI
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
        value.truncatingRemainder(dividingBy: 1) == 0
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
        subjects = try values.decodeIfPresent([Subject].self, forKey: .subjects) ?? []
        items = try values.decodeIfPresent([Item].self, forKey: .items) ?? []
        deadlines = try values.decodeIfPresent([Deadline].self, forKey: .deadlines) ?? []
        todos = try values.decodeIfPresent([TodoItem].self, forKey: .todos) ?? []
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
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            library = Library()
            return
        }
        do {
            let data = try Data(contentsOf: indexURL)
            library = try JSONDecoder().decode(Library.self, from: data)
            persistenceError = nil
            Reminders.reschedule(deadlines: deadlines, todos: todos)
        } catch {
            // Keep the unreadable file so a failed decode never silently destroys user data.
            let preserved = Self.root.appendingPathComponent("index-corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: indexURL, to: preserved)
            library = Library()
            persistenceError = Lang.tr("تعذر قراءة بياناتك. احتفظنا بالملف الأصلي في %@", preserved.lastPathComponent)
        }
    }

    func dismissPersistenceError() {
        persistenceError = nil
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(library)
            try data.write(to: indexURL, options: .atomic)
            persistenceError = nil
            return true
        } catch {
            persistenceError = error.localizedDescription
            return false
        }
    }

    func url(for item: Item) -> URL { Self.root.appendingPathComponent(item.file) }
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
    }

    func toggleTodo(_ todo: TodoItem) {
        guard let index = library.todos?.firstIndex(where: { $0.id == todo.id }) else { return }
        library.todos?[index].done.toggle()
        if let updated = library.todos?.first(where: { $0.id == todo.id }) {
            if updated.done { Reminders.cancelTask(updated) }
            else { Reminders.scheduleTask(updated) }
        }
        save()
    }

    func deleteTodo(_ todo: TodoItem) {
        Reminders.cancelTask(todo)
        library.todos?.removeAll { $0.id == todo.id }
        save()
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
        save()
    }

    var deadlines: [Deadline] {
        (library.deadlines ?? []).sorted { $0.due < $1.due }
    }

    func addDeadline(_ deadline: Deadline) {
        library.deadlines = (library.deadlines ?? []) + [deadline]
        save()
    }

    func deleteDeadline(_ deadline: Deadline) {
        Reminders.cancel(deadline)
        library.deadlines?.removeAll { $0.id == deadline.id }
        save()
    }

    func setText(_ text: String, for id: UUID) {
        guard let index = library.items.firstIndex(where: { $0.id == id }) else { return }
        library.items[index].text = text
        save()
    }

    func backup() throws -> URL {
        guard save() else { throw BackupError.persistence }
        let stamp = Date().formatted(.iso8601.year().month().day())
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Studix-\(stamp)-\(UUID().uuidString.prefix(8)).zip")
        try FileManager.default.zipItem(at: Self.root, to: destination, shouldKeepParent: false)
        return destination
    }

    func restore(from zip: URL) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("Studix-Restore-\(UUID().uuidString)", isDirectory: true)
        let previous = fm.temporaryDirectory.appendingPathComponent("Studix-Previous-\(UUID().uuidString)", isDirectory: true)
        var preservePrevious = false
        defer {
            try? fm.removeItem(at: staging)
            if !preservePrevious { try? fm.removeItem(at: previous) }
        }

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
              let restored = try? JSONDecoder().decode(Library.self, from: data),
              isValid(restored, in: staging) else {
            throw BackupError.invalid
        }

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

        library = restored
        persistenceError = nil
        Reminders.reschedule(deadlines: deadlines, todos: todos)
    }

    private func isValid(_ candidate: Library, in directory: URL) -> Bool {
        guard candidate.version <= 1 else { return false }
        for item in candidate.items {
            guard Self.isSafeFileName(item.file),
                  FileManager.default.fileExists(atPath: directory.appendingPathComponent(item.file).path) else {
                return false
            }
            if item.kind == .note,
               let noteData = try? Data(contentsOf: directory.appendingPathComponent(item.file)),
               let note = try? JSONDecoder().decode(NoteContent.self, from: noteData) {
                for block in note.blocks {
                    if let file = block.file {
                        guard Self.isSafeFileName(file),
                              FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path) else {
                            return false
                        }
                    }
                }
            }
        }
        return true
    }

    private static func isSafeFileName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else { return false }
        return URL(fileURLWithPath: name).lastPathComponent == name
    }
}
