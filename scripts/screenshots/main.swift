import AppKit
import SnaplineCore

// Screenshot harness for the README – see render.sh. Usage:
//   SnaplineShots <output dir> <file suffix> -AppleLanguages "(de)" …
// Renders invented demo scenes around Snapline's real view code and writes
// <name><suffix>.png. Never captures the screen, never reads Snapline's data.

/// A 32:9 display ("looks like" 1920×540, e.g. a 3840×1080 super ultrawide).
final class DemoScreen: NSScreen {
    private let demoFrame = NSRect(x: 0, y: 0, width: 1920, height: 540)
    override var frame: NSRect { demoFrame }
    override var visibleFrame: NSRect {
        NSRect(x: 0, y: 0, width: demoFrame.width, height: demoFrame.height - menuBarHeight)
    }
}

let maxPixelWidth = 1600
let outerPadding: CGFloat = 36

@MainActor
func layout(_ id: String, on screen: NSScreen) -> (layout: Layout, index: Int, count: Int) {
    let all = LayoutCatalog.layouts(for: screen.screenClass)
    let index = all.firstIndex { $0.id == id }!
    return (all[index], index, all.count)
}

/// Zone frame on the demo screen, top-left origin in screen points – exactly what
/// SnapEngine computes for a real screen.
@MainActor
func zoneFrame(_ zone: Zone, on screen: NSScreen) -> CGRect {
    SnapEngine.shared.frame(for: zone, on: screen).offsetBy(dx: -screen.axFrame.minX, dy: -screen.axFrame.minY)
}

@MainActor
func candidate(_ w: DemoWindow, id: CGWindowID) -> WindowCandidate {
    // The AX element is never used for anything; it only satisfies the type.
    WindowCandidate(window: AXWindow(AXUIElementCreateApplication(getpid())), windowID: id, bundleID: nil,
                    frame: .zero, title: w.title, appName: w.appName, icon: w.icon)
}

/// Places a scene on a soft neutral backdrop with rounded corners and a shadow, so it
/// reads well on both GitHub themes, and scales it down to `maxPixelWidth`.
@MainActor
func framed(_ scene: CGImage, cornerRadius: CGFloat = 12) -> CGImage {
    let size = CGSize(width: CGFloat(scene.width) / renderScale, height: CGFloat(scene.height) / renderScale)
    let canvas = CGSize(width: size.width + outerPadding * 2, height: size.height + outerPadding * 2)
    let full = render(canvas) { cg in
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let bg = CGGradient(colorsSpace: space, colors: [NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1).cgColor,
                                                         NSColor(srgbRed: 0.87, green: 0.89, blue: 0.92, alpha: 1).cgColor] as CFArray,
                            locations: [0, 1])!
        cg.addPath(roundedPath(CGRect(origin: .zero, size: canvas), 22))
        cg.clip()
        cg.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: canvas.height), options: [])
        let rect = CGRect(x: outerPadding, y: outerPadding, width: size.width, height: size.height)
        withShadow(cg, blur: 22, y: 8, alpha: 0.28) {
            fill(cg, rect, .white, radius: cornerRadius)
        }
        cg.saveGState()
        cg.addPath(roundedPath(rect, cornerRadius))
        cg.clip()
        draw(scene, in: rect, cg)
        cg.restoreGState()
    }
    guard full.width > maxPixelWidth else { return full }
    let width = maxPixelWidth
    let height = Int((CGFloat(full.height) * CGFloat(width) / CGFloat(full.width)).rounded())
    let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    cg.interpolationQuality = .high
    cg.draw(full, in: CGRect(x: 0, y: 0, width: width, height: height))
    return cg.makeImage()!
}

func write(_ image: CGImage, _ name: String, outDir: String, suffix: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name)\(suffix).png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("  \(url.path)  \(image.width)×\(image.height)")
}

/// Panel background like NSVisualEffectView (.popover / .hudWindow, light): the
/// blurred desktop underneath plus a light tint, rounded, with a window shadow.
func drawPanel(_ rect: CGRect, radius: CGFloat, backdrop: CGImage, tint: NSColor, border: Bool, _ cg: CGContext) {
    withShadow(cg, blur: 24, y: 10, alpha: 0.3) { fill(cg, rect, .white, radius: radius) }
    cg.saveGState()
    cg.addPath(roundedPath(rect, radius))
    cg.clip()
    draw(blurredCrop(backdrop, rect), in: rect, cg)
    fill(cg, rect, tint)
    cg.restoreGState()
    if border {
        cg.addPath(roundedPath(rect.insetBy(dx: 0.5, dy: 0.5), radius))
        cg.setStrokeColor(NSColor.separatorColor.cgColor)
        cg.setLineWidth(1)
        cg.strokePath()
    }
}

