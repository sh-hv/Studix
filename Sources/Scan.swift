import SwiftUI
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
        return UIGraphicsImageRenderer(size: size).image { _ in
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
}

struct ScanEditor: View {
    @Environment(\.dismiss) var dismiss
    @State var pages: [UIImage]
    @State var thumbs: [UIImage]
    @State var filter = ScanFilter.document
    @State var brightness = 0.0
    @State var contrast = 1.0
    @State var current = 0
    let onSave: ([UIImage]) -> Void

    init(pages: [UIImage], onSave: @escaping ([UIImage]) -> Void) {
        _pages = State(initialValue: pages)
        _thumbs = State(initialValue: pages.map { $0.preparingThumbnail(of: CGSize(width: 900, height: 1300)) ?? $0 })
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TabView(selection: $current) {
                    ForEach(thumbs.indices, id: \.self) { index in
                        Image(uiImage: ScanProcessor.apply(thumbs[index], filter: filter, brightness: brightness, contrast: contrast))
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
            .navigationTitle("\(thumbs.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("حفظ") { save() } }
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) { removeCurrent() } label: { Image(systemName: "trash") }
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
        current = min(current, pages.count - 1)
    }

    func save() {
        onSave(pages.map { ScanProcessor.apply($0, filter: filter, brightness: brightness, contrast: contrast) })
        dismiss()
    }
}
