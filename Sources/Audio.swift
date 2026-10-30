import SwiftUI
import AVFoundation

func clock(_ time: Double) -> String {
    String(format: "%02d:%02d", locale: Lang.locale, arguments: [Int(time) / 60, Int(time) % 60])
}

@MainActor
final class RecorderModel: ObservableObject {
    enum State { case idle, recording, paused }

    @Published var elapsed: TimeInterval = 0
    @Published var marks: [Double] = []
    @Published var levels: [Float] = []
    @Published var state = State.idle
    var recorder: AVAudioRecorder?
    var timer: Timer?

    func start(to url: URL) async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard granted else { return false }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        recorder = try? AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        guard recorder?.record() == true else { return false }
        state = .recording
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        return true
    }

    func tick() {
        guard let recorder, state == .recording else { return }
        recorder.updateMeters()
        elapsed = recorder.currentTime
        let level = max(0.05, min(1, (recorder.averagePower(forChannel: 0) + 50) / 50))
        levels.append(level)
        if levels.count > 90 { levels.removeFirst() }
    }

    func togglePause() {
        guard let recorder else { return }
        if state == .recording {
            recorder.pause()
            state = .paused
        } else {
            recorder.record()
            state = .recording
        }
    }

    func mark() { marks.append(elapsed) }

    func stop() {
        recorder?.stop()
        timer?.invalidate()
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

struct Waveform: View {
    let levels: [Float]

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 3) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule()
                        .fill(Theme.accent.gradient)
                        .frame(width: 3, height: max(4, CGFloat(levels[index]) * geometry.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct RecorderView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @StateObject var model = RecorderModel()
    @State var file = ""
    @State var denied = false
    let subject: UUID?

    var body: some View {
        VStack(spacing: 28) {
            HStack {
                Button("إلغاء") { cancel() }
                Spacer()
            }
            Spacer()
            Text(clock(model.elapsed))
                .font(.system(size: 64, weight: .light, design: .rounded))
                .monospacedDigit()
            Waveform(levels: model.levels)
                .frame(height: 90)
                .padding(.horizontal)
            Label("\(model.marks.count) علامة", systemImage: "flag.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .opacity(model.marks.isEmpty ? 0 : 1)
            Spacer()
            controls
                .padding(.bottom, 24)
        }
        .padding()
        .interactiveDismissDisabled(model.state != .idle)
        .alert("لا يوجد إذن للميكروفون", isPresented: $denied) {
            Button("حسنًا") { dismiss() }
        } message: {
            Text("فعّل الميكروفون من إعدادات الجهاز")
        }
    }

    @ViewBuilder var controls: some View {
        if model.state == .idle {
            VStack(spacing: 12) {
                Button { Task { await begin() } } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(Color.red.gradient, in: Circle())
                }
                Text("اضغط لبدء التسجيل").font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 30) {
                Button { model.mark() } label: {
                    Image(systemName: "flag.fill")
                        .font(.title2)
                        .frame(width: 60, height: 60)
                        .background(Color.orange.opacity(0.15), in: Circle())
                        .foregroundStyle(.orange)
                }
                Button { model.togglePause() } label: {
                    Image(systemName: model.state == .paused ? "mic.fill" : "pause.fill")
                        .font(.title2)
                        .frame(width: 60, height: 60)
                        .background(Theme.accent.opacity(0.15), in: Circle())
                        .foregroundStyle(Theme.accent)
                }
                Button { finish() } label: {
                    Image(systemName: "stop.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(Color.red.gradient, in: Circle())
                }
            }
        }
    }

    func begin() async {
        file = store.newFile(ext: "m4a")
        let started = await model.start(to: Store.root.appendingPathComponent(file))
        if !started { denied = true }
    }

    func finish() {
        model.stop()
        let title = store.subject(subject).map { $0.name + " · " + dateStamp() } ?? defaultTitle("تسجيل")
        store.add(Item(subjectID: subject, kind: .recording, title: title, file: file, marks: model.marks))
        dismiss()
    }

    func cancel() {
        model.stop()
        if !file.isEmpty { try? FileManager.default.removeItem(at: Store.root.appendingPathComponent(file)) }
        dismiss()
    }
}

@MainActor
final class PlayerModel: ObservableObject {
    @Published var current: Double = 0
    @Published var duration: Double = 0
    @Published var playing = false
    @Published var rate: Float = 1
    var player: AVAudioPlayer?
    var timer: Timer?

    func load(_ url: URL, start: Double = 0) {
        timer?.invalidate()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.enableRate = true
        duration = player?.duration ?? 0
        player?.currentTime = start
        current = start
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func tick() {
        guard let player else { return }
        current = player.currentTime
        playing = player.isPlaying
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
        } else {
            player.rate = rate
            player.play()
        }
        playing = player.isPlaying
    }

    func seek(_ time: Double) {
        player?.currentTime = min(max(time, 0), duration)
        current = player?.currentTime ?? 0
    }

    func jump(to time: Double) {
        seek(time)
        if !playing { toggle() }
    }

    func setRate(_ value: Float) {
        rate = value
        player?.rate = value
    }

    func stop() {
        player?.stop()
        timer?.invalidate()
    }
}

struct PlayerView: View {
    @EnvironmentObject var store: Store
    @StateObject var player = PlayerModel()
    let item: Item

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                Image(systemName: "waveform")
                    .font(.system(size: 54))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 140, height: 140)
                    .background(Theme.accent.opacity(0.12), in: Circle())
                    .padding(.top, 24)

                VStack(spacing: 22) {
                    VStack(spacing: 4) {
                        Slider(value: Binding(get: { player.current }, set: { player.seek($0) }),
                               in: 0...max(player.duration, 1))
                        HStack {
                            Text(clock(player.current))
                            Spacer()
                            Text(clock(player.duration))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 36) {
                        Button { player.seek(player.current - 15) } label: { Image(systemName: "gobackward.15") }
                        Button { player.toggle() } label: {
                            Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 72))
                        }
                        Button { player.seek(player.current + 15) } label: { Image(systemName: "goforward.15") }
                    }
                    .font(.title)
                }
                .environment(\.layoutDirection, .leftToRight)

                Menu {
                    ForEach([0.75, 1, 1.25, 1.5, 2], id: \.self) { value in
                        Button("\(value, specifier: "%g")×") { player.setRate(Float(value)) }
                    }
                } label: {
                    Text("السرعة \(Double(player.rate), specifier: "%g")×")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                }

                if let marks = item.marks, !marks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("العلامات").font(.headline)
                        ForEach(marks.indices, id: \.self) { index in
                            Button { player.jump(to: marks[index]) } label: {
                                HStack {
                                    Image(systemName: "flag.fill").foregroundStyle(.orange)
                                    Text(clock(marks[index])).monospacedDigit()
                                    Spacer()
                                    Image(systemName: "play.fill").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(14)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { player.load(store.url(for: item), start: item.progress ?? 0) }
        .onDisappear {
            store.setProgress(player.current, for: item.id)
            player.stop()
        }
    }
}

struct MiniPlayer: View {
    @EnvironmentObject var store: Store
    @StateObject var player = PlayerModel()
    @State var expanded = false
    @State var selected: Item?
    let subject: UUID

    var recordings: [Item] { store.items(.recording, subject: subject) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if expanded { panel }
            Button { withAnimation { expanded.toggle() } } label: {
                Image(systemName: player.playing ? "waveform" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Theme.accent.gradient, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            }
        }
        .padding()
        .onDisappear { player.stop() }
    }

    var panel: some View {
        VStack(spacing: 12) {
            if let selected {
                Text(selected.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Slider(value: Binding(get: { player.current }, set: { player.seek($0) }),
                       in: 0...max(player.duration, 1))
                HStack {
                    Text(clock(player.current)).font(.caption.monospacedDigit())
                    Spacer()
                    Button { player.seek(player.current - 15) } label: { Image(systemName: "gobackward.15") }
                    Button { player.toggle() } label: {
                        Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill").font(.title)
                    }
                    Button { player.seek(player.current + 15) } label: { Image(systemName: "goforward.15") }
                    Spacer()
                    Button { player.setRate(player.rate == 1 ? 1.5 : player.rate == 1.5 ? 2 : 1) } label: {
                        Text("\(Double(player.rate), specifier: "%g")×").font(.caption.weight(.semibold))
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                Divider()
            }
            if recordings.isEmpty {
                Text("لا توجد تسجيلات لهذه المادة").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(recordings) { recording in
                Button { play(recording) } label: {
                    HStack {
                        Image(systemName: recording.id == selected?.id ? "speaker.wave.2.fill" : "play.fill")
                            .frame(width: 22)
                        Text(recording.title).lineLimit(1)
                        Spacer()
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    func play(_ recording: Item) {
        selected = recording
        player.stop()
        player.load(store.url(for: recording))
        player.toggle()
    }
}
