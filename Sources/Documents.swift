import SwiftUI
import PDFKit
import PencilKit
import VisionKit

enum PDFMaker {
    static func make(_ images: [UIImage]) -> PDFDocument {
        let document = PDFDocument()
        for (index, image) in images.enumerated() {
            if let page = PDFPage(image: image) { document.insert(page, at: index) }
        }
        return document
    }
}

struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.dismiss()
        }
    }
}

final class PDFReader: NSObject, ObservableObject, PDFPageOverlayViewProvider {
    let view = PDFView()
    let picker = PKToolPicker()
    var url: URL?
    var ink: [Int: Data] = [:]
    var canvases: [PDFPage: PKCanvasView] = [:]

    @Published var inking = false {
        didSet { applyInking() }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func open(_ url: URL, page: Int = 0) {
        self.url = url
        loadInk()
        view.pageOverlayViewProvider = self
        view.document = PDFDocument(url: url)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        if page > 0, let target = view.document?.page(at: page) { view.go(to: target) }
        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: view)
    }

    var currentPage: Int {
        guard let page = view.currentPage, let index = view.document?.index(for: page) else { return 0 }
        return index
    }

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        if let existing = canvases[page] { return existing }
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.isUserInteractionEnabled = inking
        if let index = view.document?.index(for: page), let data = ink[index], let stored = try? PKDrawing(data: data) {
            canvas.drawing = stored
        }
        picker.addObserver(canvas)
        canvases[page] = canvas
        return canvas
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        guard let canvas = overlayView as? PKCanvasView else { return }
        keepInk(canvas, for: page)
    }

    func keepInk(_ canvas: PKCanvasView, for page: PDFPage) {
        guard let index = view.document?.index(for: page) else { return }
        ink[index] = canvas.drawing.strokes.isEmpty ? nil : canvas.drawing.dataRepresentation()
    }

    @objc func pageChanged() {
        if inking { focusCurrent() }
    }

    func focusCurrent() {
        guard let page = view.currentPage, let canvas = canvases[page] else { return }
        picker.setVisible(true, forFirstResponder: canvas)
        canvas.becomeFirstResponder()
    }

    func applyInking() {
        for canvas in canvases.values { canvas.isUserInteractionEnabled = inking }
        if inking {
            focusCurrent()
        } else {
            for canvas in canvases.values { canvas.resignFirstResponder() }
        }
    }

    func highlight() {
        guard let selection = view.currentSelection else { return }
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let annotation = PDFAnnotation(bounds: line.bounds(for: page), forType: .highlight, withProperties: nil)
                annotation.color = UIColor.systemYellow.withAlphaComponent(0.5)
                page.addAnnotation(annotation)
            }
        }
        view.clearSelection()
    }

    func save() {
        guard let url else { return }
        view.document?.write(to: url)
    }

    var inkURL: URL? { url?.deletingPathExtension().appendingPathExtension("ink") }

    func loadInk() {
        guard let inkURL, let data = try? Data(contentsOf: inkURL),
              let stored = try? JSONDecoder().decode([String: Data].self, from: data) else { return }
        ink = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in Int(key).map { ($0, value) } })
    }

    func collectInk() {
        for (page, canvas) in canvases { keepInk(canvas, for: page) }
    }

    func saveInk() {
        collectInk()
        guard let inkURL else { return }
        if ink.isEmpty {
            try? FileManager.default.removeItem(at: inkURL)
            return
        }
        let payload = Dictionary(uniqueKeysWithValues: ink.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(payload) { try? data.write(to: inkURL, options: .atomic) }
    }

    func exportAnnotated() -> URL? {
        guard let document = view.document else { return nil }
        collectInk()
        let renderer = UIGraphicsPDFRenderer(bounds: .zero)
        let data = renderer.pdfData { context in
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let area = CGRect(origin: .zero, size: bounds.size)
                context.beginPage(withBounds: area, pageInfo: [:])
                let cg = context.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: area.height)
                cg.scaleBy(x: 1, y: -1)
                page.draw(with: .mediaBox, to: cg)
                cg.restoreGState()
                if let raw = ink[index], let stored = try? PKDrawing(data: raw) {
                    var image = UIImage()
                    UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                        image = stored.image(from: area, scale: 2)
                    }
                    image.draw(in: area)
                }
            }
        }
        let name = url?.deletingPathExtension().lastPathComponent ?? "Studix"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Annotated-\(name).pdf")
        try? data.write(to: destination)
        return destination
    }
}

struct PDFRepresentable: UIViewRepresentable {
    let view: PDFView
    func makeUIView(context: Context) -> PDFView { view }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}

struct PDFScreen: View {
    @EnvironmentObject var store: Store
    @StateObject var reader = PDFReader()
    @State var shareItem: ShareFile?
    let item: Item

    var body: some View {
        PDFRepresentable(view: reader.view)
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottomLeading) {
                if let subject = item.subjectID { MiniPlayer(subject: subject) }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { reader.inking.toggle() } label: {
                        Image(systemName: reader.inking ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                    }
                    Button { reader.highlight() } label: { Image(systemName: "highlighter") }
                    Menu {
                        ShareLink(item: store.url(for: item)) { Label("مشاركة الملف الأصلي", systemImage: "doc") }
                        Button {
                            if let url = reader.exportAnnotated() { shareItem = ShareFile(url: url) }
                        } label: { Label("مشاركة مع الكتابة", systemImage: "pencil.and.outline") }
                    } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
            .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
            .onAppear { reader.open(store.url(for: item), page: Int(item.progress ?? 0)) }
            .onDisappear {
                reader.inking = false
                reader.save()
                reader.saveInk()
                store.setProgress(Double(reader.currentPage), for: item.id)
            }
    }
}
