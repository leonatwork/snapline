# Issue #19 – Datenschutz und datensparsames Debug-Log

## Grundlage und Lieferstand

- Ausgangsstand: sauberer Arbeitsbaum, `HEAD` identisch mit lokalem `origin/main`:
  `3c17b64250102ed9a8193ffef665a973c366423d`.
- Verbindliche Grundlage ist das strukturierte Issue-Formular im Auftrag, das
  die ältere Beschreibung konkretisiert: Titel entfallen ohne Hash, genau ein
  Backup `debug.log.1`, Rotation oberhalb von 1 MB, zwei Datenschutzdateien.
- Der GitHub-Abruf mit `gh` wurde von den Harness-Berechtigungen gesperrt.
  **Vollständiger Live-Thread samt Kommentaren, offene PRs und Aktualität des
  lokalen Remote-Stands sind nicht verifiziert.** Vor Review auf GitHub abgleichen.
- `AGENTS.md`, `CLAUDE.md` und `CONTRIBUTING.md` sind im Checkout nicht vorhanden.
  Gelesen: relevante App-/Core-Quellen und Testkonventionen, beide READMEs,
  `PLAN.md`, `Package.swift`, Lokalisierungsskript, CI- und Release-Workflow.
- Lieferung als uncommittierter Patch auf dem vorhandenen Checkout. Kein
  Branchwechsel, keine Branch-Erstellung, kein Cherry-Pick, Commit, Push, PR,
  Merge oder Deployment. Keine Abhängigkeiten ergänzt.
- Die Lösung verwendet ausschließlich den Ausgangsstand. Keine technische
  Abhängigkeit von fremdem PR-Code erkennbar; offene PRs konnten nicht geprüft
  werden.

## Akzeptanzkriterien und Status

Die Tabelle beschreibt Umsetzung und statische Prüfung. Sie ist **kein Nachweis
bestandener Swift-Tests oder macOS-Laufzeitprüfungen**.

| Kriterium | Umsetzung / verbleibender Nachweis |
|---|---|
| AC-1: PRIVACY en/de, lokale Daten, keine Netzwerkübertragung, Berechtigungszwecke und Löschpfade | `PRIVACY.md` und `PRIVACY.de.md` nennen Layouts, Workspaces einschließlich Titel, Einstellungen, RAM-Vorschauen und optionales Log. Konkrete JSON-/Log-/Preferences-Pfade, Abschalten/Zurücksetzen und Rechteentzug beschrieben. Netzwerkfreiheit der App und externe Browserlinks klar erläutert. |
| AC-2a: keine Fenstertitel im Debug-Log | Einzige Titelinterpolation aus dem Candidate-Log in `DragController` entfernt. Alle acht Log-Aufrufe geprüft: kein Fenstertitel und kein Hash. `debugLog()` bleibt opt-in mit verzögerter Nachrichtenauswertung; Titel/Window-Content dürfen von Aufrufern nicht übergeben werden. Manuelle macOS-Prüfung offen. |
| AC-2b: neue und bestehende Datei mit 0600 | `DebugLogFile` erstellt die leere Datei mit expliziten Rechten vor dem Inhalt; bestehende Datei wird vor Append/Rotation auf `0600` gesetzt. Auch ein vorhandenes Backup wird gehärtet. Dateisystemtests für neue/bestehende Dateien und ein übergroßes Legacy-Log ergänzt; Lauf offen. |
| AC-2c: Rotation über 1 MB vor nächstem Schreiben, Backup ersetzen | Größe der aktuellen Datei wird vor jedem Append geprüft; oberhalb von 1.000.000 Bytes wird `.1` ersetzt und die aktuelle Datei dorthin verschoben. Neuer Eintrag landet in einer neuen privaten Datei. Tests decken exaktes Limit, folgenden Write, zwei Rotationen und unveränderte Inhalte ab; Lauf offen. |
| AC-3: reine Entscheidung in SnaplineCore, Tests unter/auf/über Limit | `DebugLogRotation.shouldRotate(fileSize:)` ist reine Logik ohne Imports/Dateisystemzugriff. Drei Core-Tests für 0/999.999, 1.000.000, 1.000.001 und UInt64.max; Lauf offen. |
| AC-4: beide READMEs verlinken PRIVACY in jeweiliger Sprache | Datenschutzabschnitte mit relativen Links hinzugefügt. |
| AC-5: Workspace-Titel weiter speichern, bestehende Tests unverändert grün | `Workspace.swift`, `WorkspaceController.swift`, `LayoutStore.swift` und alle vorhandenen Tests unverändert. Bestehende `WorkspaceTests.titleMatchesWinThenOrder` bleiben erhalten. Erfolgreicher Lauf offen. |
| AC-6: Lokalisierungsprüfung und macOS-CI grün | `TMPDIR=/tmp/opencode bash scripts/check-localizations.sh`: Exit 0, zehn Sprachen mit je 134 Schlüsseln, Syntax/Platzhalter korrekt. Keine UI-Texte, Resources, Skripte oder Workflows geändert. macOS-CI nicht ausgeführt/bestätigt. |

### Klarstellungen und nicht erfüllbare Nachweise