// MARK: - Scenes

/// 1. The Snap Layouts flyout below a window's green button (hover mode).
@MainActor
func snapLayouts(_ screen: NSScreen) -> CGImage {
    let grid = LayoutGridView()
    let layouts = LayoutCatalog.layouts(for: screen.screenClass)
    grid.configure(layouts: layouts, activeIndex: 0, screenClass: screen.screenClass, interactive: true, numbered: false)
    let target = layout("stacks-center", on: screen)
    grid.highlighted = LayoutPick(layout: target.layout, zoneIndex: 2)
    let gridImage = snapshot(grid)
    let gridSize = grid.bounds.size

    let window = CGRect(x: 24, y: 24, width: gridSize.width + 60, height: gridSize.height + 150)
    let size = CGSize(width: window.maxX + 24, height: gridSize.height + 110)
    let button = zoomButtonRect(of: window)
    // FlyoutController: top-left at (button.minX - 12, button.maxY + 6).
    let flyout = CGRect(x: button.minX - 12, y: button.maxY + 6, width: gridSize.width, height: gridSize.height)

    let desktop = render(size) { cg in
        drawWallpaper(cg, CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height * 2.2)))
        drawWindow(.report, in: window, active: true, cg)
    }
    return render(size) { cg in
        draw(desktop, in: CGRect(origin: .zero, size: size), cg)
        drawPanel(flyout, radius: 14, backdrop: desktop, tint: NSColor(white: 0.97, alpha: 0.82), border: false, cg)
        draw(gridImage, in: flyout, cg)
        // Cursor on the highlighted zone (center half of "Stack · ½ · stack").
        let index = target.index
        let columns = LayoutCatalog.flyoutColumns(for: screen.screenClass)
        let tileWidth = (gridSize.width - 24 - CGFloat(columns - 1) * 12) / CGFloat(columns)
        let tileHeight = (tileWidth / (32.0 / 9)).rounded()
        let tile = CGRect(x: flyout.minX + 12 + CGFloat(index % columns) * (tileWidth + 12),
                          y: flyout.minY + 12 + CGFloat(index / columns) * (tileHeight + 16 + 12),
                          width: tileWidth, height: tileHeight)
        drawCursor(at: CGPoint(x: tile.midX + 6, y: tile.midY + 4), cg)
    }
}

/// 2. ⌘-drag: the zones of the active layout while a window is being dragged.
@MainActor
func zoneOverlay(_ screen: NSScreen) -> CGImage {
    let size = screen.frame.size
    let target = layout("stacks-center", on: screen)
    let overlay = ZoneOverlayView()
    overlay.frame = CGRect(origin: .zero, size: size)
    overlay.configure(layout: target.layout, number: target.index + 1, count: target.count, screen: screen,
                      highlighted: [2], hint: L10n.tr("zones.hint", ZoneModifier.command.spanSymbol))
    let overlayImage = snapshot(overlay)

    return render(size) { cg in
        drawWallpaper(cg, CGRect(origin: .zero, size: size))
        drawMenuBar(cg, width: size.width, app: DemoWindow.report.appName)
        drawWindow(.notes, in: CGRect(x: 40, y: 64, width: 540, height: 430), cg)
        drawWindow(.maps, in: CGRect(x: 1330, y: 80, width: 520, height: 400), cg)
        let dragged = CGRect(x: 840, y: 150, width: 560, height: 360)
        drawWindow(.report, in: dragged, active: true, cg)
        draw(overlayImage, in: CGRect(origin: .zero, size: size), cg)
        drawCursor(at: CGPoint(x: dragged.minX + 120, y: dragged.minY + 14), cg)
    }
}

