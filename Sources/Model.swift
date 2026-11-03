// mBACKUP — modèle des tâches de synchronisation (Foundation seulement, testable sans interface).
import Foundation

/// Volume à monter avant la tâche (disque externe ou partage réseau).
struct MountInfo: Codable, Hashable {
    var mountPoint: String      // ex. /Volumes/Softwares
    var smbURL: String?         // ex. smb://utilisateur@nas.local/Partage
    var volumeUUID: String?     // pour `diskutil mount`
    var autoMount: Bool
}

/// Jours de la semaine, lundi = 0 … dimanche = 6 (31 = lundi à vendredi).
struct Schedule: Codable, Hashable {
    var days: Set<Int> = [0, 1, 2, 3, 4, 5, 6]
    var hour = 3
    var minute = 0

    /// Masque binaire des jours (bit 0 = lundi).
    static func days(fromMask mask: Int) -> Set<Int> {
        Set((0..<7).filter { mask & (1 << $0) != 0 })
    }

    /// Dernière échéance ≤ `date` (jusqu'à 8 jours en arrière), nil si aucun jour n'est coché.
    func lastOccurrence(onOrBefore date: Date, calendar: Calendar = .current) -> Date? {
        guard !days.isEmpty else { return nil }
        for back in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: date),
                  let at = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  at <= date, days.contains(Self.index(of: at, calendar)) else { continue }
            return at
        }
        return nil
    }

    /// Prochaine échéance > `date`.
    func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date? {
        guard !days.isEmpty else { return nil }
        for ahead in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: ahead, to: date),
                  let at = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  at > date, days.contains(Self.index(of: at, calendar)) else { continue }
            return at
        }
        return nil
    }

    private static func index(of date: Date, _ calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7   // dimanche (1) → 6, lundi (2) → 0
    }
}

/// Seconde destination d'une même source (double sauvegarde : disque + NAS, par exemple).
struct Destination: Codable, Hashable {
    var path: String
    var mount: MountInfo?
}

enum RunOutcome: String, Codable { case success, warnings, failed, skipped }

struct RunRecord: Codable, Hashable {
    var date: Date
    var outcome: RunOutcome
    var detail: String          // message court (« 12 fichiers copiés, 3 supprimés » ou raison)
    var logFile: String?        // nom du fichier dans le dossier des journaux
    var dryRun = false
}

struct BackupTask: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var source: String
    var destination: String
    var sourceMount: MountInfo?
    var destinationMount: MountInfo?
    var secondDestination: Destination?     // facultative : la même source copiée aussi ailleurs
    var enabled = true
    var schedule = Schedule()
    var catchUp = true                  // rattrapage d'une échéance manquée (Mac éteint, disque absent)
    var useAdmin = false
    var deleteExtra = true              // miroir : supprime à l'arrivée ce qui n'existe plus à la source
    var excludeHidden = false
    var excludes: [String] = []         // motifs rsync, un par ligne
    var versioning = false
    var versionsKept = 10
    var lastAttempt: Date?              // dernière échéance traitée (réussie ou non)
    var last: RunRecord?
}

enum PathTools {
    /// Un chemin de dossier se termine par « / » pour rsync : on copie le contenu, pas le dossier lui-même.
    static func dir(_ path: String) -> String { path.hasSuffix("/") ? path : path + "/" }

    static func safeName(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\\0")
        let s = name.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "tache" : s
    }

    /// Dossier des copies versionnées : à côté de la destination, jamais dedans.
    static func versionsRoot(for task: BackupTask) -> String { versionsRoot(destination: task.destination, name: task.name) }

    static func versionsRoot(destination: String, name: String) -> String {
        let parent = (destination as NSString).deletingLastPathComponent
        return (parent as NSString).appendingPathComponent("mBACKUP versions/" + safeName(name))
    }

    /// Nom court d'une destination pour les bilans : le volume (« NAS ») ou, hors /Volumes, le dernier dossier.
    static func label(_ path: String) -> String {
        let parts = path.split(separator: "/")
        if parts.count >= 2, parts[0] == "Volumes" { return String(parts[1]) }
        return parts.last.map(String.init) ?? path
    }
}
