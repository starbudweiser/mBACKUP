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
            MenuBarIcon(running: !store.queue.isEmpty)
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

/// Image qui tourne : un tour en 12 images, indépendant du Store pour ne pas redessiner la fenêtre à chaque image.
@MainActor
final class Spinner: ObservableObject {
    static let shared = Spinner()
    @Published private(set) var frame = 0
    private var timer: Timer?
    static let frames = 12

    func set(running: Bool) {
        if running, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                Task { @MainActor in Spinner.shared.frame = (Spinner.shared.frame + 1) % Spinner.frames }
            }
        } else if !running {
            timer?.invalidate(); timer = nil; frame = 0
        }
    }
}

/// Icône de la barre des menus : monochrome (celle du système) au repos, orange et tournante pendant qu'une tâche tourne.
struct MenuBarIcon: View {
    let running: Bool
    @ObservedObject private var spinner = Spinner.shared
    private static let amber = NSColor(srgbRed: 0xf5 / 255, green: 0x9e / 255, blue: 0x0b / 255, alpha: 1)   // orange « action » de Socle
    private static let base = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "mBACKUP") ?? NSImage()
    private static let colored = base.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [amber]).applying(NSImage.SymbolConfiguration(weight: .semibold))) ?? base
    /// Images pré-calculées : l'icône orange tournée de 30° en 30°, sur un carré pour que rien ne soit rogné.
    private static let frames: [NSImage] = (0..<Spinner.frames).map { i in
        let side = ceil(max(colored.size.width, colored.size.height)) + 2
        let size = NSSize(width: side, height: side)
        let img = NSImage(size: size, flipped: false) { rect in
            let t = AffineTransform(translationByX: side / 2, byY: side / 2)
            var rot = AffineTransform(rotationByDegrees: -CGFloat(i) * 360 / CGFloat(Spinner.frames))
            rot.prepend(AffineTransform(translationByX: -side / 2, byY: -side / 2))
            var all = t; all.prepend(rot)
            (all as NSAffineTransform).concat()
            colored.draw(in: NSRect(x: (side - colored.size.width) / 2, y: (side - colored.size.height) / 2, width: colored.size.width, height: colored.size.height))
            return true
        }
        img.isTemplate = false          // une image « modèle » serait recolorée en blanc ou noir par le système
        return img
    }

    var body: some View {
        if running { Image(nsImage: Self.frames[spinner.frame]) }
        else { Image(nsImage: Self.template) }
    }

    private static let template: NSImage = { base.isTemplate = true; return base }()
}
