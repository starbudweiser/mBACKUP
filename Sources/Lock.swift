// mBACKUP — verrous exclusifs : une seule exécution à la fois par destination, une seule instance de l'appli.
import Foundation
import CryptoKit

/// Verrou exclusif `flock` : tenu tant que l'objet vit, libéré par le système si le processus meurt
/// (arrêt brutal, pkill). Il vaut entre processus : deux instances de l'appli ne peuvent pas le tenir ensemble.
final class FileLock {
    private let fd: Int32
    private init(fd: Int32) { self.fd = fd }

    /// Prend le verrou sans attendre ; nil s'il est déjà tenu (par ce processus ou un autre).
    static func tryAcquire(_ url: URL) -> FileLock? {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return nil }
        return FileLock(fd: fd)
    }

    deinit { flock(fd, LOCK_UN); close(fd) }
}

enum Locks {
    /// Dossier commun à toutes les éditions de l'appli (installée et développement) : elles se voient mutuellement.
    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/mBACKUP/Locks")
    }

    /// Clé d'une destination : chemin normalisé (sans « / » final), haché pour faire un nom de fichier sûr.
    static func key(_ destination: String) -> String {
        var p = (destination as NSString).standardizingPath
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return SHA256.hash(data: Data(p.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Verrou d'une destination : deux tâches (ou deux exécutions de la même) n'écrivent jamais en même temps au même endroit.
    static func destination(_ destination: String, in dir: URL = Locks.dir) -> FileLock? {
        FileLock.tryAcquire(dir.appendingPathComponent("dest-" + key(destination) + ".lock"))
    }
}
