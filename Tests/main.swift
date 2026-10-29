import Foundation
import Darwin
import Security

// These cases catch lost snapshots, false success, and skipped rollback.
final class FilePower: PowerBackend {
    let url: URL
    var rejectNextWrite = false
    var ignoreNextWrite = false
    init(_ original: Bool) throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data((original ? "1" : "0").utf8).write(to: url)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
    func read() throws -> Bool {
        let value = try String(contentsOf: url, encoding: .utf8)
        guard value == "0" || value == "1" else { throw TestError.expected }
        return value == "1"
    }
    func write(_ disabled: Bool) throws {
        if rejectNextWrite { rejectNextWrite = false; throw TestError.expected }
        if ignoreNextWrite { ignoreNextWrite = false; return }
        try Data((disabled ? "1" : "0").utf8).write(to: url)
    }
}
enum TestError: Error { case expected }
var failures = 0
func check(_ condition: @autoclosure () throws -> Bool, _ name: String) {
    do {
        if try condition() { print("PASS \(name)") }
        else { failures += 1; print("FAIL \(name)") }
    } catch { failures += 1; print("FAIL \(name): \(error)") }
}
func run(_ name: String, _ body: () throws -> Void) {
    do { try body() } catch { failures += 1; print("FAIL \(name): \(error)") }
}
run("enable and restore") {
    let power = try FilePower(false)
    let lease = SleepLease(power: power)
    try lease.start()
    try lease.start()
    check(try power.read(), "enabling prevents system sleep")
    check(lease.isActive, "reports active only after enable")
    try lease.stop()
    check(try !power.read(), "stopping restores previous sleep state")
    check(!lease.isActive, "successful restoration releases ownership")
}
run("preserve previous state") {
    let power = try FilePower(true)
    let lease = SleepLease(power: power)
    try lease.start()
    try lease.start() // Starting twice must never overwrite the saved original.
    try lease.stop()
    check(try power.read(), "pre-existing disabled sleep remains unchanged")
}
run("failed enable") {
    let power = try FilePower(false)
    let lease = SleepLease(power: power)
    power.ignoreNextWrite = true
    var failed = false
    do { try lease.start() } catch { failed = true }
    check(failed, "failed verification is reported")
    check(try !power.read(), "failed enable rolls back to original")
    check(!lease.isActive, "rolled-back enable releases ownership")
}
run("retry restoration") {
    let power = try FilePower(false)
    let lease = SleepLease(power: power)
    try lease.start()
    power.rejectNextWrite = true
    var failed = false
    do { try lease.stop() } catch { failed = true }
    check(failed && lease.isActive, "restore failure retains ownership for retry")
    try lease.stop()
    check(try !power.read(), "restore can succeed on retry")
}
run("malformed power state") {
    let power = try FilePower(false)
    try Data("unknown".utf8).write(to: power.url)
    let lease = SleepLease(power: power)
    var failed = false
    do { try lease.start() } catch { failed = true }
    check(failed && !lease.isActive, "unreadable original never activates")
    check(try String(contentsOf: power.url, encoding: .utf8) == "unknown", "unreadable original is not overwritten")
}
run("shell escaping") {
    // The command must preserve literal quotes, spaces, dollar signs and backticks.
    let input = "a'b $(touch /tmp/never-created) `echo no` 中文"
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = ["-c", "printf %s " + shellQuote(input)]
    let pipe = Pipe(); task.standardOutput = pipe
    try task.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    check(String(data: output, encoding: .utf8) == input, "shell arguments remain literal")
}
run("secure session files") {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("target")
    try Data("preserved".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("status"), withDestinationURL: target)
    let folder = try SessionFolder(path: root.path, owner: getuid())
    try folder.create("status", text: "active", replace: true)
    check(try String(contentsOf: target, encoding: .utf8) == "preserved", "status updates never follow a symlink")
    check(try String(contentsOf: root.appendingPathComponent("status"), encoding: .utf8) == "active", "status is written in the validated directory")
    let link = root.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
    var rejected = false
    do { _ = try SessionFolder(path: link.path, owner: getuid()) } catch { rejected = true }
    check(rejected, "symlinked session directories are rejected")
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
    rejected = false
    do { _ = try SessionFolder(path: root.path, owner: getuid()) } catch { rejected = true }
    check(rejected, "shared session directories are rejected")
}
if ProcessInfo.processInfo.environment["LIDAWAKE_SKIP_SYSTEM_POWER_TEST"] == "1" {
    print("SKIP host power preferences comparison (CI)")
} else {
run("read actual power setting") {
    // Read-only integration with this machine; never changes its power settings.
    let value = try SystemPower().read()
    let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); task.arguments = ["-g"]
    let pipe = Pipe(); task.standardOutput = pipe
    try task.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
    let text = String(data: data, encoding: .utf8) ?? ""
    let expression = try NSRegularExpression(pattern: "SleepDisabled\\s+([01])")
    let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    if let match, let range = Range(match.range(at: 1), in: text) {
        check(value == (text[range] == "1"), "IOKit state agrees with pmset")
    } else { failures += 1; print("FAIL pmset did not report SleepDisabled") }
}
}
final class TestJournal: SessionJournal {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    deinit { try? FileManager.default.removeItem(at: url) }
    func load() throws -> SessionRecord? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(SessionRecord.self, from: Data(contentsOf: url))
    }
    func save(_ record: SessionRecord) throws { try JSONEncoder().encode(record).write(to: url, options: .atomic) }
    func clear() throws { try FileManager.default.removeItem(at: url) }
}
let owner = SessionOwner(uid: 501, pid: 111, stamp: "100.1")
let otherOwner = SessionOwner(uid: 501, pid: 222, stamp: "100.2")
run("persistent service sessions") {
    let power = try FilePower(false); let journal = TestJournal()
    let service = try AwakeServiceEngine(power: power, journal: journal)
    try service.enable(owner: owner)
    check(try power.read(), "service enables sleep prevention")
    check(try journal.load()?.original == false, "service saves original state before changing power")
    try service.enable(owner: owner)
    try service.disable(owner: owner)
    check(try !power.read(), "repeated service enable preserves the original state")
    check(try journal.load() == nil, "successful service stop clears recovery journal")
    // A second launch uses the same installed service, with a new process identity.
    try service.enable(owner: otherOwner)
    check(try power.read(), "a new app process reuses the service")
    try service.disable(owner: otherOwner)
    check(try !power.read(), "second launch also restores correctly")
}
run("session ownership") {
    let power = try FilePower(false); let journal = TestJournal()
    let service = try AwakeServiceEngine(power: power, journal: journal)
    try service.enable(owner: owner)
    var rejected = false
    do { try service.disable(owner: otherOwner) } catch { rejected = true }
    check(try rejected && power.read(), "another process cannot stop the active session")
    rejected = false
    do { try service.enable(owner: otherOwner) } catch { rejected = true }
    check(rejected, "another process cannot replace the saved session")
    try service.disable(owner: owner)
}
run("app crash recovery") {
    let power = try FilePower(false); let journal = TestJournal()
    let service = try AwakeServiceEngine(power: power, journal: journal)
    try service.enable(owner: owner)
    try service.maintain { _ in false }
    check(try !power.read(), "app process death restores sleep")
    check(service.record == nil, "app process death releases the session")
}
run("daemon restart recovery") {
    let power = try FilePower(true); let journal = TestJournal()
    try journal.save(SessionRecord(original: false, owner: owner))
    let restarted = try AwakeServiceEngine(power: power, journal: journal)
    try restarted.maintain { _ in true }
    check(try !power.read(), "restarted service restores the interrupted original state")
    check(try journal.load() == nil, "restart recovery removes the stale journal")
}
run("service restore retries") {
    let power = try FilePower(false); let journal = TestJournal()
    let service = try AwakeServiceEngine(power: power, journal: journal)
    try service.enable(owner: owner)
    power.rejectNextWrite = true
    do { try service.disable(owner: owner) } catch {}
    check(service.recovering && service.record != nil, "failed service restore retains ownership")
    check(try journal.load() != nil, "failed service restore retains durable recovery")
    try service.maintain { _ in true }
    check(try !power.read(), "service retries restoration without another authorization")
}
run("service rollback") {
    let power = try FilePower(false); let journal = TestJournal()
    let service = try AwakeServiceEngine(power: power, journal: journal)
    power.ignoreNextWrite = true
    var rejected = false
    do { try service.enable(owner: owner) } catch { rejected = true }
    check(rejected && !service.recovering, "service does not report a rejected enable as active")
    check(try !power.read(), "rejected service enable rolls back")
}
run("durable journal") {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    let record = SessionRecord(original: false, owner: owner)
    let journal = try DiskJournal(path: root.path)
    try journal.save(record)
    let reopened = try DiskJournal(path: root.path)
    check(try reopened.load() == record, "recovery journal survives reopening")
    try reopened.clear()
    check(try journal.load() == nil, "clearing journal persists")
}
run("local IPC") {
    var sockets = [Int32](repeating: 0, count: 2)
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else { throw TestError.expected }
    defer { close(sockets[0]); close(sockets[1]) }
    configureSocket(sockets[0]); configureSocket(sockets[1])
    try sendPacket(ServiceRequest(command: "enable"), to: sockets[0])
    let decoded = try receivePacket(ServiceRequest.self, from: sockets[1])
    check(decoded.command == "enable", "IPC transfers command without shell execution")
    try sendPacket(ServiceReply("on"), to: sockets[1])
    check(try receivePacket(ServiceReply.self, from: sockets[0]).state == "on", "IPC transfers verified state response")
    var requirement: SecRequirement?
    _ = SecRequirementCreateWithString("identifier \"never.authorized\"" as CFString, [], &requirement)
    var rejected = false
    do { _ = try verifiedPeer(sockets[1], requirement: requirement!) } catch { rejected = true }
    check(rejected, "unrecognized client signature is rejected")
}
run("recognized peer identity") {
    let path = "/tmp/lidawake-test-" + UUID().uuidString + ".sock"
    let server = socket(AF_UNIX, SOCK_STREAM, 0); let client = socket(AF_UNIX, SOCK_STREAM, 0)
    defer { close(server); close(client); unlink(path) }
    var address = try socketAddress(path)
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let bound = withUnsafePointer(to: &address) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(server, $0, size) } }
    guard bound == 0, listen(server, 1) == 0 else { throw TestError.expected }
    let connected = withUnsafePointer(to: &address) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(client, $0, size) } }
    guard connected == 0 else { throw TestError.expected }
    let accepted = accept(server, nil, nil); defer { close(accepted) }
    var code: SecCode?; var staticCode: SecStaticCode?; var information: CFDictionary?
    guard SecCodeCopySelf([], &code) == errSecSuccess,
          SecCodeCopyStaticCode(code!, [], &staticCode) == errSecSuccess,
          SecCodeCopySigningInformation(staticCode!, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
          let hash = (information! as NSDictionary)[kSecCodeInfoUnique] as? Data else { throw TestError.expected }
    let hex = hash.map { String(format: "%02x", $0) }.joined()
    var ownRequirement: SecRequirement?
    guard SecRequirementCreateWithString(("cdhash H\"" + hex + "\"") as CFString, [], &ownRequirement) == errSecSuccess else { throw TestError.expected }
    let peer = try verifiedPeer(accepted, requirement: ownRequirement!)
    check(peer.pid == getpid() && peer.uid == getuid(), "signed client is authenticated from the socket audit token")
}
exit(failures == 0 ? 0 : 1)
