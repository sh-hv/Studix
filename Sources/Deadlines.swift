import SwiftUI

struct Deadline: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var due: Date
    var subjectID: UUID?
}

struct DeadlinesCard: View {
    @EnvironmentObject var store: Store
    @State var adding = false

    var upcoming: [Deadline] {
        let today = Calendar.current.startOfDay(for: Date())
        return Array(store.deadlines.filter { $0.due >= today }.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("المواعيد القادمة").font(.headline)
                Spacer()
                Button { adding = true } label: { Image(systemName: "plus") }
            }
            if upcoming.isEmpty {
                Text("أضف موعد تسليم أو اختبار ليظهر هنا بعدّ تنازلي")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(upcoming) { row($0) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding([.horizontal, .top])
        .sheet(isPresented: $adding) { AddDeadlineSheet() }
    }

    func row(_ deadline: Deadline) -> some View {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: deadline.due)).day ?? 0
        let tint = days <= 2 ? Color.red : Theme.accent
        let label = days == 0 ? "اليوم" : days == 1 ? "غدًا" : "\(days) يوم"
        let detail = store.subject(deadline.subjectID)?.name ?? deadline.due.formatted(date: .abbreviated, time: .omitted)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(deadline.title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(label)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(tint)
                .background(tint.opacity(0.12), in: Capsule())
        }
        .contextMenu {
            Button(role: .destructive) { store.deleteDeadline(deadline) } label: {
                Label("حذف", systemImage: "trash")
            }
        }
    }
}

struct AddDeadlineSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State var title = ""
    @State var due = Date().addingTimeInterval(86400)
    @State var subjectID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                TextField("العنوان (مثال: اختبار منتصف الفصل)", text: $title)
                DatePicker("الموعد", selection: $due, displayedComponents: .date)
                Picker("المادة", selection: $subjectID) {
                    Text("بدون مادة").tag(UUID?.none)
                    ForEach(store.library.subjects) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            .navigationTitle("موعد جديد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("إضافة") {
                        store.addDeadline(Deadline(title: title, due: due, subjectID: subjectID))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
