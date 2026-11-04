import SwiftUI
import PDFKit
import VisionKit

enum PDFMaker {
    /// Filters each page and adds it to a PDF, one page at a time.
    static func make(_ images: [UIImage], filter: ScanFilter, brightness: Double, contrast: Double) -> PDFDocument {
        let document = PDFDocument()
        for image in images {
            autoreleasepool {
                let processed = ScanProcessor.apply(image, filter: filter, brightness: brightness, contrast: contrast)
                if let page = PDFPage(image: processed) {
                    document.insert(page, at: document.pageCount)
                }
            }
        }
        return document
    }
}

struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void
    var onError: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

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
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onFinish(images)
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onError?(error.localizedDescription)
            parent.dismiss()
        }
    }
}

final class PDFReader: ObservableObject {
    let view = PDFView()
    private(set) var url: URL?

    @discardableResult
    func open(_ url: URL, page: Int = 0) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let document = PDFDocument(url: url) else {
            self.url = nil
            view.document = nil
            return false
        }
        self.url = url
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        if document.pageCount > 0 {
            let safePage = min(max(page, 0), document.pageCount - 1)
            if let target = document.page(at: safePage) { view.go(to: target) }
        }
        return true
    }

    var currentPage: Int {
        guard let page = view.currentPage, let index = view.document?.index(for: page) else { return 0 }
        return max(0, index)
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
    @State private var loadFailed = false
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var shareFile: ShareFile?
    @State private var shareFailed = false
    let item: Item

    /// The stored item is the source of truth, so a rename shows up immediately.
    private var current: Item {
        store.library.items.first { $0.id == item.id } ?? item
    }

    private func startRename() {
        newTitle = current.title
        renaming = true
    }

    private func rename() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var updated = current
        updated.title = title
        store.update(updated)
    }

    private func share() {
        if let url = store.exportCopy(of: current) {
            shareFile = ShareFile(url: url)
        } else {
            shareFailed = true
        }
    }

    var body: some View {
        PDFRepresentable(view: reader.view)
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottomLeading) {
                if let subject = item.subjectID { MiniPlayer(subject: subject) }
            }
            .navigationTitle(current.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: startRename) {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel(Text("تغيير الاسم"))

                    Button(action: share) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(Text("مشاركة"))
                }
            }
            .onAppear {
                loadFailed = !reader.open(store.url(for: item), page: Int(item.progress ?? 0))
            }
            .onDisappear {
                store.setProgress(Double(reader.currentPage), for: item.id)
            }
            .sheet(item: $shareFile) { ShareSheet(url: $0.url) }
            .alert("تغيير الاسم", isPresented: $renaming) {
                TextField("اسم الملف", text: $newTitle)
                Button("حفظ") { rename() }
                Button("إلغاء", role: .cancel) {}
            }
            .alert("تعذر فتح المستند", isPresented: $loadFailed) {
                Button("حسنًا", role: .cancel) {}
            } message: {
                Text("الملف غير موجود أو تالف، حاول استيراده مرة أخرى.")
            }
            .alert("تعذرت المشاركة", isPresented: $shareFailed) {
                Button("حسنًا", role: .cancel) {}
            } message: {
                Text("تعذر تجهيز الملف للمشاركة.")
            }
    }
}
