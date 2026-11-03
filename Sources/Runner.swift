// mBACKUP — exécution d'une tâche : montage des volumes, contrôles de sécurité, rsync, journal. Hors interface.
import Foundation
import Security

enum Paths {
    static let support: URL = {
        let u = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/mBACKUP")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    static var logs: URL {
        let u = support.appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var tasksFile: URL { support.appendingPathComponent("tasks.json") }
}

/// Mot de passe administrateur, rangé dans le Trousseau (jamais en clair sur le disque).
enum Keychain {
    private static let service = "fr.stephan.mbackup.admin"
    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: NSUserName()]
    }
    static func get() -> String? {
        var q = query(); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    @discardableResult static func set(_ password: String) -> Bool {
        remove()
        var q = query(); q[kSecValueData as String] = Data(password.utf8)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
    static func remove() { SecItemDelete(query() as CFDictionary) }
}

struct DryRunResult: Identifiable {
    let id = UUID()
    let taskName: String
    let summary: RsyncReport.Summary
    let lines: [String]
    let truncated: Bool
}

struct ExecResult {
    var outcome: RunOutcome
    var detail: String
    var logFile: String?
    var retryLater = false          // volume ou mot de passe manquant : on réessaiera, sans compter l'échéance comme traitée
    var dry: DryRunResult?
}

/// Reçoit la sortie de rsync par morceaux : journal, progression, compteurs de simulation, lignes de bilan.
final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var partial = ""
    private let log: FileHandle?
    private var statsLines: [String] = []
    private(set) var dryLines: [String] = []
    private var dryCounts = RsyncReport.Summary()
    private var truncated = false
    private var lastProgress = Date.distantPast
    private let onProgress: @Sendable (Double) -> Void
    private let keepDry: Bool

    init(logURL: URL?, append: Bool, header: String, keepDry: Bool, onProgress: @escaping @Sendable (Double) -> Void) {
        if let logURL {
            if !append || !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
            log = try? FileHandle(forWritingTo: logURL)
            _ = try? log?.seekToEnd()
            try? log?.write(contentsOf: Data(("=== " + header + " ===\n").utf8))
        } else { log = nil }
        self.keepDry = keepDry
        self.onProgress = onProgress
    }

    func feed(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        partial += String(decoding: data, as: UTF8.self)
        // La progression globale sépare ses mises à jour par « \r » ; le reste par « \n ».
        var pieces = partial.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
        partial = pieces.removeLast()
        for line in pieces where !line.isEmpty { handle(line, endsWithNewline: true) }
    }

    func finish() {
        lock.lock(); defer { lock.unlock() }
        if !partial.isEmpty { handle(partial, endsWithNewline: true); partial = "" }
        try? log?.close()
    }

    var stats: String { lock.lock(); defer { lock.unlock() }; return statsLines.joined(separator: "\n") }
    var dryResult: (RsyncReport.Summary, [String], Bool) { lock.lock(); defer { lock.unlock() }; return (dryCounts, dryLines, truncated) }

    private func handle(_ line: String, endsWithNewline: Bool) {
        if let r = line.range(of: #"(\d{1,3})%"#, options: .regularExpression), line.contains("to-chk") || line.contains("xfr#") || line.contains("/s") {
            let pct = Double(line[r].dropLast()) ?? 0
            if Date().timeIntervalSince(lastProgress) > 0.25 { lastProgress = Date(); onProgress(pct / 100) }
            return
        }
        try? log?.write(contentsOf: Data((line + "\n").utf8))
        if line.hasPrefix("Number of") || line.hasPrefix("Total file size") { statsLines.append(line) }
        if line.hasPrefix("*deleting") { dryCounts.deleted += 1; addDry(line) }
        else if line.hasPrefix(">f+++++++++") || line.hasPrefix("cd+++++++++") { dryCounts.created += 1; addDry(line) }
        else if line.hasPrefix(">f") { dryCounts.updated += 1; addDry(line) }
    }

    private func addDry(_ line: String) {
        guard keepDry else { return }
        if dryLines.count < 4000 { dryLines.append(line) } else { truncated = true }
    }
}

