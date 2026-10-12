import AppKit
import CoreImage

// Invented demo content for the README screenshots: wallpaper, menu bar and
// windows are drawn here from scratch. Nothing is read from the real screen.

/// Pixel density of every rendered image.
let renderScale: CGFloat = 2

// MARK: - Rendering

/// Renders `body` into a top-left-origin context of `size` points at `renderScale`.
@MainActor
func render(_ size: CGSize, _ body: (CGContext) -> Void) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let cg = CGContext(data: nil, width: Int(size.width * renderScale), height: Int(size.height * renderScale),
                       bitsPerComponent: 8, bytesPerRow: 0, space: space,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    cg.interpolationQuality = .high
    cg.scaleBy(x: renderScale, y: renderScale)
    cg.translateBy(x: 0, y: size.height)
    cg.scaleBy(x: 1, y: -1)
    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { body(cg) }
    NSGraphicsContext.current = previous
    return cg.makeImage()!
}

/// Draws a CGImage into `rect` of the current (flipped) context.
func draw(_ image: CGImage, in rect: CGRect, _ cg: CGContext) {
    cg.saveGState()
    cg.translateBy(x: rect.minX, y: rect.maxY)
    cg.scaleBy(x: 1, y: -1)
    cg.draw(image, in: CGRect(origin: .zero, size: rect.size))
    cg.restoreGState()
}

/// Snapshot of one of Snapline's views (light appearance, `renderScale`).
@MainActor
func snapshot(_ view: NSView) -> CGImage {
    view.appearance = NSAppearance(named: .aqua)
    view.layoutSubtreeIfNeeded()
    let size = view.bounds.size
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * renderScale),
                               pixelsHigh: Int(size.height * renderScale), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep.cgImage!
}

/// Gaussian blur of the part of `image` under `rect` (points) – stands in for the
/// behind-window blur of NSVisualEffectView, which needs a real window server.
func blurredCrop(_ image: CGImage, _ rect: CGRect, radius: CGFloat = 24) -> CGImage {
    let px = CGRect(x: rect.minX * renderScale, y: rect.minY * renderScale,
                    width: rect.width * renderScale, height: rect.height * renderScale)
    let input = CIImage(cgImage: image)
    // CIImage has a bottom-left origin.
    let ciRect = CGRect(x: px.minX, y: CGFloat(image.height) - px.maxY, width: px.width, height: px.height)
    let blurred = input.clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius * renderScale])
        .cropped(to: ciRect)
    return CIContext().createCGImage(blurred, from: ciRect)!
}

func withShadow(_ cg: CGContext, blur: CGFloat, y: CGFloat, alpha: CGFloat, _ body: () -> Void) {
    cg.saveGState()
    // Shadow offsets live in device space (y up, pixels).
    cg.setShadow(offset: CGSize(width: 0, height: -y * renderScale), blur: blur * renderScale,
                 color: NSColor.black.withAlphaComponent(alpha).cgColor)
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    body()
    cg.endTransparencyLayer()
    cg.restoreGState()
}

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fill(_ cg: CGContext, _ rect: CGRect, _ color: NSColor, radius: CGFloat = 0) {
    cg.setFillColor(color.cgColor)
    cg.addPath(roundedPath(rect, min(radius, rect.width / 2, rect.height / 2)))
    cg.fillPath()
}

