import Foundation
import ZIPFoundation

enum ItemKind: String, Codable, CaseIterable, Identifiable {
    case document, recording, note

    var id: String { rawValue }
    var title: String {
        switch self {
        case .document: return "المستندات"
        case .recording: return "التسجيلات"
        case .note: return "الملاحظات"
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
}

struct Library: Codable {
    var version = 1
    var subjects: [Subject] = []
    var items: [Item] = []
    var deadlines: [Deadline]?
}

enum BackupError: LocalizedError {
    case invalid
    var errorDescription: String? { "الملف ليس نسخة احتياطية صالحة" }
}

func defaultTitle(_ prefix: String) -> String {
    prefix + " " + Date().formatted(.dateTime.day().month().hour().minute())
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
            .sorted { $0.date > $1.date }
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
        try? FileManager.default.removeItem(at: url(for: item))
        library.items.removeAll { $0.id == item.id }
        save()
    }

    func addSubject(name: String, colorIndex: Int) {
        library.subjects.append(Subject(name: name, colorIndex: colorIndex))
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
