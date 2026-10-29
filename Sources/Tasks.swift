import SwiftUI
import UserNotifications

struct TodoItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var done = false
    var due: Date?
    var subjectID: UUID?
}

extension Reminders {
    static func scheduleTask(_ todo: TodoItem) {
        guard let due = todo.due, due > Date() else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = todo.title
            content.body = Lang.tr("موعد المهمة الآن")
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: "task-\(todo.id)", content: content, trigger: trigger))
        }
    }

    static func cancelTask(_ todo: TodoItem) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["task-\(todo.id)"])
    }
}

struct TaskRow: View {
    @EnvironmentObject var store: Store
    let todo: TodoItem

    var detail: String? {
        let parts = [store.subject(todo.subjectID)?.name, todo.due?.styled(.abbreviated, .shortened)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button { withAnimation { store.toggleTodo(todo) } } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.done ? Color.green : Theme.accent)
            }
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .strikethrough(todo.done)
                    .foregroundStyle(todo.done ? Color.secondary : Color.primary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
        }
    }
}

struct TasksCard: View {
    @EnvironmentObject var store: Store
    @State var adding = false

    var open: [TodoItem] { Array(store.todos.filter { !$0.done }.prefix(4)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("المهام").font(.headline)
                Spacer()
                NavigationLink { TasksView() } label: { Text("عرض الكل").font(.footnote) }
                Button { adding = true } label: { Image(systemName: "plus") }
            }
            if open.isEmpty {
                Text("لا توجد مهام").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(open) { TaskRow(todo: $0) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding([.horizontal, .top])
        .sheet(isPresented: $adding) { AddTaskSheet() }
    }
}

struct TasksView: View {
    @EnvironmentObject var store: Store
    @State var adding = false

    var body: some View {
        List {
            Section {
                ForEach(store.todos.filter { !$0.done }) { todo in
                    TaskRow(todo: todo).swipeActions {
                        Button(role: .destructive) { store.deleteTodo(todo) } label: { Label("حذف", systemImage: "trash") }
                    }
                }
            }
            let finished = store.todos.filter { $0.done }
            if !finished.isEmpty {
                Section("منجزة") {
                    ForEach(finished) { todo in
                        TaskRow(todo: todo).swipeActions {
                            Button(role: .destructive) { store.deleteTodo(todo) } label: { Label("حذف", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .overlay {
            if store.todos.isEmpty { EmptyState(icon: "checklist", text: "لا توجد مهام") }
        }
        .navigationTitle("المهام")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Image(systemName: "plus.circle.fill") }
            }
        }
        .sheet(isPresented: $adding) { AddTaskSheet() }
    }
}

struct AddTaskSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State var title = ""
    @State var hasDue = false
    @State var due = Date().addingTimeInterval(3600)
    @State var subjectID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                TextField("عنوان المهمة", text: $title)
                Toggle("تحديد موعد", isOn: $hasDue)
                if hasDue {
                    DatePicker("الموعد", selection: $due, displayedComponents: [.date, .hourAndMinute])
                }
                Picker("المادة", selection: $subjectID) {
                    Text("بدون مادة").tag(UUID?.none)
                    ForEach(store.library.subjects) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            .navigationTitle("مهمة جديدة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("إضافة") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }

    func save() {
        let todo = TodoItem(title: title.trimmingCharacters(in: .whitespaces), due: hasDue ? due : nil, subjectID: subjectID)
        store.addTodo(todo)
        Reminders.scheduleTask(todo)
        dismiss()
    }
}