func text(_ string: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor = .labelColor, mono: Bool = false, maxWidth: CGFloat? = nil, centered: Bool = false) {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    let s = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    let width = min(s.size().width, maxWidth ?? .greatestFiniteMagnitude)
    let x = centered ? point.x - width / 2 : point.x
    s.draw(with: CGRect(x: x, y: point.y, width: width + 1, height: s.size().height),
           options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
}

func symbol(_ name: String, in rect: CGRect, color: NSColor, weight: NSFont.Weight = .regular) {
    let config = NSImage.SymbolConfiguration(pointSize: rect.height, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    else { return }
    let s = image.size
    let scale = min(rect.width / s.width, rect.height / s.height)
    let fitted = CGRect(x: rect.midX - s.width * scale / 2, y: rect.midY - s.height * scale / 2,
                        width: s.width * scale, height: s.height * scale)
    image.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

/// The system arrow cursor with its hotspot at `point`.
@MainActor
func drawCursor(at point: CGPoint, _ cg: CGContext) {
    let cursor = NSCursor.arrow
    let size = cursor.image.size
    cursor.image.draw(in: CGRect(x: point.x - cursor.hotSpot.x, y: point.y - cursor.hotSpot.y,
                                 width: size.width, height: size.height),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

// MARK: - Localized demo strings

/// The harness's own demo texts. They are not part of the app's Localizable.strings.
enum Demo {
    static let german = (Locale.preferredLanguages.first ?? "en").hasPrefix("de")
    static func t(_ en: String, _ de: String) -> String { german ? de : en }
}

// MARK: - Desktop

func drawWallpaper(_ cg: CGContext, _ rect: CGRect) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let colors = [NSColor(srgbRed: 0.55, green: 0.66, blue: 0.86, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.72, green: 0.70, blue: 0.90, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.95, green: 0.78, blue: 0.80, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.55, 1])!
    cg.saveGState()
    cg.clip(to: rect)
    cg.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY),
                          end: CGPoint(x: rect.maxX, y: rect.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // A few soft hills for depth.
    for (i, alpha) in [0.18, 0.14, 0.10].enumerated() {
        let path = CGMutablePath()
        let base = rect.maxY - rect.height * (0.18 + 0.12 * CGFloat(i))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: base))
        let steps = 6
        for s in 1...steps {
            let x = rect.minX + rect.width * CGFloat(s) / CGFloat(steps)
            let cx = x - rect.width / CGFloat(steps * 2)
            let wobble = (s + i) % 2 == 0 ? -0.08 : 0.06
            path.addQuadCurve(to: CGPoint(x: x, y: base + rect.height * CGFloat(wobble) * 0.5),
                              control: CGPoint(x: cx, y: base + rect.height * CGFloat(wobble)))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        cg.addPath(path)
        cg.setFillColor(NSColor(srgbRed: 0.30, green: 0.32, blue: 0.55, alpha: alpha).cgColor)
        cg.fillPath()
    }
    cg.restoreGState()
}

let menuBarHeight: CGFloat = 24

func drawMenuBar(_ cg: CGContext, width: CGFloat, app: String) {
    fill(cg, CGRect(x: 0, y: 0, width: width, height: menuBarHeight), NSColor.white.withAlphaComponent(0.55))
    let ink = NSColor.black.withAlphaComponent(0.85)
    symbol("apple.logo", in: CGRect(x: 14, y: 5, width: 14, height: 14), color: ink)
    var x: CGFloat = 44
    let menus = Demo.german
        ? ["Ablage", "Bearbeiten", "Format", "Darstellung", "Fenster", "Hilfe"]
        : ["File", "Edit", "Format", "View", "Window", "Help"]
    for (i, item) in ([app] + menus).enumerated() {
        let weight: NSFont.Weight = i == 0 ? .bold : .regular
        text(item, at: CGPoint(x: x, y: 4), size: 13, weight: weight, color: ink)
        x += NSAttributedString(string: item, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: weight)]).size().width + 20
    }
    let clock = Demo.t("Mon 12 Oct  9:41", "Mo. 12. Okt.  9:41")
    let clockWidth = NSAttributedString(string: clock, attributes: [.font: NSFont.systemFont(ofSize: 13)]).size().width
    text(clock, at: CGPoint(x: width - 16 - clockWidth, y: 4), size: 13, color: ink)
    var sx = width - 16 - clockWidth - 30
    for name in ["switch.2", "wifi", "battery.75percent", "rectangle.split.3x1"] {
        symbol(name, in: CGRect(x: sx, y: 5, width: 18, height: 14), color: ink)
        sx -= 32
    }
}

// MARK: - Demo windows

enum WindowKind {
    case notes, report, code, calendar, browser, maps
}

struct DemoWindow {
    let kind: WindowKind
    let title: String
    let appName: String
    let appPath: String

    var icon: NSImage { NSWorkspace.shared.icon(forFile: appPath) }

    static let notes = DemoWindow(kind: .notes, title: Demo.t("Trip to Lisbon – Notes", "Reise nach Lissabon – Notizen"),
                                  appName: Demo.t("Notes", "Notizen"), appPath: "/System/Applications/Notes.app")
    static let report = DemoWindow(kind: .report, title: Demo.t("Quarterly Report.pdf", "Quartalsbericht.pdf"),
                                   appName: Demo.t("Preview", "Vorschau"), appPath: "/System/Applications/Preview.app")
    static let code = DemoWindow(kind: .code, title: "main.swift — Snapline",
                                 appName: "Terminal", appPath: "/System/Applications/Utilities/Terminal.app")
    static let calendar = DemoWindow(kind: .calendar, title: Demo.t("Calendar – Week 42", "Kalender – KW 42"),
                                     appName: Demo.t("Calendar", "Kalender"), appPath: "/System/Applications/Calendar.app")
    static let browser = DemoWindow(kind: .browser, title: Demo.t("Three Days in Lisbon", "Drei Tage in Lissabon"),
                                    appName: "Safari", appPath: "/Applications/Safari.app")
    static let maps = DemoWindow(kind: .maps, title: Demo.t("Lisbon", "Lissabon"),
                                 appName: Demo.t("Maps", "Karten"), appPath: "/System/Applications/Maps.app")
}

let titleBarHeight: CGFloat = 30

/// Frame of the green (zoom) button of a window drawn at `rect`.
func zoomButtonRect(of rect: CGRect) -> CGRect {
    CGRect(x: rect.minX + 48, y: rect.minY + 9, width: 12, height: 12)
}

func drawWindow(_ w: DemoWindow, in rect: CGRect, active: Bool = false, shadow: Bool = true, _ cg: CGContext) {
    let radius: CGFloat = 10
    if shadow {
        withShadow(cg, blur: active ? 26 : 14, y: active ? 12 : 5, alpha: active ? 0.38 : 0.22) {
            fill(cg, rect, .white, radius: radius)
        }
    }
    cg.saveGState()
    cg.addPath(roundedPath(rect, radius))
    cg.clip()
    fill(cg, rect, .white)

    let bar = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: titleBarHeight)
    fill(cg, bar, NSColor(white: active ? 0.955 : 0.97, alpha: 1))
    fill(cg, CGRect(x: rect.minX, y: bar.maxY - 0.5, width: rect.width, height: 0.5), NSColor(white: 0.82, alpha: 1))
    let lights: [NSColor] = active
        ? [NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1), NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
           NSColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1)]
        : Array(repeating: NSColor(white: 0.84, alpha: 1), count: 3)
    for (i, color) in lights.enumerated() {
        let r = CGRect(x: rect.minX + 12 + CGFloat(i) * 18, y: rect.minY + 9, width: 12, height: 12)
        cg.setFillColor(color.cgColor)
        cg.fillEllipse(in: r)
    }
    text(w.title, at: CGPoint(x: rect.midX, y: rect.minY + 7), size: 13, weight: .semibold,
         color: NSColor.black.withAlphaComponent(active ? 0.85 : 0.45), maxWidth: rect.width - 160, centered: true)

    let content = CGRect(x: rect.minX, y: bar.maxY, width: rect.width, height: rect.height - titleBarHeight)
    cg.saveGState()
    cg.clip(to: content)
    switch w.kind {
    case .notes: drawNotes(content, cg)
    case .report: drawReport(content, cg)
    case .code: drawCode(content, cg)
    case .calendar: drawCalendar(content, cg)
    case .browser: drawBrowser(content, cg)
    case .maps: drawMaps(content, cg)
    }
    cg.restoreGState()
    cg.restoreGState()

    cg.addPath(roundedPath(rect.insetBy(dx: 0.25, dy: 0.25), radius))
    cg.setStrokeColor(NSColor.black.withAlphaComponent(0.2).cgColor)
    cg.setLineWidth(0.5)
    cg.strokePath()
}

