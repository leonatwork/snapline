# Issue #5: Stage Manager und macOS-Kacheln – Handover

## Grundlage und Prüflücken

- Ausgangsstand: sauberer Arbeitsbaum; `HEAD` und lokales `origin/main` identisch:
  `8b4133acdce7d11e2083a90b4eb11526d2d404cb`.
- Grundlage ist der vollständig mitgelieferte Issue-Text. Die Entscheidungen im
  strukturierten Formular gelten gegenüber den ursprünglichen offenen Fragen:
  Schreiben nach Bestätigung ist erlaubt; Stage-Manager-Streifen/Gruppen sind
  ein Folge-Issue; Stage Manager selbst darf nicht ausgeschaltet werden.
- `gh` zum Lesen von Issue-Kommentaren und offenen PRs wurde durch die
  Tool-Berechtigungen gesperrt. Vollständiger Live-Thread, offene PRs und
  Aktualität des lokalen `origin/main` gegenüber GitHub sind **nicht verifiziert**.
  Vor Review abgleichen. Die Lösung verwendet ausschließlich den Ausgangsstand.
- `AGENTS.md`, `CLAUDE.md` und `CONTRIBUTING.md` sind im Checkout nicht vorhanden.
  Gelesen wurden beide READMEs, `PLAN.md`, `Package.swift`, bestehende Tests,
  Lokalisierungsprüfung, Release-Workflow und der vorhandene Issue-4-Handover.

## Verbindliche Akzeptanzkriterien

Die Implementierung ist statisch geprüft; macOS-Laufzeitnachweise stehen aus.

| Kriterium | Umsetzung / Nachweis |
|---|---|
| AC-1: Stage Manager an → Warnung oben, Klick zu Schreibtisch & Dock | `AppDelegate.menuNeedsUpdate` fügt die eigene Warnung im oberen Warnungsblock ein. Beide Systemwarnungen nutzen den vorhandenen Desktop-Settings-Link. |
| AC-2: aus oder fehlender Schlüssel → keine Warnung | `WindowManagerSettings` verwendet für `GloballyEnabled` den Default `false`; Testmatrix mit `nil`, `false`, `true`. |
| AC-3: Laufzeitwechsel beim nächsten Öffnen | Jedes Öffnen liest einen neuen `NativeTiling.snapshot`; `CFPreferencesSynchronize` aktualisiert zuvor den externen Benutzer-/AnyHost-Domain-Cache. Kontrollzentrum-/Systemeinstellungen-Wechsel muss auf macOS geprüft werden. |
| AC-4: bisherige Kacheln-Warnung unverändert | Gleiche Defaults (`true`) und Bedingung: Rand oder oben oder (Option und ⌥-Modifier), zusätzlich Drag-Snap oder Zonen-Drag. Titel und Link bleiben erhalten. |
| AC-5: reine Warnentscheidung, alle Kombinationen und Modifier | `WindowManagerSettings.warnings` in SnaplineCore ohne Preferences/AppKit. Swift-Testing-Matrix prüft 648 Kombinationen (vier dreistufige Werte × zwei Modifier × zwei Drag-Snap-Werte × zwei Zonen-Drag-Werte). |
| AC-6: Abbrechen ändert nichts | Abbrechen ist die erste/Standard-Schaltfläche. Nur `.alertSecondButtonReturn` erreicht den Schreibpfad. Zusätzlich verhindert die Core-Funktion bei `confirmed: false` jeden Writer-Aufruf; Regressionstest. |
| AC-7: genau aufgelistete Schlüssel aus oder Systemeinstellungen-Schritt erklären | Dialog und Writer teilen `tilingKeys`: `EnableTilingByEdgeDrag`, `EnableTopTilingByEdgeDrag`, `EnableTilingOptionAccelerator`, jeweils `false`. Einzelne CFPreferences-Schreibzugriffe, Synchronisation und Read-back. Ergebnisdialog erklärt bei Erfolg die ggf. verzögerte Anwendung und bei Fehler den manuellen Schritt; öffnet Schreibtisch & Dock. Schreibmenge und Erhalt fremder Schlüssel werden getestet. |
| AC-8: zehn Sprachen, Skript grün, READMEs | Neun neue Texte in allen zehn Sprachen; beide READMEs ergänzen Button und Stage Manager. Skript lief, ist mangels `plutil` **nicht grün**; alle weiteren Skriptprüfungen meldeten keine Fehler. Vollständiger macOS-Lauf erforderlich. |

### Klarstellung zu AC-7

