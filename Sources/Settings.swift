import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @AppStorage("lockEnabled") var lockEnabled = false
    @State var backupURL: URL?
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
                Button { makeBackup() } label: { Label("إنشاء نسخة احتياطية", systemImage: "archivebox.fill") }
                if let backupURL {
                    ShareLink(item: backupURL) { Label("حفظ أو مشاركة النسخة", systemImage: "square.and.arrow.up") }
                }
                Button { importing = true } label: { Label("استرجاع من نسخة", systemImage: "arrow.counterclockwise") }
            } header: {
                Text("النسخ الاحتياطي")
            } footer: {
                Text("تُحفظ كل مواد الدراسة والمستندات والتسجيلات والملاحظات في ملف مضغوط واحد.")
            }

            Section {
                Toggle(isOn: $lockEnabled) { Label("قفل التطبيق بـ Face ID", systemImage: "faceid") }
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
            backupURL = try store.backup()
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
            message = "تم الاسترجاع بنجاح"
        } catch {
            message = error.localizedDescription
        }
    }
}