/// A miniature of a demo window, used as Snap Assist "live preview".
@MainActor
func thumbnail(_ w: DemoWindow, logicalSize: CGSize = CGSize(width: 900, height: 560)) -> NSImage {
    let size = CGSize(width: 320, height: 200)
    let image = render(size) { cg in
        let scale = min(size.width / logicalSize.width, size.height / logicalSize.height)
        let drawn = CGSize(width: logicalSize.width * scale, height: logicalSize.height * scale)
        cg.translateBy(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2)
        cg.scaleBy(x: scale, y: scale)
        drawWindow(w, in: CGRect(origin: .zero, size: logicalSize), shadow: false, cg)
    }
    return NSImage(cgImage: image, size: size)
}

private let gray = NSColor(white: 0.55, alpha: 1)

/// Grey placeholder lines standing in for body text.
private func lines(_ cg: CGContext, x: CGFloat, y: CGFloat, width: CGFloat, count: Int, spacing: CGFloat = 14,
                   color: NSColor = NSColor(white: 0.86, alpha: 1)) {
    for i in 0..<count {
        let w = width * [1, 0.92, 0.97, 0.7, 0.88, 0.95, 0.6][i % 7]
        fill(cg, CGRect(x: x, y: y + CGFloat(i) * spacing, width: w, height: 6), color, radius: 3)
    }
}