/// 3. Snap Assist: one window snapped into a third, the other zones offer the rest.
@MainActor
func snapAssist(_ screen: NSScreen) -> CGImage {
    let size = screen.frame.size
    let thirds = layout("cols-1-1-1", on: screen).layout
    let frames = thirds.zones.map { zoneFrame($0, on: screen) }
    let offered: [DemoWindow] = [.notes, .browser, .report, .calendar]
    let candidates = offered.enumerated().map { candidate($1, id: CGWindowID($0 + 1)) }
    let thumbnails = offered.map { thumbnail($0) }

    let desktop = render(size) { cg in
        drawWallpaper(cg, CGRect(origin: .zero, size: size))
        drawMenuBar(cg, width: size.width, app: "Terminal")
        drawWindow(.notes, in: CGRect(x: 760, y: 70, width: 560, height: 420), cg)
        drawWindow(.calendar, in: CGRect(x: 1300, y: 110, width: 580, height: 380), cg)
        drawWindow(.browser, in: CGRect(x: 980, y: 140, width: 600, height: 360), cg)
        drawWindow(.code, in: frames[0], active: true, cg)
    }

    // AssistPanel's content: 16 pt inset, title (13 pt semibold, secondary), 12 pt gap, card grid.
    var panels: [(frame: CGRect, grid: CGImage, firstCard: CGRect)] = []
    for zone in 1...2 {
        let frame = frames[zone]
        let grid = CardGridView()
        grid.appearance = NSAppearance(named: .aqua)
        grid.setCandidates(candidates, width: frame.width - 32)
        for (i, c) in candidates.enumerated() { grid.setThumbnail(thumbnails[i], for: c.windowID) }
        // Let the cards' 0.2 s icon → thumbnail cross-fade finish.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        if zone == 1, let card = grid.subviews.first,
           let enter = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                              windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) {
            card.mouseEntered(with: enter)
        }
        panels.append((frame, snapshot(grid), grid.subviews.first?.frame ?? .zero))
    }

    let titleHeight: CGFloat = 17
    return render(size) { cg in
        draw(desktop, in: CGRect(origin: .zero, size: size), cg)
        for panel in panels {
            let frame = panel.frame
            drawPanel(frame, radius: 14, backdrop: desktop, tint: NSColor(white: 0.95, alpha: 0.8), border: true, cg)
            text(L10n.tr("assist.title"), at: CGPoint(x: frame.minX + 16, y: frame.minY + 16), size: 13, weight: .semibold,
                 color: .secondaryLabelColor)
            let gridRect = CGRect(x: frame.minX + 16, y: frame.minY + 16 + titleHeight + 12,
                                  width: CGFloat(panel.grid.width) / renderScale, height: CGFloat(panel.grid.height) / renderScale)
            cg.saveGState()
            cg.clip(to: CGRect(x: gridRect.minX, y: gridRect.minY, width: gridRect.width, height: frame.maxY - 16 - gridRect.minY))
            draw(panel.grid, in: gridRect, cg)
            cg.restoreGState()
        }
        let first = panels[0]
        drawCursor(at: CGPoint(x: first.frame.minX + 16 + first.firstCard.midX + 30,
                               y: first.frame.minY + 16 + titleHeight + 12 + first.firstCard.midY + 10), cg)
    }
}

/// 4. A finished arrangement: five windows in "Stack · ½ · stack" on 32:9.
@MainActor
func desktop(_ screen: NSScreen) -> CGImage {
    let size = screen.frame.size
    let target = layout("stacks-center", on: screen).layout
    let windows: [DemoWindow] = [.notes, .calendar, .code, .report, .maps]
    return render(size) { cg in
        drawWallpaper(cg, CGRect(origin: .zero, size: size))
        drawMenuBar(cg, width: size.width, app: "Terminal")
        for (i, zone) in target.zones.enumerated() where i != 2 {
            drawWindow(windows[i], in: zoneFrame(zone, on: screen), cg)
        }
        drawWindow(windows[2], in: zoneFrame(target.zones[2], on: screen), active: true, cg)
    }
}

// MARK: - Main

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    NSApp.appearance = NSAppearance(named: .aqua)
    // Registration domain only (in memory); nothing is written to any preferences.
    Settings.registerDefaults()

    let args = CommandLine.arguments
    guard args.count >= 3 else {
        FileHandle.standardError.write("usage: SnaplineShots <output dir> <suffix>\n".data(using: .utf8)!)
        exit(2)
    }
    let outDir = args[1], suffix = args[2]
    let screen = DemoScreen()
    print("Rendering (\(Locale.preferredLanguages.first ?? "?"), gap \(Int(Settings.gap)) pt):")
    write(framed(snapLayouts(screen), cornerRadius: 14), "snap-layouts", outDir: outDir, suffix: suffix)
    write(framed(zoneOverlay(screen)), "zone-overlay", outDir: outDir, suffix: suffix)
    write(framed(snapAssist(screen)), "snap-assist", outDir: outDir, suffix: suffix)
    write(framed(desktop(screen)), "desktop", outDir: outDir, suffix: suffix)
}
