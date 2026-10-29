import Foundation
import Darwin
import Security
import SystemConfiguration

private var stopping: sig_atomic_t = 0
signal(SIGTERM) { _ in stopping = 1 }
signal(SIGINT) { _ in stopping = 1 }
signal(SIGPIPE, SIG_IGN)

func runDaemon() throws {
    guard geteuid() == 0 else { throw AwakeError.message("辅助服务必须由系统安装并启动。") }
    let base = "/Library/Application Support/LidAwake"
    let configPath = base + "/client.requirement"
    let configFD = open(configPath, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard configFD >= 0 else { throw AwakeError.message("缺少应用身份记录。") }
    let configFile = FileHandle(fileDescriptor: configFD, closeOnDealloc: true)
    var statInfo = stat()
    guard fstat(configFD, &statInfo) == 0, statInfo.st_uid == 0,
          statInfo.st_mode & 0o022 == 0, statInfo.st_mode & S_IFMT == S_IFREG, statInfo.st_size < 2048,
          let requirementText = String(data: try configFile.readToEnd() ?? Data(), encoding: .utf8) else {
        throw AwakeError.message("应用身份记录无效。")
    }
    var requirement: SecRequirement?
    guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
          let requirement else { throw AwakeError.message("应用身份验证规则无效。") }
    let lock = open("/var/run/local.lidawake.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard lock >= 0 else { throw AwakeError.message("无法锁定电源服务。") }
    defer { close(lock) }
    guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw AwakeError.message("旧会话仍在退出，请稍候。") }
    let engine = try AwakeServiceEngine(power: SystemPower(), journal: DiskJournal(path: base))
    func alive(_ owner: SessionOwner) -> Bool {
        guard let identity = ProcessIdentity.read(owner.pid) else { return false }
        return identity.uid == owner.uid && identity.stamp == owner.stamp
    }
    try engine.maintain { _ in false } // Recover an interrupted daemon/reboot before taking requests.
    let listener = socket(AF_UNIX, SOCK_STREAM, 0)
    guard listener >= 0 else { throw AwakeError.message("无法创建服务连接。") }
    defer { close(listener); unlink(helperSocketPath) }
    configureSocket(listener)
    unlink(helperSocketPath)
    var address = try socketAddress(helperSocketPath)
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard result == 0, chmod(helperSocketPath, 0o666) == 0, listen(listener, 8) == 0 else {
        throw AwakeError.message("无法启动服务连接。")
    }
    while stopping == 0 || engine.record != nil {
        do { try engine.maintain { owner in stopping == 0 && alive(owner) } }
        catch { NSLog("LidAwake restoration pending: %@", error.localizedDescription) }
        if stopping != 0 { if engine.record != nil { Thread.sleep(forTimeInterval: 0.25) }; continue }
        var event = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
        guard poll(&event, 1, 250) > 0, event.revents & Int16(POLLIN) != 0 else { continue }
        let fd = accept(listener, nil, nil)
        if fd < 0 { continue }
        configureSocket(fd)
        do {
            let owner = try verifiedPeer(fd, requirement: requirement)
            var consoleUID: uid_t = 0; var consoleGID: gid_t = 0
            _ = SCDynamicStoreCopyConsoleUser(nil, &consoleUID, &consoleGID)
            guard consoleUID == owner.uid else { throw AwakeError.message("请从当前登录的 Mac 账户使用本应用。") }
            let request = try receivePacket(ServiceRequest.self, from: fd)
            switch request.command {
            case "status": break
            case "enable": try engine.enable(owner: owner)
            case "disable": try engine.disable(owner: owner)
            default: throw AwakeError.message("不支持的操作。")
            }
            let state: String
            if engine.recovering { state = "recovery" }
            else if let record = engine.record { state = record.owner == owner ? "on" : "busy" }
            else { state = "off" }
            try sendPacket(ServiceReply(state), to: fd)
        } catch { try? sendPacket(ServiceReply("error", message: error.localizedDescription), to: fd) }
        close(fd)
    }
}
do { try runDaemon() }
catch { NSLog("LidAwake helper: %@", error.localizedDescription); exit(1) }
