# Issue #7: Display-spezifische Layouts – Paket 1

## Grundlage und Lieferstand

- Ausgangsstand: sauberer Arbeitsbaum, `HEAD` identisch mit lokalem `origin/main`:
  `96796247d65fdb01fcf6ae051e8fee1c60ae0f57`.
- Verbindliche Grundlage ist das mitgelieferte strukturierte Issue-Formular:
  Paket 1 umfasst ausschließlich Core-Modell, reine Listenberechnung und Tests.
  Die weitergehenden App-/Editor-Anforderungen der ursprünglichen Beschreibung
  sind durch die Paketaufteilung den Folgepaketen 2 und 3 zugeordnet.
- Die GitHub-Aufrufe zum vollständigen Thread samt Kommentaren und zu offenen
  PRs wurden von den Tool-Berechtigungen gesperrt. **Live-Thread, offene PRs und
  Aktualität des lokalen Remote-Stands sind nicht verifiziert.** Vor Review
  müssen sie mit GitHub abgeglichen werden.
- `AGENTS.md`, `CLAUDE.md` und `CONTRIBUTING.md` fehlen im Checkout. Geprüft wurden
  die relevanten Core-/Store-Sources, bestehenden Core-Tests, `README.md`,
  `PLAN.md`, `Package.swift`, Lokalisierungsskript, Release-Workflow und das
  Issue-6-Handover. `kb ask` zu Entscheidungen/Regeln/Abhängigkeiten lieferte
  Leons Delegation der UX-Empfehlung, keine zusätzlich verifizierten Kommentare
  oder offenen PRs.
- Lieferung als uncommitteter Patch auf dem vorhandenen Checkout. Kein
  Branchwechsel, keine Branch-Erstellung, kein Cherry-Pick, Commit, Push oder
  PR. Keine fremden PR-Inhalte oder neuen Dependencies.

## API und Integrationsvertrag

```swift
LayoutCatalog.visibleLayouts(
    for: screenClass,
    displayID: displayKey,
    custom: customLayouts,
    hiddenBuiltInIDs: hiddenIDs,
    order: orderedIDs
)
```

- `CustomLayout.displayIDs: [String]?` enthält stabile Display-UUID-Strings
  (`NSScreen.displayKey`), keine numerischen `CGDirectDisplayID`-Werte.
- `CustomLayout.screenClasses: [ScreenClass]?` und UUIDs werden per ODER
  verknüpft. Beide nil/leer bedeutet global. Eine leere Seite hebt eine
  Einschränkung auf der anderen Seite nicht auf.
- `ScreenClass` codiert seine bestehenden String-Rohwerte. Die synthetisierte
  `CustomLayout`-Codable-Konformität decodiert fehlende optionale Felder als nil;
  ein eigener Decoder oder eine Änderung am layouts.json-Arrayformat ist unnötig.
- Die Funktion bezieht unveränderte Vorlagen aus `builtIn(for:)`, filtert eigene
  Layouts und blendet ausschließlich Vorlagen aus. Standardreihenfolge:
  passende eigene Layouts in Eingabereihenfolge, dann Vorlagen ihrer Klasse.
- `order` ordnet bekannte sichtbare IDs; unbekannte, ausgeblendete und nicht
  zugeordnete IDs werden ignoriert. Wiederholte Reihenfolge-IDs werden nur
  einmal verwendet. Nicht aufgeführte Layouts folgen in Standardreihenfolge.
- Kein gespeicherter Zustand wird gelesen oder verändert. Ausblendung und
  Reihenfolge betreffen ausschließlich den jeweiligen Funktionsaufruf.

### Präzisierungen der Kriterien

1. **AC-2 vs. AC-4:** Stabile bisherige Positionen und neue eigene Layouts am
   Ende sind garantiert, wenn `order` alle bisher sichtbaren IDs enthält.
   Bei einer unvollständigen Reihenfolge gilt AC-4: fehlende Einträge werden
   in Standardreihenfolge angehängt. Ohne vorherige vollständige Liste kann
   die reine Funktion nicht zwischen neuen und bereits bestehenden, aber
   nicht aufgeführten Einträgen unterscheiden. Paket 2 muss die vollständige
   Ausgangsreihenfolge pro `displayKey` initialisieren und beim Hinzufügen
   neuer Layouts entsprechend fortschreiben. Ohne Reihenfolge hat die
   rückwärtskompatible Reihenfolge aus AC-6 Vorrang.
2. **AC-3 vs. AC-5:** Würden Zuordnung und Ausblendung alles entfernen, hat
   Nicht-Leerheit Vorrang. Genau die erste Vorlage der Klasse wird zurückgegeben,
   auch wenn sie ausgeblendet ist. Ein unpassendes eigenes Layout wird niemals
   als Fallback sichtbar. Ist mindestens ein eigenes Layout sichtbar, werden
   keine ausgeblendeten Vorlagen zurückgeholt.

## Akzeptanzkriterien und Testabdeckung

Die Tabelle beschreibt Implementierung und geschriebene Tests, **keine
bestandenen Swift-Testläufe**. Neue Datei: `Tests/SnaplineCoreTests/VisibleLayoutTests.swift`.

