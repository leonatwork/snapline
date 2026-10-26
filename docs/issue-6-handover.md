# Issue #6: Mehrere Monitore – Handover

## Grundlage und Lieferstand

- Ausgangsstand: sauberer Arbeitsbaum; `HEAD` und lokal gespeichertes `origin/main`
  identisch: `8e1899688822fc397f346af625ef1546df7cbf11`.
- Grundlage ist der vollständig mitgelieferte Issue-Text. Das strukturierte
  Formular entscheidet die ursprünglichen offenen Fragen: kein Snapping an
  inneren Kanten, feste Kürzel ⌃⌥⇧ + Pfeil, kein Umlauf, Systemton ohne Nachbarn.
- Der Versuch, mit `gh` den vollständigen Thread einschließlich Kommentaren und
  offene PRs zu lesen, wurde durch die Harness-Berechtigungen gesperrt.
  **Live-Thread, offene PRs und Aktualität des lokalen Remote-Stands sind nicht
  verifiziert.** Vor Review mit GitHub abgleichen.
- `AGENTS.md`, `CLAUDE.md` und `CONTRIBUTING.md` fehlen im Checkout.
  Gelesen wurden die relevanten Sources und Tests, beide READMEs, `PLAN.md`,
  `Package.swift`, Lokalisierungsprüfung, Release-Workflow und Issue-5-Handover.
  Die angefragte Wissensbasis lieferte keine zusätzliche passende Notiz.
- Lieferung: uncommitteter Arbeitsbaum-Patch auf dem ursprünglichen Checkout.
  Keine Branch-Erstellung, kein Branchwechsel, kein Cherry-Pick, Commit, Push,
  PR, Merge, Release oder Deployment. Keine neuen Dependencies.

## Verbindliche Akzeptanzkriterien

Die Tabelle beschreibt Implementierung und Testabdeckung, **keine bestandenen
macOS-Laufzeitprüfungen**.

| Kriterium | Umsetzung / Nachweis |
|---|---|
| AC-1: keine Vorschau an gemeinsamen Seitenkanten; Außenkanten funktionieren | `ScreenGeometry.innerEdges` erkennt gemeinsame Kantenabschnitte. `EdgeSnapResolver` unterdrückt dort alle Ziele, auch an Ecken. Tests auf beiden Seiten innerhalb des Hot-Bereichs, Außenkante und freiliegendem Abschnitt eines versetzten Monitors. |
| AC-2: gemeinsame Ober-/Unterkante löst weder Maximieren noch Leiste noch Spalte aus | Gleiche Unterdrückung für `.up`/`.down`. Tests für Mitte, Maximierungsbereich und Ecken auf beiden Seiten. `DragController` schließt eine bereits offene Drag-Leiste beim Erreichen einer inneren Kante, beim Bildschirmwechsel und außerhalb der Bildschirmframes. |
| AC-3: dokumentierte stabile Punktzuordnung, auch negativ | Min-Kanten inklusiv, Max-Kanten exklusiv: rechts/unten gewinnt. Exponierte Max-Kanten werden als Fallback eingeschlossen; an gemeinsamen Endpunkten gewinnen weiterhin Min-Kanten. Überlappende Frames: geometrische Reihenfolge (oben, links, Höhe, Breite), Listenreihenfolge nur bei identischen Frames. Tests mit vertauschter Liste, negativen x/y, gemeinsamen Endpunkten und Punkten außerhalb. |
| AC-4: gerichteter Monitorwechsel mit relativer Position/Größe | Vier zusätzliche Carbon-Hotkeys ⌃⌥⇧←/→/↑/↓. `Screens.neighbor(direction:)` nutzt reine Core-Geometrie. `ScreenGeometry.transfer` skaliert Position und Größe relativ zu den sichtbaren Bereichen; Tests für alle Richtungen und unterschiedliche sichtbare Größen/Ursprünge. |
| AC-5: gesnapptes Fenster bleibt in derselben Zone | `SnapEngine.Record` speichert die normalisierte Zone neben tatsächlichem Frame und ursprünglichem Restore-Frame. Nur ein noch passender Snap-Record wird übertragen; die Zielzone wird mit dem aktuellen Gap neu berechnet. Auch Zonen-Drag und verbundene Zonen speichern die normalisierte Zone. Tests für Maximieren, halbe Drittel und freie/custom Zone auf 32:9 → Hochkant. |
| AC-6: kein Nachbar → unverändertes Fenster und Systemton | Neue Aktion prüft den Nachbarn vor jedem Fenster-Write; bei fehlendem Nachbarn `NSSound.beep()`. Core-Tests prüfen alle vier Richtungen mit nur einem Monitor. Systemton und ausbleibende AX-Schreibzugriffe manuell auf macOS prüfen. |
| AC-7: tatsächlichen Frame begrenzen; zu große Mindestgröße oben links | `AXWindow.setFrame` begrenzt zunächst den angeforderten Frame, liest nach dem letzten Resize den tatsächlichen Frame und verschiebt ihn ohne weiteres Resize. Wenn dessen Mindestgröße in einer Dimension nicht passt, wird der ganze Frame oben links verankert. Ziel-`axVisibleFrame` wird bei Snap und Monitorwechsel explizit übergeben. Core-Tests prüfen Verschieben, Verkleinern, negative Ursprünge, passende Mindestgröße und zu große Frames in einer/beiden Dimensionen. |
| AC-8: bisheriges Ein-Monitor-Rand- und ⌃⌥-Pfeilverhalten | `KeyboardSnap.action`, `HorizontalSide` und die bestehende Up/Down-Zustandsmaschine bleiben erhalten. Ein-Monitor-Test vergleicht alle bisherigen Rand-Zielarten mit dem Resolver ohne Monitorliste; bestehende EdgeSnapResolver- und KeyboardSnap-Tests bleiben enthalten. Erfolgreicher Testlauf steht aus. Die neue Frame-Begrenzung gilt auch hier (siehe Klarstellung). |