private func drawNotes(_ r: CGRect, _ cg: CGContext) {
    let sidebarWidth = min(max(r.width * 0.32, 130), 220)
    let sidebar = CGRect(x: r.minX, y: r.minY, width: sidebarWidth, height: r.height)
    fill(cg, sidebar, NSColor(white: 0.965, alpha: 1))
    fill(cg, CGRect(x: sidebar.maxX - 0.5, y: r.minY, width: 0.5, height: r.height), NSColor(white: 0.85, alpha: 1))
    let notes = Demo.german
        ? [("Reise nach Lissabon", "Gestern"), ("Einkaufsliste", "Montag"), ("Bücher für den Herbst", "Sonntag"),
           ("Ideen fürs Wochenende", "Samstag"), ("Rezept: Pastel de Nata", "Freitag")]
        : [("Trip to Lisbon", "Yesterday"), ("Groceries", "Monday"), ("Books for autumn", "Sunday"),
           ("Weekend ideas", "Saturday"), ("Recipe: Pastel de Nata", "Friday")]
    for (i, note) in notes.enumerated() {
        let row = CGRect(x: sidebar.minX + 8, y: r.minY + 10 + CGFloat(i) * 50, width: sidebarWidth - 16, height: 44)
        if i == 0 { fill(cg, row, NSColor(srgbRed: 0.99, green: 0.86, blue: 0.45, alpha: 1), radius: 6) }
        text(note.0, at: CGPoint(x: row.minX + 10, y: row.minY + 6), size: 12, weight: .semibold,
             color: .black.withAlphaComponent(0.85), maxWidth: row.width - 20)
        text(note.1, at: CGPoint(x: row.minX + 10, y: row.minY + 23), size: 11, color: gray)
    }
    let x = sidebar.maxX + 24
    text(notes[0].0, at: CGPoint(x: x, y: r.minY + 18), size: 20, weight: .bold, color: .black.withAlphaComponent(0.88))
    let bullets = Demo.german
        ? ["Tram 28 früh am Morgen nehmen", "Pastéis de Belém probieren", "Sonnenuntergang am Miradouro",
           "Sonntags zur LX Factory", "Ausflug nach Sintra", "Fado-Abend in der Alfama"]
        : ["Take tram 28 early in the morning", "Try the pastéis de Belém", "Sunset at the Miradouro",
           "LX Factory on Sunday", "Day trip to Sintra", "Fado evening in Alfama"]
    for (i, b) in bullets.enumerated() {
        let y = r.minY + 58 + CGFloat(i) * 24
        cg.setFillColor(NSColor(white: 0.35, alpha: 1).cgColor)
        cg.fillEllipse(in: CGRect(x: x + 2, y: y + 6, width: 5, height: 5))
        text(b, at: CGPoint(x: x + 16, y: y), size: 13, color: .black.withAlphaComponent(0.8), maxWidth: r.maxX - x - 30)
    }
    lines(cg, x: x, y: r.minY + 58 + CGFloat(bullets.count) * 24 + 16, width: max(r.maxX - x - 40, 40), count: 8)
}

