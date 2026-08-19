import SwiftUI

@main
struct DSHRemoteApp: App {
    @StateObject private var hostStore = RemoteHostStore()

    init() {
        RemoteNotificationManager.shared.configure()
    }

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
