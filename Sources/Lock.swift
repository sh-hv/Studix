import SwiftUI
import LocalAuthentication

struct LockGate<Content: View>: View {
    @AppStorage("lockEnabled") var enabled = false
    @Environment(\.scenePhase) var phase
    @State var unlocked = false
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
            if enabled && !unlocked {
                VStack(spacing: 18) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.accent)
                    Text("Studix مقفل").font(.headline)
                    Button("فتح") { authenticate() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
        .onAppear { authenticate() }
        .onChange(of: phase) { newPhase in
            if newPhase == .background { unlocked = false }
            if newPhase == .active { authenticate() }
        }
    }

    func authenticate() {
        guard enabled, !unlocked else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            unlocked = true
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "فتح Studix") { success, _ in
            DispatchQueue.main.async { if success { unlocked = true } }
        }
    }
}