private func drawReport(_ r: CGRect, _ cg: CGContext) {
    fill(cg, r, NSColor(white: 0.86, alpha: 1))
    let pageWidth = min(r.width - 40, (r.height - 30) * 0.78)
    let page = CGRect(x: r.midX - pageWidth / 2, y: r.minY + 16, width: pageWidth, height: pageWidth / 0.72)
    withShadow(cg, blur: 6, y: 2, alpha: 0.2) { fill(cg, page, .white) }
    let p = page.insetBy(dx: pageWidth * 0.08, dy: pageWidth * 0.08)
    text(Demo.t("Quarterly Report", "Quartalsbericht"), at: CGPoint(x: p.minX, y: p.minY), size: max(11, pageWidth * 0.05),
         weight: .bold, color: .black.withAlphaComponent(0.85))
    text("Q3 2026", at: CGPoint(x: p.minX, y: p.minY + pageWidth * 0.075), size: max(9, pageWidth * 0.03), color: gray)
    let chart = CGRect(x: p.minX, y: p.minY + pageWidth * 0.16, width: p.width, height: p.width * 0.48)
    fill(cg, CGRect(x: chart.minX, y: chart.maxY, width: chart.width, height: 1), NSColor(white: 0.8, alpha: 1))
    let values: [CGFloat] = [0.42, 0.55, 0.48, 0.66, 0.74, 0.69, 0.86, 0.95]
    let barWidth = chart.width / CGFloat(values.count) * 0.62
    for (i, v) in values.enumerated() {
        let x = chart.minX + chart.width / CGFloat(values.count) * (CGFloat(i) + 0.19)
        let color = i >= 6 ? NSColor(srgbRed: 0.18, green: 0.48, blue: 0.95, alpha: 1)
                           : NSColor(srgbRed: 0.45, green: 0.68, blue: 0.98, alpha: 1)
        fill(cg, CGRect(x: x, y: chart.maxY - chart.height * v, width: barWidth, height: chart.height * v), color, radius: 2)
    }
    lines(cg, x: p.minX, y: chart.maxY + pageWidth * 0.08, width: p.width, count: 10, spacing: max(10, pageWidth * 0.04),
          color: NSColor(white: 0.88, alpha: 1))
}

private func drawCode(_ r: CGRect, _ cg: CGContext) {
    fill(cg, r, NSColor(srgbRed: 0.12, green: 0.125, blue: 0.15, alpha: 1))
    let keyword = NSColor(srgbRed: 0.99, green: 0.37, blue: 0.64, alpha: 1)
    let type = NSColor(srgbRed: 0.36, green: 0.85, blue: 1, alpha: 1)
    let plain = NSColor(white: 0.9, alpha: 1)
    let string = NSColor(srgbRed: 0.99, green: 0.42, blue: 0.36, alpha: 1)
    let comment = NSColor(white: 0.5, alpha: 1)
    let code: [[(String, NSColor)]] = [
        [("import", keyword), (" AppKit", plain)],
        [("import", keyword), (" SnaplineCore", plain)],
        [],
        [("// ", comment), (Demo.t("Built-in layouts for a 32:9 display", "Eingebaute Layouts für einen 32:9-Monitor"), comment)],
        [("let", keyword), (" screen = ", plain), ("ScreenClass", type), ("(size: ", plain), ("CGSize", type), ("(width: 5120, height: 1440))", plain)],
        [("let", keyword), (" layouts = ", plain), ("LayoutCatalog", type), (".builtIn(for: screen)", plain)],
        [],
        [("for", keyword), (" layout ", plain), ("in", keyword), (" layouts {", plain)],
        [("    let", keyword), (" frames = layout.zones.map {", plain)],
        [("        FrameCalculator", type), (".frame(for: $0, in: visible, gap: 8)", plain)],
        [("    }", plain)],
        [("    print", type), ("(layout.name, frames.count, ", plain), ("\"zones\"", string), (")", plain)],
        [("}", plain)],
        [],
        [("$ ", comment), ("swift run", plain)],
        [("Build complete!", NSColor(srgbRed: 0.45, green: 0.85, blue: 0.45, alpha: 1))],
    ]
    for (i, line) in code.enumerated() {
        let y = r.minY + 14 + CGFloat(i) * 18
        text("\(i + 1)", at: CGPoint(x: r.minX + 12, y: y), size: 11, color: NSColor(white: 0.4, alpha: 1), mono: true)
        let s = NSMutableAttributedString()
        for (part, color) in line {
            s.append(NSAttributedString(string: part, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: color]))
        }
        s.draw(at: CGPoint(x: r.minX + 40, y: y - 1))
    }
}

