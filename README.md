# Snapline

[![Package: I love macOS, but I miss some Windows features](https://img.shields.io/badge/Package-I_love_macOS%2C_but_I_miss_some_Windows_features-0A84FF)](https://github.com/search?q=topic%3Ai-love-macos-but-i-miss-windows-features+user%3Aleonatwork&type=repositories)

Windows-11-Fensterverwaltung für macOS: Snap Layouts, Snap Bar, Aero Snap, Snap Assist und Win+Pfeiltasten. Gebaut für Ultrawide- und Super-Ultrawide-Monitore wie den Samsung Odyssey G9 (32:9).

Menüleisten-App, ohne Abhängigkeiten, Swift + AppKit.

Sprachen: Snapline folgt der macOS-Sprache und spricht Englisch, Deutsch, Französisch, Spanisch, Italienisch, Portugiesisch (Brasilien), Niederländisch, Japanisch, Chinesisch (vereinfacht) und Koreanisch.

## Teil des Pakets

Snapline gehört zum Paket **„I love macOS, but I miss some Windows features“**: vier kleine Tools, die Windows-Funktionen auf den Mac bringen.

| Tool | Was es macht | Download |
|---|---|---|
| [Tappi](https://github.com/leonatwork/Tappi) | Alt+Tab zwischen Fenstern statt Apps | [Neueste Version](https://github.com/leonatwork/Tappi/releases/latest) |
| [Klemmi](https://github.com/leonatwork/Klemmi) | Zwischenablage-Verlauf wie Win+V, mit Quell-App | [Neueste Version](https://github.com/leonatwork/Klemmi/releases/latest) |
| **[Snapline](https://github.com/leonatwork/snapline)** (dieses Tool) | Snap Layouts, Aero Snap und Snap Assist aus Windows 11 | [Neueste Version](https://github.com/leonatwork/snapline/releases/latest) |
| [Snapboard](https://github.com/leonatwork/snapboard) | Screenshots wie mit dem Snipping Tool, direkt in die Zwischenablage | [Neueste Version](https://github.com/leonatwork/snapboard/releases/latest) |

Vermisst du mehr als eine dieser Funktionen? Dann lad dir am besten [alle vier](https://github.com/search?q=topic%3Ai-love-macos-but-i-miss-windows-features+user%3Aleonatwork&type=repositories) herunter. In Snapline findest du sie auch im Menü unter **Weitere Apps, die dir gefallen könnten**.

## Funktionen

| Windows 11 | Snapline |
|---|---|
| Hover über Maximieren → Snap Layouts | Hover über den **grünen Knopf** → Layout-Flyout, Zone anklicken |
| Win + Z | **⌃⌥Z** (auf deutscher Tastatur auch ⌃⌥Y) |
| Fenster oben in die Mitte ziehen → Snap Bar | genauso: Leiste mit Layouts erscheint, Fenster auf eine Zone ziehen |
| Fenster an Rand/Ecke ziehen | linker/rechter Rand → äußere Spalte, Ecke → halbe Spalte, oberer Rand → maximieren, **unterer Rand → Spalte unter dem Cursor** |
| Snap Assist | Nach dem Snappen per Layout werden die übrigen Fenster in den freien Zonen angeboten |
| Win + ← / → | **⌃⌥← / →** wandert durch die Spalten und weiter auf den nächsten Monitor |
| Win + ↑ / ↓ | **⌃⌥↑** maximieren bzw. obere Hälfte · **⌃⌥↓** wiederherstellen, untere Hälfte, minimieren |
| Gesnapptes Fenster wegziehen | bekommt seine ursprüngliche Größe zurück |
| FancyZones: ⇧ + Ziehen | **⌘ + Ziehen** (Taste im Menü umstellbar: ⌘, ⌥ oder ⇧) legt das Fenster in die Zonen des aktiven Layouts. Dabei wechseln **Mausrad / 1–9 / Tab** das Layout, **⇧** verbindet mehrere Zonen, **Esc** bricht ab |
| FancyZones: Layout wechseln | **⌃⌥1…9** wählt das aktive Layout des Monitors (kurz eingeblendet) |
| FancyZones-Editor | **Layouts bearbeiten…**: Zonen teilen, Trennlinien ziehen, Zonen entfernen |
| – | **Arbeitsbereiche**: aktuelle Anordnung speichern, mit **⌃⌥⇧1…9** wiederherstellen, fehlende Apps werden gestartet |

Das macOS-eigene Kachel-Menü am grünen Knopf wird unterdrückt. Snapline fängt die Hover-Events dort per Event Tap ab (wie Tappi), sodass nur noch das Snapline-Flyout erscheint. Snap Assist zeigt Live-Vorschauen der Fenster (ScreenCaptureKit, wie in Tappi).

### Seitenverhältnisse

Layouts und Spalten passen sich pro Monitor an:

- **32:9** (z. B. G9, 5120×1440): Drittel, ¼+½+¼, Viertel, Hälften, Stapel-Layouts, 3×2-Raster. Rand und Tastatur arbeiten mit Dritteln (im Menü auf Hälften oder Viertel umstellbar).
- **21:9**: Hälften, Drittel, ¼+½+¼, ⅔+⅓ …
- **16:9 / 16:10**: Hälften, ⅔+⅓, Drittel, Viertel …
- **Hochformat**: Zeilen statt Spalten.

## Installation

Benötigt macOS 14 oder neuer.

### Herunterladen

1. `Snapline-<Version>.zip` aus dem [neuesten Release](https://github.com/leonatwork/snapline/releases/latest) laden und entpacken.
2. `Snapline.app` in den Ordner **Programme** ziehen.
3. Beim ersten Start: Rechtsklick ▸ **Öffnen**. Ab macOS 15 stattdessen unter **Systemeinstellungen → Datenschutz & Sicherheit** auf **Dennoch öffnen** klicken.

Schritt 3 ist nötig, weil Snapline nicht von Apple notarisiert ist.

### Selbst bauen

Dafür reichen die Xcode Command Line Tools (`xcode-select --install`).

```bash
scripts/install.sh
```

Das baut die App, kopiert sie nach `/Applications` und startet sie. Beim ersten Start fragt macOS nach dem Zugriff auf **Bedienungshilfen**. Den brauchen wir, um Fenster anderer Apps zu verschieben.

### macOS-eigenes Kacheln abschalten

Seit macOS 15 kachelt macOS selbst, wenn man Fenster an den Rand zieht. Das kollidiert mit Snapline. Snapline zeigt im Menü eine Warnung, solange es aktiv ist.

**Systemeinstellungen → Schreibtisch & Dock → Fenster** und dort ausschalten:
- „Fenster an Bildschirmränder ziehen, um sie zu kacheln“
- „Fenster in die Menüleiste ziehen, um den Bildschirm zu füllen“

Außerdem „Halte ⌥ beim Ziehen gedrückt, um zu kacheln“, sonst kollidiert es mit ⌥ + Ziehen.

### Berechtigungen

- **Bedienungshilfen**: Fenster verschieben, Event Tap
- **Bildschirmaufnahme** (optional): Live-Vorschau in Snap Assist

Damit die Berechtigungen einen Neubau überleben, einmal ausführen:

```bash
scripts/setup-signing.sh
```

Das legt ein lokales, selbstsigniertes Zertifikat „Snapline Local Signing“ an (wie bei Tappi). `scripts/build-app.sh` nutzt es automatisch, ansonsten wird ad-hoc signiert, und macOS vergisst die Berechtigungen bei jedem Build.

## Entwicklung

```bash
swift test               # Logik-Tests (Layouts, Geometrie, Rand- und Tastaturlogik)
swift run Snapline       # direkt starten (Berechtigung gilt dann fürs Terminal)
scripts/build-app.sh     # dist/Snapline.app bauen
scripts/check-localizations.sh  # Übersetzungen prüfen (alle Schlüssel in allen Sprachen, plutil -lint)
```

Aufbau:

- `Sources/SnaplineCore`: reine Logik ohne AppKit, vollständig getestet
- `Sources/Snapline/AX`: Accessibility-Zugriff auf Fenster
- `Sources/Snapline/Controllers`: Drag, Hover, Tastatur, Hotkeys
- `Sources/Snapline/UI`: Vorschau, Layout-Flyout, Zonen-Overlay, Snap Assist, Layout-Editor
- `Resources/<Sprache>.lproj/Localizable.strings`: Texte der Oberfläche (Englisch ist die Entwicklungssprache), Zugriff über `L10n.tr("schlüssel")`

Eigene Layouts und Arbeitsbereiche liegen als JSON in `~/Library/Application Support/Snapline/`.

Das Icon wird mit `swift scripts/make-icon.swift` erzeugt.

Details und Roadmap stehen in [PLAN.md](PLAN.md).

## Lizenz

[MIT](LICENSE) — freie Nutzung, Änderung und Weitergabe, ohne Gewährleistung.
