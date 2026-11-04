import SwiftUI
import PencilKit
import PhotosUI
import Charts

struct PaperBackground: View {
    let template: String

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 32
            var path = Path()
            if template == "ruled" || template == "grid" {
                for y in stride(from: step * 2, to: size.height, by: step) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            if template == "grid" {
                for x in stride(from: step, to: size.width, by: step) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
            }
            context.stroke(path, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea()
    }
}

struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        let picker = PKToolPicker()
        picker.addObserver(canvas)
        picker.setVisible(true, forFirstResponder: canvas)
        context.coordinator.picker = picker
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: CanvasView
        var picker: PKToolPicker?
        init(_ parent: CanvasView) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

enum BlockKind: String, Codable {
    case heading, text, bullet, todo, table, chart, image, drawing
}

struct Block: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: BlockKind
    var text = ""
    var done = false
    var rows: [[String]] = []
    var file: String?
    var style: String?
    var rev: Int?
}

struct NoteContent: Codable {
    var blocks: [Block] = []

    /// Text that search can match: typed text plus table and chart cells.
    var plainText: String {
        blocks
            .flatMap { block -> [String] in
                switch block.kind {
                case .table, .chart: return block.rows.flatMap { $0 }
                case .image, .drawing: return []
                default: return [block.text]
                }
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    /// True when the note holds nothing the user wrote, drew or attached.
    var isEmpty: Bool {
        blocks.allSatisfy { block in
            switch block.kind {
            case .image, .drawing: return block.file == nil
            case .table, .chart: return block.rows.allSatisfy { $0.allSatisfy { $0.isEmpty } }
            default: return block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }
}

struct NoteEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) var phase
    @State var blocks: [Block] = []
    @State var loaded = false
    @State var drawingBlock: Block?
    @State var pickingImage = false
    @State var pickedImage: PhotosPickerItem?
    @State var corrupted = false
    @State var saveError: String?
    @State var errorShown = false
    let item: Item

    var body: some View {
        List {
            ForEach($blocks) { $block in
                BlockRow(block: $block) { drawingBlock = block }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove { blocks.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { offsets in
                offsets.forEach { discard(blocks[$0]) }
                blocks.remove(atOffsets: offsets)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background { PaperBackground(template: item.template ?? "blank") }
        .overlay {
            if corrupted {
                EmptyState(icon: "exclamationmark.triangle", text: "تعذر قراءة هذه الملاحظة. حفظنا نسخة من الملف الأصلي ولن نكتب فوقه")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                EditButton()
                Menu {
                    Button { add(.heading) } label: { Label("عنوان", systemImage: "textformat.size") }
                    Button { add(.text) } label: { Label("نص", systemImage: "text.alignleft") }
                    Button { add(.bullet) } label: { Label("نقاط", systemImage: "list.bullet") }
                    Button { add(.todo) } label: { Label("مهام", systemImage: "checklist") }
                    Button { add(.table) } label: { Label("جدول", systemImage: "tablecells") }
                    Button { add(.chart) } label: { Label("مخطط", systemImage: "chart.bar.xaxis") }
                    Button { pickingImage = true } label: { Label("صورة", systemImage: "photo") }
                    Button { add(.drawing) } label: { Label("رسم", systemImage: "pencil.tip.crop.circle") }
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(corrupted)
                .accessibilityLabel(Text("إضافة عنصر"))
            }
        }
        .alert("تعذر حفظ الملاحظة", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .photosPicker(isPresented: $pickingImage, selection: $pickedImage, matching: .images)
        .onChange(of: pickedImage) { picked in loadImage(picked) }
        .fullScreenCover(item: $drawingBlock) { target in
            DrawingEditor(block: target, template: item.template ?? "blank") { name in
                guard let index = blocks.firstIndex(where: { $0.id == target.id }) else { return }
                blocks[index].file = name
                blocks[index].rev = (blocks[index].rev ?? 0) + 1
            }
        }
        .onAppear(perform: load)
        .onDisappear {
            save()
            indexText()
        }
        .onChange(of: blocks) { _ in save() }
        .onChange(of: phase) {
            if $0 != .active {
                save()
                indexText()
            }
        }
    }

    func reportSaveError(_ error: Error) {
        // One alert per editing session is enough; a full disk would otherwise alert on every keystroke.
        guard !errorShown else { return }
        errorShown = true
        saveError = error.localizedDescription
    }

    func indexText() {
        guard loaded, !corrupted else { return }
        store.setText(NoteContent(blocks: blocks).plainText, for: item.id)
    }

    func starter() -> [Block] { [Block(kind: .heading), Block(kind: .text)] }

    func load() {
        guard !loaded else { return }
        loaded = true
        let fileURL = store.url(for: item)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            blocks = starter()
            return
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            corrupted = true
            return
        }
        if let note = try? JSONDecoder().decode(NoteContent.self, from: data) {
            blocks = note.blocks
        } else if (try? PKDrawing(data: data)) != nil {
            let file = store.newFile(ext: "drawing")
            do {
                try data.write(to: Store.root.appendingPathComponent(file), options: .atomic)
                blocks = [Block(kind: .drawing, file: file)]
            } catch {
                corrupted = true
                reportSaveError(error)
            }
        } else {
            // Never replace an unreadable note with an empty one: keep a copy and stop autosaving.
            let copy = fileURL.appendingPathExtension("corrupt")
            if !FileManager.default.fileExists(atPath: copy.path) {
                try? FileManager.default.copyItem(at: fileURL, to: copy)
            }
            corrupted = true
        }
    }

    func save() {
        guard loaded, !corrupted else { return }
        do {
            let data = try JSONEncoder().encode(NoteContent(blocks: blocks))
            try data.write(to: store.url(for: item), options: .atomic)
        } catch {
            reportSaveError(error)
        }
    }

    func add(_ kind: BlockKind) {
        var block = Block(kind: kind)
        if kind == .table { block.rows = [["", "", ""], ["", "", ""], ["", "", ""]] }
        if kind == .chart {
            block.rows = [["", ""], ["", ""], ["", ""]]
            block.style = "bar"
        }
        blocks.append(block)
        if kind == .drawing { drawingBlock = block }
    }

    func loadImage(_ picked: PhotosPickerItem?) {
        guard let picked else { return }
        Task {
            if let data = try? await picked.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                let small = image.preparingThumbnail(of: CGSize(width: 1600, height: 1600)) ?? image
                if let jpeg = small.jpegData(compressionQuality: 0.8) {
                    let file = store.newFile(ext: "jpg")
                    do {
                        try jpeg.write(to: Store.root.appendingPathComponent(file), options: .atomic)
                        blocks.append(Block(kind: .image, file: file))
                    } catch {
                        reportSaveError(error)
                    }
                }
            }
            pickedImage = nil
        }
    }

    func discard(_ block: Block) {
        guard let file = block.file else { return }
        try? FileManager.default.removeItem(at: Store.root.appendingPathComponent(file))
    }
}

struct BlockRow: View {
    @Binding var block: Block
    let openDrawing: () -> Void

    var body: some View {
        content
            .buttonStyle(.borderless)
            .padding(.vertical, 4)
    }

    @ViewBuilder var content: some View {
        switch block.kind {
        case .heading:
            TextField("عنوان", text: $block.text, axis: .vertical).font(.title2.bold())
        case .text:
            TextField("اكتب هنا", text: $block.text, axis: .vertical)
        case .bullet:
            HStack(alignment: .firstTextBaseline) {
                Text("•").bold()
                TextField("نقطة", text: $block.text, axis: .vertical)
            }
        case .todo:
            HStack(alignment: .firstTextBaseline) {
                Button { block.done.toggle() } label: {
                    Image(systemName: block.done ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.accent)
                }
                TextField("مهمة", text: $block.text, axis: .vertical)
                    .strikethrough(block.done)
                    .foregroundStyle(block.done ? Color.secondary : Color.primary)
            }
        case .table:
            TableBlockView(block: $block)
        case .chart:
            ChartBlockView(block: $block)
        case .image:
            if let file = block.file, let image = UIImage(contentsOfFile: Store.root.appendingPathComponent(file).path) {
                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .drawing:
            Button(action: openDrawing) { DrawingPreview(file: block.file).id(block.rev ?? 0) }
        }
    }
}

struct DrawingPreview: View {
    let file: String?

    var image: UIImage? {
        guard let file,
              let data = try? Data(contentsOf: Store.root.appendingPathComponent(file)),
              let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty else { return nil }
        // The preview sits on a white card, so always render the ink for light mode.
        var rendered: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            rendered = drawing.image(from: drawing.bounds.insetBy(dx: -16, dy: -16), scale: 2)
        }
        return rendered
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Label("اضغط للرسم", systemImage: "pencil.tip").foregroundStyle(.secondary).frame(height: 120)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.secondary.opacity(0.25)))
    }
}

struct DrawingEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State var drawing = PKDrawing()
    @State var saveFailed = false
    let block: Block
    let template: String
    let onDone: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground(template: template)
                CanvasView(drawing: $drawing)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("تم") { finish() } }
            }
            .alert("تعذر حفظ الرسم", isPresented: $saveFailed) {
                Button("حسنًا", role: .cancel) {}
            } message: {
                Text("تأكد من توفر مساحة تخزين كافية ثم حاول مرة أخرى.")
            }
            .onAppear {
                if let file = block.file,
                   let data = try? Data(contentsOf: Store.root.appendingPathComponent(file)),
                   let stored = try? PKDrawing(data: data) {
                    drawing = stored
                }
            }
        }
    }

    func finish() {
        let name = block.file ?? store.newFile(ext: "drawing")
        do {
            try drawing.dataRepresentation().write(to: Store.root.appendingPathComponent(name), options: .atomic)
        } catch {
            saveFailed = true
            return
        }
        onDone(name)
        dismiss()
    }
}