private func drawCalendar(_ r: CGRect, _ cg: CGContext) {
    text(Demo.t("October 2026", "Oktober 2026"), at: CGPoint(x: r.minX + 16, y: r.minY + 12), size: 18, weight: .bold,
         color: .black.withAlphaComponent(0.85))
    let days = Demo.german ? ["Mo 12", "Di 13", "Mi 14", "Do 15", "Fr 16"] : ["Mon 12", "Tue 13", "Wed 14", "Thu 15", "Fri 16"]
    let grid = CGRect(x: r.minX + 50, y: r.minY + 72, width: r.width - 60, height: r.height - 80)
    let col = grid.width / CGFloat(days.count)
    for (i, d) in days.enumerated() {
        text(d, at: CGPoint(x: grid.minX + col * CGFloat(i) + 8, y: r.minY + 46), size: 12, weight: i == 0 ? .bold : .regular,
             color: i == 0 ? NSColor.systemRed : .black.withAlphaComponent(0.7))
        fill(cg, CGRect(x: grid.minX + col * CGFloat(i), y: grid.minY, width: 0.5, height: grid.height), NSColor(white: 0.88, alpha: 1))
    }
    let hour = grid.height / 9
    for h in 0..<9 {
        let y = grid.minY + CGFloat(h) * hour
        fill(cg, CGRect(x: grid.minX, y: y, width: grid.width, height: 0.5), NSColor(white: 0.9, alpha: 1))
        text(String(format: "%02d:00", 9 + h), at: CGPoint(x: r.minX + 8, y: y - 6), size: 10, color: gray)
    }
    let events: [(Int, CGFloat, CGFloat, String, NSColor)] = [
        (0, 0.2, 0.5, "Standup", .systemBlue), (1, 0.2, 0.5, "Standup", .systemBlue),
        (2, 0.2, 0.5, "Standup", .systemBlue), (3, 0.2, 0.5, "Standup", .systemBlue),
        (0, 1.5, 1.5, Demo.t("Design review", "Design-Review"), .systemPurple),
        (1, 3, 1, Demo.t("Lunch", "Mittagessen"), .systemOrange), (3, 3, 1, Demo.t("Lunch", "Mittagessen"), .systemOrange),
        (2, 1, 3, Demo.t("Focus time", "Fokuszeit"), .systemGreen), (4, 4.5, 2, Demo.t("Sprint demo", "Sprint-Demo"), .systemPink),
        (1, 5, 1.5, Demo.t("Workshop", "Workshop"), .systemTeal), (3, 6, 1, Demo.t("Gym", "Sport"), .systemOrange),
    ]
    for (day, start, length, title, color) in events {
        let e = CGRect(x: grid.minX + col * CGFloat(day) + 3, y: grid.minY + start * hour + 1, width: col - 6, height: length * hour - 2)
        fill(cg, e, color.withAlphaComponent(0.2), radius: 4)
        fill(cg, CGRect(x: e.minX, y: e.minY, width: 3, height: e.height), color, radius: 1.5)
        if e.height > 14 {
            text(title, at: CGPoint(x: e.minX + 7, y: e.minY + 2), size: 10, weight: .semibold,
                 color: color.blended(withFraction: 0.45, of: .black)!, maxWidth: e.width - 10)
        }
    }
}

private func drawBrowser(_ r: CGRect, _ cg: CGContext) {
    let bar = CGRect(x: r.minX, y: r.minY, width: r.width, height: 34)
    fill(cg, bar, NSColor(white: 0.955, alpha: 1))
    let pill = CGRect(x: r.midX - min(r.width * 0.3, 220), y: bar.minY + 6, width: min(r.width * 0.6, 440), height: 22)
    fill(cg, pill, NSColor(white: 0.89, alpha: 1), radius: 7)
    text("lisbon-guide.example", at: CGPoint(x: pill.midX, y: pill.minY + 4), size: 12, color: NSColor(white: 0.3, alpha: 1),
         maxWidth: pill.width - 20, centered: true)
    let hero = CGRect(x: r.minX, y: bar.maxY, width: r.width, height: min(r.height * 0.42, 220))
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let sky = CGGradient(colorsSpace: space, colors: [NSColor(srgbRed: 0.98, green: 0.72, blue: 0.45, alpha: 1).cgColor,
                                                      NSColor(srgbRed: 0.93, green: 0.48, blue: 0.45, alpha: 1).cgColor] as CFArray,
                         locations: [0, 1])!
    cg.saveGState()
    cg.clip(to: hero)
    cg.drawLinearGradient(sky, start: CGPoint(x: 0, y: hero.minY), end: CGPoint(x: 0, y: hero.maxY), options: [])
    cg.setFillColor(NSColor(srgbRed: 1, green: 0.95, blue: 0.8, alpha: 0.9).cgColor)
    cg.fillEllipse(in: CGRect(x: hero.minX + hero.width * 0.68, y: hero.minY + hero.height * 0.25, width: hero.height * 0.32, height: hero.height * 0.32))
    // Roofs.
    var x = hero.minX
    var i = 0
    while x < hero.maxX {
        let w = CGFloat([46, 64, 38, 58, 52][i % 5])
        let h = hero.height * CGFloat([0.34, 0.46, 0.3, 0.52, 0.4][i % 5])
        fill(cg, CGRect(x: x, y: hero.maxY - h, width: w - 3, height: h),
             [NSColor(srgbRed: 0.98, green: 0.93, blue: 0.85, alpha: 1), NSColor(srgbRed: 0.95, green: 0.84, blue: 0.62, alpha: 1),
              NSColor(srgbRed: 0.85, green: 0.9, blue: 0.95, alpha: 1)][i % 3])
        fill(cg, CGRect(x: x - 2, y: hero.maxY - h - 6, width: w + 1, height: 8), NSColor(srgbRed: 0.78, green: 0.36, blue: 0.24, alpha: 1), radius: 2)
        x += w
        i += 1
    }
    cg.restoreGState()
    let tx = r.minX + max(24, (r.width - 520) / 2)
    text(Demo.t("Three Days in Lisbon", "Drei Tage in Lissabon"), at: CGPoint(x: tx, y: hero.maxY + 18), size: 22, weight: .bold,
         color: .black.withAlphaComponent(0.88), maxWidth: r.width - 48)
    text(Demo.t("Trams, viewpoints and the best custard tarts", "Straßenbahnen, Aussichtspunkte und die besten Puddingtörtchen"),
         at: CGPoint(x: tx, y: hero.maxY + 50), size: 13, color: gray, maxWidth: r.width - 48)
    lines(cg, x: tx, y: hero.maxY + 82, width: min(520, r.width - 48), count: 12)
}

