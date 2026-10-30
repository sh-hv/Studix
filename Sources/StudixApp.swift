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
    static let accent = Color(red: 0.34, green: 0.36, blue: 0.96)
    static let palette: [Color] = [.indigo, .teal, .orange, .pink, .green, .purple, .red, .blue]
    static func color(_ index: Int) -> Color { palette[index % palette.count] }
}

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { SubjectsView() }
                .tabItem { Label("المواد", systemImage: "square.grid.2x2.fill") }
            ForEach(ItemKind.allCases) { kind in
                NavigationStack {
                    ItemListView(kind: kind).navigationTitle(kind.title)
                }
                .tabItem { Label(kind.title, systemImage: kind.icon) }
            }
            NavigationStack { SettingsView() }
                .tabItem { Label("الإعدادات", systemImage: "gearshape.fill") }
        }
    }
}