- „Überschreitet … vor dem nächsten Schreiben“ (AC-2c) bedeutet strikt `>`.
  Eine Datei genau am Limit wird noch beschrieben und kann um einen Eintrag
  überlaufen. Ein strikt niemals überschrittenes Byte-Limit würde dieser
  Regel widersprechen. Einträge werden nicht gekürzt; die derzeitigen
  Diagnosen sind kurze Ereignisnachrichten. Ein vorbestehendes übergroßes Log
  wird beim nächsten Write als Ganzes zum einzigen Backup; es wird nicht
  rückwirkend gekürzt. Diese Semantik ist in beiden PRIVACY-Dateien erklärt.
- Aktualisieren entfernt keine Titel aus alten Log-Inhalten. Beide
  Datenschutzdateien nennen die Löschung des aktuellen Logs **und** des Backups.
- Bei deaktiviertem Debug-Log gibt es weiterhin keinerlei Log-Dateizugriffe;
  die Rechte bestehender Dateien werden beim nächsten aktivierten Write gehärtet.
- Der Auftrag verlangt einen nachgewiesenen roten Testlauf, grüne Tests und
  macOS-CI, verbietet zugleich Swift-/App-Ausführung auf diesem Linux-Server.
  **Rot-/Grün-Lauf, App-Build, macOS-CI und manuelle Log-Prüfung sind deshalb
  nicht erbracht.** Statische Tests-first-Prüfung ersetzt diese Nachweise nicht.
- Durch das Commit-/Push-Verbot wird hier kein CI-Lauf für den Patch ausgelöst.

## Tests-first und lokale QS

1. Zuerst `Tests/SnaplineCoreTests/DebugLogRotationTests.swift` und
   `Tests/SnaplineTests/DebugLogFileTests.swift` angelegt.
2. Anschließend nach `DebugLogRotation|DebugLogFile` in `Sources` gesucht:
   keine Treffer. Beide APIs fehlten vor dem Fix; die neuen Tests könnten dort
   nicht kompilieren. Das ist ein statischer Fehlstellen-Nachweis, **kein
   ausgeführter roter Testlauf**.
3. Erst danach Core-Entscheidung, App-Dateischreiber und Integration umgesetzt.
   Vier Dateisystemtests verwenden getrennte temporäre UUID-Verzeichnisse und
   bereinigen sie wieder; sie berühren weder UserDefaults noch echte App-Logs.
4. Lokalisierungsprüfung erfolgreich: zehn Sprachen, 134 Schlüssel je Sprache.
5. `git diff --check` sowie Whitespace-Prüfung der neuen Dateien erfolgreich.
6. Statischer Review: Logger serialisiert Size-Check/Rotation/Append über ein
   `NSLock`; Fehler bei Rechtevergabe oder Rotation brechen den Write ab.
   FileHandles werden geschlossen. Kein Titelzugriff mehr in Debug-Aufrufen.
   Titel-Erfassung/-Zuordnung/-Persistierung von Workspaces unangetastet.

## Ausstehende macOS-Prüfungen

In einer separaten macOS-Testarbeitskopie bzw. einem Test-Benutzerkonto:

1. Für den Rot-Nachweis nur die beiden neuen Testdateien auf den Ausgangscommit
   anwenden. `swift test --filter DebugLogRotationTests` und
   `swift test --filter DebugLogFileTests` müssen wegen der fehlenden neuen APIs
   scheitern. Erwarteten Fehler dokumentieren.
2. Vollständigen Patch anwenden, dieselben Filter erneut ausführen, anschließend
   `swift test` (inklusive unveränderter Workspace-/App-Tests) und
   `scripts/check-localizations.sh` ausführen. CI auf macOS 15 muss zusätzlich
   `swift build`, `scripts/build-app.sh` und die Ad-hoc-Signaturprüfung bestehen,
   wie im unveränderten `.github/workflows/ci.yml` vorgegeben.
3. Debug-Log im Testkonto aktivieren:
   `defaults write io.github.leonatwork.snapline debugLog -bool true`.
   App neu starten, ein Fenster mit eindeutigem Testtitel über seine Titelleiste
   ziehen. Das Candidate-Ereignis muss vorhanden sein, der Titel darf weder in
   `debug.log` noch in neu erzeugtem `debug.log.1` stehen.
4. `ls -l ~/Library/Logs/Snapline/debug.log*` muss `-rw-------` zeigen.
   App beenden, bestehendes Log im Testkonto auf `0644` setzen, erneut starten
   und einen Log-Eintrag auslösen: wieder `0600`, bisheriger Inhalt erhalten.
5. Für die Rotationsprüfung Test-Log genau auf 1.000.000 Bytes vorbereiten.
   Nächster Eintrag noch im selben Log; erst der darauf folgende Write rotiert.
   Bei einem bereits größeren Test-Log muss sofort vor Append rotiert werden.
   Vorbestehendes `.1` wird ersetzt, nie `.2` erzeugt, beide Dateien `0600`.
6. Arbeitsbereich speichern/wiederherstellen und Fenstertitel in
   `workspaces.json` prüfen. Danach Log deaktivieren, App beenden und Testdaten
   gemäß PRIVACY löschen. Bei deaktiviertem Log werden keine neuen Einträge
   oder Dateien erzeugt.
