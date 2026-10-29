import AppKit

final class AwakeController {
    enum State { case needsInstall, installing, waitingService, off, starting, on, stopping, recovery }
    private(set) var state: State = .starting { didSet { onChange?() } }
    var onChange: (() -> Void)?
    var onError: ((String) -> Void)?
    var onStopped: (() -> Void)?
    private let client = ServiceClient()
    private let queue = DispatchQueue(label: "local.lidawake.client")
    private var timer: Timer?
    private var installer: Process?
    private var pending = false
    private var stopRequested = false
    private var ownsSession = false

    func prepare() {
        pending = true
        queue.async { [weak self] in
            guard let self else { return }
            let reply = try? self.client.request("status")
            DispatchQueue.main.async {
                self.pending = false
                if let reply { self.apply(reply); if self.stopRequested && self.state == .on { self.send("disable") } }
                else if self.stopRequested { self.state = .needsInstall; self.onStopped?() }
                else if FileManager.default.fileExists(atPath: "/Library/PrivilegedHelperTools/local.lidawake.helper") {
                    self.state = .waitingService
                } else { self.state = .needsInstall; self.installOnce() }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.pending, self.state == .on || self.state == .recovery || self.state == .waitingService else { return }
            self.send("status", polling: true)
        }
    }
    deinit { timer?.invalidate() }
    func toggle() {
        switch state {
        case .needsInstall: installOnce()
        case .off: stopRequested = false; send("enable")
        case .on, .recovery: stop()
        case .installing, .waitingService, .starting, .stopping: break
        }
    }
    func stop() {
        stopRequested = true
        if state == .off || state == .needsInstall { onStopped?(); return }
        if installer != nil || pending { return }
        if !ownsSession { state = .off; onStopped?(); return }
        send("disable")
    }
    private func send(_ command: String, polling: Bool = false) {
        guard !pending else { return }
        pending = true
        if command == "enable" { ownsSession = true }
        if !polling { state = command == "enable" ? .starting : .stopping }
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.client.request(command) }
            DispatchQueue.main.async {
                self.pending = false
                switch result {
                case .success(let reply):
                    self.apply(reply)
                    if self.stopRequested && self.state == .on { self.send("disable") }
                case .failure(let error):
                    if self.stopRequested && !self.ownsSession {
                        self.state = .off; self.onStopped?(); return
                    }
                    self.state = self.ownsSession ? .recovery : .waitingService
                    if !polling { self.onError?(error.localizedDescription) }
                }
            }
        }
    }
    private func apply(_ reply: ServiceReply) {
        switch reply.state {
        case "off": ownsSession = false; state = .off; if stopRequested { onStopped?() }
        case "on": ownsSession = true; state = .on
        case "recovery": state = .recovery
        case "busy": state = .off; onError?("另一份合盖不眠正在运行，请使用原来的窗口。")
        default: state = .needsInstall
        }
    }
    private func installOnce() {
        guard installer == nil, !stopRequested,
              let script = Bundle.main.url(forResource: "install-service", withExtension: "sh") else { return }
        state = .installing
        let command = ["/bin/sh", script.path, Bundle.main.bundleURL.path].map(shellQuote).joined(separator: " ")
        let source = """
        on run argv
            with timeout of 600 seconds
                do shell script (item 1 of argv) with administrator privileges with prompt "首次安装合盖不眠的系统辅助服务。只需授权一次，之后打开和切换均无需重复授权。"
            end timeout
        end run
        """
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source, command]
        let errors = Pipe(); task.standardError = errors; task.standardOutput = FileHandle.nullDevice
        task.terminationHandler = { [weak self] process in
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }
                self.installer = nil
                if process.terminationStatus == 0 {
                    self.state = .off
                    if self.stopRequested { self.onStopped?() } else { self.send("status", polling: true) }
                } else {
                    self.state = .needsInstall
                    if self.stopRequested { self.onStopped?() }
                    else if !message.contains("(-128)") { self.onError?(message.isEmpty ? "安装未完成，请重试或使用安装包。" : message) }
                }
            }
        }
        installer = task
        do { try task.run() }
        catch { installer = nil; state = .needsInstall; onError?(error.localizedDescription) }
    }
}
