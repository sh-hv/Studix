import SwiftUI
import UserNotifications

struct Deadline: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var due: Date
    var subjectID: UUID?
    var offsets: [Int]?
}

enum Reminders {
    static let options = [10080, 4320, 1440, 600, 180, 60]

    static func phrase(_ minutes: Int) -> String {
        if minutes % 1440 == 0 { return String(localized: "\(minutes / 1440) يوم") }
        if minutes % 60 == 0 { return String(localized: "\(minutes / 60) ساعة") }
        return String(localized: "\(minutes) دقيقة")
    }

    static func schedule(_ deadline: Deadline) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            for minutes in deadline.offsets ?? [] {
                let fire = deadline.due.addingTimeInterval(-Double(minutes) * 60)
                guard fire > Date() else { continue }
                let content = UNMutableNotificationContent()
                content.title = deadline.title
                content.body = String(localized: "باقي \(phrase(minutes)) على الموعد")
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: "\(deadline.id)-\(minutes)", content: content, trigger: trigger))
            }
        }
    }

    static func cancel(_ deadline: Deadline) {
        let identifiers = (deadline.offsets ?? []).map { "\(deadline.id)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
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
                Text("أضف موعد تسليم أو اختبار مع تذكيرات بالتوقيت اللي تحدده")
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
        let label = days == 0 ? String(localized: "اليوم") : days == 1 ? String(localized: "غدًا") : String(localized: "\(days) يوم")
        let detail = store.subject(deadline.subjectID)?.name ?? deadline.due.formatted(date: .abbreviated, time: .shortened)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(deadline.title).font(.subheadline.weight(.semibold))
                Text(detail + " · " + deadline.due.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    @State var offsets: Set<Int> = [1440, 600]
    @State var customHours = 0

    var body: some View {
        NavigationStack {
            Form {
                TextField("العنوان (مثال: اختبار منتصف الفصل)", text: $title)
                DatePicker("الموعد", selection: $due, displayedComponents: [.date, .hourAndMinute])
                Picker("المادة", selection: $subjectID) {
                    Text("بدون مادة").tag(UUID?.none)
                    ForEach(store.library.subjects) { Text($0.name).tag(Optional($0.id)) }
                }
                Section("ذكّرني") {
                    ForEach(Reminders.options, id: \.self) { minutes in
                        Toggle(String(localized: "قبل \(Reminders.phrase(minutes))"), isOn: Binding(
                            get: { offsets.contains(minutes) },
                            set: { if $0 { offsets.insert(minutes) } else { offsets.remove(minutes) } }
                        ))
                    }
                    Stepper(value: $customHours, in: 0...168) {
                        if customHours == 0 {
                            Text("وقت مخصص: بدون")
                        } else {
                            Text("وقت مخصص: قبل \(customHours) ساعة")
                        }
                    }
                }
            }
            .navigationTitle("موعد جديد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("إضافة") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    func save() {
        var all = Array(offsets)
        if customHours > 0 { all.append(customHours * 60) }
        let deadline = Deadline(title: title, due: due, subjectID: subjectID, offsets: all)
        store.addDeadline(deadline)
        Reminders.schedule(deadline)
        dismiss()
    }
}
