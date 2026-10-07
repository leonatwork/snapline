// Renders Resources/AppIcon.icns: an ultrawide screen split into three zones,
// the middle one snapped in. Run: swift scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824 pt body, centered, continuous corners.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor(red: 0.16, green: 0.22, blue: 0.55, alpha: 1).setFill()
bodyPath.fill()
ctx.restoreGState()

bodyPath.addClip()
NSGradient(colors: [
    NSColor(red: 0.36, green: 0.51, blue: 1.00, alpha: 1),
    NSColor(red: 0.22, green: 0.30, blue: 0.82, alpha: 1),
    NSColor(red: 0.13, green: 0.17, blue: 0.50, alpha: 1),
])!.draw(in: body, angle: -90)

// Soft top highlight.
NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    .draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)

// Ultrawide screen.
let screen = CGRect(x: 172, y: 372, width: 680, height: 248)
let screenPath = NSBezierPath(roundedRect: screen, xRadius: 34, yRadius: 34)
NSColor.black.withAlphaComponent(0.30).setFill()
screenPath.fill()
NSColor.white.withAlphaComponent(0.35).setStroke()
screenPath.lineWidth = 6
screenPath.stroke()

// Stand.
NSColor.white.withAlphaComponent(0.35).setFill()
NSBezierPath(roundedRect: CGRect(x: 482, y: 318, width: 60, height: 54), xRadius: 6, yRadius: 6).fill()
NSBezierPath(roundedRect: CGRect(x: 402, y: 300, width: 220, height: 22), xRadius: 11, yRadius: 11).fill()

// Three zones; the middle one is the snapped window.
let inner = screen.insetBy(dx: 22, dy: 22)
let gap: CGFloat = 16
let w = (inner.width - 2 * gap) / 3
for i in 0..<3 {
    let r = CGRect(x: inner.minX + CGFloat(i) * (w + gap), y: inner.minY, width: w, height: inner.height)
    let p = NSBezierPath(roundedRect: r, xRadius: 16, yRadius: 16)
    if i == 1 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        NSColor.white.setFill()
        p.fill()
        ctx.restoreGState()
        // Title bar dots.
        for (j, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: CGRect(x: r.minX + 18 + CGFloat(j) * 22, y: r.maxY - 32, width: 14, height: 14)).fill()
        }
    } else {
        NSColor.white.withAlphaComponent(0.28).setFill()
        p.fill()
        NSColor.white.withAlphaComponent(0.55).setStroke()
        p.setLineDash([14, 10], count: 2, phase: 0)
        p.lineWidth = 4
        p.stroke()
    }
}
image.unlockFocus()

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png")
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
