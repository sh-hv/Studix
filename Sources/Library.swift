import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

struct SubjectsView: View {
    @EnvironmentObject var store: Store
    @State var adding = false
    @State var query = ""
    @State var editingSubject: Subject?
    let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            if query.isEmpty {
                DeadlinesCard()
                TasksCard()
            }
            if !query.isEmpty {
                SearchResults(query: query)
            } else if store.library.subjects.isEmpty {
                EmptyState(icon: "square.grid.2x2", text: "أضف موادك الدراسية لتجمع ملفاتها وتسجيلاتها وملاحظاتها في مكان واحد")
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(store.library.subjects) { subject in
                        NavigationLink(value: subject) { SubjectCard(subject: subject) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { editingSubject = subject } label: { Label("تعديل المادة", systemImage: "pencil") }
                                Button(role: .destructive) { store.deleteSubject(subject) } label: {
                                    Label("حذف المادة", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Studix")
        .searchable(text: $query, prompt: "ابحث في كل ملفاتك")
        .navigationDestination(for: Subject.self) { SubjectDetail(subject: $0) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }
        }
        .sheet(isPresented: $adding) { SubjectSheet() }
        .sheet(item: $editingSubject) { SubjectSheet(subject: $0) }
    }
}

struct SubjectCard: View {
    @EnvironmentObject var store: Store
    let subject: Subject

    var body: some View {
        let count = store.library.items.filter { $0.subjectID == subject.id }.count
        let tint = Theme.color(subject.colorIndex)
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "book.closed.fill")
                .font(.title2)
                .padding(10)
                .background(.white.opacity(0.22), in: Circle())
            Spacer(minLength: 18)
            Text(subject.name).font(.headline).lineLimit(2)
            Text("\(count) عنصر").font(.caption).opacity(0.85)
            if let summary = subject.gradeSummary {
                Text(summary).font(.caption2.weight(.semibold)).opacity(0.95)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(colors: [tint, tint.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: tint.opacity(0.3), radius: 10, y: 5)
    }
}

struct SubjectDetail: View {
    let subject: Subject
    @State var kind = ItemKind.document

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $kind) {
                ForEach(ItemKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()
            ItemListView(kind: kind, subject: subject.id).id(kind)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(subject.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

func parseNumber(_ text: String) -> Double? {
    let digits = Array("٠١٢٣٤٥٦٧٨٩")
    var result = ""
    for character in text.replacingOccurrences(of: "٫", with: ".").replacingOccurrences(of: ",", with: ".") {
        if let index = digits.firstIndex(of: character) {
            result.append(String(index))
        } else {
            result.append(character)
        }
    }
    return Double(result)
}

struct GradeFields {
    var max = ""
    var score = ""

    init(_ grade: Grade?) {
        guard let grade else { return }
        max = Grade.fmt(grade.max)
        score = grade.score.map(Grade.fmt) ?? ""
    }

    var grade: Grade? {
        guard let maxValue = parseNumber(max), maxValue > 0 else { return nil }
        return Grade(max: maxValue, score: parseNumber(score))
    }
}

struct SubjectSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State var subject: Subject
    @State var theoryOn: Bool
    @State var practicalOn: Bool
    @State var theory: GradeFields
    @State var practical: GradeFields
    let isNew: Bool

    init(subject: Subject? = nil) {
        let base = subject ?? Subject(name: "", colorIndex: 0)
        _subject = State(initialValue: base)
        _theoryOn = State(initialValue: base.theory != nil)
        _practicalOn = State(initialValue: base.practical != nil)
        _theory = State(initialValue: GradeFields(base.theory))
        _practical = State(initialValue: GradeFields(base.practical))
        isNew = subject == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("اسم المادة", text: $subject.name)
                Section("اللون") {
                    HStack {
                        ForEach(Theme.palette.indices, id: \.self) { index in
                            Circle()
                                .fill(Theme.palette[index])
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(.primary, lineWidth: subject.colorIndex == index ? 3 : 0).padding(-4))
                                .onTapGesture { subject.colorIndex = index }
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                Section("الدرجات (اختياري)") {
                    Toggle("إضافة نظري", isOn: $theoryOn)
                    if theoryOn { fields($theory) }
                    Toggle("إضافة عملي", isOn: $practicalOn)
                    if practicalOn { fields($practical) }
                }
            }
            .navigationTitle(LocalizedStringKey(isNew ? "مادة جديدة" : "تعديل المادة"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey(isNew ? "إضافة" : "حفظ")) { save() }
                        .disabled(subject.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    func fields(_ binding: Binding<GradeFields>) -> some View {
        HStack {
            TextField("الدرجة العظمى", text: binding.max).keyboardType(.decimalPad)
            Divider()
            TextField("حصلت عليها", text: binding.score).keyboardType(.decimalPad)
        }
    }

    func save() {
        subject.name = subject.name.trimmingCharacters(in: .whitespaces)
        subject.theory = theoryOn ? theory.grade : nil
        subject.practical = practicalOn ? practical.grade : nil
        if isNew { store.addSubject(subject) } else { store.updateSubject(subject) }
        dismiss()
    }
}

struct ItemListView: View {
    @EnvironmentObject var store: Store
    let kind: ItemKind
    var subject: UUID? = nil

    @State var filter: UUID?
    @State var editing: Item?
    @State var opened: Item?
    @State var showScanner = false
    @State var showRecorder = false
    @State var showPhotos = false
    @State var showImporter = false
    @State var photos: [PhotosPickerItem] = []
    @State var batch: ScanBatch?

    var active: UUID? { subject ?? filter }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if subject == nil && !store.library.subjects.isEmpty { chips }
                let items = store.items(kind, subject: active)
                if items.isEmpty {
                    EmptyState(icon: kind.icon, text: "لا يوجد شيء هنا بعد. اضغط + للبدء")
                        .padding(.top, 60)
                } else {
                    ForEach(items) { item in
                        NavigationLink(value: item) { ItemCard(item: item) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { store.toggleFavorite(item) } label: {
                                    Label(LocalizedStringKey(item.favorite == true ? "إزالة من المفضلة" : "إضافة للمفضلة"), systemImage: "star")
                                }
                                Button { editing = item } label: { Label("تعديل", systemImage: "pencil") }
                                Button(role: .destructive) { store.delete(item) } label: {
                                    Label("حذف", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .padding(.horizontal)
        }
        .background(Color(.systemGroupedBackground))
        .navigationDestination(for: Item.self) { ItemDestination(item: $0) }
        .toolbar { ToolbarItem(placement: .primaryAction) { addButton } }
        .sheet(item: $editing) { EditItemSheet(item: $0) }
        .sheet(isPresented: $showScanner) {
            DocumentScanner { images in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { batch = ScanBatch(images: images) }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $batch) { batch in
            ScanEditor(pages: batch.images) { savePDF(PDFMaker.make($0)) }
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showRecorder) { RecorderView(subject: active) }
        .fullScreenCover(item: $opened) { item in
            NavigationStack {
                NoteEditor(item: item)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("تم") { opened = nil } }
                    }
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photos, matching: .images)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { importPDF($0) }
        .onChange(of: photos) { picked in loadPhotos(picked) }
    }

    var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                chip(Lang.tr("الكل"), id: nil)
                ForEach(store.library.subjects) { chip($0.name, id: $0.id) }
            }
        }
        .padding(.top, 8)
    }

    func chip(_ title: String, id: UUID?) -> some View {
        let selected = filter == id
        return Text(title)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Theme.accent : Color(.secondarySystemGroupedBackground), in: Capsule())
            .onTapGesture { filter = id }
    }

    @ViewBuilder var addButton: some View {
        if kind == .recording {
            Button { showRecorder = true } label: { Image(systemName: "mic.circle.fill").font(.title3) }
        } else {
            Menu {
                if kind == .document {
                    Button { showScanner = true } label: { Label("مسح بالكاميرا", systemImage: "doc.viewfinder") }
                    Button { showPhotos = true } label: { Label("صور من الألبوم", systemImage: "photo.on.rectangle") }
                    Button { showImporter = true } label: { Label("استيراد PDF", systemImage: "square.and.arrow.down") }
                } else {
                    Button { newNote("blank") } label: { Label("ورقة فارغة", systemImage: "doc") }
                    Button { newNote("ruled") } label: { Label("ورقة مسطّرة", systemImage: "text.alignleft") }
                    Button { newNote("grid") } label: { Label("ورقة مربعات", systemImage: "squareshape.split.3x3") }
                }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title3)
            }
        }
    }

    func savePDF(_ document: PDFDocument) {
        let file = store.newFile(ext: "pdf")
        guard document.write(to: Store.root.appendingPathComponent(file)) else { return }
        let item = Item(subjectID: active, kind: .document, title: defaultTitle("مستند"), file: file)
        store.add(item)
        index(item, document)
    }

    func index(_ item: Item, _ document: PDFDocument) {
        Task {
            let text = await OCR.text(from: document)
            if !text.isEmpty { store.setText(text, for: item.id) }
        }
    }

    func loadPhotos(_ picked: [PhotosPickerItem]) {
        guard !picked.isEmpty else { return }
        Task {
            var images: [UIImage] = []
            for entry in picked {
                if let data = try? await entry.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            photos = []
            if !images.isEmpty { batch = ScanBatch(images: images) }
        }
    }

    func importPDF(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let file = store.newFile(ext: "pdf")
        guard (try? FileManager.default.copyItem(at: url, to: Store.root.appendingPathComponent(file))) != nil else { return }
        let item = Item(subjectID: active, kind: .document, title: url.deletingPathExtension().lastPathComponent, file: file)
        store.add(item)
        if let document = PDFDocument(url: Store.root.appendingPathComponent(file)) { index(item, document) }
    }

    func newNote(_ template: String) {
        let item = Item(subjectID: active, kind: .note, title: defaultTitle("ملاحظة"), file: store.newFile(ext: "note"), template: template)
        store.add(item)
        opened = item
    }
}

struct ItemCard: View {
    @EnvironmentObject var store: Store
    let item: Item

    var body: some View {
        let subject = store.subject(item.subjectID)
        let tint = subject.map { Theme.color($0.colorIndex) } ?? Theme.accent
        let date = item.date.styled(.abbreviated, .omitted)
        HStack(spacing: 14) {
            Image(systemName: item.kind.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.headline).lineLimit(1)
                Text(subject.map { "\($0.name) · \(date)" } ?? date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.favorite == true { Image(systemName: "star.fill").foregroundStyle(.yellow) }
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct ItemDestination: View {
    let item: Item

    var body: some View {
        switch item.kind {
        case .document: PDFScreen(item: item)
        case .recording: PlayerView(item: item)
        case .note: NoteEditor(item: item)
        }
    }
}

struct EditItemSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State var item: Item

    var body: some View {
        NavigationStack {
            Form {
                TextField("العنوان", text: $item.title)
                Picker("المادة", selection: $item.subjectID) {
                    Text("بدون مادة").tag(UUID?.none)
                    ForEach(store.library.subjects) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            .navigationTitle("تعديل")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { store.update(item); dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

struct EmptyState: View {
    let icon: String
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
                .frame(width: 88, height: 88)
                .background(Theme.accent.opacity(0.12), in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
    }
}
