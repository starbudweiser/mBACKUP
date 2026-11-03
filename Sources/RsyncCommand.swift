// mBACKUP — construction de la ligne de commande rsync (options d'un miroir).
import Foundation

struct RsyncCommand {
    var executable: String
    var arguments: [String]
    var excludeFileContent: String?     // à écrire dans un fichier temporaire, référencé par --exclude-from

    /// - Parameters:
    ///   - rsync: chemin de rsync ; `modern` indique un rsync 3.x (attributs étendus, iconv, progression globale).
    ///   - stamp: horodatage du dossier de versions (yyyy-MM-dd_HH-mm-ss).
    static func make(for task: BackupTask, rsync: String, modern: Bool, dryRun: Bool, stamp: String,
                     excludeFile: String) -> RsyncCommand {
        var args = ["-t", "-l", "-H", "-x", "-S", "-v", "-pgo", "-r", "--ignore-errors", "-u", "--stats"]
        if modern { args += ["-X", "--no-inc-recursive", "--iconv=UTF-8", "--info=progress2"] }
        if task.deleteExtra { args += ["--delete-before", "--delete-excluded"] }
        if task.versioning {
            args += ["--backup", "--backup-dir=" + (PathTools.versionsRoot(for: task) as NSString).appendingPathComponent(stamp)]
        }
        if dryRun { args += ["-n", "--itemize-changes"] }

        var patterns = task.excludes.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if task.excludeHidden { patterns.append(".*") }
        if !patterns.isEmpty { args.append("--exclude-from=" + excludeFile) }

        args += [PathTools.dir(task.source), PathTools.dir(task.destination)]
        return RsyncCommand(executable: rsync, arguments: args,
                            excludeFileContent: patterns.isEmpty ? nil : patterns.joined(separator: "\n") + "\n")
    }
}

/// Lecture du bilan rsync (--stats) et de la sortie d'une simulation.
enum RsyncReport {
    struct Summary: Equatable {
        var created = 0, updated = 0, deleted = 0
        var transferred = 0
        var totalBytes: Int64 = 0
    }

    static func summary(from output: String) -> Summary {
        var s = Summary()
        for line in output.split(whereSeparator: \.isNewline) {
            let l = String(line)
            if l.hasPrefix("Number of regular files transferred:") { s.transferred = number(l) }
            else if l.hasPrefix("Number of created files:") { s.created = number(l) }
            else if l.hasPrefix("Number of deleted files:") { s.deleted = number(l) }
            else if l.hasPrefix("Total file size:") { s.totalBytes = Int64(number(l)) }
        }
        return s
    }

    /// Simulation (`-n --itemize-changes`) : compte les créations, mises à jour et suppressions annoncées.
    static func dryRunSummary(from output: String) -> Summary {
        var s = Summary()
        for line in output.split(whereSeparator: \.isNewline) {
            let l = String(line)
            if l.hasPrefix("*deleting") { s.deleted += 1 }
            else if l.hasPrefix(">f+++++++++") || l.hasPrefix("cd+++++++++") { s.created += 1 }
            else if l.hasPrefix(">f") { s.updated += 1 }
        }
        return s
    }

    /// 0 = succès ; 23, 24 = transfert partiel ou fichiers disparus (avertissements) ; le reste = échec.
    static func outcome(forExitCode code: Int32) -> RunOutcome {
        switch code {
        case 0: return .success
        case 23, 24: return .warnings
        default: return .failed
        }
    }

    private static func number(_ line: String) -> Int {
        guard let colon = line.firstIndex(of: ":") else { return 0 }
        let digits = line[line.index(after: colon)...].prefix { $0 != "(" }.filter(\.isNumber)
        return Int(digits) ?? 0
    }
}