| Kriterium | Umsetzung / Tests |
|---|---|
| AC-1: UUID-/Klassenfilter, ohne Zuordnung überall | Tests für UUIDs, alle vier Klassen, ODER-Verknüpfung, nil/leere Listen sowie einseitig leere Zuordnung. |
| AC-2: bestehende Positionen stabil, neue Layouts ans Ende | Test für alle Klassen mit umgekehrter vollständiger Ausgangsreihenfolge und zwei neuen Layouts, auch bei Einfügen vorne in der Custom-Eingabe. Voraussetzung siehe oben. |
| AC-3: Vorlagen ausblenden, andere Aufrufe unabhängig | Ausblenden einer Vorlage; eigene/unbekannte IDs in der Ausblendliste haben keinen Effekt; andere UUID und erneuter Aufruf ohne Ausblendung bleiben unverändert. Fallback-Ausnahme siehe oben. |
| AC-4: Reihenfolge, unbekannte IDs ignorieren, fehlende anhängen | Gemischte Reihenfolge aus eigenen Layouts/Vorlagen, unbekannte und doppelte IDs, leere Reihenfolge; Reihenfolge kann ausgeblendete/unpassende Layouts nicht zurückholen. |
| AC-5: nie leer | Für alle Klassen: alle Vorlagen ausgeblendet, Custom unpassend oder fehlend; genau erste Vorlage als Fallback. Separater Test mit verbleibendem eigenen Layout. |
| AC-6: alte JSON laden, Zuordnung nil, bisherige Liste | Festes altes JSON-Array mit Blatt und Splitbaum, ohne neue Felder; für alle Klassen und zwei UUIDs Vergleich mit bisheriger Core-API. |
| AC-7: Codable-Rundreise | Alle Klassen mit unveränderten Rohwerten; Custom-Array mit UUID-, Klassen-, kombinierter, leerer und fehlender Zuordnung sowie Splitbaum. |
| AC-8: neue und bestehende Tests in macOS-CI grün | **Offen:** Tests wurden hier nicht ausgeführt; kein macOS-CI-Nachweis verfügbar. Bestehende Tests unverändert. |

## Testgetriebenes Vorgehen und QS-Nachweise

1. Zuerst die neue Testdatei mit 14 Swift-Testing-Tests angelegt, sechs davon
   über alle vier Klassen parametrisiert (32 Testfälle).
2. Vor jeder Produktionsänderung im Core nach `visibleLayouts`, `displayIDs`,
   `screenClasses` und der `ScreenClass`-Deklaration gesucht. Die Funktion und
   Zuordnungsfelder fehlten, `ScreenClass` war nicht Codable. Auf der Baseline
   können die neuen Tests damit nicht kompilieren. Das ist ein **statischer
   Fehlstellen-Nachweis, kein ausgeführter Rot-Lauf**.
3. Erst danach drei Core-Dateien geändert: Codable-Konformität, zwei optionale
   Modellfelder mit rückwärtskompatiblen Initializer-Defaults, Listenfunktion.
4. `command -v swift` und `command -v plutil`: beide nicht vorhanden. Gemäß
   Linux-/Ausführungsvorgabe keine Swift-Tests oder App-Builds ausgeführt.
5. `git diff --check`: erfolgreich; neue, ungetrackte Dateien zusätzlich per
   `git diff --no-index --check -- /dev/null <Datei>` geprüft.
6. `TMPDIR=/tmp/opencode bash scripts/check-localizations.sh`: Exit 1,
   ausschließlich fehlendes `plutil` in allen zehn Sprachen gemeldet. Keine
   gemeldeten Schlüssel-, Format- oder Platzhalterfehler. Keine UI-/Textänderungen.
7. Statischer Review: alte Core-API und Vorlagen erhalten, Filter vor Reihenfolge,
   kein globaler Zustand, Fallback nur bei leerer Liste, optionale Codable-Felder,
   unveränderte Store-Aufrufe weiterhin quellkompatibel.

## Ausstehende Verifikation und Folgepakete

- In einer separaten macOS-Arbeitskopie der Baseline zuerst nur die neue
  Testdatei anwenden und `swift test --filter VisibleLayoutTests` ausführen:
  erwarteter Fehler sind die fehlenden APIs/Codable-Konformität. Anschließend
  den vollständigen Patch anwenden und denselben Filter erneut ausführen.
- Danach auf macOS `swift test` für AC-8 und `scripts/check-localizations.sh`
  ausführen und die Ergebnisse im Review hinterlegen. Weder ein tatsächlicher
  roter noch ein grüner Testlauf ist Bestandteil dieses lokalen Nachweises.
- Der Checkout enthält ausschließlich `.github/workflows/release.yml` mit
  `swift test` auf `macos-15`. Er läuft bei Tags/manuell, nicht bei Push/PR.
  Er wurde nicht ausgelöst. Ein reguläres macOS-PR-Testgate gehört zum separaten
  CI-Issue #2; dessen PR-/Lieferstand ist wegen gesperrtem GitHub-Zugriff unbekannt.
  **Keine Code-Abhängigkeit von einem offenen PR** für diese Core-Lieferung.
- Paket 2: Store-Anbindung, Präferenzen pro `displayKey`, vollständige
  Ausgangsreihenfolge sichern/fortschreiben. Paket 3: Editor-Zuordnung,
  Ausblenden/Umsortieren und lokalisierte UI. Diese Folgepakete sind nötig,
  damit die Core-Funktion in Flyout, Menü, Drag und Kürzeln wirksam wird.
- Der manuelle Zwei-Display-Test ist laut Paket-1-Formular erst nach Paket 3
  vorgesehen. Keine App-/Release-/Deploy-Skripte, Produktionsdaten oder
  Produktionsdienste wurden verwendet.
