// mBACKUP — interface SwiftUI (design system Socle).
import SwiftUI
import AppKit

enum Brand {
    /// Vert-turquoise du logo : la lettre « m » de mBACKUP.
    static let color = Color(red: 0x2d / 255, green: 0xd4 / 255, blue: 0xbf / 255)
}

/// Motif de l'icône (anneau fléché + deux disques), d'une seule teinte : logo, filigrane, état vide.
/// Même géométrie que Resources/make_icon.swift (repère mathématique, y vers le haut, unités de l'icône 1024).
struct MbackupMark: View {
    var body: some View {
        Canvas { ctx, size in
            let k = min(size.width, size.height) / 640
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + x * k, y: c.y - y * k) }
            var ring = Path()
            let r: CGFloat = 270
            for (i, deg) in stride(from: 40.0, through: 325.0, by: 2.0).enumerated() {
                let a = deg * .pi / 180
                let p = pt(r * cos(a), r * sin(a))
                if i == 0 { ring.move(to: p) } else { ring.addLine(to: p) }
            }
            ctx.stroke(ring, with: .foreground, lineWidth: 58 * k)
            let a = 325.0 * .pi / 180, dir = a + .pi / 2
            let end = (x: r * cos(a), y: r * sin(a)), u = (x: cos(dir), y: sin(dir)), p = (x: -sin(dir), y: cos(dir))
            var head = Path()
            head.move(to: pt(end.x + 105 * u.x, end.y + 105 * u.y))
            head.addLine(to: pt(end.x + 85 * p.x, end.y + 85 * p.y))
            head.addLine(to: pt(end.x - 85 * p.x, end.y - 85 * p.y))
            head.closeSubpath()
            ctx.fill(head, with: .foreground)
            for dy in [CGFloat(-62), 62] {
                ctx.fill(Path(roundedRect: CGRect(x: c.x - 150 * k, y: c.y - (dy + 38) * k, width: 300 * k, height: 76 * k), cornerRadius: 30 * k), with: .foreground)
            }
        }
    }
}

// MARK: - Composants

struct Card<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
                if let subtitle { Text(branded: subtitle).socle(Socle.T.body).foregroundStyle(Socle.C.accentText) }
            }
            content
        }
        .padding(Socle.M.space6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusLg))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusLg).stroke(Socle.C.border, lineWidth: 1))
        .socleModule()
    }
}

struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(branded: text).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true) }
}

struct Check: View {
    let title: String
    var help: String?
    @Binding var isOn: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: $isOn) { Text(title).socle(Socle.T.body).foregroundStyle(Socle.C.text).fixedSize(horizontal: false, vertical: true) }
                .toggleStyle(.checkbox).tint(Socle.C.accent)
            if let help { Hint(help).padding(.leading, 22) }
        }
    }
}

struct PathField: View {
    let label: String
    @Binding var path: String
    let onPick: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).socle(Socle.T.label).foregroundStyle(Socle.C.textMuted)
            HStack(spacing: Socle.M.space2) {
                TextField("", text: $path).socle(Socle.T.mono).socleValue().socleField()
                Button(L.t("btn.choose")) {
                    let p = NSOpenPanel()
                    p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
                    if !path.isEmpty { p.directoryURL = URL(fileURLWithPath: path) }
                    if p.runModal() == .OK, let u = p.url { onPick(u.path) }
                }.buttonStyle(SocleButtonStyle(.secondary)).frame(width: 120)
            }
        }
    }
}

struct StatusDot: View {
    let outcome: RunOutcome?
    let running: Bool
    var color: Color {
        if running { return Socle.C.accentText }
        switch outcome {
        case .success: return Socle.C.success
        case .warnings: return Socle.C.warning
        case .failed: return Socle.C.danger
        default: return Socle.C.textSubtle
        }
    }
    var body: some View { Circle().fill(color).frame(width: 8, height: 8) }
}

struct ProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Socle.C.bgSunken)
                Rectangle().fill(Socle.C.accent).frame(width: g.size.width * min(1, max(0, value)))
            }
        }.frame(height: 6).clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Fenêtre principale

