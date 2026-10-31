import SwiftUI
import PDFKit
import VisionKit

enum PDFMaker {
    static func make(_ images: [UIImage]) -> PDFDocument {
        let document = PDFDocument()
        for image in images {
            guard let page = PDFPage(image: image) else { continue }
            document.insert(page, at: document.pageCount)
        }
        return document
    }
}

struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void
    var onError: ((String) -> Void)? = nil
    @Environment(\\.dismiss) private var dismiss

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

    func highlight() {
        guard let selection = view.currentSelection else { return }
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let annotation = PDFAnnotation(bounds: line.bounds(for: page), forType: .highlight, withProperties: nil)
                annotation.color = UIColor.systemYellow.withAlphaComponent(0.45)
                page.addAnnotation(annotation)
            }
        }
        view.clearSelection()
    }

    @discardableResult
    func save() -> Bool {
        guard let url, let document = view.document else { return false }
        return document.write(to: url)
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
    @State private var saveFailed = false
    @State private var isMarkupMode = false
    let item: Item

    private func toggleMarkupMode() {
        guard reader.view.document != nil else { return }

        if isMarkupMode {
            // Leave markup mode before writing so PDFKit can finish committing annotations.
            reader.view.isInMarkupMode = false
            isMarkupMode = false
            saveFailed = !reader.save()
        } else {
            reader.view.isInMarkupMode = true
            isMarkupMode = true
        }
    }

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
                    Button(action: toggleMarkupMode) {
                        Label(
                            isMarkupMode ? "إنهاء التعديل" : "تعديل",
                            systemImage: isMarkupMode ? "checkmark" : "pencil"
                        )
                    }
                    .disabled(reader.view.document == nil)

                    Button { reader.highlight() } label: { Image(systemName: "highlighter") }
                        .disabled(reader.view.document == nil)

                    ShareLink(item: store.url(for: item))
                        .disabled(!FileManager.default.fileExists(atPath: store.url(for: item).path))
                }
            }
            .onAppear {
                loadFailed = !reader.open(store.url(for: item), page: Int(item.progress ?? 0))
                isMarkupMode = reader.view.isInMarkupMode
            }
            .onDisappear {
                reader.view.isInMarkupMode = false
                _ = reader.save()
                store.setProgress(Double(reader.currentPage), for: item.id)
            }
            .alert("تعذر فتح المستند", isPresented: $loadFailed) {
                Button("حسناً", role: .cancel) {}
            } message: {
                Text("الملف غير موجود أو تالف، حاول استيراده مرة أخرى.")
            }
            .alert("تعذر حفظ التعديلات", isPresented: $saveFailed) {
                Button("حسناً", role: .cancel) {}
            } message: {
                Text("لم نتمكن من حفظ التعديلات على ملف PDF. تأكد من توفر مساحة تخزين كافية ثم حاول مرة أخرى.")
            }
    }
}
