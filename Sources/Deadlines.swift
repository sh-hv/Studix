import SwiftUI
import UserNotifications

struct Deadline: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var due: Date
    var subjectID: UUID?
    var offsets: [Int]?
}

/// Lets reminders appear as banners even while Studix is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

enum Reminders {
    static let options = [10080, 4320, 1440, 600, 180, 60]
    /// iOS keeps at most 64 pending local notifications, so only the soonest ones are scheduled.
    static let maxPending = 60

    static func phrase(_ minutes: Int) -> String {
        if minutes % 1440 == 0 { return Lang.tr("%lld يوم", minutes / 1440) }
        if minutes % 60 == 0 { return Lang.tr("%lld ساعة", minutes / 60) }
        return Lang.tr("%lld دقيقة", minutes)
    }

    /// Rebuilds every pending notification from the current data.
    /// Replacing everything keeps reminders in sync after edits, deletions and restores.
    static func rescheduleAll(deadlines: [Deadline], todos: [TodoItem]) {
        let center = UNUserNotificationCenter.current()
        let now = Date()
        var pending: [(fire: Date, request: UNNotificationRequest)] = []

        for deadline in deadlines {
            for minutes in Set(deadline.offsets ?? []) {
                let fire = deadline.due.addingTimeInterval(-Double(minutes) * 60)
                guard fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = deadline.title
                content.body = Lang.tr("باقي %@ على الموعد", phrase(minutes))
                content.sound = .default
                pending.append((fire, request("deadline-\(deadline.id)-\(minutes)", content, fire)))
            }
        }
        for todo in todos where !todo.done {
            guard let due = todo.due, due > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = todo.title
            content.body = Lang.tr("موعد المهمة الآن")
            content.sound = .default
            pending.append((due, request("task-\(todo.id)", content, due)))
        }

        center.removeAllPendingNotificationRequests()
        guard !pending.isEmpty else { return }
        let soonest = Array(pending.sorted { $0.fire < $1.fire }.prefix(maxPending))
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            for entry in soonest { center.add(entry.request) }
        }
    }

    private static func request(_ id: String, _ content: UNNotificationContent, _ fire: Date) -> UNNotificationRequest {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    static func notificationsDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
}

struct DeadlineRow: View {
    @EnvironmentObject var store: Store
    let deadline: Deadline

    var body: some View {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: deadline.due)).day ?? 0
        let tint = days < 0 ? Color.secondary : (days <= 2 ? Color.red : Theme.accent)
        let label = days < 0 ? Lang.tr("انتهى") : days == 0 ? Lang.tr("اليوم") : days == 1 ? Lang.tr("غدًا") : Lang.tr("%lld يوم", days)
        let detail = store.subject(deadline.subjectID)?.name ?? deadline.due.styled(.abbreviated, .shortened)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(deadline.title).font(.subheadline.weight(.semibold))
                Text(detail + " · " + deadline.due.styled(.omitted, .shortened))
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
                NavigationLink { DeadlinesView() } label: { Text("عرض الكل").font(.footnote) }
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel(Text("إضافة موعد"))
            }
            if upcoming.isEmpty {
                Text("أضف موعد تسليم أو اختبار مع تذكيرات بالتوقيت اللي تحدده")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(upcoming) { deadline in
                DeadlineRow(deadline: deadline)
                    .contextMenu {
                        Button(role: .destructive) { store.deleteDeadline(deadline) } label: {
                            Label("حذف", systemImage: "trash")
                        }
                    }
            }
        }
        .studixSurface(radius: 22, padding: 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding([.horizontal, .top])
        .sheet(isPresented: $adding) { AddDeadlineSheet() }
    }
}

/// Every deadline, including the ones that already passed, which can be edited or deleted here.
struct DeadlinesView: View {
    @EnvironmentObject var store: Store
    @State var adding = false
    @State var editing: Deadline?

    private var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }
    var upcoming: [Deadline] { store.deadlines.filter { $0.due >= startOfToday } }
    var past: [Deadline] { store.deadlines.filter { $0.due < startOfToday }.reversed() }

    var body: some View {
        List {
            if !upcoming.isEmpty {
                Section("القادمة") { ForEach(upcoming) { rowButton($0) } }
            }
            if !past.isEmpty {
                Section("المنتهية") { ForEach(past) { rowButton($0) } }
            }
        }
        .overlay {
            if store.deadlines.isEmpty { EmptyState(icon: "calendar.badge.clock", text: "لا توجد مواعيد") }
        }
        .navigationTitle("المواعيد")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Image(systemName: "plus.circle.fill") }
                    .accessibilityLabel(Text("إضافة موعد"))
            }
        }
        .sheet(isPresented: $adding) { AddDeadlineSheet() }
        .sheet(item: $editing) { AddDeadlineSheet(deadline: $0) }
    }

    func rowButton(_ deadline: Deadline) -> some View {
        Button { editing = deadline } label: { DeadlineRow(deadline: deadline) }
            .buttonStyle(.plain)
            .swipeActions {
                Button(role: .destructive) { store.deleteDeadline(deadline) } label: {
                    Label("حذف", systemImage: "trash")
                }
            }
    }
}

struct AddDeadlineSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State var title: String
    @State var due: Date
    @State var subjectID: UUID?
    @State var offsets: Set<Int>
    @State var customHours: Int
    @State var notificationsOff = false
    let existing: Deadline?

    init(deadline: Deadline? = nil) {
        existing = deadline
        let saved = Set(deadline?.offsets ?? [1440, 600])
        let custom = saved.first { !Reminders.options.contains($0) && $0 % 60 == 0 && $0 <= 168 * 60 }
        _title = State(initialValue: deadline?.title ?? "")
        _due = State(initialValue: deadline?.due ?? Date().addingTimeInterval(86400))
        _subjectID = State(initialValue: deadline?.subjectID)
        _offsets = State(initialValue: saved.filter { Reminders.options.contains($0) })
        _customHours = State(initialValue: (custom ?? 0) / 60)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("العنوان (مثال: اختبار منتصف الفصل)", text: $title)
                DatePicker("الموعد", selection: $due, displayedComponents: [.date, .hourAndMinute])
                Picker("المادة", selection: $subjectID) {
                    Text("بدون مادة").tag(UUID?.none)
                    ForEach(store.library.subjects) { Text($0.name).tag(Optional($0.id)) }
                }
                if notificationsOff {
                    Section {
                        Text("الإشعارات متوقفة لهذا التطبيق، فلن تصلك التذكيرات")
                            .font(.footnote)
                            .foregroundStyle(.red)
                        Button("فتح إعدادات الإشعارات") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
                Section("ذكّرني") {
                    ForEach(Reminders.options, id: \.self) { minutes in
                        Toggle(Lang.tr("قبل %@", Reminders.phrase(minutes)), isOn: Binding(
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
            .navigationTitle(LocalizedStringKey(existing == nil ? "موعد جديد" : "تعديل الموعد"))
            .navigationBarTitleDisplayMode(.inline)
            .task { notificationsOff = await Reminders.notificationsDenied() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey(existing == nil ? "إضافة" : "حفظ")) { save() }
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
        let deadline = Deadline(
            id: existing?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            due: due,
            subjectID: subjectID,
            offsets: all
        )
        store.saveDeadline(deadline)
        dismiss()
    }
}
