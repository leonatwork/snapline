# Snapline – Plan

Windows-11-Fensterverwaltung für macOS, optimiert für Ultrawide- und Super-Ultrawide-Monitore (21:9, 32:9).

## Ziel

Die vier Windows-11-Funktionen, die man im Alltag wirklich nutzt, möglichst originalgetreu nachbauen:

| Windows 11 | Snapline | Auslöser |
|---|---|---|
| **Snap Layouts** (Hover über Maximieren) | Layout-Flyout | Hover über den grünen Fensterknopf oder `⌃⌥Z` |
| **Snap Bar** (Fenster oben in die Mitte ziehen) | Layout-Leiste beim Ziehen | Fenster an den oberen Rand (Mitte) ziehen |
| **Aero Snap** (an Rand/Ecke ziehen) | Rand-Snapping mit Vorschau | Fenster an Rand/Ecke ziehen |
| **Snap Assist** (Rest auffüllen) | Fensterauswahl in leeren Zonen | Automatisch nach Snap per Layout |
| **Win + Pfeiltasten** | Tastatur-Snapping | `⌃⌥ ← → ↑ ↓` |
| Ursprungsgröße beim Wegziehen | Restore on Drag | Gesnapptes Fenster wegziehen |

## Seitenverhältnis-Klassen

Layouts und Spalten passen sich pro Monitor an:

| Klasse | Verhältnis | Spalten (Rand/Tastatur) | Layouts |
|---|---|---|---|
| `portrait` | < 1:1 | 2 | Zeilen ½, Zeilen ⅓, ⅔+⅓, Viertel |
| `standard` | bis ~2:1 (16:9, 16:10) | 2 | ½+½, ⅔+⅓, ⅓×3, ½+Stapel, Viertel, ¼+½+¼ |
| `wide` | ~2.1–3:1 (21:9) | 2 | ½+½, ⅓×3, ¼+½+¼, ⅔+⅓, ½+Stapel, Viertel |
| `superWide` | ≥ 3:1 (32:9) | 3 (einstellbar 2/3/4) | ⅓×3, ¼+½+¼, ¼×4, ½+½, ⅓+⅓+Stapel, Stapel+½+Stapel, 3×2, ⅔+⅓ |

Rand-Snapping auf 32:9: linker/rechter Rand → äußere Spalte, Ecken → obere/untere Hälfte der Spalte, unterer Rand → Spalte unter dem Cursor, oberer Rand → maximieren, oben Mitte → Snap Bar.

## Architektur

Swift Package, ohne Abhängigkeiten. Menüleisten-App (`LSUIElement`), AppKit plus etwas SwiftUI.

```
Sources/
  SnaplineCore/          reine Logik, ohne AppKit, getestet
    Zone.swift           normalisierte Rechtecke (0…1, Ursprung oben links)
    ScreenClass.swift    Seitenverhältnis → Klasse → Spalten
    LayoutCatalog.swift  Layouts pro Klasse
    FrameCalculator.swift Zone + Bildschirm + Abstand → Pixel-Frame
    EdgeSnapResolver.swift Cursor am Rand → Ziel (Zone / Maximieren / Snap Bar)
    KeyboardSnap.swift   Win+Pfeil-Logik (Spalten durchwandern, Hälften, Monitorwechsel)
  Snapline/              App
    AX/                  Accessibility-Wrapper (Fenster finden, Frame setzen)
    Screens.swift        Koordinatenumrechnung Cocoa ↔ AX
    SnapEngine.swift     Snappen + Ursprungsgrößen merken
    UI/                  Vorschau-Overlay, Layout-Flyout, Snap-Assist-Panels
    Controllers/         Drag-, Hover-, Tastatur-Controller, Hotkeys
    AppDelegate.swift    Menüleiste, Einstellungen, Berechtigungen
Tests/SnaplineCoreTests  Swift Testing
scripts/build-app.sh     baut Snapline.app (Release, signiert)
```

### Technische Eckpunkte

- **Fenstersteuerung** über die Accessibility-API (`AXUIElement`). Dafür braucht die App die Berechtigung „Bedienungshilfen“.
- **Ziehen erkennen**: globaler Maus-Monitor. Bei `mouseDown` wird das Fenster unter dem Cursor gemerkt, bei `mouseDragged` geprüft, ob sich nur die Position ändert (Verschieben, nicht Größe ändern).
- **Hover über den grünen Knopf**: entprellte AX-Abfrage des Elements unter dem Cursor (`AXFullScreenButton` / `AXZoomButton`).
- **Snap Assist** listet Fenster über AX plus `CGWindowList` (nur Bounds und PID, daher keine Bildschirmaufnahme-Berechtigung nötig). Es gibt Icons und Titel statt Live-Thumbnails.
- **Hotkeys** über Carbon `RegisterEventHotKey`, dafür ist keine Berechtigung nötig.
- **Konfigurierbare Tastenkürzel**: Codable-Modell in `Shortcuts.swift`, UserDefaults, eigener AppKit-Recorder mit Konfliktprüfung. Carbon-Kürzel werden bei Änderungen abgemeldet und neu registriert; Fehler stehen oben im Statusmenü. Beschriftungen und Standard-Flyout-Z folgen der aktiven Eingabequelle (`TIS`/`UCKeyTranslate`). Standards bleiben ⌃⌥, für Arbeitsbereiche zusätzlich ⇧. Monitorwechsel-Kürzel bleiben fest reserviert.
- **Chrome/Electron**: `AXEnhancedUserInterface` wird während des Resize kurz deaktiviert, sonst animieren diese Apps träge.
- **Konflikt mit macOS-Kacheln**: Die App erkennt, ob „Fenster an Bildschirmränder ziehen, um sie zu kacheln“ aktiv ist, und weist im Menü darauf hin.

## Meilensteine

1. **Core** – Layouts, Geometrie, Rand- und Tastaturlogik und Tests
2. **AX-Schicht** – Fenster lesen, setzen, finden
3. **Drag-Snap** – Randzonen, Vorschau, Snap Bar
4. **Snap-Layouts-Flyout** – Hover und `⌃⌥Z`
5. **Snap Assist**
6. **Tastatur** – `⌃⌥` + Pfeile
7. **Menüleiste** – Einstellungen, Anmeldestart, Berechtigungs-Onboarding
8. **Build-Skript, README, privates GitHub-Repo**

## v0.2 (umgesetzt)

- Event Tap (Tappi-Ansatz): macOS-Kachelmenü am grünen Knopf unterdrückt
- ⌥ + Ziehen in Zonen des aktiven Layouts, Layoutwechsel live (Tab / Mausrad / 1–9), ⇧ verbindet Zonen
- Aktives Layout pro Monitor, ⌃⌥1–9
- Win+Z-Ziffernauswahl im Flyout
- Layout-Editor (Zonen-Baum: teilen, Trennlinien ziehen, entfernen)
- Arbeitsbereiche speichern/wiederherstellen, ⌃⌥⇧1–9
- Live-Vorschau in Snap Assist (ScreenCaptureKit, aus Tappi)
- Abstand 0 als Standard, App-Icon, stabile lokale Signatur

## Später

- Snap Groups (gemeinsam gesnappte Fenster als Gruppe wiederherstellen)
- Gemeinsames Resize benachbarter Fenster (Trennlinie zwischen Fenstern ziehen)
