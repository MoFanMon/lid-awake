import Foundation

struct SessionRecord: Codable, Equatable {
    let original: Bool
    let owner: SessionOwner
}
protocol SessionJournal: AnyObject {
    func load() throws -> SessionRecord?
    func save(_ record: SessionRecord) throws
    func clear() throws
}

/// One durable lease shared across launches; mutations are serialized by the daemon.
final class AwakeServiceEngine {
    private let power: PowerBackend
    private let journal: SessionJournal
    private(set) var record: SessionRecord?
    private(set) var recovering = false
    init(power: PowerBackend, journal: SessionJournal) throws {
        self.power = power; self.journal = journal
        record = try journal.load()
        recovering = record != nil
    }
    func enable(owner: SessionOwner) throws {
        if let record {
            guard record.owner == owner && !recovering else { throw AwakeError.message("另一会话正在运行或恢复。") }
            return
        }
        let saved = try power.read()
        let next = SessionRecord(original: saved, owner: owner)
        try journal.save(next) // Must reach disk before changing a persistent system setting.
        record = next
        do {
            try power.write(true)
            guard try power.read() else { throw AwakeError.message("系统未接受防休眠设置。") }
        } catch {
            recovering = true
            try? restore()
            throw error
        }
    }
    func disable(owner: SessionOwner) throws {
        guard let record else { return }
        guard record.owner == owner else { throw AwakeError.message("不能关闭其他进程的会话。") }
        recovering = true
        try restore()
    }
    func maintain(isAlive: (SessionOwner) -> Bool) throws {
        guard let record else { return }
        if recovering || !isAlive(record.owner) { recovering = true; try restore() }
    }
    private func restore() throws {
        guard let saved = record?.original else { return }
        try power.write(saved)
        guard try power.read() == saved else { throw AwakeError.message("原设置尚未恢复，辅助服务会继续重试。") }
        try journal.clear()
        record = nil; recovering = false
    }
}