### Geometrie- und UX-Regeln

- Alle Funktionen arbeiten in AX-Koordinaten, Ursprung oben links am Hauptschirm,
  y nach unten. Rand-Snapping/Nachbarn verwenden volle Bildschirmframes,
  Fensterübertragung und Begrenzung die sichtbaren Frames.
- Nachbarschaft setzt Kantenabstand höchstens 1 pt und mindestens 1 pt gemeinsame
  Länge voraus. Reine Eckberührung zählt nicht. Bei mehreren Nachbarn gewinnt
  die längste gemeinsame Kante, dann die geringste Entfernung der Mittelpunkte
  quer zur Bewegungsrichtung, dann geometrische Reihenfolge. Kein Umlauf.
- Nur tatsächlich gemeinsame Abschnitte sind innere Kanten. Deren Endpunkte
  sind inklusiv, damit dort kein anderes Eck-Ziel entsteht. Außenabschnitte
  versetzter Displays bleiben nutzbar. Pflichtfall 32:9 neben Hochkant enthalten.
- Manuell veränderte Fenster mit veraltetem Snap-Record werden als freie Frames
  übertragen. Der ursprüngliche Restore-Frame bleibt im Snap-Record erhalten;
  die bestehende Restore-Aktion wird nicht neu definiert.

### Klarstellungen und nicht erfüllbare Nachweise

- AC-4 verlangt relative Übertragung, das Gesamtziel/AC-7 zugleich vollständige
  Begrenzung. Für bereits außerhalb liegende oder zu große Ausgangsframes hat
  Begrenzung Vorrang vor mathematisch exakter relativer Position/Größe.
- „Genau wie heute“ in AC-8 kann nicht zugleich das bisherige Überragen bei
  App-Mindestgrößen und die in AC-7 verlangte Korrektur bedeuten. Unverändert
  bleiben Snap-Zielwahl und die bestehenden Tastaturaktionen; die ausdrücklich
  geforderte Frame-Korrektur wirkt auch mit nur einem Monitor sowie bei anderen
  Aufrufern von `AXWindow.setFrame`.
- Die Issue-Vorgabe „je Teilschritt ein Commit und Draft-PR“ wird von der späteren
  Arbeitsanweisung „Do NOT commit, push or create branches“ begrenzt. Daher
  erfolgt die Lieferung ausschließlich als lokaler Patch.
- Ein ausgeführter roter Testlauf, grüne Swift-Tests, App-Kompilation,
  macOS-CI-Nachweis und manuelle Monitorprüfungen sind hier wegen Linux ohne
  Swift/Xcode/AppKit und der Ausführungssperre **nicht erbracht**.
- Der Lokalisierungs-Gesamtcheck ist wegen fehlendem `plutil` **nicht grün**.

## Testgetriebenes Vorgehen und QS

1. Zuerst `Tests/SnaplineCoreTests/ScreenGeometryTests.swift` angelegt, danach
   in `Sources/SnaplineCore` nach der neuen API gesucht: `ScreenGeometry`,
   `SnapDirection.allCases` und der neue Resolver-Parameter fehlen im Baseline-Code.
   Erst anschließend Produktionscode implementiert. Das ist ein statischer
   API-Fehlstellen-Nachweis, **kein ausgeführter Rot-Lauf**. Die zwei zusätzlichen
   Endpunkt-Assertions wurden vor der entsprechenden Fallback-Korrektur ergänzt.
