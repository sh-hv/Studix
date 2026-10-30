import SwiftUI

@main
struct StudixApp: App {
    @StateObject var store = Store()
    @AppStorage("appLanguage") var language = "system"

    var languageToken: String {
        Bundle.setLanguage(Lang.resolved)
        return language
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.locale, Lang.locale)
                .environment(\.layoutDirection, Lang.direction)
                .id(languageToken)
                .tint(Theme.accent)
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.29, green: 0.34, blue: 0.88)
    static let palette: [Color] = [
        Color(red: 0.31, green: 0.37, blue: 0.91),
        Color(red: 0.08, green: 0.59, blue: 0.58),
        Color(red: 0.91, green: 0.48, blue: 0.22),
        Color(red: 0.82, green: 0.34, blue: 0.52),
        Color(red: 0.24, green: 0.62, blue: 0.43),
        Color(red: 0.55, green: 0.39, blue: 0.78),
        Color(red: 0.82, green: 0.31, blue: 0.31),
        Color(red: 0.20, green: 0.53, blue: 0.78)
    ]
    static func color(_ index: Int) -> Color { palette[abs(index) % palette.count] }
}

struct RootView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        TabView {
            NavigationStack { SubjectsView() }
                .tabItem { Label("الرئيسية", systemImage: "house.fill") }
            ForEach(ItemKind.allCases) { kind in
                NavigationStack {
                    ItemListView(kind: kind).navigationTitle(kind.title)
                }
                .tabItem { Label(kind.title, systemImage: kind.icon) }
            }
            NavigationStack { SettingsView() }
                .tabItem { Label("الإعدادات", systemImage: "slider.horizontal.3") }
        }
        .tint(Theme.accent)
        .toolbarBackground(.visible, for: .tabBar)
        .alert("تعذر حفظ بعض البيانات", isPresented: Binding(
            get: { store.persistenceError != nil },
            set: { if !$0 { store.dismissPersistenceError() } }
        )) {
            Button("حسنًا", role: .cancel) { store.dismissPersistenceError() }
        } message: {
            Text(store.persistenceError ?? "")
        }
    }
}