struct TableBlockView: View {
    @Binding var block: Block

    var columns: Int { block.rows.first?.count ?? 0 }

    /// Bounds-checked binding: SwiftUI can ask for a cell right after its row or column was deleted.
    private func cell(_ row: Int, _ column: Int) -> Binding<String> {
        Binding(
            get: {
                guard block.rows.indices.contains(row), block.rows[row].indices.contains(column) else { return "" }
                return block.rows[row][column]
            },
            set: { value in
                guard block.rows.indices.contains(row), block.rows[row].indices.contains(column) else { return }
                block.rows[row][column] = value
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(block.rows.indices, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(block.rows[row].indices, id: \.self) { column in
                                TextField("", text: cell(row, column))
                                    .font(row == 0 ? .subheadline.bold() : .subheadline)
                                    .padding(.horizontal, 8)
                                    .frame(width: 100, height: 42)
                                    .background(row == 0 ? Theme.accent.opacity(0.12) : Color.clear)
                                    .overlay(Rectangle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                            }
                        }
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            HStack(spacing: 16) {
                Button { block.rows.append(Array(repeating: "", count: columns)) } label: { Label("صف", systemImage: "plus") }
                Button { if block.rows.count > 1 { block.rows.removeLast() } } label: { Label("صف", systemImage: "minus") }
                Button { for index in block.rows.indices { block.rows[index].append("") } } label: { Label("عمود", systemImage: "plus") }
                Button {
                    if columns > 1 { for index in block.rows.indices { block.rows[index].removeLast() } }
                } label: { Label("عمود", systemImage: "minus") }
            }
            .font(.footnote)
            .labelStyle(.titleAndIcon)
        }
    }
}

struct ChartBlockView: View {
    @Binding var block: Block

    private func cell(_ row: Int, _ column: Int) -> Binding<String> {
        Binding(
            get: {
                guard block.rows.indices.contains(row), block.rows[row].indices.contains(column) else { return "" }
                return block.rows[row][column]
            },
            set: { value in
                guard block.rows.indices.contains(row), block.rows[row].indices.contains(column) else { return }
                block.rows[row][column] = value
            }
        )
    }

    var points: [(label: String, value: Double)] {
        block.rows.compactMap { row in
            guard row.count > 1, let value = parseNumber(row[1]) else { return nil }
            return (row[0].isEmpty ? "–" : row[0], value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: Binding(get: { block.style ?? "bar" }, set: { block.style = $0 })) {
                Text("أعمدة").tag("bar")
                Text("خطي").tag("line")
            }
            .pickerStyle(.segmented)
            if points.isEmpty {
                Text("أدخل أرقامك في البيانات").font(.footnote).foregroundStyle(.secondary)
            } else {
                Chart(points.indices, id: \.self) { index in
                    if block.style == "line" {
                        LineMark(x: .value("x", points[index].label), y: .value("y", points[index].value))
                            .symbol(.circle)
                    } else {
                        BarMark(x: .value("x", points[index].label), y: .value("y", points[index].value))
                    }
                }
                .foregroundStyle(Theme.accent)
                .frame(height: 200)
            }
            DisclosureGroup("البيانات") {
                ForEach(block.rows.indices, id: \.self) { index in
                    HStack {
                        TextField("الاسم", text: cell(index, 0))
                        TextField("القيمة", text: cell(index, 1)).keyboardType(.decimalPad)
                    }
                }
                HStack(spacing: 16) {
                    Button { block.rows.append(["", ""]) } label: { Label("صف", systemImage: "plus") }
                    Button { if block.rows.count > 1 { block.rows.removeLast() } } label: { Label("صف", systemImage: "minus") }
                }
                .font(.footnote)
            }
        }
    }
}
