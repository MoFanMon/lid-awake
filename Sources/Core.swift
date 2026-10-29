import Foundation

protocol PowerBackend: AnyObject {
    func read() throws -> Bool
    func write(_ disabled: Bool) throws
}

enum AwakeError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

/// Owns exactly one setting, preserving its original value until verified restoration.
final class SleepLease {
    private let power: PowerBackend
    private(set) var original: Bool?
    var isActive: Bool { original != nil }
    init(power: PowerBackend) { self.power = power }

    func start(beforeChange: (Bool) throws -> Void = { _ in }) throws {
        guard original == nil else { return }
        let saved = try power.read()
        try beforeChange(saved)
        original = saved
        do {
            try power.write(true)
            guard try power.read() else { throw AwakeError.message("系统没有接受防休眠设置。") }
        } catch {
            let activationError = error
            do { try stop() } catch {
                throw AwakeError.message("开启失败，恢复设置也未成功。请再次点击恢复。\n\(error.localizedDescription)")
            }
            throw activationError
        }
    }

    func stop() throws {
        guard let saved = original else { return }
        try power.write(saved)
        guard try power.read() == saved else { throw AwakeError.message("休眠设置尚未恢复，请重试。") }
        original = nil
    }
}

func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

struct SessionOwner: Codable, Equatable {
    let uid: UInt32
    let pid: Int32
    let stamp: String
}
