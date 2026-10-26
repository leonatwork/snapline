# Issue #3 – Konfigurierbare Tastenkürzel

## Grundlage und Lieferstand

- Ausgangsstand: sauberer Arbeitsbaum, `HEAD` identisch mit lokalem `origin/main`:
  `acb87f03d947ddc063ed9c6d121eba8c358def22`.
- Grundlage ist der vollständig mitgelieferte strukturierte Issue-Text samt
  ursprünglicher Beschreibung. Der Versuch, den Live-Thread inklusive Kommentare
  und offene PRs mit `gh` zu lesen, wurde durch Tool-Berechtigungen gesperrt.
  **Live-Kommentare, offene PRs und Aktualität des lokalen Remote-Refs sind nicht
  verifiziert.** Vor Review auf GitHub abgleichen.
- `AGENTS.md`, `CLAUDE.md` und `CONTRIBUTING.md` sind im Checkout nicht vorhanden.
  Berücksichtigt: mitgelieferte Repository-Regeln, `Package.swift`, bestehende
  Core-Tests, betroffene App-/Controller-/Editor-Sources, Lokalisierungsskript,
  README, PLAN, vorheriges Handover sowie `.github/workflows/ci.yml` und
  `release.yml`. `kb ask` lieferte die bereits mitgelieferte Standbeschreibung.
- Ein zusammenhängender, uncommitteter Patch auf dem vorhandenen Checkout.
  Kein Branchwechsel, kein neuer Branch, Cherry-Pick, Commit, Push oder PR.
  Die spätere ausdrückliche Vorgabe „Do NOT commit, push or create branches“
  bestimmt die Lieferung; der im Issue gewünschte Draft-PR ist nicht erstellt.
- Keine SwiftPM-Abhängigkeiten hinzugefügt. Keine Deployments, Produktionsdaten,
  Supabase-Zugriffe, Releases oder Release-Workflow-Ausführung.
- Keine Lösungsteile aus offenen PRs übernommen. Keine bekannte Code-Abhängigkeit
  von einem offenen PR; dessen tatsächlicher Stand konnte nicht geprüft werden.

## Implementierung und Entscheidungen

- `Sources/SnaplineCore/Shortcuts.swift`: Codable-Belegungen mit physischem
  Tastencode, Carbon-kompatiblen Modifiern, deaktiviertem Zustand sowie getrennten
  Varianten für layoutabhängiges Standard-Z und feste Zifferngruppen. Nur
  Abweichungen vom Standard werden gespeichert.
- `Settings.shortcuts`: JSON-Data in UserDefaults unter `shortcuts`; fehlende oder
  nicht decodierbare Daten ergeben die Standardbelegung. Eine synchrone lokale
  Notification löst die Neuregistrierung aus.
- `HotKeyCenter`: alte Registrierungen und Handler entfernen, neue OSStatus-Werte
  einschließlich Fehlern beim Installieren des Event-Handlers zurückgeben. IDs
  werden nicht wiederverwendet, damit alte wartende Events keine neue Aktion treffen.
- `KeyboardController`: Änderungen und Eingabequellenwechsel registrieren sofort
  neu. Fehlgeschlagene Registrierungen bleiben mit Aktion, Kürzel und Status
  verfügbar. Deaktivierte Belegungen werden nicht registriert.
- `ShortcutRecorderController`: eigenes AppKit-Fenster aus dem Kürzel-Untermenü
  und allen Kürzel-Warnungen. Aufnehmen, Löschen, einzelnes Zurücksetzen sowie
  „Auf Standard zurücksetzen“. Fehler erklären fehlende Modifier oder die andere
  belegende Aktion; sie bleiben auch nach Loslassen der Modifier sichtbar.
- Während der Aufnahme werden Carbon-Kürzel vorübergehend freigegeben, damit
  bestehende Snapline-Belegungen beim Recorder ankommen. Aufgenommene Events
  werden konsumiert. Erfolg, Esc, Fensterschließen oder Fokusverlust beenden die
  Aufnahme und registrieren wieder. Das Fenster allein deaktiviert keine Kürzel.
- Zifferngruppen: gewünschte Modifier halten und mit einer Taste bestätigen.
  Die bestätigende Taste wird nicht gespeichert; alle neun bisherigen physischen
  Zifferntasten bleiben fest. Kein Modifier ist auch für Gruppen unzulässig.
- Bereits in Main vorhandene Monitorwechsel-Kürzel bleiben unverändert und sind
  bei der Konfliktprüfung reserviert. Es gibt keine neue Monitoraktion und keine
  zusätzliche konfigurierbare Aktion außerhalb des Issues.
- `ShortcutLabels`: `TISCopyCurrentKeyboardLayoutInputSource` und `UCKeyTranslate`
  liefern die Zeichen. Standard-Flyout sucht unmodifiziertes Z (US-Z-Fallback);
  aufgenommene Flyout-Kürzel bleiben physisch fest. Sondertasten haben Symbole.
  Menü, Recorder und Layout-Editor aktualisieren ihre Beschriftungen.
