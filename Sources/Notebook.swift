import SwiftUI
import PencilKit

struct PageInfo: Codable, Identifiable, Hashable {
    var id = UUID()
    var file: String
    var template: String
}

struct NotebookContent: Codable {
    var pages: [PageInfo] = []
}

struct NoteRouter: View {
    let item: Item

    var body: some View {
        if item.file.hasSuffix(".nb") {
            NotebookEditor(item: item)
        } else {
            NoteEditor(item: item)
        }
    }
}

struct NotebookEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) var phase
    @State var pages: [PageInfo] = []
    @State var index = 0
    @State var drawing = PKDrawing()
    @State var loaded = false
    @State var fingerDraws = true
    @State var canvasSize = CGSize(width: 390, height: 700)
    @State var shareItem: ShareFile?
    let item: Item

    var page: PageInfo? { pages.indices.contains(index) ? pages[index] : nil }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    if let page {
                        PaperBackground(template: page.template)
                        CanvasView(drawing: $drawing, anyInput: fingerDraws).id(page.id)
                    }
                }
                .onAppear { canvasSize = geometry.size }
                .onChange(of: geometry.size) { canvasSize = $0 }
            }
            bar
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
        .onAppear(perform: load)
        .onDisappear(perform: save)
        .onChange(of: phase) { if $0 != .active { save() } }
    }

    var bar: some View {
        HStack(spacing: 18) {
            Button { go(index - 1) } label: { Image(systemName: "chevron.backward") }
                .disabled(index == 0)
            Text("\(index + 1) / \(pages.count)").font(.subheadline.monospacedDigit())
            Button { go(index + 1) } label: { Image(systemName: "chevron.forward") }
                .disabled(index >= pages.count - 1)
            Spacer()
            Button { addPage() } label: { Label("إضافة صفحة", systemImage: "plus.square.on.square") }
                .labelStyle(.iconOnly)
            Menu {
                Picker("القالب", selection: Binding(get: { page?.template ?? "blank" }, set: { setTemplate($0) })) {
                    Text("فارغ").tag("blank")
                    Text("مسطّر").tag("ruled")
                    Text("مربعات").tag("grid")
                    Text("منقّط").tag("dots")
                    Text("كورنيل").tag("cornell")
                }
                Toggle("الرسم بالإصبع", isOn: $fingerDraws)
                Button { move(-1) } label: { Label("نقل للأمام", systemImage: "arrow.up") }
                    .disabled(index == 0)
                Button { move(1) } label: { Label("نقل للخلف", systemImage: "arrow.down") }
                    .disabled(index >= pages.count - 1)
                Button { exportPDF() } label: { Label("تصدير PDF", systemImage: "square.and.arrow.up") }
                Button(role: .destructive) { deletePage() } label: { Label("حذف الصفحة", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    func pageURL(_ page: PageInfo) -> URL { Store.root.appendingPathComponent(page.file) }

    func load() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: store.url(for: item)),
           let content = try? JSONDecoder().decode(NotebookContent.self, from: data), !content.pages.isEmpty {
            pages = content.pages
        } else {
            pages = [PageInfo(file: store.newFile(ext: "drawing"), template: "ruled")]
        }
        loadPage()
    }

    func loadPage() {
        guard let page, let data = try? Data(contentsOf: pageURL(page)), let stored = try? PKDrawing(data: data) else {
            drawing = PKDrawing()
            return
        }
        drawing = stored
    }

    func savePage() {
        guard let page else { return }
        try? drawing.dataRepresentation().write(to: pageURL(page), options: .atomic)
    }

    func save() {
        guard loaded else { return }
        savePage()
        if let data = try? JSONEncoder().encode(NotebookContent(pages: pages)) {
            try? data.write(to: store.url(for: item), options: .atomic)
        }
    }

    func go(_ target: Int) {
        guard pages.indices.contains(target) else { return }
        savePage()
        index = target
        loadPage()
    }

    func addPage() {
        savePage()
        pages.insert(PageInfo(file: store.newFile(ext: "drawing"), template: page?.template ?? "ruled"), at: index + 1)
        index += 1
        drawing = PKDrawing()
    }

    func setTemplate(_ template: String) {
        guard pages.indices.contains(index) else { return }
        pages[index].template = template
    }

    func move(_ offset: Int) {
        let target = index + offset
        guard pages.indices.contains(target) else { return }
        savePage()
        pages.swapAt(index, target)
        index = target
    }

    func deletePage() {
        guard let page else { return }
        try? FileManager.default.removeItem(at: pageURL(page))
        pages.remove(at: index)
        if pages.isEmpty { pages = [PageInfo(file: store.newFile(ext: "drawing"), template: "ruled")] }
        index = min(index, pages.count - 1)
        loadPage()
    }

    func exportPDF() {
        savePage()
        let size = canvasSize
        let area = CGRect(origin: .zero, size: size)
        let renderer = UIGraphicsPDFRenderer(bounds: area)
        let data = renderer.pdfData { context in
            for info in pages {
                context.beginPage()
                UIColor.white.setFill()
                UIRectFill(area)
                let cg = context.cgContext
                cg.addPath(paperPath(info.template, size: size).cgPath)
                cg.setStrokeColor(UIColor.gray.withAlphaComponent(0.4).cgColor)
                cg.setLineWidth(1)
                cg.strokePath()
                if let raw = try? Data(contentsOf: pageURL(info)), let stored = try? PKDrawing(data: raw), !stored.bounds.isEmpty {
                    var image = UIImage()
                    UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                        image = stored.image(from: area, scale: 2)
                    }
                    image.draw(in: area)
                }
            }
        }
        let name = item.title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".pdf")
        try? data.write(to: url)
        shareItem = ShareFile(url: url)
    }
}