private func drawMaps(_ r: CGRect, _ cg: CGContext) {
    fill(cg, r, NSColor(srgbRed: 0.96, green: 0.95, blue: 0.91, alpha: 1))
    // River.
    let river = CGMutablePath()
    river.move(to: CGPoint(x: r.minX, y: r.maxY - r.height * 0.22))
    river.addCurve(to: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.34),
                   control1: CGPoint(x: r.minX + r.width * 0.35, y: r.maxY - r.height * 0.12),
                   control2: CGPoint(x: r.minX + r.width * 0.6, y: r.maxY - r.height * 0.42))
    river.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
    river.addLine(to: CGPoint(x: r.minX, y: r.maxY))
    river.closeSubpath()
    cg.addPath(river)
    cg.setFillColor(NSColor(srgbRed: 0.62, green: 0.82, blue: 0.96, alpha: 1).cgColor)
    cg.fillPath()
    // Parks.
    fill(cg, CGRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.14, width: r.width * 0.16, height: r.height * 0.2),
         NSColor(srgbRed: 0.75, green: 0.89, blue: 0.7, alpha: 1), radius: 10)
    fill(cg, CGRect(x: r.minX + r.width * 0.62, y: r.minY + r.height * 0.08, width: r.width * 0.12, height: r.height * 0.16),
         NSColor(srgbRed: 0.75, green: 0.89, blue: 0.7, alpha: 1), radius: 8)
    // Roads.
    cg.setStrokeColor(NSColor.white.cgColor)
    cg.setLineCap(.round)
    for (i, frac) in [0.2, 0.42, 0.58, 0.8].enumerated() {
        cg.setLineWidth(i == 1 ? 7 : 4)
        cg.move(to: CGPoint(x: r.minX + r.width * frac, y: r.minY))
        cg.addLine(to: CGPoint(x: r.minX + r.width * (frac + 0.08), y: r.maxY))
        cg.strokePath()
    }
    for (i, frac) in [0.25, 0.5].enumerated() {
        cg.setLineWidth(i == 0 ? 6 : 4)
        cg.move(to: CGPoint(x: r.minX, y: r.minY + r.height * frac))
        cg.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * (frac + 0.06)))
        cg.strokePath()
    }
    let pin = CGPoint(x: r.minX + r.width * 0.47, y: r.minY + r.height * 0.42)
    symbol("mappin.circle.fill", in: CGRect(x: pin.x - 14, y: pin.y - 14, width: 28, height: 28), color: .systemRed)
    text(Demo.t("Lisbon", "Lissabon"), at: CGPoint(x: pin.x + 18, y: pin.y - 8), size: 13, weight: .semibold,
         color: .black.withAlphaComponent(0.75))
}
