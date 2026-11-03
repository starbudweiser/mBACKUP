// mBACKUP — état de l'appli : tâches, file d'exécution, planificateur, notifications.
import Foundation
import SwiftUI
import UserNotifications
import ServiceManagement

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var tasks: [BackupTask] = [] { didSet { save() } }
    @Published var selection: UUID?
    @Published var progress: [UUID: Double] = [:]
    @Published var queue: [UUID] = []                 // en attente ou en cours (le premier est en cours)
    @Published var dryRun: DryRunResult?
    @Published var notice: String?
    @Published var showSettings = false

    private var current: Process?
    private var retryAfter: [UUID: Date] = [:]
    private var queuedDry: Set<UUID> = []
    private var scheduledRun: Set<UUID> = []
    private var skipNotified: Set<UUID> = []             // tâches dont l'absence de volume ou de mot de passe a déjà été signalée
    private var timer: Timer?
    private var loading = false

    private init() {
        load()
        selection = tasks.first?.id
    }

    // MARK: Persistance

    private func load() {
        guard let data = try? Data(contentsOf: Paths.tasksFile) else { return }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        loading = true
        tasks = (try? d.decode([BackupTask].self, from: data)) ?? []
        loading = false
    }

    private func save() {
        guard !loading else { return }
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? e.encode(tasks) { try? data.write(to: Paths.tasksFile, options: .atomic) }
    }

    // MARK: Démarrage

    func start() {
        guard timer == nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        if UserDefaults.standard.object(forKey: "launchAtLoginSet") == nil {
            UserDefaults.standard.set(true, forKey: "launchAtLoginSet")
            setLaunchAtLogin(true)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in Task { @MainActor in Store.shared.tick() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Store.shared.tick() }
    }

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    func setLaunchAtLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
        objectWillChange.send()
    }

    // MARK: Planificateur

    /// Lance les tâches dont l'échéance est passée : à l'heure dite, ou en rattrapage si la tâche l'autorise.
    func tick(now: Date = Date()) {
        Updater.shared.tick(busy: !queue.isEmpty)
        for t in tasks where t.enabled && !queue.contains(t.id) {
            guard let due = t.schedule.lastOccurrence(onOrBefore: now),
                  (t.lastAttempt ?? .distantPast) < due,
                  now.timeIntervalSince(due) <= 180 || t.catchUp,
                  (retryAfter[t.id] ?? .distantPast) <= now else { continue }
            scheduledRun.insert(t.id)
            enqueue(t.id, dry: false)
        }
    }

    func nextRun(_ t: BackupTask) -> Date? { t.enabled ? t.schedule.nextOccurrence(after: Date()) : nil }

    // MARK: File d'exécution (une tâche à la fois)

    func isRunning(_ id: UUID) -> Bool { queue.first == id }
    func isQueued(_ id: UUID) -> Bool { queue.contains(id) }

    func enqueue(_ id: UUID, dry: Bool) {
        guard !queue.contains(id) else { return }
        queue.append(id)
        if dry { queuedDry.insert(id) }
        Spinner.shared.set(running: true)
        pump()
    }

    func runAll() { tasks.filter(\.enabled).forEach { enqueue($0.id, dry: false) } }

    func stop(_ id: UUID) {
        if queue.first == id { current?.terminate() } else { queue.removeAll { $0 == id }; queuedDry.remove(id); if queue.isEmpty { Spinner.shared.set(running: false) } }
    }

    private func pump() {
        guard current == nil, let id = queue.first, let task = tasks.first(where: { $0.id == id }) else { return }
        let dry = queuedDry.contains(id)
        progress[id] = 0
        let password = task.useAdmin ? Keychain.get() : nil
        Task {
            let result = await Runner.execute(task, dry: dry, password: password,
                                              setProcess: { p in Task { @MainActor in Store.shared.current = p } },
                                              onProgress: { v in Task { @MainActor in Store.shared.progress[id] = v } })
            finish(id, task: task, dry: dry, result: result)
        }
    }

    private func finish(_ id: UUID, task: BackupTask, dry: Bool, result: ExecResult) {
        current = nil
        queue.removeAll { $0 == id }
        queuedDry.remove(id)
        progress[id] = nil
        if queue.isEmpty { Spinner.shared.set(running: false) }
        let scheduled = scheduledRun.remove(id) != nil

        if dry {
            dryRun = result.dry
            if result.dry == nil { notice = result.detail }
        } else if let i = tasks.firstIndex(where: { $0.id == id }) {
            tasks[i].last = RunRecord(date: Date(), outcome: result.outcome, detail: result.detail, logFile: result.logFile)
            if result.retryLater {
                retryAfter[id] = Date().addingTimeInterval(600)     // volume absent : nouvel essai dans 10 min
            } else {
                tasks[i].lastAttempt = Date()
                retryAfter[id] = nil
            }
            if result.retryLater {
                if skipNotified.insert(id).inserted { notify(task.name, result) }     // une seule alerte, pas une toutes les 10 min
            } else {
                skipNotified.remove(id)
                if scheduled || result.outcome != .success { notify(task.name, result) }
            }
        }
        pump()
    }

    private func notify(_ name: String, _ r: ExecResult) {
        let errorsOnly = UserDefaults.standard.object(forKey: "notifyErrorsOnly") as? Bool ?? true
        if errorsOnly && r.outcome == .success { return }
        let key: String
        switch r.outcome { case .success: key = "notif.ok"; case .warnings: key = "notif.warn"; default: key = "notif.fail" }
        let c = UNMutableNotificationContent()
        c.title = L.t(key, name); c.body = r.detail
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    // MARK: Édition

    @discardableResult
    func addTask() -> UUID {
        var t = BackupTask(name: L.t("task.new"), source: "", destination: "")
        t.lastAttempt = Date()
        tasks.append(t)
        selection = t.id
        return t.id
    }

    func delete(_ id: UUID) {
        stop(id)
        tasks.removeAll { $0.id == id }
        if selection == id { selection = tasks.first?.id }
    }

    func binding(for id: UUID) -> Binding<BackupTask>? {
        guard tasks.contains(where: { $0.id == id }) else { return nil }
        return Binding(get: { self.tasks.first { $0.id == id } ?? BackupTask(name: "", source: "", destination: "") },
                       set: { new in if let i = self.tasks.firstIndex(where: { $0.id == id }) { self.tasks[i] = new } })
    }

    // MARK: Statut affiché

    func statusKey(_ t: BackupTask) -> String {
        if isRunning(t.id) { return "status.running" }
        if isQueued(t.id) { return "status.idle" }
        if !t.enabled { return "status.disabled" }
        guard let last = t.last else { return "status.never" }
        switch last.outcome {
        case .success: return "status.success"
        case .warnings: return "status.warnings"
        case .failed: return "status.failed"
        case .skipped: return "status.skipped"
        }
    }

    func logURL(_ t: BackupTask) -> URL? { t.last?.logFile.map { Paths.logs.appendingPathComponent($0) } }
}
