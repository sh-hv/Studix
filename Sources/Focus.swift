import SwiftUI
import UIKit

// MARK: - Model

enum FocusMode: String, Codable, CaseIterable, Identifiable {
    case countdown, stopwatch

    var id: String { rawValue }
    var title: String {
        switch self {
        case .countdown: return Lang.tr("عدّاد تنازلي")
        case .stopwatch: return Lang.tr("عدّاد تصاعدي")
        }
    }
}

struct FocusRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var subjectID: UUID?
    var end: Date
    var seconds: Int
}

/// A running (or paused) session. Time is derived from the device clock, so it stays
/// correct when the screen locks, the app is suspended, or the app is relaunched.
struct ActiveFocus: Codable {
    var mode: FocusMode
    var subjectID: UUID?
    var target: Int            // seconds, 0 for the stopwatch
    var accumulated: Double    // seconds counted before `runningSince`
    var runningSince: Date?    // nil while paused

    func elapsed(at now: Date) -> Double {
        accumulated + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    func remaining(at now: Date) -> Double {
        max(0, Double(target) - elapsed(at: now))
    }

    func isFinished(at now: Date) -> Bool {
        mode == .countdown && target > 0 && elapsed(at: now) >= Double(target)
    }

    /// The moment a running countdown reached zero.
    var endDate: Date? {
        guard mode == .countdown, let since = runningSince else { return nil }
        return since.addingTimeInterval(Double(target) - accumulated)
    }
}

// MARK: - Store

struct FocusDayTotal: Identifiable {
    let day: Date
    let seconds: Int
    var id: Date { day }
}

struct FocusSubjectTotal: Identifiable {
    let subjectID: UUID?
    let seconds: Int
    var id: String { subjectID?.uuidString ?? "none" }
}

final class FocusStore: ObservableObject {
    static let shared = FocusStore()

    @Published private(set) var records: [FocusRecord] = []
    @Published private(set) var active: ActiveFocus? {
        didSet {
            saveActive()
            updateIdleTimer()
        }
    }
    @Published private(set) var finishedRecord: FocusRecord?

    let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let recordsKey = "focus.records"
    private let activeKey = "focus.active"

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: recordsKey),
           let saved = try? JSONDecoder().decode([FocusRecord].self, from: data) {
            records = saved
        }
        if let data = defaults.data(forKey: activeKey),
           let saved = try? JSONDecoder().decode(ActiveFocus.self, from: data) {
            active = saved
        }
        updateIdleTimer()
        checkCompletion()
    }

    // MARK: Session control

    func start(mode: FocusMode, subjectID: UUID?, seconds: Int) {
        guard active == nil else { return }
        finishedRecord = nil
        active = ActiveFocus(
            mode: mode,
            subjectID: subjectID,
            target: mode == .countdown ? max(1, seconds) : 0,
            accumulated: 0,
            runningSince: Date()
        )
    }

    func pause() {
        guard var session = active, let since = session.runningSince else { return }
        session.accumulated += max(0, Date().timeIntervalSince(since))
        session.runningSince = nil
        active = session
    }

    func resume() {
        guard var session = active, session.runningSince == nil else { return }
        session.runningSince = Date()
        active = session
    }

    func finish() {
        guard let session = active else { return }
        let now = Date()
        var seconds = session.elapsed(at: now)
        var end = now
        if session.isFinished(at: now) {
            seconds = Double(session.target)
            end = session.endDate ?? now
        }
        let total = Int(seconds.rounded())
        if total >= 5 {
            let record = FocusRecord(subjectID: session.subjectID, end: end, seconds: total)
            records.insert(record, at: 0)
            saveRecords()
            finishedRecord = record
        } else {
            finishedRecord = nil
        }
        active = nil
    }

    func discard() {
        finishedRecord = nil
        active = nil
    }

    func clearFinished() {
        finishedRecord = nil
    }

    func checkCompletion() {
        if let session = active, session.isFinished(at: Date()) { finish() }
    }

    func delete(_ record: FocusRecord) {
        records.removeAll { $0.id == record.id }
        saveRecords()
    }

    // MARK: Statistics

    private var calendar: Calendar { Calendar.current }

    func seconds(from start: Date, to end: Date) -> Int {
        records.filter { $0.end >= start && $0.end < end }.reduce(0) { $0 + $1.seconds }
    }

    var todaySeconds: Int {
        let start = calendar.startOfDay(for: Date())
        return seconds(from: start, to: start.addingTimeInterval(86_400 * 2))
    }

    var weekStart: Date {
        calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    var weekSeconds: Int {
        seconds(from: weekStart, to: Date().addingTimeInterval(86_400))
    }

    /// Totals for the last seven days, oldest first.
    var dayTotals: [FocusDayTotal] {
        (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            return FocusDayTotal(day: day, seconds: seconds(from: day, to: next))
        }
    }

    /// Time per subject over the last seven days, largest first.
    var subjectTotals: [FocusSubjectTotal] {
        var totals: [UUID?: Int] = [:]
        for record in records where record.end >= weekStart {
            totals[record.subjectID, default: 0] += record.seconds
        }
        return totals.map { FocusSubjectTotal(subjectID: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
    }

    // MARK: Persistence and screen

    private func saveRecords() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
    }

    private func saveActive() {
        if let session = active, let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: activeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeKey)
        }
    }

    /// While a session is running the screen never auto-locks.
    private func updateIdleTimer() {
        let keepAwake = active?.runningSince != nil
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
    }
}