- Menü-Kürzel sind bewusst reine Beschriftungen am Eintrag, keine zusätzlichen
  AppKit-Key-Equivalents. Carbon bleibt der einzige globale Dispatcher; dadurch
  interpretiert AppKit AZERTY-Ziffernzeichen nicht als andere physische Tasten und
  deaktivierte/alte Belegungen bleiben nicht als Menü-Kürzel wirksam.
- Alle geänderten festen Kürzeltexte verwenden vollständige `%@`-Platzhalter;
  21 neue Schlüssel in allen zehn Sprachen. README in Englisch/Deutsch beschreibt
  Standards, Konfiguration, Konflikte und Tastaturlayouts; PLAN aktualisiert.
- Das Lokalisierungsskript nutzt weiterhin `plutil`, wo vorhanden. Ohne Apple-Tools
  prüft Python 3 mit seiner Standardbibliothek die hier verwendete `.strings`-
  Syntax. Schlüssel-, Duplikat- und Platzhalterprüfungen bleiben bestehen.

## Verbindliche Akzeptanzkriterien

Die Tabelle beschreibt den Patch, **keine bestandenen macOS-Laufzeittests**.

| AC | Umsetzung / Nachweis |
|---|---|
| 1: Neues Kürzel sofort, altes frei, Neustart persistent | Abmelden vor Registrierung, Settings-Notification, UserDefaults. Core-Test für physische Belegung/Codable. App-Neustart und tatsächliche Auslösung auf Mac offen. |
| 2: Registrierungsfehler oben mit Namen, Klick öffnet Recorder | OSStatus-Fehlerliste, Warnung mit Aktion und Kürzel, Recorder-Selector, Status im Tooltip. Rectangle-Nachweis auf Mac offen. |
| 3: Interne Doppelbelegung und kein Modifier ablehnen, Grund nennen | Core-Validierung aller neun Gruppentasten und reservierter Monitor-Kürzel; Recorder-Fehlertexte. Regressionstests für Doppelbelegung, Gruppen, layoutabhängiges Z und leere Modifier. |
| 4: Löschen deaktiviert, keine Warnung | Explizit `.disabled`, leere aufgelöste Kürzelliste, nach Änderung neue Fehlerliste. Tests für Deaktivierung, Codable und Freigabe der Belegung. |
| 5: Standard wieder ⌃⌥ | Einzel-Reset validiert gegen andere aktuelle Belegungen; globaler Reset stellt sämtliche Standards wieder her, Arbeitsbereiche zusätzlich ⇧. Standard-/Reset-Tests. |
| 6: QWERTZ/AZERTY Standard-Z und aktive Beschriftungen | Layoutübersetzung und Eingabequellen-Notification; Tests mit Z-Keycodes 6/16/13 sowie unverändertem aufgenommenem physischem Keycode. Tatsächliche TIS-/Carbon-Integration auf Mac offen. |
| 7: Konfiguration in Menü, Editor-Seitenleiste/-Hinweis und Kürzelanzeigen | Gemeinsame dynamische Labels; deaktivierte Gruppen haben keine Nummernanzeige/keinen Aktivierungshinweis. Statische Prüfung der betroffenen Aufrufstellen; UI-Prüfung auf Mac offen. |
| 8: Zehn Sprachen und grünes Lokalisierungsskript | Lokal bestanden: zehn Sprachen, je 134 Schlüssel, gültige Syntax und passende Platzhalter. macOS-plutil-Lauf zusätzlich offen. |

Keine bekannten fachlichen Widersprüche zwischen den strukturierten ACs. Die
offenen Fragen der ursprünglichen Beschreibung sind durch die strukturierte
Entscheidung geklärt: eigener Recorder, keine Abhängigkeit, ⌃⌥ als Standard.
Nicht erfüllbar auf diesem Server sind der ausgeführte Swift-Rot-/Grün-Nachweis
und sämtliche macOS-Integrationstests. Live-Thread-Prüfung ist separat blockiert.

## Testgetriebenes Vorgehen und verfügbare QS

1. Zuerst `Tests/SnaplineCoreTests/ShortcutTests.swift` mit sechs `@Test`-Funktionen
   angelegt: Standards, Codable, Konflikte, fehlende Modifier, Deaktivierung/Reset,
   Modifier-Symbole. Danach nach den neuen Typen im Produktionscode gesucht:
   `ShortcutSettings`, `ShortcutModifiers`, `ShortcutChord` und `ShortcutAction`
   fehlten. Erst anschließend das Modell und die Integration implementiert;
   bei Review die Standard-Assertions weiter vervollständigt.
2. Auf der Baseline können diese Tests mangels APIs nicht kompilieren. Das ist
   **nur ein statischer Fehlstellen-Nachweis, kein ausgeführter Rot-Lauf**.
   Entsprechend der ausdrücklichen Linux-Regel keine Swift-/App-Builds oder
   Tests gestartet.
3. Erster Lauf `bash scripts/check-localizations.sh`: Exit 1 ausschließlich
   wegen fehlendem `plutil`. Nach Ergänzung des Linux-Fallbacks: Exit 0,
   `10 languages, 134 keys each, all files lint OK, placeholders match`.
