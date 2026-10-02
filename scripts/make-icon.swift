// Рисует иконку приложения и собирает Resources/AppIcon.icns.
// Запуск: swift scripts/make-icon.swift
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Подложка по сетке иконок macOS: 824×824 с отступом 100.
let base = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: base, xRadius: 185, yRadius: 185)

ctx.saveGState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor.black.setFill()
squircle.fill()
ctx.restoreGState()

NSGradient(colors: [
    NSColor(red: 1.00, green: 0.42, blue: 0.36, alpha: 1),
    NSColor(red: 0.86, green: 0.11, blue: 0.29, alpha: 1),
    NSColor(red: 0.55, green: 0.06, blue: 0.30, alpha: 1),
])!.draw(in: squircle, angle: -90)

// Лёгкий блик сверху.
ctx.saveGState()
squircle.addClip()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
ctx.restoreGState()

// Белая стрелка вниз с «плеем» внутри стержня и лоток под ней.
ctx.saveGState()
let glyphShadow = NSShadow()
glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
glyphShadow.shadowBlurRadius = 16
glyphShadow.shadowOffset = NSSize(width: 0, height: -6)
glyphShadow.set()
// Прозрачный слой — чтобы тень легла один раз на весь значок, а не на каждую фигуру.
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
NSColor.white.setFill()

let shaft = NSBezierPath(roundedRect: NSRect(x: 392, y: 430, width: 240, height: 360), xRadius: 48, yRadius: 48)
shaft.fill()

let head = NSBezierPath()
head.move(to: NSPoint(x: 512, y: 300))
head.line(to: NSPoint(x: 712, y: 500))
head.line(to: NSPoint(x: 312, y: 500))
head.close()
head.lineJoinStyle = .round
head.lineWidth = 40
head.fill()
NSColor.white.setStroke()
head.stroke()

let tray = NSBezierPath()
tray.move(to: NSPoint(x: 270, y: 300))
tray.line(to: NSPoint(x: 270, y: 225))
tray.line(to: NSPoint(x: 754, y: 225))
tray.line(to: NSPoint(x: 754, y: 300))
tray.lineWidth = 52
tray.lineCapStyle = .round
tray.lineJoinStyle = .round
tray.stroke()
ctx.endTransparencyLayer()
ctx.restoreGState()

// Треугольник «плей», вырезанный цветом подложки.
let play = NSBezierPath()
play.move(to: NSPoint(x: 476, y: 700))
play.line(to: NSPoint(x: 476, y: 560))
play.line(to: NSPoint(x: 580, y: 630))
play.close()
play.lineJoinStyle = .round
play.lineWidth = 18
NSColor(red: 0.90, green: 0.20, blue: 0.32, alpha: 1).set()
play.fill()
play.stroke()

image.unlockFocus()

// Сборка .iconset → .icns
let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
func write(_ px: Int, _ name: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.imageInterpolation = .high
    NSGraphicsContext.current!.cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
}
for s in [16, 32, 128, 256, 512] {
    write(s, "icon_\(s)x\(s).png")
    write(s * 2, "icon_\(s)x\(s)@2x.png")
}

try! fm.createDirectory(at: root.appendingPathComponent("Resources"), withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "Resources/AppIcon.icns готов" : "iconutil завершился с ошибкой")
