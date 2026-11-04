import SwiftUI
import PDFKit
import CoreImage

enum ScanFilter: String, CaseIterable, Identifiable {
    case original, document, gray, blackWhite

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .original: return "أصلي"
        case .document: return "مستند"
        case .gray: return "رمادي"
        case .blackWhite: return "أبيض وأسود"
        }
    }
}

struct ScanBatch: Identifiable {
    let id = UUID()
    let images: [UIImage]
}

extension UIImage {
    var upright: UIImage {
        guard imageOrientation != .up else { return self }
        // Render at the image's own scale. The renderer's default is the screen scale (3x),
        // which would make a 12 MP photo about nine times larger in memory.
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

enum ScanProcessor {
    static let context = CIContext()

    static func apply(_ image: UIImage, filter: ScanFilter, brightness: Double, contrast: Double) -> UIImage {
        let source = image.upright
        guard let cgImage = source.cgImage else { return image }
        var output = CIImage(cgImage: cgImage)
        switch filter {
        case .original:
            break
        case .document:
            output = output.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.2, kCIInputContrastKey: 1.3, kCIInputBrightnessKey: 0.05
            ])
        case .gray:
            output = output.applyingFilter("CIPhotoEffectMono")
        case .blackWhite:
            output = output.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0, kCIInputContrastKey: 2.4, kCIInputBrightnessKey: 0.1
            ])
        }
        output = output.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: brightness, kCIInputContrastKey: contrast
        ])
        guard let result = context.createCGImage(output, from: output.extent) else { return image }
        return UIImage(cgImage: result)
    }

    /// Applies the filters to several images off the main thread.
    static func render(_ images: [UIImage], filter: ScanFilter, brightness: Double, contrast: Double) async -> [UIImage] {
        await Task.detached(priority: .userInitiated) {
            images.map { apply($0, filter: filter, brightness: brightness, contrast: contrast) }
        }.value
    }
}

struct ScanEditor: View {
    @Environment(\.dismiss) var dismiss
    @State var pages: [UIImage]
    @State var thumbs: [UIImage]
    @State var previews: [UIImage]
    @State var filter = ScanFilter.document
    @State var brightness = 0.0
    @State var contrast = 1.0
    @State var current = 0
    @State var saving = false
    let onSave: (PDFDocument) async -> Void

    init(pages: [UIImage], onSave: @escaping (PDFDocument) async -> Void) {
        let small = pages.map { $0.preparingThumbnail(of: CGSize(width: 900, height: 1300)) ?? $0 }
        _pages = State(initialValue: pages)
        _thumbs = State(initialValue: small)
        _previews = State(initialValue: small)
        self.onSave = onSave
    }

    private var renderKey: String {
        "\(filter.rawValue)|\(brightness)|\(contrast)|\(thumbs.count)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TabView(selection: $current) {
                    ForEach(previews.indices, id: \.self) { index in
                        Image(uiImage: previews[index])
                            .resizable()
                            .scaledToFit()
                            .padding(.horizontal)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page)
                .frame(maxHeight: .infinity)

                Picker("", selection: $filter) {
                    ForEach(ScanFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 6) {
                    HStack {
                        Text("السطوع").font(.caption).frame(width: 70, alignment: .leading)
                        Slider(value: $brightness, in: -0.3...0.3)
                    }
                    HStack {
                        Text("التباين").font(.caption).frame(width: 70, alignment: .leading)
                        Slider(value: $contrast, in: 0.7...1.6)
                    }
                }
            }
            .padding()
            .disabled(saving)
            .overlay {
                if saving {
                    ProgressView()
                        .controlSize(.large)
                        .padding(26)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            // Filters are applied to small previews off the main thread, and only when a setting changes.
            .task(id: renderKey) {
                let snapshot = thumbs
                let chosen = filter
                let chosenBrightness = brightness
                let chosenContrast = contrast
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
                let rendered = await ScanProcessor.render(snapshot, filter: chosen, brightness: chosenBrightness, contrast: chosenContrast)
                guard !Task.isCancelled, rendered.count == thumbs.count else { return }
                previews = rendered
            }
            .navigationTitle("\(thumbs.count) صفحة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { save() }.disabled(saving)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) { removeCurrent() } label: { Image(systemName: "trash") }
                        .disabled(saving)
                        .accessibilityLabel(Text("حذف الصفحة"))
                }
            }
        }
    }

    func removeCurrent() {
        guard pages.count > 1 else {
            dismiss()
            return
        }
        pages.remove(at: current)
        thumbs.remove(at: current)
        if previews.indices.contains(current) { previews.remove(at: current) }
        current = min(current, pages.count - 1)
    }

    func save() {
        guard !saving else { return }
        saving = true
        let images = pages
        let chosen = filter
        let chosenBrightness = brightness
        let chosenContrast = contrast
        Task { @MainActor in
            // Pages are processed and written one at a time off the main thread to keep memory low.
            let document = await Task.detached(priority: .userInitiated) {
                PDFMaker.make(images, filter: chosen, brightness: chosenBrightness, contrast: chosenContrast)
            }.value
            await onSave(document)
            dismiss()
        }
    }
}
