// mBACKUP — exécution d'une tâche « archives » : un zip épuré par dossier, déposé à la destination.
import Foundation

extension Runner {
    private static var stateURL: URL { Paths.support.appendingPathComponent("archives-state.json") }
    private static func loadState() -> [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: stateURL))) ?? [:]
    }
    private static func saveState(_ s: [String: String]) { try? JSONEncoder().encode(s).write(to: stateURL, options: .atomic) }

    static func executeArchive(_ task: BackupTask, dry: Bool, logName: String, append: Bool,
                               setProcess: @escaping @Sendable (Process?) -> Void,
                               onProgress: @escaping @Sendable (Double) -> Void) async -> ExecResult {
        let fm = FileManager.default
        let opts = task.archive ?? ArchiveOptions()
        let patterns = ArchiveTool.patterns(task.excludes)
        let units = ArchiveTool.units(source: task.source, perSubfolder: opts.perSubfolder, patterns: patterns,
                                       only: (opts.only ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        guard !units.isEmpty else { return ExecResult(outcome: .skipped, detail: L.t("arc.nounit"), logFile: logName) }
        // Dossiers temporaires laissés par un arrêt brutal : on retire ceux de plus de 2 h.
        let tmpRoot = NSTemporaryDirectory()
        for n in (try? fm.contentsOfDirectory(atPath: tmpRoot)) ?? [] where n.hasPrefix("mbackup-zip-") {
            let p = tmpRoot + n
            if let m = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date, Date().timeIntervalSince(m) > 7200 { try? fm.removeItem(atPath: p) }
        }
        if !dry { try? fm.createDirectory(atPath: task.destination, withIntermediateDirectories: true) }

        var log = "=== " + task.source + " → " + task.destination + " (zip) ===\n"
        func flush() {
            let url = Paths.logs.appendingPathComponent(logName)
            if append, let h = try? FileHandle(forWritingTo: url) { _ = try? h.seekToEnd(); try? h.write(contentsOf: Data(log.utf8)); try? h.close() }
            else { try? log.write(to: url, atomically: true, encoding: .utf8) }
        }

        var state = loadState()
        var made = 0, same = 0, failed: [String] = [], warned = false
        var dryLines: [String] = [], dryNew = 0, dryUpd = 0
        for (i, unit) in units.enumerated() {
            onProgress(Double(i) / Double(units.count))
            let finalZip = (task.destination as NSString).appendingPathComponent(unit.zipName)
            let key = task.id.uuidString + "|" + finalZip
            let fp = ArchiveTool.fingerprint(of: unit.path, patterns: patterns)
            let exists = fm.fileExists(atPath: finalZip)
            if exists && state[key] == fp { same += 1; log += "= \(unit.zipName) (inchangé)\n"; continue }
            if dry {
                if exists { dryUpd += 1 } else { dryNew += 1 }
                dryLines.append((exists ? ">f.st...... " : ">f+++++++++ ") + unit.zipName)
                continue
            }

            // Le zip se construit en local, puis part d'un seul bloc vers la destination (un gros fichier plutôt que des milliers de petits).
            let work = NSTemporaryDirectory() + "mbackup-zip-" + UUID().uuidString
            try? fm.createDirectory(atPath: work, withIntermediateDirectories: true)
            defer { try? fm.removeItem(atPath: work) }
            let tmpZip = (work as NSString).appendingPathComponent(unit.zipName)

            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            p.currentDirectoryURL = URL(fileURLWithPath: unit.parent)
            p.arguments = ["-r", "-X", "-y", "-q", tmpZip, unit.name] + ArchiveTool.zipExcludeArgs(patterns)
            let err = Pipe()
            p.standardOutput = FileHandle.nullDevice; p.standardError = err
            setProcess(p)
            let exited = ProcessExit(p)
            do { try p.run() } catch { setProcess(nil); failed.append(unit.name); log += "! \(unit.zipName) : \(error.localizedDescription)\n"; continue }
            let errData = await Task.detached { let d = err.fileHandleForReading.readDataToEndOfFile(); exited.waitSync(); return d }.value
            setProcess(nil)
            if p.terminationReason == .uncaughtSignal { log += "— arrêt demandé\n"; flush(); return ExecResult(outcome: .skipped, detail: L.t("res.stopped"), logFile: logName) }
            let code = p.terminationStatus
            let msg = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if code != 0 && code != 18 { failed.append(unit.name); log += "! \(unit.zipName) : zip code \(code) \(msg)\n"; continue }
            if code == 18 { warned = true; log += "~ \(unit.zipName) : fichiers illisibles ignorés \(msg)\n" }

            let part = finalZip + "." + UUID().uuidString.prefix(8) + ".part"      // nom propre à cette exécution
            do {
                // L'ancien zip n'est jamais supprimé avant que le nouveau soit entièrement copié et mis à sa place.
                try fm.copyItem(atPath: tmpZip, toPath: part)
                let size = ((try? fm.attributesOfItem(atPath: tmpZip))?[.size] as? NSNumber)?.uint64Value
                try ArchiveTool.replace(part: part, final: finalZip, expectedSize: size)
            } catch {
                try? fm.removeItem(atPath: part)      // uniquement le .part de cette exécution
                failed.append(unit.name); log += "! \(unit.zipName) : \(error.localizedDescription)\n"; continue
            }
            state[key] = fp; saveState(state)
            made += 1; log += "+ \(unit.zipName)\n"
        }
        onProgress(1)
        flush()

        if dry {
            let sum = RsyncReport.Summary(created: dryNew, updated: dryUpd, deleted: 0)
            let d = DryRunResult(taskName: task.name, summary: sum, lines: dryLines, truncated: false)
            return ExecResult(outcome: .success, detail: L.t("dry.summary", dryNew, dryUpd, 0), logFile: logName, dry: d)
        }
        pruneLogs()
        if !failed.isEmpty {
            let detail = L.t("arc.err", failed.joined(separator: ", "))
            return ExecResult(outcome: made > 0 || same > 0 ? .warnings : .failed, detail: detail, logFile: logName)
        }
        return ExecResult(outcome: warned ? .warnings : .success, detail: L.t("arc.ok", made, same), logFile: logName)
    }
}
