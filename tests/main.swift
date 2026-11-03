// Tests de logique : planification, ligne rsync, bilans, traductions.
import Foundation

var failures = 0
func check(_ ok: Bool, _ msg: String, line: Int = #line) { if !ok { failures += 1; print("ÉCHEC (l.\(line)) : \(msg)") } }

// --- Planification (calendrier fixe pour un test déterministe)
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!
func date(_ s: String) -> Date { let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd HH:mm"; return f.date(from: s)! }
let weekdays = Schedule(days: [0, 1, 2, 3, 4], hour: 4, minute: 0)      // lun-ven 04:00
// 2026-11-03 est un mardi
check(weekdays.lastOccurrence(onOrBefore: date("2026-11-03 09:00"), calendar: cal) == date("2026-11-03 04:00"), "dernière échéance du jour")
check(weekdays.lastOccurrence(onOrBefore: date("2026-11-03 03:00"), calendar: cal) == date("2026-11-02 04:00"), "avant l'heure : la veille")
check(weekdays.lastOccurrence(onOrBefore: date("2026-11-08 12:00"), calendar: cal) == date("2026-11-06 04:00"), "dimanche : retour au vendredi")
check(weekdays.nextOccurrence(after: date("2026-11-06 05:00"), calendar: cal) == date("2026-11-09 04:00"), "après vendredi : lundi")
check(Schedule(days: [], hour: 1, minute: 0).nextOccurrence(after: Date()) == nil, "aucun jour : pas d'échéance")

// --- Ligne rsync
var t = BackupTask(name: "DEV SKYRIM", source: "/Volumes/SKYRIM/TOOLS/MAC", destination: "/Volumes/Softwares/_DEV/SKYRIM TOOLS")
t.excludes = [".DS_Store", " ", "node_modules/"]; t.excludeHidden = true
let cmd = RsyncCommand.make(for: t, rsync: "/x/rsync", modern: true, dryRun: false, stamp: "S", excludeFile: "/tmp/ex")
check(cmd.arguments.suffix(2) == ["/Volumes/SKYRIM/TOOLS/MAC/", "/Volumes/Softwares/_DEV/SKYRIM TOOLS/"], "barres finales")
check(cmd.arguments.contains("--delete-before") && cmd.arguments.contains("--delete-excluded"), "miroir")
check(cmd.arguments.contains("--exclude-from=/tmp/ex"), "fichier d'exclusions")
check(cmd.excludeFileContent == ".DS_Store\nnode_modules/\n.*\n", "contenu des exclusions : \(cmd.excludeFileContent ?? "nil")")
check(!cmd.arguments.contains("-n"), "pas de simulation")
t.deleteExtra = false; t.versioning = true
let cmd2 = RsyncCommand.make(for: t, rsync: "/x/rsync", modern: false, dryRun: true, stamp: "2026-11-03_04-00-00", excludeFile: "/tmp/ex")
check(!cmd2.arguments.contains("--delete-before"), "sans miroir : pas de suppression")
check(cmd2.arguments.contains("-n") && cmd2.arguments.contains("--itemize-changes"), "simulation")
check(cmd2.arguments.contains("--backup-dir=/Volumes/Softwares/_DEV/mBACKUP versions/DEV SKYRIM/2026-11-03_04-00-00"), "dossier de versions : \(cmd2.arguments)")
check(!cmd2.arguments.contains("-X") && !cmd2.arguments.contains("--iconv=UTF-8"), "rsync ancien : sans options 3.x")

// --- Double destination
check(PathTools.label("/Volumes/NAS/Photos/2026") == "NAS" && PathTools.label("/Users/x/Backups") == "Backups", "nom court de destination")
check(PathTools.versionsRoot(destination: "/Volumes/NAS/Photos", name: "PHOTOS") == "/Volumes/NAS/mBACKUP versions/PHOTOS", "versions par destination")
// Un tasks.json écrit avant la seconde destination doit toujours se lire
let old = #"[{"id":"11111111-1111-1111-1111-111111111111","name":"A","source":"/a","destination":"/b","enabled":true,"catchUp":true,"useAdmin":false,"deleteExtra":true,"excludeHidden":false,"excludes":[],"versioning":false,"versionsKept":10,"schedule":{"days":[0],"hour":1,"minute":0}}]"#
let decoded = try? JSONDecoder().decode([BackupTask].self, from: Data(old.utf8))
check(decoded?.first?.secondDestination == nil && decoded?.first?.name == "A", "ancien tasks.json lisible")
var two = BackupTask(name: "PHOTOS", source: "/s", destination: "/d1"); two.secondDestination = Destination(path: "/Volumes/NAS/p", mount: nil)
let back = try? JSONDecoder().decode(BackupTask.self, from: JSONEncoder().encode(two))
check(back?.secondDestination?.path == "/Volumes/NAS/p", "seconde destination conservée")

// --- Bilans
let stats = "Number of files: 79,338 (reg: 54,710, dir: 24,628)\nNumber of created files: 12 (reg: 10)\nNumber of deleted files: 3 (reg: 3)\nNumber of regular files transferred: 47,265\nTotal file size: 21,692,070,308 bytes"
let s = RsyncReport.summary(from: stats)
check(s.transferred == 47265 && s.created == 12 && s.deleted == 3 && s.totalBytes == 21_692_070_308, "bilan : \(s)")
let dry = RsyncReport.dryRunSummary(from: "*deleting   old.txt\n>f+++++++++ new.txt\n>f.st...... changed.txt\ncd+++++++++ dir/\n.d..t...... ./")
check(dry.created == 2 && dry.updated == 1 && dry.deleted == 1, "simulation : \(dry)")
check(RsyncReport.outcome(forExitCode: 0) == .success && RsyncReport.outcome(forExitCode: 24) == .warnings && RsyncReport.outcome(forExitCode: 12) == .failed, "codes de sortie")

// --- Traductions : mêmes clés dans les quatre langues, mêmes formats
let fr = L.tables["fr"]!
for lang in ["en", "es", "it"] {
    let tab = L.tables[lang]!
    check(Set(tab.keys) == Set(fr.keys), "clés \(lang) : manquantes \(Set(fr.keys).subtracting(tab.keys)), en trop \(Set(tab.keys).subtracting(fr.keys))")
    for (k, v) in fr {
        let count = { (x: String) in x.components(separatedBy: "%").count - 1 }
        if let o = tab[k], count(o) != count(v) { check(false, "\(lang).\(k) : nombre de « % » différent") }
    }
}
check(fr.keys.contains { $0.hasPrefix("about.") }, "clés about.*")

check(VersionCompare.isNewer("v1.0.1", than: "1.0.0") && VersionCompare.isNewer("1.10.0", than: "1.9.9") && !VersionCompare.isNewer("1.0.0", than: "1.0") && !VersionCompare.isNewer("1.0.0", than: "v1.0.0") && VersionCompare.isNewer("2", than: "1.9.9"), "comparaison de versions")

print(failures == 0 ? "Tous les tests passent." : "\(failures) échec(s).")
exit(failures == 0 ? 0 : 1)
