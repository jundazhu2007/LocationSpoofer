#!/usr/bin/env swift
// 產生 Resources/AppIcon.icns(macOS 26 風格:連續圓角、層次與玻璃高光)。
// 用法: swift scripts/make_icon.swift [輸出資料夾]   預設為 Resources
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources", isDirectory: true)
let S: CGFloat = 1024

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

/// 超橢圓(連續圓角),macOS 圖示的外形。
func squircle(_ rect: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2, cx = rect.midX, cy = rect.midY
    let steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func gradient(_ colors: [NSColor], _ locs: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors.map(\.cgColor) as CFArray, locations: locs)!
}

func render() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    ctx.setAllowsAntialiasing(true); ctx.interpolationQuality = .high

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body)

    // 1) 柔和落影(系統圖示慣例)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 26, color: rgb(0x0A1B4D, 0.30).cgColor)
    ctx.addPath(shape); ctx.setFillColor(rgb(0x1747D6).cgColor); ctx.fillPath()
    ctx.restoreGState()

    // 2) 裁切到外形,畫底色漸層(天空藍 → 深藍)
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0x55C2FF), rgb(0x1E73F0), rgb(0x1A3FC4)], [0, 0.5, 1]),
                           start: CGPoint(x: 330, y: 930), end: CGPoint(x: 700, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // 左上角柔光
    ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.38), rgb(0xFFFFFF, 0)]), startCenter: CGPoint(x: 300, y: 860), startRadius: 0,
                           endCenter: CGPoint(x: 300, y: 860), endRadius: 560, options: [])

    // 3) 地球經緯線(淡)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.14).cgColor); ctx.setLineWidth(7)
    let globe = CGRect(x: 160, y: 130, width: 704, height: 704)
    ctx.strokeEllipse(in: globe)
    for k in [0.38, 0.72] { ctx.strokeEllipse(in: globe.insetBy(dx: globe.width * (1 - k) / 2, dy: 0)) }
    for dy in [-190.0, 0.0, 190.0] {
        let w = 2 * sqrt(max(0, 352 * 352 - dy * dy))
        ctx.strokeEllipse(in: CGRect(x: 512 - w / 2, y: 482 + dy - 34, width: w, height: 68))
    }

    // 4) 航跡:大圓虛線,從左下飛向圖釘
    ctx.saveGState()
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.7).cgColor); ctx.setLineWidth(15); ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [1, 38])
    let trail = CGMutablePath()
    trail.move(to: CGPoint(x: 205, y: 250))
    trail.addCurve(to: CGPoint(x: 470, y: 470), control1: CGPoint(x: 250, y: 440), control2: CGPoint(x: 360, y: 500))
    ctx.addPath(trail); ctx.strokePath()
    ctx.restoreGState()

    // 5) 圖釘(玻璃白):水滴外形 + 內孔
    let cx: CGFloat = 560, cy: CGFloat = 520, r: CGFloat = 178
    let tipDist: CGFloat = 330
    let tangent = acos(r / tipDist)                      // 圓心看向尖端時,兩條切線的夾角
    let aRight = -CGFloat.pi / 2 + tangent, aLeft = -CGFloat.pi / 2 - tangent
    let tip = CGPoint(x: cx, y: cy - tipDist)
    let pin = CGMutablePath()
    pin.move(to: tip)
    pin.addLine(to: CGPoint(x: cx + r * cos(aRight), y: cy + r * sin(aRight)))
    pin.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: aRight, endAngle: aLeft + 2 * .pi, clockwise: false)
    pin.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 40, color: rgb(0x0A2A7A, 0.55).cgColor)
    ctx.addPath(pin); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0xFFFFFF), rgb(0xD6EBFF)]), start: CGPoint(x: cx, y: cy + r), end: CGPoint(x: cx, y: cy - tipDist), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
    // 外框高光
    ctx.addPath(pin); ctx.setStrokeColor(rgb(0xFFFFFF, 0.9).cgColor); ctx.setLineWidth(4); ctx.setLineJoin(.round); ctx.strokePath()
    // 內孔:深藍玻璃
    let hole = CGRect(x: cx - 84, y: cy - 84, width: 168, height: 168)
    ctx.saveGState()
    ctx.addEllipse(in: hole); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0x2F8CFF), rgb(0x143BB5)]), start: CGPoint(x: cx, y: hole.maxY), end: CGPoint(x: cx, y: hole.minY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.55).cgColor); ctx.setLineWidth(5); ctx.strokeEllipse(in: hole)

    // 6) 飛機(SF Symbol,白色)飛在圖釘右上方
    if let base = NSImage(systemSymbolName: "airplane", accessibilityDescription: nil),
       let sym = base.withSymbolConfiguration(.init(pointSize: 170, weight: .bold)) {
        let size = sym.size
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        sym.draw(in: NSRect(origin: .zero, size: size))
        NSColor.white.set(); NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: rgb(0x0A2A7A, 0.5).cgColor)
        ctx.translateBy(x: 742, y: 782); ctx.rotate(by: .pi * 0.17)
        tinted.draw(in: NSRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        ctx.restoreGState()
    }

    // 7) 玻璃高光:上半部由亮到透明的柔和反光(不留硬邊)
    ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.26), rgb(0xFFFFFF, 0.08), rgb(0xFFFFFF, 0.0)], [0, 0.45, 1]),
                           start: CGPoint(x: 512, y: 930), end: CGPoint(x: 512, y: 520), options: [.drawsAfterEndLocation])
    ctx.restoreGState()   // 結束外形裁切

    // 8) 邊緣:內側亮邊 + 下緣暗邊
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    ctx.addPath(shape); ctx.setStrokeColor(rgb(0xFFFFFF, 0.5).cgColor); ctx.setLineWidth(6); ctx.strokePath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(squircle(body.insetBy(dx: 3, dy: 3))); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0x000000, 0), rgb(0x0A1B66, 0.28)]), start: CGPoint(x: 512, y: 300), end: CGPoint(x: 512, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to url: URL, size: Int) {
    let img = NSImage(size: NSSize(width: S, height: S)); img.addRepresentation(rep)
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    NSGraphicsContext.current?.imageInterpolation = .high
    img.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try? out.representation(using: .png, properties: [:])?.write(to: url)
}

let master = render()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    write(master, to: iconset.appendingPathComponent("icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"), size: pt * scale)
}
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
write(master, to: outDir.appendingPathComponent("AppIcon-1024.png"), size: 1024)

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", outDir.appendingPathComponent("AppIcon.icns").path]
try p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(p.terminationStatus == 0 ? "已產生 \(outDir.path)/AppIcon.icns" : "iconutil 失敗")