struct ContentView: View {
    @ObservedObject var store = Store.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Socle.M.space3) {
                Text(branded: "mBACKUP").socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
                Spacer()
                Button(L.t("menu.settings")) { store.showSettings = true }.buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).frame(width: 130)
            }
            .padding(.horizontal, Socle.M.space3).frame(height: Socle.M.sizeBar)
            .background(Socle.C.surfaceRaised)
            Rectangle().fill(Socle.C.border).frame(height: 1)
            HStack(spacing: 0) {
                Sidebar().frame(width: 270)
                Rectangle().fill(Socle.C.border).frame(width: 1)
                Group {
                    if store.tasks.isEmpty { EmptyState() }
                    else if let id = store.selection, let b = store.binding(for: id) { TaskEditor(task: b).id(id) }
                    else { Color.clear }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Socle.C.bg)
        .frame(minWidth: 1000, minHeight: 660)
        .environment(\.locale, L.locale)
        .background(WindowSetup())
        .sheet(isPresented: $store.showSettings) { SettingsSheet() }
        .sheet(item: $store.dryRun) { DryRunSheet(result: $0) }
        .alert(store.notice ?? "", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("OK") { store.notice = nil }
        }
    }
}

/// Centre la fenêtre à l'ouverture (écran du pointeur) et applique le thème.
struct WindowSetup: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { v.window?.socleCenter() }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct Sidebar: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        VStack(spacing: 0) {
            Text(L.t("tasks.title")).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Socle.M.space4).padding(.top, Socle.M.space4).padding(.bottom, Socle.M.space2)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.tasks) { t in
                        Button { store.selection = t.id } label: {
                            HStack(spacing: Socle.M.space2_5) {
                                StatusDot(outcome: t.last?.outcome, running: store.isRunning(t.id))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.name).socle(Socle.T.label).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                                    Text(sub(t)).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space2)
                            .background(store.selection == t.id ? Socle.C.surfaceSelected : .clear, in: RoundedRectangle(cornerRadius: Socle.M.radius))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, Socle.M.space2)
            }
            VStack(spacing: Socle.M.space2) {
                Button(L.t("tasks.add")) { store.addTask() }.buttonStyle(SocleButtonStyle(.secondary))
            }.padding(Socle.M.space3)
        }
        .background(Socle.C.surfaceRaised)
        .socleWatermark { MbackupMark() }
    }

    private func sub(_ t: BackupTask) -> String {
        if store.isRunning(t.id) { return "\(L.t("status.running")) · \(Int((store.progress[t.id] ?? 0) * 100)) %" }
        if let n = store.nextRun(t) { return L.t("next.at", L.date(n)) }
        return L.t(store.statusKey(t))
    }
}

struct EmptyState: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        GeometryReader { g in ScrollView {
            VStack(spacing: Socle.M.space4) {
                MbackupMark().frame(width: 88, height: 88).foregroundStyle(Brand.color)
                Text(L.t("empty.title")).socle(Socle.T.display).foregroundStyle(Socle.C.textStrong)
                Text(branded: L.t("empty.body")).socle(Socle.T.reading).foregroundStyle(Socle.C.textMuted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button(L.t("tasks.add")) { store.addTask() }.buttonStyle(SocleButtonStyle(.action)).frame(width: 300).padding(.top, Socle.M.space2)
            }
            .padding(Socle.M.space6).frame(maxWidth: 560)
            .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusLg))
            .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusLg).stroke(Socle.C.border, lineWidth: 1))
            .frame(maxWidth: .infinity, minHeight: g.size.height).padding(28)
        } }
    }
}

// MARK: - Éditeur d'une tâche

