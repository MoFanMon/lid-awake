import AppKit
import Foundation
let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(srgbRed: 0.965, green: 0.96, blue: 0.94, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 205, yRadius: 205).fill()
NSColor(srgbRed: 0.80, green: 0.92, blue: 0.59, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 202, y: 202, width: 620, height: 620)).fill()
let path = NSBezierPath(); path.lineWidth = 27; path.lineCapStyle = .round
path.appendArc(withCenter: NSPoint(x: 512, y: 499), radius: 158, startAngle: 135, endAngle: 405)
path.move(to: NSPoint(x: 512, y: 711)); path.line(to: NSPoint(x: 512, y: 554))
NSColor(srgbRed: 0.22, green: 0.27, blue: 0.18, alpha: 1).setStroke(); path.stroke()
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
