import Foundation
import Darwin

final class DiskJournal: SessionJournal {
    private let directory: Int32
    init(path: String) throws {
        directory = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw AwakeError.message("无法打开恢复记录目录。") }
        var info = stat()
        guard fstat(directory, &info) == 0, info.st_uid == geteuid(), info.st_mode & 0o777 == 0o700 else {
            close(directory); throw AwakeError.message("恢复记录目录权限不正确。")
        }
    }
    deinit { close(directory) }
    func load() throws -> SessionRecord? {
        let fd = openat(directory, "session.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 && errno == ENOENT { return nil }
        guard fd >= 0 else { throw AwakeError.message("无法读取恢复记录。") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_size < 4096, info.st_nlink == 1 else { throw AwakeError.message("恢复记录无效。") }
        return try JSONDecoder().decode(SessionRecord.self, from: file.readToEnd() ?? Data())
    }
    func save(_ record: SessionRecord) throws {
        let temporary = UUID().uuidString
        let fd = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw AwakeError.message("无法保存恢复记录。") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { _ = unlinkat(directory, temporary, 0) }
        try file.write(contentsOf: JSONEncoder().encode(record))
        guard fsync(fd) == 0, renameat(directory, temporary, directory, "session.json") == 0,
              fsync(directory) == 0 else { throw AwakeError.message("恢复记录未能写入磁盘。") }
    }
    func clear() throws {
        guard unlinkat(directory, "session.json", 0) == 0 || errno == ENOENT else { throw AwakeError.message("无法清理恢复记录。") }
        guard fsync(directory) == 0 else { throw AwakeError.message("无法确认恢复记录已清理。") }
    }
}
