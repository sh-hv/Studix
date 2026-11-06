import SwiftUI
import UniformTypeIdentifiers

struct XLogo: View {
    var body: some View {
        if UIImage(named: "XLogo") != nil {
            Image("XLogo").renderingMode(.template).resizable().scaledToFit().frame(width: 22, height: 22)
        } else {
            Image(systemName: "at").frame(width: 22, height: 22)
        }
    }
}

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
    @AppStorage("appLanguage") var language = "system"
    @State var shareItem: ShareFile?
    @State var pickedURL: URL?
    @State var importing = false
    @State var confirming = false
    @State var working = false
    @State var message: String?

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Spacer()
                        Text("v\(version)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                    Text("Studix").font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(.white)
                    Text("مساحتك الدراسية، مرتبة في مكان واحد")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Theme.accent, Color(red: 0.20, green: 0.58, blue: 0.72)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "النسخ الاحتياطي", subtitle: "احتفظ بنسخة من ملفاتك وملاحظاتك")
                    Button { makeBackup() } label: {
                        SettingsActionRow(icon: "archivebox.fill", title: "إنشاء نسخة احتياطية", detail: "تصدير بياناتك في ملف ZIP", tint: .indigo)
                    }
                    .buttonStyle(.plain)
                    Divider()
                    Button { importing = true } label: {
                        SettingsActionRow(icon: "arrow.down.doc.fill", title: "استعادة نسخة احتياطية", detail: "استرجاع بيانات من ملف سابق", tint: .teal)
                    }
                    .buttonStyle(.plain)
                }
                .studixSurface()

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "اللغة", subtitle: "اختر لغة واجهة التطبيق")
                    Picker("اللغة", selection: $language) {
                        Text("تلقائي (حسب الجوال)").tag("system")
                        Text("العربية").tag("ar")
                        Text("الإنجليزية").tag("en")
                    }
                    .pickerStyle(.segmented)
                    Text("لتحديث عناصر النظام مثل زر «تعديل» وحقل البحث، أعد فتح التطبيق بعد تغيير اللغة")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .studixSurface()

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "مساحة دراستك", subtitle: "ملخص المحتوى المحفوظ على هذا الجهاز")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        SettingsMetric(title: "المواد", value: store.library.subjects.count, icon: "books.vertical.fill", tint: .indigo)
                        SettingsMetric(title: "المستندات", value: store.items(.document).count, icon: "doc.text.fill", tint: .blue)
                        SettingsMetric(title: "التسجيلات", value: store.items(.recording).count, icon: "waveform", tint: .orange)
                        SettingsMetric(title: "الملاحظات", value: store.items(.note).count, icon: "pencil.and.scribble", tint: .purple)
                    }
                }
                .studixSurface()

                Link(destination: URL(string: "https://x.com/sh_hhv")!) {
                    HStack(spacing: 12) {
                        XLogo().foregroundStyle(.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Spidey").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text("تابع أخبار وتحديثات المشروع").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .studixSurface(radius: 18, padding: 15)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("الإعدادات")
        .navigationBarTitleDisplayMode(.large)
        .disabled(working)
        .overlay {
            if working {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    if let status = store.restoreStatus {
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(26)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
        // The file picker and the confirmation dialog each get their own anchor view. Stacking a picker,
        // a dialog and an alert on one view makes iOS drop or freeze whichever appears right after another closes.
        .background {
            Color.clear.fileImporter(isPresented: $importing, allowedContentTypes: [.zip, .data]) { result in
                switch result {
                case .success(let url):
                    pickedURL = url
                    // Let the picker finish closing before the dialog opens.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { confirming = true }
                case .failure(let error):
                    if (error as? CocoaError)?.code != .userCancelled {
                        message = error.localizedDescription
                    }
                }
            }
        }
        .background {
            Color.clear.confirmationDialog("استرجاع نسخة احتياطية", isPresented: $confirming, titleVisibility: .visible) {
                Button("استبدال البيانات الحالية", role: .destructive) { restore() }
            } message: {
                Text("سيتم استبدال كل بياناتك الحالية بمحتوى النسخة بعد التحقق من سلامتها.")
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("حسنًا", role: .cancel) {}
        }
    }

    func makeBackup() {
        guard !working else { return }
        working = true
        Task { @MainActor in
            defer { working = false }
            do {
                shareItem = ShareFile(url: try await store.backup())
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func restore() {
        guard let url = pickedURL, !working else { return }
        working = true
        Task { @MainActor in
            // Keep access to the picked file open for the whole restore.
            let granted = url.startAccessingSecurityScopedResource()
            defer {
                if granted { url.stopAccessingSecurityScopedResource() }
                working = false
            }
            do {
                let skipped = try await store.restore(from: url)
                message = skipped > 0
                    ? Lang.tr("تم الاسترجاع، لكن %lld عنصر لم نجد ملفاته داخل النسخة فتم تخطيه", skipped)
                    : Lang.tr("تم الاسترجاع بنجاح")
            } catch {
                message = error.localizedDescription
            }
        }
    }
}


private struct SettingsActionRow: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct SettingsMetric: View {
    let title: LocalizedStringKey
    let value: Int
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(value.formatted(.number.locale(Lang.locale))).font(.title3.weight(.bold)).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}
