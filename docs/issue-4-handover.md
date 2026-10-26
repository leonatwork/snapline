# Issue #4: App-Ausschlussliste – Handover

## Grundlage und Prüflücken

- Ausgangsstand: `HEAD` und lokales `origin/main` waren identisch:
  `84317c3d5f4fc596423b684d08f62294b2b8e5a6`; Arbeitsverzeichnis war sauber.
- Grundlage ist die vollständige Issue-Beschreibung aus dem Auftrag sowie die
  Wissensbasis: Leon wählte am 2026-10-21 einen globalen Ausschluss und eine
  anfangs leere Liste. Diese Entscheidungen ersetzen die offenen Fragen in der
  ursprünglichen Beschreibung.
- Der Versuch, Issue inklusive Kommentaren und offene PRs über `gh` zu lesen,
  wurde durch die Harness-Berechtigungen abgewiesen. Vollständiger Thread,
  aktuelle offene PRs und Aktualität des lokalen `origin/main` gegenüber GitHub
  sind deshalb **nicht verifiziert**. Vor Review bitte diese Informationen
  abgleichen. Es wurde kein fremder PR-Stand verwendet.
- `AGENTS.md`, `CLAUDE.md` und `CONTRIBUTING.md` sind im ausgecheckten Repository
  nicht vorhanden. Gelesen wurden README-Fassungen, `PLAN.md`, `Package.swift`,
  Lokalisierungsprüfung und vorhandener Release-Workflow; die zusätzlichen
  Regeln des Auftrags wurden angewendet.

## Verbindliche Kriterien und Umsetzung

Alle Angaben zur Umsetzung sind durch Code-Review nachvollziehbar, aber noch
kein Laufzeitnachweis auf macOS.

| Kriterium | Umsetzung / Review-Punkt |
|---|---|
| AC-1: kein Drag-/Zonen-Snap und keine Vorschau | `DragController` verwirft ausgeschlossene Fenster vor Drag-Erkennung und Wiederherstellung der Größe; laufende Drags und verzögerte Commits prüfen ebenfalls. Dies deckt auch die Snap Bar ab. |
| AC-2: kein Hover-Flyout, natives Menü bleibt verfügbar | `GreenButtonIndex` behält ausgeschlossene Fenster als verdeckende Bounds, aber ohne Button-Ziel. `hit` und der verzögerte Hover-Aufruf prüfen den Ausschluss. Ohne Hit werden Mausbewegungen nicht unterdrückt. |
| AC-3: Pfeile und ⌃⌥Z nur mit Systemton | Beide Fenster-Guards in `KeyboardController` nutzen den bisherigen `NSSound.beep()`-Pfad; gilt auch für ⌃⌥Y und den Menüaufruf des Flyouts. |
| AC-4: keine ausgeschlossenen Snap-Assist-Kandidaten | Snap Assist übergibt die aktuelle Liste an `WindowList.visibleWindows`; Filter erfolgt vor AX-Abfragen. Auswahl prüft erneut. |
| AC-5: aktive App sofort ausschließen, Menü umschalten, Neustart | Menü erfasst `frontmostApplication` beim Öffnen und speichert deren Bundle-ID am Eintrag. Eigene PID und fehlende Bundle-ID blenden ihn aus. `Settings.appExclusions` speichert die Liste in UserDefaults unter `excludedApps`; registrierter Default ist leer. |
| AC-6: Untermenü-Klick aktiviert wieder | Alle gespeicherten Einträge sind entfernbar, mit auflösbarem App-Namen/Icon oder Bundle-ID-Fallback. Menüaktionen aktualisieren den Hover-Index und schließen laufende Auswahlen sofort. |
| AC-7: leere Liste bewahrt Verhalten | Leere Liste schließt keine App aus; unbekannte Bundle-IDs bleiben erlaubt. Kein App-Lookup im PID-Filter bei leerer Liste. |
| AC-8: zehn Sprachen, Lokalisierungsprüfung grün | Vier neue Schlüssel sind in allen zehn Sprachen vorhanden; beide App-Aktionsnamen haben genau einen `%@`-Platzhalter. Der vorgeschriebene Skriptlauf ist noch offen. |

Bundle-IDs werden vollständig und ohne Groß-/Kleinschreibung verglichen.
Hinzufügen dedupliziert, Entfernen ist ebenfalls case-insensitiv. Originalschreibweise
und Reihenfolge bleiben für Menü und Speicherung erhalten.