struct TaskEditor: View {
    @Binding var task: BackupTask
    @ObservedObject var store = Store.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Socle.C.border).frame(height: 1)
            ScrollView {
                SocleModuleGrid(minimum: 370) {
                    general; paths; schedule; options; excludes; lastRun
                }.padding(28)
            }
        }
    }

    private var header: some View {
        HStack(spacing: Socle.M.space3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.name).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                Text(L.t(store.statusKey(task))).socle(Socle.T.meta).foregroundStyle(statusColor)
            }
            Spacer()
            if store.isQueued(task.id) {
                Button(L.t("btn.stop")) { store.stop(task.id) }.buttonStyle(SocleButtonStyle(.secondary)).frame(width: 120)
            } else {
                Button(L.t("btn.dry")) { store.enqueue(task.id, dry: true) }.buttonStyle(SocleButtonStyle(.secondary)).frame(width: 120)
                Button(L.t("btn.run")) { store.enqueue(task.id, dry: false) }.buttonStyle(SocleButtonStyle(.primary)).frame(width: 120)
            }
        }
        .padding(.horizontal, 28).frame(height: 64).background(Socle.C.surfaceRaised)
    }

    private var statusColor: Color {
        if store.isRunning(task.id) { return Socle.C.accentText }
        switch task.last?.outcome {
        case .success: return Socle.C.success
        case .warnings: return Socle.C.warning
        case .failed: return Socle.C.danger
        default: return Socle.C.textMuted
        }
    }

    private var general: some View {
        Card(title: L.t("sec.general")) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("f.name")).socle(Socle.T.label).foregroundStyle(Socle.C.textMuted)
                TextField("", text: $task.name).socle(Socle.T.body).socleField()
            }
            Check(title: L.t("f.enabled"), isOn: $task.enabled)
            if let from = task.importedFrom { Hint(from) }
            Button(L.t("btn.delete")) { store.delete(task.id) }.buttonStyle(SocleButtonStyle(.tertiary)).frame(width: 200)
        }
    }

    private var paths: some View {
        Card(title: L.t("sec.paths"), subtitle: L.t("sec.paths.sub")) {
            PathField(label: L.t("f.source"), path: $task.source) { task.source = $0; task.sourceMount = Self.mountInfo($0, keeping: task.sourceMount) }
            if task.sourceMount != nil {
                Check(title: L.t("f.automount"), isOn: Binding(get: { task.sourceMount?.autoMount ?? false }, set: { task.sourceMount?.autoMount = $0 }))
            }
            PathField(label: L.t("f.dest"), path: $task.destination) { task.destination = $0; task.destinationMount = Self.mountInfo($0, keeping: task.destinationMount) }
            if task.destinationMount != nil {
                Check(title: L.t("f.automount"), isOn: Binding(get: { task.destinationMount?.autoMount ?? false }, set: { task.destinationMount?.autoMount = $0 }))
            }
        }
    }

    /// Un chemin sous /Volumes se rattache à son volume (pour le montage automatique) ; ailleurs, aucun montage.
    static func mountInfo(_ path: String, keeping old: MountInfo?) -> MountInfo? {
        guard let root = Runner.volumeRoot(of: path) else { return nil }
        if let old, old.mountPoint == root { return old }
        return MountInfo(mountPoint: root, smbURL: nil, volumeUUID: nil, autoMount: false)
    }

    private var schedule: some View {
        Card(title: L.t("sec.schedule")) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("f.days")).socle(Socle.T.label).foregroundStyle(Socle.C.textMuted)
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { d in
                        let on = task.schedule.days.contains(d)
                        Button {
                            if on { task.schedule.days.remove(d) } else { task.schedule.days.insert(d) }
                        } label: {
                            Text(L.weekdays[d]).socle(Socle.T.label).frame(maxWidth: .infinity, minHeight: 30)
                                .foregroundStyle(on ? Socle.C.onAccentFill : Socle.C.textMuted)
                                .background(on ? Socle.C.accentFill : Socle.C.bgSunken, in: RoundedRectangle(cornerRadius: Socle.M.radius))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Text(L.t("f.time")).socle(Socle.T.label).foregroundStyle(Socle.C.textMuted)
                DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.stepperField)
                Spacer()
            }
            Check(title: L.t("f.catchUp"), help: L.t("f.catchUp.help"), isOn: $task.catchUp)
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: task.schedule.hour, minute: task.schedule.minute, second: 0, of: Date()) ?? Date() },
                set: { d in let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                    task.schedule.hour = c.hour ?? 0; task.schedule.minute = c.minute ?? 0 })
    }

    private var options: some View {
        Card(title: L.t("sec.options")) {
            Check(title: L.t("f.mirror"), isOn: $task.deleteExtra)
            Check(title: L.t("f.hidden"), isOn: $task.excludeHidden)
            Check(title: L.t("f.admin"), help: L.t("f.admin.help"), isOn: $task.useAdmin)
            Check(title: L.t("f.versioning"), help: L.t("f.versioning.help"), isOn: $task.versioning)
            if task.versioning {
                HStack(spacing: Socle.M.space3) {
                    Text(L.t("f.keep")).socle(Socle.T.label).foregroundStyle(Socle.C.textMuted)
                    Stepper(value: $task.versionsKept, in: 1...100) { Text("\(task.versionsKept)").socle(Socle.T.mono).socleValue() }
                    Spacer()
                }
                Button(L.t("btn.versions")) {
                    let root = PathTools.versionsRoot(for: task)
                    if FileManager.default.fileExists(atPath: root) { NSWorkspace.shared.open(URL(fileURLWithPath: root)) }
                }.buttonStyle(SocleButtonStyle(.secondary)).frame(width: 220)
            }
        }
    }

    private var excludes: some View {
        Card(title: L.t("sec.excludes"), subtitle: L.t("f.excludes")) {
            TextEditor(text: Binding(get: { task.excludes.joined(separator: "\n") },
                                     set: { task.excludes = $0.components(separatedBy: "\n") }))
                .socle(Socle.T.mono).socleField(multiline: true).frame(minHeight: 130)
            Hint(L.t("f.excludes.help"))
        }
    }

    private var lastRun: some View {
        Card(title: L.t("sec.last")) {
            if store.isQueued(task.id) { ProgressBar(value: store.progress[task.id] ?? 0) }
            if let last = task.last {
                HStack(spacing: Socle.M.space2) {
                    StatusDot(outcome: last.outcome, running: false)
                    Text(L.t("last.at", L.date(last.date))).socle(Socle.T.body).foregroundStyle(Socle.C.text)
                }
                Text(last.detail).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).fixedSize(horizontal: false, vertical: true)
                if let url = store.logURL(task), FileManager.default.fileExists(atPath: url.path) {
                    Button(L.t("btn.log")) { NSWorkspace.shared.open(url) }.buttonStyle(SocleButtonStyle(.secondary)).frame(width: 200)
                }
            } else {
                Text(L.t("status.never")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
            }
            if let n = store.nextRun(task) { Hint(L.t("next.at", L.date(n))) }
        }
    }
}

