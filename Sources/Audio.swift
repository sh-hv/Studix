import SwiftUI
import AVFoundation

func clock(_ time: Double) -> String {
    String(format: "%02d:%02d", Int(time) / 60, Int(time) % 60)
}

@MainActor
final class RecorderModel: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    @Published var marks: [Double] = []
    @Published var isRecording = false
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
        guard recorder?.record() == true else { return false }
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed = self?.recorder?.currentTime ?? 0 }
        }
        return true
    }

    func mark() { marks.append(elapsed) }

    func stop() {
        recorder?.stop()
        timer?.invalidate()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
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
            Label("\(model.marks.count) علامة", systemImage: "flag.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .opacity(model.marks.isEmpty ? 0 : 1)
            Spacer()
            HStack(spacing: 40) {
                Button { model.mark() } label: {
                    Image(systemName: "flag.fill")
                        .font(.title2)
                        .frame(width: 64, height: 64)
                        .background(Color.orange.opacity(0.15), in: Circle())
                        .foregroundStyle(.orange)
                }
                Button { finish() } label: {
                    Image(systemName: "stop.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(Color.red.gradient, in: Circle())
                }
            }
            Text("اضغط العلم لوضع علامة عند نقطة مهمة")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
        }
        .padding()
        .interactiveDismissDisabled()
        .task { await begin() }
        .alert("لا يوجد إذن للميكروفون", isPresented: $denied) {
            Button("حسنًا") { dismiss() }
        } message: {
            Text("فعّل الميكروفون من إعدادات الجهاز")
        }
    }

    func begin() async {
        file = store.newFile(ext: "m4a")
        let started = await model.start(to: Store.root.appendingPathComponent(file))
        if !started { denied = true }
    }

    func finish() {
        model.stop()
        store.add(Item(subjectID: subject, kind: .recording, title: defaultTitle("تسجيل"), file: file, marks: model.marks))
        dismiss()
    }

    func cancel() {
        model.stop()
        try? FileManager.default.removeItem(at: Store.root.appendingPathComponent(file))
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

    func load(_ url: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.enableRate = true
        duration = player?.duration ?? 0
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
        .onAppear { player.load(store.url(for: item)) }
        .onDisappear { player.stop() }
    }
}
