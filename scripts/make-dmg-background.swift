import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-dmg-background.swift <output.png>\n".utf8))
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 760, height: 420)
let image = NSImage(size: size)

image.lockFocus()

NSColor(calibratedRed: 0.965, green: 0.972, blue: 0.984, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.12, alpha: 1)
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 16, weight: .medium),
    .foregroundColor: NSColor(calibratedRed: 0.40, green: 0.43, blue: 0.50, alpha: 1)
]
let hintAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
    .foregroundColor: NSColor(calibratedRed: 0.48, green: 0.51, blue: 0.58, alpha: 1)
]

func drawCentered(_ text: String, y: CGFloat, attributes: [NSAttributedString.Key: Any]) {
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let textSize = attributed.size()
    attributed.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: y))
}

drawCentered("拖到 Applications 安装", y: 340, attributes: titleAttributes)
drawCentered("Drag Codex Synced to Applications", y: 313, attributes: subtitleAttributes)
drawCentered("修复或恢复前请先退出 Codex", y: 56, attributes: hintAttributes)
drawCentered("Quit Codex before repairing or restoring history", y: 35, attributes: hintAttributes)

let arrowColor = NSColor(calibratedRed: 0.02, green: 0.37, blue: 0.92, alpha: 1)
arrowColor.setStroke()
arrowColor.setFill()

let arrow = NSBezierPath()
arrow.lineWidth = 7
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 305, y: 205))
arrow.line(to: NSPoint(x: 455, y: 205))
arrow.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 455, y: 205))
head.line(to: NSPoint(x: 430, y: 228))
head.line(to: NSPoint(x: 430, y: 182))
head.close()
head.fill()

let dotColor = NSColor(calibratedWhite: 1, alpha: 0.75)
dotColor.setFill()
for x in stride(from: CGFloat(90), through: CGFloat(670), by: 24) {
    for y in stride(from: CGFloat(96), through: CGFloat(284), by: 24) {
        let rect = NSRect(x: x, y: y, width: 3, height: 3)
        NSBezierPath(ovalIn: rect).fill()
    }
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to render background\n".utf8))
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL)
