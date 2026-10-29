import AppKit

final class PowerButton: NSButton {
    var active = false { didSet { needsDisplay = true } }
    var busy = false { didSet { isEnabled = !busy; needsDisplay = true } }
    private var hovering = false
    override var acceptsFirstResponder: Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 10, dy: 10)
        let fill = active ? NSColor(srgbRed: 0.80, green: 0.92, blue: 0.59, alpha: 1)
                          : NSColor(srgbRed: 0.90, green: 0.90, blue: 0.87, alpha: 1)
        NSGraphicsContext.saveGraphicsState()
        if !isHighlighted {
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(hovering ? 0.10 : 0.04)
            shadow.shadowBlurRadius = hovering ? 12 : 7; shadow.shadowOffset = NSSize(width: 0, height: -3); shadow.set()
        }
        (isHighlighted ? fill.blended(withFraction: 0.08, of: .black)! : fill).setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSGraphicsContext.restoreGraphicsState()
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let glyph = NSBezierPath()
        glyph.lineWidth = 3.0; glyph.lineCapStyle = .round
        glyph.appendArc(withCenter: center, radius: 20, startAngle: 135, endAngle: 405)
        glyph.move(to: NSPoint(x: center.x, y: center.y + 27))
        glyph.line(to: NSPoint(x: center.x, y: center.y + 7))
        NSColor(srgbRed: 0.22, green: 0.27, blue: 0.18, alpha: busy ? 0.35 : 0.88).setStroke()
        if isFlipped {
            glyph.transform(using: AffineTransform(m11: 1, m12: 0, m21: 0, m22: -1, tX: 0, tY: bounds.midY * 2))
        }
        glyph.stroke()
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.7).setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 5, dy: 5)); ring.lineWidth = 2; ring.stroke()
        }
    }
}

final class AwakeView: NSView {
    let powerButton = PowerButton(frame: NSRect(x: 96, y: 112, width: 138, height: 138))
    private let status = NSTextField(labelWithString: "")
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let footer = NSTextField(labelWithString: "关闭按钮或窗口，恢复原设置")
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 0.97, green: 0.965, blue: 0.945, alpha: 1).cgColor
        let title = NSTextField(labelWithString: "合盖不眠")
        title.font = .systemFont(ofSize: 23, weight: .medium)
        title.textColor = NSColor(srgbRed: 0.20, green: 0.23, blue: 0.18, alpha: 1)
        title.alignment = .center; title.frame = NSRect(x: 20, y: 282, width: 290, height: 32)
        addSubview(title)
        let subtitle = NSTextField(labelWithString: "合上屏幕，也继续工作")
        subtitle.font = .systemFont(ofSize: 12); subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center; subtitle.frame = NSRect(x: 20, y: 257, width: 290, height: 20)
        addSubview(subtitle)
        powerButton.isBordered = false; powerButton.title = ""; powerButton.keyEquivalent = " "
        powerButton.setAccessibilityIdentifier("awake-toggle")
        addSubview(powerButton)
        status.alignment = .center; status.font = .systemFont(ofSize: 14, weight: .medium)
        status.frame = NSRect(x: 20, y: 84, width: 290, height: 23); addSubview(status)
        hint.alignment = .center; hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 28, y: 44, width: 274, height: 34); addSubview(hint)
        footer.alignment = .center; footer.font = .systemFont(ofSize: 10); footer.textColor = .tertiaryLabelColor
        footer.frame = NSRect(x: 15, y: 16, width: 300, height: 17); addSubview(footer)
        update(.off)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(_ state: AwakeController.State) {
        powerButton.active = state == .on || state == .recovery
        powerButton.busy = state == .starting || state == .stopping || state == .installing || state == .waitingService
        switch state {
        case .needsInstall:
            status.stringValue = "点击完成首次安装"
            hint.stringValue = "只需一次管理员授权，之后直接使用"
            powerButton.setAccessibilityLabel("安装辅助服务")
        case .installing:
            status.stringValue = "正在完成首次安装…"
            hint.stringValue = "请在系统窗口中授权，之后无需重复授权"
        case .waitingService:
            status.stringValue = "等待辅助服务…"
            hint.stringValue = "无需重新授权，服务恢复后自动连接"
        case .off:
            status.stringValue = "点击开启"
            hint.stringValue = "已准备就绪，无需重复授权"
            powerButton.setAccessibilityLabel("开启合盖不眠")
        case .starting:
            status.stringValue = "正在开启…"
            hint.stringValue = "由已安装的辅助服务处理"
        case .on:
            status.stringValue = "已开启 · 点击关闭"
            hint.stringValue = "合盖后任务继续运行\n请保持通风，留意电量"
            powerButton.setAccessibilityLabel("关闭并恢复原设置")
        case .stopping:
            status.stringValue = "正在恢复原设置…"
            hint.stringValue = "恢复完成后即可正常休眠"
        case .recovery:
            status.stringValue = "点击恢复原设置"
            hint.stringValue = "辅助服务会重试恢复，也可点击重试"
            powerButton.setAccessibilityLabel("恢复原设置")
        }
        powerButton.setAccessibilityValue(state == .on ? "已开启" : status.stringValue)
        status.setAccessibilityIdentifier("awake-state")
        NSAccessibility.post(element: status, notification: .valueChanged)
    }
}
