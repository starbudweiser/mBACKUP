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

// --- Archives zip
let pats = ArchiveTool.patterns([".build", " ", "node_modules/", "*.tmp"])
check(pats == [".build", "node_modules", "*.tmp"], "motifs nettoyés : \(pats)")
check(ArchiveTool.isExcluded(".build", pats) && ArchiveTool.isExcluded("a.tmp", pats) && !ArchiveTool.isExcluded("Sources", pats), "correspondance des noms")
check(ArchiveTool.zipExcludeArgs(["dist"]) == ["-x", "*/dist/*", "*/dist"] && ArchiveTool.zipExcludeArgs([]).isEmpty, "arguments -x de zip")
let arcRoot = NSTemporaryDirectory() + "mbackup-test-" + UUID().uuidString
let fm = FileManager.default
for d in ["AppA/Sources", "AppA/.build/x", "AppB/node_modules/y", ".caché", "AppC"] { try? fm.createDirectory(atPath: arcRoot + "/" + d, withIntermediateDirectories: true) }
fm.createFile(atPath: arcRoot + "/AppA/Sources/a.swift", contents: Data("a".utf8))
fm.createFile(atPath: arcRoot + "/AppA/.build/x/junk", contents: Data("j".utf8))
fm.createFile(atPath: arcRoot + "/loose.txt", contents: Data("l".utf8))
let us = ArchiveTool.units(source: arcRoot + "/", perSubfolder: true, patterns: ["AppC"])
check(ArchiveTool.units(source: arcRoot, perSubfolder: true, patterns: [], only: ["AppB", "AppC"]).map(\.name) == ["AppB", "AppC"], "limité à une liste de sous-dossiers")
check(us.map(\.name) == ["AppA", "AppB"], "un zip par sous-dossier visible, hors exclusions : \(us.map(\.name))")
check(us[0].zipName == "AppA.zip" && us[0].parent == arcRoot, "nom du zip et dossier parent")
let one = ArchiveTool.units(source: arcRoot, perSubfolder: false, patterns: [])
check(one.count == 1 && one[0].parent == (arcRoot as NSString).deletingLastPathComponent, "zip unique de la source")
let fp1 = ArchiveTool.fingerprint(of: arcRoot + "/AppA", patterns: ArchiveTool.devFilters)
fm.createFile(atPath: arcRoot + "/AppA/.build/x/more", contents: Data("m".utf8))
check(ArchiveTool.fingerprint(of: arcRoot + "/AppA", patterns: ArchiveTool.devFilters) == fp1, "un fichier exclu ne change pas l'empreinte")
fm.createFile(atPath: arcRoot + "/AppA/Sources/b.swift", contents: Data("b".utf8))
check(ArchiveTool.fingerprint(of: arcRoot + "/AppA", patterns: ArchiveTool.devFilters) != fp1, "un fichier ajouté change l'empreinte")
// zip réel : les dossiers exclus n'y sont pas
let zp = arcRoot + "/AppA.zip"
let zproc = Process(); zproc.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); zproc.currentDirectoryURL = URL(fileURLWithPath: arcRoot)
zproc.arguments = ["-r", "-X", "-y", "-q", zp, "AppA"] + ArchiveTool.zipExcludeArgs(ArchiveTool.devFilters)
try? zproc.run(); zproc.waitUntilExit()
let lister = Process(); lister.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo"); lister.arguments = ["-1", zp]
let lp = Pipe(); lister.standardOutput = lp; try? lister.run(); lister.waitUntilExit()
let zl = String(decoding: lp.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
check(zl.contains("AppA/Sources/a.swift") && !zl.contains(".build"), "le zip contient les sources sans .build : \(zl)")
try? fm.removeItem(atPath: arcRoot)
var arcTask = BackupTask(name: "t", source: "/a", destination: "/b")
check(arcTask.archive == nil, "par défaut : miroir")
arcTask.archive = ArchiveOptions()
let roundTrip = try? JSONDecoder().decode(BackupTask.self, from: JSONEncoder().encode(arcTask))
check(roundTrip?.archive?.perSubfolder == true, "tâche archive : encodage")
let oldJSON = try? JSONEncoder().encode(BackupTask(name: "t", source: "/a", destination: "/b"))
check((try? JSONDecoder().decode(BackupTask.self, from: oldJSON ?? Data()))?.archive == nil, "ancien fichier sans type : miroir")

// --- Verrous et remplacement sûr d'une archive
let lockDir = URL(fileURLWithPath: NSTemporaryDirectory() + "mbackup-test-locks-" + UUID().uuidString)
check(Locks.key("/Volumes/X/dest/") == Locks.key("/Volumes/X/dest"), "clé de verrou : « / » final ignoré")
check(Locks.key("/Volumes/X/a") != Locks.key("/Volumes/X/b"), "clé de verrou : destinations distinctes")
var l1 = Locks.destination("/Volumes/X/dest", in: lockDir)
check(l1 != nil, "premier verrou pris")
check(Locks.destination("/Volumes/X/dest/", in: lockDir) == nil, "même destination : second verrou refusé")
check(Locks.destination("/Volumes/X/autre", in: lockDir) != nil, "autre destination : verrou libre")
l1 = nil
check(Locks.destination("/Volumes/X/dest", in: lockDir) != nil, "verrou libéré puis repris")
// Verrou tenu par un autre processus : refusé ici aussi.
let holder = Process(); holder.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
let lockFile = lockDir.appendingPathComponent("dest-" + Locks.key("/Volumes/X/proc") + ".lock").path
holder.arguments = ["-c", "import fcntl,sys,time;f=open(sys.argv[1],'w');fcntl.flock(f,fcntl.LOCK_EX);print('ok',flush=True);time.sleep(30)", lockFile]
let hp = Pipe(); holder.standardOutput = hp; try? holder.run()
_ = hp.fileHandleForReading.availableData            // attend « ok » : le verrou est tenu
check(Locks.destination("/Volumes/X/proc", in: lockDir) == nil, "verrou tenu par un autre processus : refusé")
holder.terminate(); holder.waitUntilExit()
check(Locks.destination("/Volumes/X/proc", in: lockDir) != nil, "processus arrêté : verrou libéré")
try? fm.removeItem(at: lockDir)

let repDir = NSTemporaryDirectory() + "mbackup-test-rep-" + UUID().uuidString
try? fm.createDirectory(atPath: repDir, withIntermediateDirectories: true)
let fin = repDir + "/A.zip", prt = repDir + "/A.zip.1234.part"
try? "ancien".write(toFile: fin, atomically: true, encoding: .utf8)
try? "nouveau".write(toFile: prt, atomically: true, encoding: .utf8)
check((try? ArchiveTool.replace(part: prt, final: fin, expectedSize: 7)) != nil, "remplacement réussi")
check((try? String(contentsOfFile: fin, encoding: .utf8)) == "nouveau" && !fm.fileExists(atPath: prt), "nouveau zip en place, .part disparu")
try? "court".write(toFile: prt, atomically: true, encoding: .utf8)
check((try? ArchiveTool.replace(part: prt, final: fin, expectedSize: 999)) == nil, "copie incomplète : refusée")
check((try? String(contentsOfFile: fin, encoding: .utf8)) == "nouveau", "copie incomplète : l'ancien zip reste")
check((try? ArchiveTool.replace(part: repDir + "/absent.part", final: fin)) == nil, ".part disparu : erreur")
check((try? String(contentsOfFile: fin, encoding: .utf8)) == "nouveau", ".part disparu : l'ancien zip reste")
check(((try? fm.contentsOfDirectory(atPath: repDir)) ?? []).filter { $0.hasSuffix(".old") }.isEmpty, "aucun .old laissé")
try? fm.removeItem(atPath: repDir)

// --- Attente de fin de processus (y compris un processus déjà terminé avant l'attente)
for _ in 0..<200 {
    let q = Process(); q.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    let ex = ProcessExit(q); try? q.run()
    usleep(UInt32.random(in: 0...3000)); ex.waitSync(); ex.waitSync()
    if q.isRunning { check(false, "processus encore en cours après l'attente"); break }
}

print(failures == 0 ? "Tous les tests passent." : "\(failures) échec(s).")
exit(failures == 0 ? 0 : 1)
