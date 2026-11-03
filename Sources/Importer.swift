// mBACKUP — import des synchronisations planifiées de Get Backup Pro 3 (lecture seule : le fichier d'origine n'est jamais modifié).
import Foundation

struct ImportReport {
    var tasks: [BackupTask] = []
    var skipped: [String] = []       // noms des éléments non importés (type non pris en charge)
}

enum GetBackupImporter {
    static var defaultFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Get Backup 3/Syncs/Projects.plist")
    }

    static func read(from url: URL = defaultFile) throws -> ImportReport {
        let data = try Data(contentsOf: url)
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let list = root["Synchrons"] as? [[String: Any]] else { throw ImportError.format }
        return parse(list)
    }

    static func parse(_ list: [[String: Any]]) -> ImportReport {
        var report = ImportReport()
        for item in list {
            let name = item["Name"] as? String ?? "?"
            // Type 0 = miroir ; direction 0 = premier → second emplacement, 1 = sens inverse.
            guard (item["SynchronizeType"] as? Int ?? 0) == 0,
                  let first = item["FirstLocation"] as? [String: Any],
                  let second = item["SecondLocation"] as? [String: Any] else { report.skipped.append(name); continue }
            let direction = item["Direction"] as? Int ?? 0
            guard direction == 0 || direction == 1 else { report.skipped.append(name); continue }
            let (a, b) = direction == 0 ? (first, second) : (second, first)

            var task = BackupTask(name: name, source: path(a), destination: path(b))
            task.sourceMount = mount(a)
            task.destinationMount = mount(b)
            task.useAdmin = item["UseAdminPrivileges"] as? Bool ?? false
            task.excludes = (item["ExcludePathList"] as? [String]) ?? []
            if let filters = item["Filters"] as? [String: Any] {
                task.excludeHidden = filters["ExcludeInvisible"] as? Bool ?? false
            }
            if let s = item["Schedule"] as? [String: Any] {
                task.enabled = s["UseScheduled"] as? Bool ?? true
                task.schedule = Schedule(days: Schedule.days(fromMask: s["WeekDay"] as? Int ?? 127),
                                         hour: s["TimeHH"] as? Int ?? 3, minute: s["TimeMM"] as? Int ?? 0)
            }
            task.lastAttempt = item["LastDate"] as? Date
            if let date = item["LastDate"] as? Date {
                let failed = item["LastProcessFailed"] as? Bool ?? false
                task.last = RunRecord(date: date, outcome: failed ? .failed : .success, detail: "Get Backup Pro 3")
            }
            task.importedFrom = "Get Backup Pro 3"
            report.tasks.append(task)
        }
        return report
    }

    /// Point de montage + chemin relatif → chemin absolu (« - » signifie : la racine du volume).
    private static func path(_ location: [String: Any]) -> String {
        let mountPoint = location["MountPoint"] as? String ?? "/"
        var rel = location["PathFromMountPoint"] as? String ?? "-"
        if rel == "-" { rel = "" }
        guard !rel.isEmpty else { return mountPoint }
        return (mountPoint as NSString).appendingPathComponent(rel)
    }

    private static func mount(_ location: [String: Any]) -> MountInfo? {
        let mountPoint = location["MountPoint"] as? String ?? "/"
        guard mountPoint != "/" else { return nil }
        let url = location["URL"] as? String
        let uuid = location["VolumeUUID"] as? String
        return MountInfo(mountPoint: mountPoint,
                         smbURL: (url?.hasPrefix("smb://") ?? false) ? url : nil,
                         volumeUUID: (uuid == nil || uuid == "-") ? nil : uuid,
                         autoMount: location["Automount"] as? Bool ?? false)
    }

    enum ImportError: Error { case format }
}