2. Zwölf Swift-Testing-Tests (acht Geometrie-, vier Multi-Monitor-Edge-Tests),
   unveränderte bestehende EdgeSnapResolver- und KeyboardSnap-Tests.
3. `command -v swift` und `command -v plutil`: beide nicht vorhanden.
   Weder Swift-Tests noch App/Build-/Installationsskripte ausgeführt.
4. `git diff --check`: erfolgreich.
5. `TMPDIR=/tmp/opencode bash scripts/check-localizations.sh`: Exit 1;
   ausschließlich fehlendes `plutil` in allen zehn Sprachen gemeldet.
   Keine gemeldeten fehlenden/zusätzlichen/doppelten Schlüssel, Format- oder
   Platzhalterfehler. Ein neuer Menüschlüssel in allen zehn Sprachen, beide
   README-Tabellen und Mehr-Monitor-Abschnitte ergänzt.
6. Statischer Diff-Review: explizite Zielbounds bei Snap/Transfer; Korrektur erst
   nach letztem Größen-Write; keine fremden PR-Inhalte; vorhandene Hotkeys und
   Ausschluss-/Standardfenster-/Fullscreen-Guards erhalten. Zonen-Spans behalten
   ihren Fallback auf die angeklickte Zone auch bei leerer Highlight-Auswahl.

## Ausstehender macOS-Nachweis

1. In einer separaten macOS-Arbeitskopie des Ausgangscommits nur die neue
   Testdatei übernehmen. `swift test --filter ScreenGeometryTests` und
   `swift test --filter MultiMonitorEdgeSnapTests`: erwarteter Baseline-Fehler
   sind die fehlenden APIs. Für einen Assertion-Rot-Nachweis können die neuen
   API-Signaturen dort mit dem bisherigen Verhalten implementiert werden:
   alle Kanten außen, keine vertikalen Nachbarn, keine Frame-Begrenzung.
   Das wurde hier nicht ausgeführt und ist kein vorhandener Nachweis.
2. Vollständigen Patch anwenden; beide Filter erneut ausführen, anschließend
   `swift test` (einschließlich bestehender Edge-/Keyboard-Tests) und
   `scripts/check-localizations.sh`. App zusätzlich auf macOS kompilieren,
   z. B. mit `swift build`. Ergebnisse im Review hinterlegen.
3. Monitore nebeneinander, links mit negativem x, übereinander mit negativem y,
   mit Höhenversatz und 32:9 neben Hochkant anordnen. Fenster langsam über beide
   Seiten der gemeinsamen Kanten einschließlich Endpunkten ziehen: keine
   Vorschau, kein Maximieren, keine Snap-Leiste. Außenabschnitte weiter prüfen.
4. Snap-Leiste an einer Außenkante öffnen und dann über eine gemeinsame Kante
   beziehungsweise auf einen anderen Bildschirm ziehen: altes Ziel/Leiste weg.
5. Freies Fenster per ⌃⌥⇧ + Pfeil in jede Richtung schicken. Relative Position
   und Größe anhand der sichtbaren Bereiche vergleichen. Mit Zone, halber
   Spalte, Maximieren, Custom-Zone und verbundenen Zonen wiederholen; Gap > 0
   und 0 prüfen. Danach manuell bewegen/verkleinern: keine alte Zone erzwingen.
6. Ohne Nachbarn (auch mit nur einem Monitor) neue Aktion auslösen:
   Frame unverändert, Systemton. Bestehende ⌃⌥←/→ und ⌃⌥↑/↓ prüfen.
   Ausgeschlossene Apps, nicht-standardmäßige und Fullscreen-Fenster werden
   auch von der neuen Aktion nicht bewegt.
7. App mit Mindestgröße (z. B. Systemeinstellungen) auf eine kleine Zone/einen
   kleinen Monitor snappen und verschieben. Passt die tatsächliche Größe in
   den sichtbaren Bereich, alle Kanten innerhalb; sonst ganzer Frame bündig
   oben links. Auch Apps mit verzögerter AX-Frame-Rückmeldung prüfen.

## CI und PR-Abhängigkeiten

Im Checkout existiert ausschließlich `.github/workflows/release.yml`; dessen
macOS-Job enthält `swift test`, läuft aber bei Tags/manuellem Release-Workflow
und ist kein PR-QS-Gate. Dieser Workflow wurde nicht ausgelöst. Der verlangte
macOS-CI-Nachweis bleibt offen; eine allgemeine PR-CI gehört nicht zu diesem
Geometrie-Issue. Ob ein entsprechender offener PR existiert, ist wegen des
gesperrten GitHub-Zugriffs unbekannt. Die Implementierung benötigt keinen
fremden PR-Code und baut ausschließlich auf dem genannten Baseline-Commit auf.
