import SwiftUI
import PDFKit
import Vision

enum OCR {
    static func text(from document: PDFDocument) async -> String {
        await Task.detached(priority: .utility) {
            var parts: [String] = []
            var recognizedPages = 0
            for index in 0..<min(document.pageCount, 500) {
                guard let page = document.page(at: index) else { continue }
                // Pages that already contain text are cheap. Only image pages go through OCR, up to a cap.
                if let embedded = page.string, embedded.count > 20 {
                    parts.append(embedded)
                    continue
                }
                guard recognizedPages < 80 else { continue }
                recognizedPages += 1
                let image = page.thumbnail(of: CGSize(width: 1400, height: 1900), for: .mediaBox)
                parts.append(recognize(image))
            }
            return parts.joined(separator: "\n")
        }.value
    }

    static func recognize(_ image: UIImage) -> String {
        guard let cgImage = image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}

struct SearchResults: View {
    @EnvironmentObject var store: Store
    let query: String

    var matches: [Item] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return store.library.items
            .filter { $0.title.localizedCaseInsensitiveContains(term) || store.searchText(for: $0.id).localizedCaseInsensitiveContains(term) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        LazyVStack(spacing: 12) {
            if matches.isEmpty {
                EmptyState(icon: "magnifyingglass", text: "لا توجد نتائج").padding(.top, 60)
            } else {
                ForEach(matches) { item in
                    NavigationLink { ItemDestination(item: item) } label: { ItemCard(item: item) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }
}
