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
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
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
    var deadlines: [Deadline]?
    var todos: [TodoItem]?
}

enum BackupError: LocalizedError {
    case invalid
    var errorDescription: String? { Lang.tr("الملف ليس نسخة احتياطية صالحة") }
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
        return args.isEmpty ? template : String(format: template, arguments: args)
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

    static let root = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Data", isDirectory: true)

    private var indexURL: URL { Self.root.appendingPathComponent("index.json") }

    init() {
        try? FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let stored = try? JSONDecoder().decode(Library.self, from: data) else {
            library = Library()
            return
        }
        library = stored
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(library) else { return }
        try? data.write(to: indexURL, options: .atomic)
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
        if item.file.hasSuffix(".nb"),
           let data = try? Data(contentsOf: url(for: item)),
           let notebook = try? JSONDecoder().decode(NotebookContent.self, from: data) {
            for page in notebook.pages {
                try? FileManager.default.removeItem(at: Self.root.appendingPathComponent(page.file))
            }
        }
        if item.kind == .document {
            try? FileManager.default.removeItem(at: url(for: item).deletingPathExtension().appendingPathExtension("ink"))
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
        if library.todos?[index].done == true { Reminders.cancelTask(todo) }
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
        save()
        let stamp = Date().formatted(.iso8601.year().month().day())
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Studix-\(stamp).zip")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.zipItem(at: Self.root, to: destination, shouldKeepParent: false)
        return destination
    }

    func restore(from zip: URL) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try fm.unzipItem(at: zip, to: staging)
        guard fm.fileExists(atPath: staging.appendingPathComponent("index.json").path) else {
            throw BackupError.invalid
        }
        try? fm.removeItem(at: Self.root)
        try fm.moveItem(at: staging, to: Self.root)
        load()
    }
}