„Die Warnungen verschwinden“ kann bei aktivem Stage Manager nicht wörtlich für
beide Warnungen gelten: `GloballyEnabled` zu ändern ist ausdrücklich außerhalb
des Umfangs. Die gewählte, vom AC erlaubte Dialog-Alternative erklärt deshalb,
dass Stage Manager unverändert bleibt, seine Warnung bei Aktivität bestehen
bleibt und er bei Bedarf manuell in Schreibtisch & Dock ausgeschaltet werden kann.
Der Kacheln-Button erscheint unter der bestehenden Kacheln-Warnung.

## Testgetriebenes Vorgehen und QS

- Zuerst ausschließlich `Tests/SnaplineCoreTests/WindowManagerSettingsTests.swift`
  angelegt, anschließend nach `WindowManagerSettings` in `Sources/` gesucht:
  kein Treffer. Erst danach Produktionscode ergänzt. Das ist ein statischer
  Nachweis der fehlenden API, **kein ausgeführter roter Testlauf**.
- Fünf Swift-Testing-Tests: vollständige Warnmatrix einschließlich fehlender
  Schlüssel, Defaultwerte, neue Snapshots bei Stage-Manager-Wechsel ohne Drag,
  null Schreibzugriffe bei Abbruch und exakte Schreibmenge bei Bestätigung.
- `command -v swift` und `command -v plutil`: beide nicht vorhanden.
  Swift-Tests und App-Build wurden gemäß Linux-Regel nicht ausgeführt.
- `git diff --check`: erfolgreich.
- `scripts/check-localizations.sh`: ausgeführt, Exit 1 ausschließlich wegen
  fehlendem `plutil` in allen zehn Sprachen. Keine gemeldeten fehlenden/zusätzlichen
  oder doppelten Schlüssel, Format- oder Platzhalterfehler. Das ersetzt keinen
  erfolgreichen `plutil`-Lint und keinen grünen Gesamtcheck.
- Diff-Review: bestehende Kacheln-Bedingung erhalten; keine Beobachter, keine
  Änderungen an Snapping-Geometrie; nur drei bestätigte Preference-Schreibzugriffe;
  kein Schreiben von `GloballyEnabled` und kein Prozessneustart.

### Ausstehender macOS-Nachweis

1. Rot reproduzieren: in einer separaten macOS-Arbeitskopie des Ausgangscommits
   nur die neue Testdatei übernehmen und
   `swift test --filter WindowManagerSettingsTests` ausführen. Erwartet:
   fehlender Typ `WindowManagerSettings`. Dann vollständigen Patch anwenden.
2. `swift test --filter WindowManagerSettingsTests`, danach `swift test` und
   `scripts/check-localizations.sh` auf macOS ausführen. Ergebnisse im Review
   hinterlegen; auch die App muss dort erfolgreich kompilieren.
3. Auf macOS 14 und 15 Stage Manager im Kontrollzentrum an/aus schalten.
   Mit `defaults read com.apple.WindowManager GloballyEnabled` vergleichen.
   Menü bei laufender App erneut öffnen; Warnung auch bei ausgeschaltetem
   Drag-Snap und Zonen-Drag prüfen. Warnung anklicken → Schreibtisch & Dock.
4. Auf macOS 15 die drei Kacheln-Optionen einzeln und gemeinsam prüfen:
   Rand/oben warnen unabhängig vom Zonen-Modifier, Option allein bei ⌥,
   nicht bei ⌘; keine Kacheln-Warnung bei beiden ausgeschalteten Drag-Funktionen.
5. Vor dem Button-Test die drei Tiling-Werte und `GloballyEnabled` notieren,
   einschließlich fehlender Schlüssel. Abbrechen und Schließen des Dialogs
   prüfen: alle Werte unverändert. Bestätigen: genau die drei genannten Werte
   `false`, `GloballyEnabled` und weitere Domain-Werte unverändert. Ergebnis
   auch in Systemeinstellungen prüfen; Warnungen beim nächsten Menüöffnen
   vergleichen. Bei aktivem Stage Manager bleibt dessen Warnung.
6. Nach der manuellen Prüfung alle vorherigen Einstellungen von Hand wieder
   herstellen (ursprünglich fehlende Schlüssel wieder entfernen).

## Abhängigkeiten und Lieferung

Keine neuen Dependencies und keine technische Abhängigkeit von fremdem PR-Code.
Vorhanden ist nur der macOS-Release-Workflow mit `swift test`; kein automatisches
PR-QS-Gate. Laut vorhandenem Handover betrifft die allgemeine CI-Erweiterung
Issue #2. Ob dazu ein offener PR existiert, konnte nicht geprüft werden; der
macOS-CI-Testnachweis bleibt offen. Der Release-Workflow wurde nicht ausgelöst.

Die Lieferung ist ein uncommitteter Arbeitsbaum-Patch. Kein Commit, Push,
Branchwechsel, neuer Branch, PR, Merge, Release oder Deployment wurde durchgeführt.
