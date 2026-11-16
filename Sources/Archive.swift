// mBACKUP — mode « archives » : un zip épuré par dossier (logique pure, testable sans interface).
import Foundation

/// Réglages d'une tâche de type archives (nil = copie miroir).
struct ArchiveOptions: Codable, Hashable {
    var perSubfolder = true         // un zip par sous-dossier de la source ; sinon un seul zip de la source elle-même
    var only: [String]?             // si renseigné (et un zip par sous-dossier) : seuls ces sous-dossiers sont archivés
}

/// Un dossier à archiver : `name` est son nom, `parent` le dossier qui le contient (le zip est lancé depuis `parent`).
struct ArchiveUnit: Hashable {
    var name: String
    var parent: String
    var path: String { (parent as NSString).appendingPathComponent(name) }
    var zipName: String { name + ".zip" }
}

enum ArchiveTool {
    /// Filtres proposés d'office pour les dossiers de développement (régénérables).
    static let devFilters = [".build", "node_modules", "dist", "build", "__pycache__"]

    /// Motifs d'exclusion nettoyés : sans lignes vides ni « / » final.
    static func patterns(_ excludes: [String]) -> [String] {
        excludes.map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
            .filter { !$0.isEmpty }
    }

    /// Un nom de fichier ou de dossier correspond-il à un motif (jokers * et ? permis) ?
    static func isExcluded(_ name: String, _ patterns: [String]) -> Bool {
        patterns.contains { fnmatch($0, name, 0) == 0 }
    }

    /// Arguments `-x` de zip : chaque motif exclut le nom où qu'il soit dans l'arborescence.
    static func zipExcludeArgs(_ patterns: [String]) -> [String] {
        guard !patterns.isEmpty else { return [] }
        return ["-x"] + patterns.flatMap { ["*/\($0)/*", "*/\($0)"] }
    }

    /// Dossiers à archiver : chaque sous-dossier visible (hors exclusions), ou la source elle-même.
    static func units(source: String, perSubfolder: Bool, patterns: [String], only: [String] = []) -> [ArchiveUnit] {
        let src = source.hasSuffix("/") && source.count > 1 ? String(source.dropLast()) : source
        guard perSubfolder else {
            return [ArchiveUnit(name: (src as NSString).lastPathComponent, parent: (src as NSString).deletingLastPathComponent)]
        }
        let fm = FileManager.default
        let names = ((try? fm.contentsOfDirectory(atPath: src)) ?? []).sorted()
        return names.compactMap { n in
            var isDir: ObjCBool = false
            guard !n.hasPrefix("."), !isExcluded(n, patterns), only.isEmpty || only.contains(n),
                  fm.fileExists(atPath: (src as NSString).appendingPathComponent(n), isDirectory: &isDir), isDir.boolValue else { return nil }
            return ArchiveUnit(name: n, parent: src)
        }
    }

    /// Empreinte du contenu archivé (nombre d'éléments + date de modification la plus récente + exclusions) :
    /// si elle n'a pas changé depuis la dernière archive, on ne refait pas le zip.
    static func fingerprint(of dir: String, patterns: [String]) -> String {
        let fm = FileManager.default
        var count = 0
        var newest: TimeInterval = 0
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        if let e = fm.enumerator(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: keys, options: []) {
            for case let url as URL in e {
                if isExcluded(url.lastPathComponent, patterns) { e.skipDescendants(); continue }
                count += 1
                if let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                    newest = max(newest, d.timeIntervalSince1970)
                }
            }
        }
        return "\(count):\(Int(newest)):" + patterns.joined(separator: "|")
    }
}
