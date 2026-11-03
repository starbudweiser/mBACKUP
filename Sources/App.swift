// mBACKUP — copies miroir planifiées, dans la barre des menus. Alternative personnelle et simplifiée à Get Backup Pro.
import SwiftUI

@main
struct MbackupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject private var store = Store.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("mBACKUP", id: "main") {
            ContentView()
        }
        .defaultSize(width: 1100, height: 720)
        .defaultLaunchBehavior((CommandLine.arguments.contains("--show") || CommandLine.arguments.contains("--settings")) ? .presented : .suppressed)  // ouverture de session : aucune fenêtre

        MenuBarExtra {
            if store.tasks.isEmpty { Text(L.t("menu.none")) }
            ForEach(store.tasks) { t in
                Button("\(t.name) — \(store.isRunning(t.id) ? L.t("menu.running") + " \(Int((store.progress[t.id] ?? 0) * 100)) %" : L.t(store.statusKey(t)))") {
                    store.enqueue(t.id, dry: false)
                }.disabled(store.isQueued(t.id))
            }
            Divider()
            Button(L.t("menu.runAll")) { store.runAll() }.disabled(store.tasks.isEmpty)
            Button(L.t("menu.open")) { show() }
            Button(L.t("menu.settings")) { show(); store.showSettings = true }
            Divider()
            Button(L.t("menu.about")) { About.show() }
            Button(L.t("menu.quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(systemName: store.queue.isEmpty ? "arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath.circle.fill")
        }
    }

    private func show() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Socle.brand("mBACKUP", color: Brand.color)
        Socle.apply()
        Store.shared.start()
        if CommandLine.arguments.contains("--settings") { Store.shared.showSettings = true }   // ouvre les réglages (mot de passe admin)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
