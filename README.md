# Snapline

Windows-11-Fensterverwaltung für macOS: Snap Layouts, Snap Bar, Aero Snap, Snap Assist und Win+Pfeiltasten. Gebaut für Ultrawide- und Super-Ultrawide-Monitore wie den Samsung Odyssey G9 (32:9).

Menüleisten-App, ohne Abhängigkeiten, Swift + AppKit.

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

### Seitenverhältnisse

Layouts und Spalten passen sich pro Monitor an:

- **32:9** (z. B. G9, 5120×1440): Drittel, ¼+½+¼, Viertel, Hälften, Stapel-Layouts, 3×2-Raster. Rand und Tastatur arbeiten mit Dritteln (im Menü auf Hälften oder Viertel umstellbar).
- **21:9**: Hälften, Drittel, ¼+½+¼, ⅔+⅓ …
- **16:9 / 16:10**: Hälften, ⅔+⅓, Drittel, Viertel …
- **Hochformat**: Zeilen statt Spalten.

## Installation

Benötigt macOS 14 oder neuer und die Xcode Command Line Tools (`xcode-select --install`).

```bash
scripts/install.sh
```

Das baut die App, kopiert sie nach `/Applications` und startet sie. Beim ersten Start fragt macOS nach dem Zugriff auf **Bedienungshilfen**. Den brauchen wir, um Fenster anderer Apps zu verschieben.

### macOS-eigenes Kacheln abschalten

Seit macOS 15 kachelt macOS selbst, wenn man Fenster an den Rand zieht. Das kollidiert mit Snapline. Snapline zeigt im Menü eine Warnung, solange es aktiv ist.

**Systemeinstellungen → Schreibtisch & Dock → Fenster** und dort ausschalten:
- „Fenster an Bildschirmränder ziehen, um sie zu kacheln“
- „Fenster in die Menüleiste ziehen, um den Bildschirm zu füllen“

### Berechtigung nach jedem Neubau

Ohne Apple-Developer-Zertifikat wird die App ad-hoc signiert. macOS behandelt dann jeden Build als neue App, deshalb musst du nach einem Neubau unter *Datenschutz & Sicherheit → Bedienungshilfen* den alten Snapline-Eintrag entfernen und neu erlauben.

Abhilfe: In der Schlüsselbundverwaltung ein selbstsigniertes Zertifikat zur Codesignierung mit dem Namen **„Snapline Dev“** anlegen (*Zertifikatsassistent → Zertifikat erstellen → Typ: Codesignierung*). `scripts/build-app.sh` verwendet es dann automatisch, und die Berechtigung bleibt erhalten. Alternativ: `SIGN_IDENTITY="Apple Development: …" scripts/build-app.sh`.

## Entwicklung

```bash
swift test               # Logik-Tests (Layouts, Geometrie, Rand- und Tastaturlogik)
swift run Snapline       # direkt starten (Berechtigung gilt dann fürs Terminal)
scripts/build-app.sh     # dist/Snapline.app bauen
```

Aufbau:

- `Sources/SnaplineCore`: reine Logik ohne AppKit, vollständig getestet
- `Sources/Snapline/AX`: Accessibility-Zugriff auf Fenster
- `Sources/Snapline/Controllers`: Drag, Hover, Tastatur, Hotkeys
- `Sources/Snapline/UI`: Vorschau, Layout-Flyout, Snap Assist

Details und Roadmap stehen in [PLAN.md](PLAN.md).
