import SwiftUI
import UniformTypeIdentifiers

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State var shareItem: ShareFile?
    @State var pickedURL: URL?
    @State var importing = false
    @State var confirming = false
    @State var message: String?

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        Form {
            Section {
                Button { makeBackup() } label: { Label("نسخ احتياطي وحفظ الملف", systemImage: "archivebox.fill") }
                Button { importing = true } label: { Label("استرجاع من نسخة", systemImage: "arrow.counterclockwise") }
            } header: {
                Text("النسخ الاحتياطي")
            } footer: {
                Text("تُحفظ كل مواد الدراسة والمستندات والتسجيلات والملاحظات في ملف مضغوط واحد.")
            }

            Section("الإحصائيات") {
                LabeledContent("المواد", value: "\(store.library.subjects.count)")
                ForEach(ItemKind.allCases) { kind in
                    LabeledContent(kind.title, value: "\(store.items(kind).count)")
                }
            }

            Section {
                LabeledContent("الإصدار", value: version)
            }
        }
        .navigationTitle("الإعدادات")
        .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result {
                pickedURL = url
                confirming = true
            }
        }
        .confirmationDialog("استرجاع نسخة احتياطية", isPresented: $confirming, titleVisibility: .visible) {
            Button("استبدال البيانات الحالية", role: .destructive) { restore() }
        } message: {
            Text("سيتم استبدال كل بياناتك الحالية بمحتوى النسخة.")
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("حسنًا", role: .cancel) {}
        }
    }

    func makeBackup() {
        do {
            shareItem = ShareFile(url: try store.backup())
        } catch {
            message = error.localizedDescription
        }
    }

    func restore() {
        guard let url = pickedURL else { return }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            try store.restore(from: url)
            message = String(localized: "تم الاسترجاع بنجاح")
        } catch {
            message = error.localizedDescription
        }
    }
}