// MARK: - Formatting

enum FocusFormat {
    static func num(_ value: Int, pad: Int = 1) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Lang.locale
        formatter.numberStyle = .none
        formatter.minimumIntegerDigits = pad
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func clock(_ total: Int) -> String {
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        let body = hours > 0
            ? "\(num(hours)):\(num(minutes, pad: 2)):\(num(seconds, pad: 2))"
            : "\(num(minutes, pad: 2)):\(num(seconds, pad: 2))"
        return "\u{200E}" + body
    }

    static func duration(_ total: Int) -> String {
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 && minutes > 0 { return Lang.tr("%lld س و %lld د", hours, minutes) }
        if hours > 0 { return Lang.tr("%lld س", hours) }
        if minutes > 0 { return Lang.tr("%lld د", minutes) }
        return total > 0 ? Lang.tr("أقل من دقيقة") : Lang.tr("%lld د", 0)
    }

}

// MARK: - Home card

struct FocusCard: View {
    @ObservedObject private var focus = FocusStore.shared

    var body: some View {
        NavigationLink {
            FocusView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: focus.active == nil ? "timer" : "hourglass")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("التركيز").font(.headline).foregroundStyle(.primary)
                    if let session = focus.active {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let seconds = session.mode == .countdown
                                ? session.remaining(at: context.date)
                                : session.elapsed(at: context.date)
                            Text(FocusFormat.clock(Int(seconds.rounded(session.mode == .countdown ? .up : .down))))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Theme.accent)
                        }
                    } else {
                        Text(Lang.tr("ذاكرت اليوم: %@", FocusFormat.duration(focus.todaySeconds)))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .studixSurface(radius: 22, padding: 16)
        }
        .buttonStyle(.plain)
        .padding([.horizontal, .top])
        .onReceive(focus.ticker) { _ in focus.checkCompletion() }
    }
}

// MARK: - Focus screen