4. `bash -n scripts/check-localizations.sh`: erfolgreich.
5. `git diff --check`: erfolgreich. Alle fünf neuen Dateien zusätzlich mit
   `git diff --no-index --check -- /dev/null <Datei>` geprüft: keine
   Whitespace-Fehler (Exit 1 bezeichnet hier den vorhandenen Datei-Diff).
6. Statischer Review: Carbon-Modiferbits, bestehende Ziffern-/Pfeilcodes,
   Lebenszyklus der Registrierung, konsumierte Recorder-Events, erhaltene
   Fehlertexte, physische Sonderbelegungen, gemeinsame Label-Aufrufstellen und
   sämtliche Lokalisierungsplatzhalter geprüft.

## Ausstehende macOS-Verifikation

### Review-Fix: Layoutwechsel bei inaktiver Menüleisten-App

- Ausschließlich den gemeldeten Observer-Befund korrigiert: `ShortcutLabels`
  hält jetzt einen Selector-Observer mit `.deliverImmediately`. Damit wird die
  lokale Layout-Notification auch bei suspendiertem DistributedNotificationCenter
  weitergeleitet und die bestehende Neuregistrierung sofort angestoßen.
- Vor dem Fix den Integrationstest in
  `Tests/SnaplineTests/ShortcutLabelsTests.swift` ergänzt. Er suspendiert den
  DistributedNotificationCenter wie AppKit bei Inaktivität, sendet die
  Eingabequellen-Notification **ohne** erzwungene Sofortzustellung und prüft den
  Empfang der lokalen Notification vor dem Aufheben der Suspendierung. Der
  vorherige `.coalesce`-Observer würde erst nach Ende der Suspendierung liefern.
  Das neue SwiftPM-Testtarget importiert dafür den tatsächlichen App-Code;
  Core-Tests können den AppKit-Observer nicht prüfen.
- Kein ausgeführter Swift-Rot-/Grün-Nachweis auf Linux möglich bzw. erlaubt.
  Auf macOS zuerst den Observer-Fix zurücknehmen und
  `swift test --filter ShortcutLabelsTests` ausführen (erwartet: fehlgeschlagene
  Empfangs-Assertion), dann mit Fix denselben Test wiederholen.
- Nach dem Review-Fix bestanden: `bash scripts/check-localizations.sh`
  (zehn Sprachen, je 134 Schlüssel), `bash -n scripts/check-localizations.sh`
  und `git diff --check`. Live-GitHub-Abgleich weiterhin durch Tool-Berechtigungen
  blockiert; kein Commit oder Push erfolgt.
- Zusätzlich manuell: Snapline im Hintergrund lassen, aus einer anderen App
  QWERTY → Französisch/AZERTY → Deutsch/QWERTZ wechseln. Ohne Snapline zu
  aktivieren muss jeweils ⌃⌥ plus die aktuell mit Z beschriftete Taste das Flyout
  öffnen; die vorige physische Standardtaste muss frei sein.

- Auf einer separaten Kopie der angegebenen Baseline zuerst nur die neue
  Testdatei anwenden, `swift test --filter ShortcutTests` ausführen und den
  erwarteten Fehler wegen fehlender APIs dokumentieren. Dann vollständigen Patch
  anwenden und denselben Filter erneut ausführen.
- Anschließend die vorhandenen CI-Schritte auf macOS prüfen: `swift build`,
  `swift test`, `scripts/check-localizations.sh`, ad-hoc App-Build und
  Signaturprüfung gemäß `.github/workflows/ci.yml`. CI ist bereits auf Main;
  kein Workflow wurde hier ausgelöst, keine CI-Ergebnisse liegen vor.
- Rectangle zuerst starten, Snapline starten, Warnungen mit Aktion/Kürzel prüfen
  und anklicken. Freies Kürzel aufnehmen: nur neues löst aus, altes ist frei;
  Snapline neu starten und gespeicherte Belegung bestätigen.
- Ohne Modifier sowie auf doppelte Pfeil-, Flyout-, letzte Gruppenziffer- und
  reservierte Monitorbelegung aufnehmen: Ablehnung mit bleibender Erklärung,
  vorherige Belegung unverändert. Esc, Fokusverlust und Schließen testen.
- Einzelbelegungen und beide Gruppen löschen: keine Auslösung, keine Warnung,
  keine falschen Menü-/Editor-Anzeigen. Einzel-Reset und globalen Reset prüfen.
- Eingabequelle während geöffneter Fenster auf Deutsch und Französisch wechseln:
  Standard-Z öffnet Flyout; alte Standard-Z-Position ist frei. Eigene physische
  Flyout-Belegung bleibt gleich, nur ihr Label ändert sich. Menü, Sidebar, Hinweis
  und Recorder prüfen, einschließlich AZERTY-Ziffernlabels und Gruppenkonflikten.
- In allen Sprachen Fensterbreite, Umbruch und alle Recorder-Buttons prüfen.
  Danach Live-Issue/PRs abgleichen und bei gewünschter Lieferung nur Draft-PR;
  kein Merge oder Release.
