import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var view: AwakeView!
    var controller: AwakeController?
    var pendingQuit = false
    let previewPath: String?
    init(previewPath: String?) { self.previewPath = previewPath }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if previewPath == nil, let identifier = Bundle.main.bundleIdentifier,
           let other = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != getpid() }) {
            other.activate(); NSApp.terminate(nil); return
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于合盖不眠", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(withTitle: "卸载系统辅助服务…", action: #selector(uninstallService), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出并恢复原设置", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 330, height: 346),
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "合盖不眠"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.delegate = self
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.backgroundColor = NSColor(srgbRed: 0.97, green: 0.965, blue: 0.945, alpha: 1)
        view = AwakeView(frame: NSRect(x: 0, y: 0, width: 330, height: 346))
        window.contentView = view
        view.powerButton.target = self; view.powerButton.action = #selector(toggle)
        window.center()
        if let previewPath {
            if CommandLine.arguments.contains("--on") { view.update(.on) }
            window.layoutIfNeeded()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: previewPath)) }
            }
            NSApp.terminate(nil); return
        }
        controller = AwakeController()
        controller?.onChange = { [weak self] in
            guard let self, let controller = self.controller else { return }
            self.view.update(controller.state)
        }
        controller?.onError = { [weak self] message in
            guard let self else { return }
            if self.pendingQuit { self.pendingQuit = false; NSApp.reply(toApplicationShouldTerminate: false) }
            let alert = NSAlert(); alert.messageText = "合盖不眠"; alert.informativeText = message
            alert.addButton(withTitle: "知道了"); alert.beginSheetModal(for: self.window)
        }
        controller?.onStopped = { [weak self] in
            guard let self, self.pendingQuit else { return }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        if let controller { view.update(controller.state); controller.prepare() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func uninstallService() {
        guard let controller, controller.state == .off || controller.state == .needsInstall else {
            let alert = NSAlert(); alert.messageText = "请先关闭防休眠，再卸载辅助服务。"; alert.beginSheetModal(for: window); return
        }
        guard let script = Bundle.main.url(forResource: "uninstall-service", withExtension: "sh") else { return }
        let command = ["/bin/sh", script.path].map(shellQuote).joined(separator: " ")
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "on run argv\n do shell script (item 1 of argv) with administrator privileges\nend run", command]
        let pipe = Pipe(); task.standardError = pipe
        task.terminationHandler = { process in
            let message = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                if process.terminationStatus == 0 { NSApp.terminate(nil) }
                else if !message.contains("(-128)") {
                    let alert = NSAlert(); alert.messageText = "卸载未完成"; alert.informativeText = message; alert.runModal()
                }
            }
        }
        do { try task.run() } catch { NSLog("%@", error.localizedDescription) }
    }
    @objc func toggle() { controller?.toggle() }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "合盖不眠", .applicationVersion: "2.0",
            .credits: NSAttributedString(string: "一个按钮，让合盖后的任务继续运行。\n关闭开关或退出，恢复原来的休眠设置。\n合盖后内置屏幕仍会关闭。")])
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller, controller.state != .off && controller.state != .needsInstall else { return .terminateNow }
        pendingQuit = true
        DispatchQueue.main.async { controller.stop() }
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil); return true
    }
}

let args = CommandLine.arguments
let preview = args.firstIndex(of: "--render-preview").flatMap { index in index + 1 < args.count ? args[index + 1] : nil }
if let index = args.firstIndex(of: "--service-check"), index + 1 < args.count {
    do {
        let response = try ServiceClient().request(args[index + 1])
        print(String(data: try JSONEncoder().encode(response), encoding: .utf8)!)
        exit(0)
    } catch { FileHandle.standardError.write(Data(error.localizedDescription.utf8)); exit(1) }
}
let app = NSApplication.shared
app.setActivationPolicy(preview == nil ? .regular : .prohibited)
let delegate = AppDelegate(previewPath: preview)
app.delegate = delegate
app.run()