Workspace-Erfassung erhält weiterhin alle bisherigen Fenster: Die Fensterliste
hat einen leeren Ausschluss-Default, Snap Assist übergibt explizit die Settings.
Workspace-Wiederherstellung wurde nicht geändert und platziert auch ausgeschlossene
Apps. Monitor-Layoutwahl und Workspace-Hotkeys behalten ihr bisheriges Verhalten;
sie sind keine Snap-Aktion auf ein fokussiertes Fenster.

## Tests und QS

- Zuerst wurde `Tests/SnaplineCoreTests/AppExclusionsTests.swift` mit sechs
  Swift-Testing-Tests angelegt, danach die Implementierung. Die Suche nach einer
  `AppExclusions`-Definition in `Sources/` lieferte vor dem Fix keinen Treffer.
  Das belegt die fehlende API statisch, **keinen ausgeführten roten Testlauf**.
- Ein zusätzlicher siebter Test deckt den ersten Eintrag und Rückkehr zur leeren
  Liste ab. Insgesamt: leer, exakte Treffer/keine Präfix-Treffer, Case-Insensitive,
  nil-Bundle-ID, duplikatfreies Hinzufügen, unveränderte Ausgangswerte,
  Deduplizierung gespeicherter Listen, Listen-Roundtrip und Entfernen.
- `git diff --check`: erfolgreich. Neue Schlüssel und Platzhalter wurden in
  allen zehn Ressourcen statisch geprüft; alle Snap-Eingänge und gemeinsamen
  Fensterlisten-Aufrufer wurden nachverfolgt.
- **Nicht ausgeführt:** Swift-Tests, Build, `scripts/check-localizations.sh`,
  manuelle UX-Tests. Der Auftrag verbietet Bauen/Ausführen auf diesem Linux-Server
  ohne Swift/Xcode/AppKit. Die Forderungen nach beobachtetem Testfehlschlagen,
  grünem Testlauf und grünem Lokalisierungsskript können hier nicht erfüllt werden.

### Ausstehender macOS-Nachweis

1. Für reproduzierbares Rot: in einer separaten macOS-Arbeitskopie des genannten
   Ausgangscommits nur die neue Testdatei übernehmen und
   `swift test --filter AppExclusionsTests` ausführen. Erwartet: fehlender Typ
   `AppExclusions`. Anschließend den vollständigen Patch anwenden.
2. `swift test --filter AppExclusionsTests`, danach `swift test` und
   `scripts/check-localizations.sh` ausführen und Ergebnisse am Review hinterlegen.
3. Beispielsweise Vorschau ausschließen. Rand-/Ecken-Drag, Snap Bar und
   Zonen-Drag prüfen: keine Snapline-Vorschau oder Platzierung, auch kein Restore
   beim Wegziehen eines zuvor gesnappten Fensters.
4. Hover prüfen: kein Snapline-Flyout, natives Menü nicht unterdrückt. Ein Fenster
   der ausgeschlossenen App vor den grünen Knopf einer anderen App legen:
   dahinter darf kein Flyout erscheinen und kein Event geschluckt werden.
5. ⌃⌥ + alle Pfeile, ⌃⌥Z/⌃⌥Y und Menü-Flyout prüfen: ausschließlich Systemton.
   Andere App snappen: Vorschau fehlt in Snap Assist.
6. Menü erneut öffnen: Wiederaktivieren-Text und Untermenü mit Name/Icon prüfen.
   Über beide Menüwege wieder aktivieren und die Funktionen erneut prüfen.
   Laufende Flyouts/Snap-Assist-Auswahl bei Listenänderung müssen geschlossen sein.
7. Mit gespeichertem Ausschluss neu starten: Eintrag und Verhalten bleiben.
   Letzten Eintrag entfernen: Ausgangsverhalten kehrt zurück. Nicht mehr installierte
   Bundle-ID muss im Untermenü entfernbar bleiben; Snapline selbst ist kein aktiver
   Ausschluss-Eintrag. Gespeicherten Workspace mit ausgeschlossener App erfassen
   und wiederherstellen.

## Abhängigkeiten und Lieferung

Die Implementierung benötigt keinen fremden PR-Code und keine neuen Dependencies.
Im Ausgangsstand existiert nur ein Release-Workflow mit `swift test`, kein
Push-/PR-QS-Workflow. Die allgemeine CI-Erweiterung ist laut Auftrag/Wissensbasis
Gegenstand von Issue #2; ein macOS-CI-Nachweis für diesen Patch bleibt erforderlich,
der Status eines zugehörigen offenen PRs konnte nicht geprüft werden. Der
Release-Workflow wurde nicht ausgelöst.

Änderungen liegen ausschließlich im Arbeitsverzeichnis. Kein Commit, Push,
Branchwechsel, neuer Branch, PR, Merge, Release oder Deployment wurde durchgeführt.