struct FocusView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var focus = FocusStore.shared

    @State private var mode: FocusMode = .countdown
    @State private var subjectID: UUID?
    @State private var hours = 0
    @State private var mins = 25
    @State private var secs = 0
    @State private var confirmingDiscard = false

    private let presets = [15, 25, 45, 60, 90]
    private var totalSeconds: Int { hours * 3600 + mins * 60 + secs }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let session = focus.active {
                    runningView(session)
                } else if let record = focus.finishedRecord {
                    finishedView(record)
                } else {
                    setupView
                }
            }
            .frame(maxWidth: 560)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("التركيز")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink { FocusStatsView() } label: { Image(systemName: "chart.bar.fill") }
                    .accessibilityLabel(Text("إحصائيات التركيز"))
            }
        }
        .onReceive(focus.ticker) { _ in focus.checkCompletion() }
        .onDisappear { if focus.active == nil { focus.clearFinished() } }
        .confirmationDialog("إلغاء الجلسة دون حفظ؟", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("إلغاء الجلسة", role: .destructive) { focus.discard() }
            Button("متابعة", role: .cancel) {}
        }
    }

    // MARK: Setup

    private var setupView: some View {
        VStack(spacing: 16) {
            Picker("النمط", selection: $mode) {
                ForEach(FocusMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 12) {
                Picker("المادة", selection: $subjectID) {
                    Text("بدون مادة").tag(UUID?.none)
                    ForEach(store.library.subjects) { subject in
                        Text(subject.name).tag(UUID?.some(subject.id))
                    }
                }
                .pickerStyle(.menu)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .studixSurface(radius: 18, padding: 14)

            if mode == .countdown {
                VStack(alignment: .leading, spacing: 12) {
                    Text("المدة").font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { preset in
                            Button { setDuration(minutes: preset) } label: {
                                Text(FocusFormat.num(preset))
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(
                                        totalSeconds == preset * 60 ? Theme.accent : Color.primary.opacity(0.07),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(totalSeconds == preset * 60 ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("الأزرار أعلاه بالدقائق، أو اضبط الساعات والدقائق والثواني بنفسك")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        wheel(value: $hours, range: 0..<24, unit: "س")
                        wheel(value: $mins, range: 0..<60, unit: "د")
                        wheel(value: $secs, range: 0..<60, unit: "ث")
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .frame(height: 120)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .studixSurface(radius: 18, padding: 14)
            } else {
                Text("يبدأ العدّاد من الصفر ويحسب وقتك دون حد، وتوقفه متى ما خلصت.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .studixSurface(radius: 18, padding: 14)
            }

            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                focus.start(mode: mode, subjectID: subjectID, seconds: totalSeconds)
            } label: {
                Label("ابدأ", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(mode == .countdown && totalSeconds < 1)

            Label("تبقى الشاشة مفتوحة أثناء الجلسة", systemImage: "sun.max")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func setDuration(minutes: Int) {
        hours = minutes / 60
        mins = minutes % 60
        secs = 0
    }

    private func wheel(value: Binding<Int>, range: Range<Int>, unit: LocalizedStringKey) -> some View {
        HStack(spacing: 2) {
            Picker("", selection: value) {
                ForEach(Array(range), id: \.self) { Text(FocusFormat.num($0)).tag($0) }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            Text(unit).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: Running

    private func runningView(_ session: ActiveFocus) -> some View {
        let subject = store.subject(session.subjectID)
        let color = subject.map { Theme.color($0.colorIndex) } ?? Theme.accent
        let paused = session.runningSince == nil

        return VStack(spacing: 22) {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let countdown = session.mode == .countdown
                let shown = countdown ? session.remaining(at: context.date) : session.elapsed(at: context.date)
                let progress = countdown && session.target > 0
                    ? min(1, session.elapsed(at: context.date) / Double(session.target))
                    : 0
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.08), lineWidth: 14)
                    if countdown {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    VStack(spacing: 6) {
                        Text(FocusFormat.clock(Int(shown.rounded(countdown ? .up : .down))))
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(subject?.name ?? Lang.tr("بدون مادة"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if paused {
                            Text("متوقفة مؤقتًا")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 28)
                }
                .frame(width: 270, height: 270)
            }
            .padding(.top, 12)

            VStack(spacing: 12) {
                Button {
                    if paused { focus.resume() } else { focus.pause() }
                } label: {
                    Label(paused ? "متابعة" : "إيقاف مؤقت", systemImage: paused ? "play.fill" : "pause.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)

                Button { focus.finish() } label: {
                    Label("إنهاء وحفظ", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)

                Button("إلغاء الجلسة", role: .destructive) { confirmingDiscard = true }
                    .font(.footnote)
            }

            Label("الشاشة تبقى مفتوحة أثناء الجلسة", systemImage: "sun.max")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Finished

    private func finishedView(_ record: FocusRecord) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .padding(.top, 30)
            Text("أحسنت!").font(.title2.weight(.bold))
            Text(Lang.tr("ذاكرت %@", FocusFormat.duration(record.seconds)))
                .font(.headline)
            if let subject = store.subject(record.subjectID) {
                Text(subject.name).foregroundStyle(.secondary)
            }
            Button { focus.clearFinished() } label: {
                Label("جلسة جديدة", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 10)
        }
    }
}

// MARK: - Statistics

struct FocusStatsView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var focus = FocusStore.shared

    var body: some View {
        List {
            Section {
                HStack {
                    statBlock(title: "اليوم", seconds: focus.todaySeconds)
                    Spacer()
                    statBlock(title: "آخر 7 أيام", seconds: focus.weekSeconds)
                }
                weekChart
            }

            let totals = focus.subjectTotals
            if !totals.isEmpty {
                Section("حسب المادة (آخر 7 أيام)") {
                    ForEach(totals) { row in
                        let subject = store.subject(row.subjectID)
                        HStack {
                            Circle()
                                .fill(subject.map { Theme.color($0.colorIndex) } ?? Color.gray)
                                .frame(width: 10, height: 10)
                            Text(subject?.name ?? Lang.tr("بدون مادة"))
                            Spacer()
                            Text(FocusFormat.duration(row.seconds)).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("آخر الجلسات") {
                if focus.records.isEmpty {
                    Text("لا توجد جلسات بعد").foregroundStyle(.secondary)
                }
                ForEach(focus.records.prefix(30)) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.subject(record.subjectID)?.name ?? Lang.tr("بدون مادة"))
                            Text(record.end.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Lang.locale)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(FocusFormat.duration(record.seconds)).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) { focus.delete(record) } label: {
                            Label("حذف", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("إحصائيات التركيز")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statBlock(title: LocalizedStringKey, seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(FocusFormat.duration(seconds)).font(.title3.weight(.bold))
        }
    }

    private var weekChart: some View {
        let days = focus.dayTotals
        let peak = max(days.map(\.seconds).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(days) { entry in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(entry.seconds > 0 ? Theme.accent : Color.primary.opacity(0.08))
                        .frame(height: max(6, 90 * CGFloat(entry.seconds) / CGFloat(peak)))
                    Text(entry.day.formatted(.dateTime.weekday(.narrow).locale(Lang.locale)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 120, alignment: .bottom)
        .padding(.vertical, 6)
    }
}
