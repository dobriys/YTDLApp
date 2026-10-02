import SwiftUI

@main
struct YTDLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState.shared

    var body: some Scene {
        Window("Загрузчик видео", id: "main") {
            ContentView()
                .environment(state)
                .frame(minWidth: 820, minHeight: 720)
        }
        .defaultSize(width: 920, height: 820)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Нужно при запуске голого бинарника через `swift run`.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.cancelAll()
    }
}