// MARK: - Feuilles

struct SheetFrame<Content: View, Footer: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    var body: some View {
        VStack(spacing: 0) {
            Text(branded: title).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
                .frame(maxWidth: .infinity, alignment: .leading).padding(Socle.M.space6)
            Rectangle().fill(Socle.C.border).frame(height: 1)
            content.padding(Socle.M.space6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(Socle.C.border).frame(height: 1)
            HStack(spacing: Socle.M.space2) { Spacer(); footer }.padding(Socle.M.space4)
        }
        .background(Socle.C.surface).environment(\.locale, L.locale)
    }
}

struct DryRunSheet: View {
    let result: DryRunResult
    @ObservedObject var store = Store.shared
    var body: some View {
        SheetFrame(title: L.t("dry.title", result.taskName)) {
            VStack(alignment: .leading, spacing: Socle.M.space3) {
                Text(L.t("dry.summary", result.summary.created, result.summary.updated, result.summary.deleted))
                    .socle(Socle.T.body).foregroundStyle(Socle.C.accentText)
                if result.lines.isEmpty { Text(L.t("dry.empty")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted) }
                else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(result.lines.enumerated()), id: \.offset) { _, l in
                                Text(l).socle(Socle.T.monoSm).foregroundStyle(l.hasPrefix("*deleting") ? Socle.C.danger : Socle.C.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.padding(Socle.M.space3)
                    }.background(Socle.C.bgSunken)
                }
                Hint(L.t("dry.note"))
            }
        } footer: {
            Button(L.t("btn.close")) { store.dryRun = nil }.buttonStyle(SocleButtonStyle(.primary)).frame(width: 130)
        }
        .frame(width: 760, height: 560)
    }
}

struct SettingsSheet: View {
    @ObservedObject var store = Store.shared
    @AppStorage("notifyErrorsOnly") private var errorsOnly = true
    @State private var password = ""
    @State private var message: String?
    @State private var refused = false
    @State private var hasPassword = Keychain.get() != nil

    var body: some View {
        SheetFrame(title: L.t("set.title")) {
            VStack(alignment: .leading, spacing: Socle.M.space4) {
                Check(title: L.t("set.login"), help: L.t("set.login.help"),
                      isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                Check(title: L.t("set.notify"), isOn: $errorsOnly)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.t("set.admin")).socle(Socle.T.label).foregroundStyle(Socle.C.textMuted)
                    HStack(spacing: Socle.M.space2) {
                        SecureField("", text: $password).socle(Socle.T.body).socleField()
                        Button(L.t("set.admin.set")) {
                            Task {
                                let r = await Runner.verifyAdmin(password)
                                if r.ok { Keychain.set(password); hasPassword = true; message = L.t("set.admin.saved"); password = ""; refused = false }
                                else { message = L.t("set.admin.bad") + " (" + r.detail + ")"; refused = true }
                            }
                        }.buttonStyle(SocleButtonStyle(.primary)).frame(width: 120).disabled(password.isEmpty)
                        if refused {
                            Button(L.t("set.admin.force")) { Keychain.set(password); hasPassword = true; message = L.t("set.admin.saved"); password = ""; refused = false }
                                .buttonStyle(SocleButtonStyle(.secondary)).frame(width: 170)
                        }
                        Button(L.t("set.admin.remove")) { Keychain.remove(); hasPassword = false; message = L.t("set.admin.none") }
                            .buttonStyle(SocleButtonStyle(.secondary)).frame(width: 120).disabled(!hasPassword)
                    }
                    Hint(message ?? (hasPassword ? L.t("set.admin.saved") : L.t("set.admin.none")))
                    Hint(L.t("set.admin.help"))
                }
                Hint(L.t("set.fda"))
            }
        } footer: {
            Button(L.t("btn.close")) { store.showSettings = false }.buttonStyle(SocleButtonStyle(.primary)).frame(width: 130)
        }
        .frame(width: 600, height: 460)
    }
}
