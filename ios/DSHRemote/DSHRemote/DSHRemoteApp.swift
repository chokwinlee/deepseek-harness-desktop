import SwiftUI

@main
struct DSHRemoteApp: App {
    @StateObject private var hostStore = RemoteHostStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(hostStore)
                .onOpenURL { url in
                    hostStore.importConnectionURL(url)
                }
        }
    }
}
