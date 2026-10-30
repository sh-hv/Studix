import SwiftUI
import PDFKit
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

final class PDFReader: ObservableObject {
    let view = PDFView()
    var url: URL?

    func open(_ url: URL, page: Int = 0) {
        self.url = url
        view.document = PDFDocument(url: url)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        if page > 0, let target = view.document?.page(at: page) { view.go(to: target) }
    }

    var currentPage: Int {
        guard let page = view.currentPage, let index = view.document?.index(for: page) else { return 0 }
        return index
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
}

struct PDFRepresentable: UIViewRepresentable {
    let view: PDFView
    func makeUIView(context: Context) -> PDFView { view }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}

struct PDFScreen: View {
    @EnvironmentObject var store: Store
    @StateObject var reader = PDFReader()
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
                    Button { reader.highlight() } label: { Image(systemName: "highlighter") }
                    ShareLink(item: store.url(for: item))
                }
            }
            .onAppear { reader.open(store.url(for: item), page: Int(item.progress ?? 0)) }
            .onDisappear {
                reader.save()
                store.setProgress(Double(reader.currentPage), for: item.id)
            }
    }
}
