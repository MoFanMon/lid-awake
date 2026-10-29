import Foundation
import Darwin
import IOKit

final class SystemPower: PowerBackend {
    func read() throws -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { throw AwakeError.message("无法读取这台 Mac 的电源状态。") }
        defer { IOObjectRelease(root) }
        guard let value = IORegistryEntryCreateCFProperty(root, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber else {
            throw AwakeError.message("此 macOS 版本未提供所需的电源状态。")
        }
        return value.boolValue
    }
    func write(_ disabled: Bool) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe
        try task.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw AwakeError.message("无法修改电源设置。\n" + (String(data: output, encoding: .utf8) ?? ""))
        }
        // pmset can return before powerd has applied the persisted preference.
        for _ in 0..<40 {
            if try read() == disabled { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw AwakeError.message("系统未应用电源设置，请重试。")
    }
}

struct ProcessIdentity: Equatable {
    let uid: uid_t
    let seconds: UInt64
    let microseconds: UInt64
    var stamp: String { "\(seconds).\(microseconds)" }
    static func read(_ pid: pid_t) -> ProcessIdentity? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_status != UInt32(SZOMB) else { return nil }
        return ProcessIdentity(uid: info.pbi_uid, seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec)
    }
}

/// Root uses an already-open directory, never follows user-controlled symlinks.
final class SessionFolder {
    let descriptor: Int32
    init(path: String, owner: uid_t) throws {
        descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw AwakeError.message("无法打开本次会话。") }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == owner,
              info.st_mode & 0o777 == 0o700 else {
            close(descriptor)
            throw AwakeError.message("本次会话目录权限不正确。")
        }
    }
    deinit { close(descriptor) }
    func create(_ name: String, text: String, replace: Bool = false) throws {
        if replace { _ = unlinkat(descriptor, name, 0) }
        let fd = openat(descriptor, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw AwakeError.message("无法记录会话状态。") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try file.write(contentsOf: Data(text.utf8))
        try file.synchronize()
    }
    func exists(_ name: String) -> Bool {
        var info = stat()
        return fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0
    }
    func readRootSnapshot() throws -> Bool {
        let fd = openat(descriptor, "original", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw AwakeError.message("找不到原来的休眠设置。") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size == 1, info.st_nlink == 1 else { throw AwakeError.message("原设置记录无效。") }
        let data = try file.readToEnd() ?? Data()
        guard data == Data("0".utf8) || data == Data("1".utf8) else { throw AwakeError.message("原设置记录无效。") }
        return data == Data("1".utf8)
    }
}