enum Runner {
    /// rsync embarqué (3.x) s'il est présent, sinon celui du système (plus ancien : sans attributs étendus).
    static var rsync: (path: String, modern: Bool) {
        if let p = Bundle.main.resourceURL?.appendingPathComponent("rsync").path, FileManager.default.isExecutableFile(atPath: p) { return (p, true) }
        return ("/usr/bin/rsync", false)
    }

    static func stamp(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: date)
    }

    // MARK: Volumes

    /// Vrai si `path` est lui-même un point de montage (un dossier vide laissé dans /Volumes ne compte pas).
    static func isMountPoint(_ path: String) -> Bool {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return false }
        let on = withUnsafePointer(to: &fs.f_mntonname) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
        return on == path || (path.hasSuffix("/") && on == String(path.dropLast()))
    }

    /// Premier niveau sous /Volumes (« /Volumes/Disque ») pour un chemin qui y est, sinon nil.
    static func volumeRoot(of path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "Volumes" else { return nil }
        return "/Volumes/" + parts[1]
    }

    /// Adresse smb:// du partage monté en `mountPoint` (lue dans la table des montages), nil si ce n'est pas un partage SMB.
    static func smbURL(forMountPoint mountPoint: String) -> String? {
        var fs = statfs()
        guard statfs(mountPoint, &fs) == 0 else { return nil }
        let type = withUnsafePointer(to: &fs.f_fstypename) { $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) } }
        guard type == "smbfs" else { return nil }
        let from = withUnsafePointer(to: &fs.f_mntfromname) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
        return from.hasPrefix("//") ? "smb:" + from : nil
    }

    /// Identifiant du volume local monté en `mountPoint` (pour `diskutil mount`), nil pour un partage réseau.
    static func volumeUUID(forMountPoint mountPoint: String) -> String? {
        try? URL(fileURLWithPath: mountPoint).resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    }

    static func mount(_ info: MountInfo) async {
        if let url = info.smbURL {
            let escaped = url.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            _ = await run("/usr/bin/osascript", ["-e", "mount volume \"\(escaped)\""], timeout: 25)
        } else if let uuid = info.volumeUUID {
            _ = await run("/usr/sbin/diskutil", ["mount", uuid], timeout: 25)
        }
        for _ in 0..<20 where !isMountPoint(info.mountPoint) { try? await Task.sleep(nanoseconds: 1_000_000_000) }
    }

    // MARK: Exécution

    /// Une tâche : sa destination, puis la seconde si elle existe. Chaque destination est traitée même si l'autre échoue.
    static func execute(_ task: BackupTask, dry: Bool, password: String?,
                        setProcess: @escaping @Sendable (Process?) -> Void,
                        onProgress: @escaping @Sendable (Double) -> Void) async -> ExecResult {
        var targets = [(path: task.destination, mount: task.destinationMount)]
        if let d = task.secondDestination, !d.path.isEmpty { targets.append((d.path, d.mount)) }
        let logName = PathTools.safeName(task.name) + "_" + stamp() + (dry ? "_simulation" : "") + ".log"
        var results: [ExecResult] = []
        for (i, t) in targets.enumerated() {
            var one = task
            one.destination = t.path; one.destinationMount = t.mount; one.secondDestination = nil
            let r = await executeOne(one, dry: dry, password: password, logName: logName, append: i > 0, setProcess: setProcess, onProgress: onProgress)
            results.append(r)
            if r.detail == L.t("res.stopped") { break }
        }
        guard results.count > 1 else { return results[0] }

        // Bilan commun : le pire résultat l'emporte, le détail nomme chaque destination.
        let labels = targets.map { PathTools.label($0.path) }
        let detail = zip(labels, results).map { "\($0) : \($1.detail)" }.joined(separator: " · ")
        let outcome: RunOutcome
        if results.contains(where: { $0.outcome == .failed }) { outcome = .failed }
        else if results.allSatisfy({ $0.outcome == .skipped }) { outcome = .skipped }
        else if results.allSatisfy({ $0.outcome == .success }) { outcome = .success }
        else { outcome = .warnings }
        var merged = ExecResult(outcome: outcome, detail: detail, logFile: results.compactMap(\.logFile).first)
        merged.retryLater = results.contains { $0.retryLater }
        if dry {
            var sum = RsyncReport.Summary(); var lines: [String] = []; var truncated = false
            for (label, r) in zip(labels, results) {
                guard let d = r.dry else { continue }
                sum.created += d.summary.created; sum.updated += d.summary.updated; sum.deleted += d.summary.deleted
                lines += ["── " + label + " ──"] + d.lines; truncated = truncated || d.truncated
            }
            merged.dry = DryRunResult(taskName: task.name, summary: sum, lines: lines, truncated: truncated)
        }
        return merged
    }

    static func executeOne(_ task: BackupTask, dry: Bool, password: String?, logName: String, append: Bool,
                           setProcess: @escaping @Sendable (Process?) -> Void,
                           onProgress: @escaping @Sendable (Double) -> Void) async -> ExecResult {
        // 1. Volumes à monter, puis garde-fou : jamais d'écriture sur le disque système à la place d'un volume absent.
        for info in [task.sourceMount, task.destinationMount].compactMap({ $0 }) where !isMountPoint(info.mountPoint) {
            if info.autoMount { await mount(info) }
            if !isMountPoint(info.mountPoint) {
                return ExecResult(outcome: .skipped, detail: L.t("res.missing", info.mountPoint), retryLater: true)
            }
        }
        for path in [task.source, task.destination] {
            if let root = volumeRoot(of: path), !isMountPoint(root) {
                return ExecResult(outcome: .skipped, detail: L.t("res.missing", root), retryLater: true)
            }
        }
        guard FileManager.default.fileExists(atPath: task.source) else {
            return ExecResult(outcome: .skipped, detail: L.t("res.nosource", task.source), retryLater: true)
        }
        if task.useAdmin && (password ?? "").isEmpty {
            return ExecResult(outcome: .skipped, detail: L.t("res.nopass"), retryLater: true)
        }

        // 2. Ligne de commande
        let started = Date()
        let st = stamp(started)
        let excludeFile = NSTemporaryDirectory() + "mbackup-" + UUID().uuidString + ".exclude"
        let r = rsync
        let cmd = RsyncCommand.make(for: task, rsync: r.path, modern: r.modern, dryRun: dry, stamp: st, excludeFile: excludeFile)
        if let content = cmd.excludeFileContent { try? content.write(toFile: excludeFile, atomically: true, encoding: .utf8) }
        defer { try? FileManager.default.removeItem(atPath: excludeFile) }
        if task.versioning && !dry { try? FileManager.default.createDirectory(atPath: PathTools.versionsRoot(for: task), withIntermediateDirectories: true) }

        let collector = OutputCollector(logURL: Paths.logs.appendingPathComponent(logName), append: append,
                                        header: task.source + " → " + task.destination, keepDry: dry, onProgress: onProgress)

        let process = Process()
        if task.useAdmin {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["-S", "-p", "", cmd.executable] + cmd.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: cmd.executable)
            process.arguments = cmd.arguments
        }
        let out = Pipe(), input = Pipe()
        process.standardOutput = out; process.standardError = out; process.standardInput = input
        setProcess(process)
        do { try process.run() } catch {
            collector.finish(); setProcess(nil)
            return ExecResult(outcome: .failed, detail: error.localizedDescription, logFile: logName)
        }
        if task.useAdmin, let password { input.fileHandleForWriting.write(Data((password + "\n").utf8)) }
        try? input.fileHandleForWriting.close()

        let handle = out.fileHandleForReading
        await Task.detached {
            while true { let d = handle.availableData; if d.isEmpty { break }; collector.feed(d) }
        }.value
        process.waitUntilExit()
        collector.finish(); setProcess(nil)

        let code = process.terminationStatus
        if process.terminationReason == .uncaughtSignal { return ExecResult(outcome: .skipped, detail: L.t("res.stopped"), logFile: logName) }
        if task.useAdmin, code == 1, collector.stats.isEmpty { return ExecResult(outcome: .failed, detail: L.t("res.badpass"), logFile: logName) }

        if dry {
            let (counts, lines, truncated) = collector.dryResult
            let d = DryRunResult(taskName: task.name, summary: counts, lines: lines, truncated: truncated)
            return ExecResult(outcome: RsyncReport.outcome(forExitCode: code), detail: L.t("dry.summary", counts.created, counts.updated, counts.deleted), logFile: logName, dry: d)
        }
        let outcome = RsyncReport.outcome(forExitCode: code)
        let s = RsyncReport.summary(from: collector.stats)
        let copied = s.transferred
        var detail: String
        switch outcome {
        case .success: detail = L.t("res.ok", copied, s.deleted)
        case .warnings: detail = L.t("res.warn", copied, s.deleted)
        default: detail = L.t("res.exit", Int(code))
        }
        if task.versioning && outcome != .failed { await prune(task, password: password) }
        pruneLogs()
        return ExecResult(outcome: outcome, detail: detail, logFile: logName)
    }

    // MARK: Entretien

    /// Ne garde que les `versionsKept` dossiers datés les plus récents (ceux qui portent un horodatage de mBACKUP).
    static func prune(_ task: BackupTask, password: String?) async {
        let root = PathTools.versionsRoot(for: task)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else { return }
        let stamps = names.filter { $0.range(of: #"^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }.sorted()
        for old in stamps.dropLast(max(1, task.versionsKept)) {
            let path = (root as NSString).appendingPathComponent(old)
            do { try FileManager.default.removeItem(atPath: path) } catch {
                if task.useAdmin, let password { _ = await run("/usr/bin/sudo", ["-S", "-p", "", "/bin/rm", "-rf", "--", path], stdin: password + "\n", timeout: 300) }
            }
        }
    }

    static func pruneLogs(keep: Int = 150) {
        let dir = Paths.logs
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let sorted = files.filter { $0.pathExtension == "log" }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        for f in sorted.dropFirst(keep) { try? FileManager.default.removeItem(at: f) }
    }

    /// Vérifie le mot de passe administrateur (`sudo -v`) ; renvoie aussi la raison donnée par sudo en cas de refus.
    static func verifyAdmin(_ password: String) async -> (ok: Bool, detail: String) {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo"); p.arguments = ["-S", "-k", "-p", "", "-v"]
            let input = Pipe(), err = Pipe()
            p.standardInput = input; p.standardOutput = FileHandle.nullDevice; p.standardError = err
            do { try p.run() } catch { return (false, error.localizedDescription) }
            input.fileHandleForWriting.write(Data((password + "\n").utf8))
            try? input.fileHandleForWriting.close()
            let deadline = Date().addingTimeInterval(20)
            while p.isRunning && Date() < deadline { try? await Task.sleep(nanoseconds: 100_000_000) }
            if p.isRunning { p.terminate(); return (false, "délai dépassé") }
            let text = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " / ")
            return (p.terminationStatus == 0, "code \(p.terminationStatus)" + (text.isEmpty ? "" : " : " + text))
        }.value
    }

    /// Petit utilitaire : lance une commande et attend sa fin (avec délai maximal).
    @discardableResult
    static func run(_ exe: String, _ args: [String], stdin: String? = nil, timeout: TimeInterval) async -> Int32 {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
            let input = Pipe()
            p.standardInput = input; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return -1 }
            if let stdin { input.fileHandleForWriting.write(Data(stdin.utf8)) }
            try? input.fileHandleForWriting.close()
            let deadline = Date().addingTimeInterval(timeout)
            while p.isRunning && Date() < deadline { try? await Task.sleep(nanoseconds: 100_000_000) }
            if p.isRunning { p.terminate(); return -2 }
            return p.terminationStatus
        }.value
    }
}
