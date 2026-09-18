import SwiftUI

@main
struct GatewireDemoApp: App {
    @State private var session = SessionModel(api: .live())

    var body: some Scene {
        WindowGroup {
            TabView {
                ProductsView(api: session.api)
                    .tabItem { Label("Каталог", systemImage: "bag") }

                AccountView()
                    .tabItem { Label("Аккаунт", systemImage: "person.crop.circle") }
            }
            .environment(session)
            .task { await session.restore() }
        }
    }
}
