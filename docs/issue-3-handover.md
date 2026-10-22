# Issue #3 – Review-Handover

## Ausgangsstand und Grenzen

- Ausgangscommit: `84317c3d5f4fc596423b684d08f62294b2b8e5a6`; `HEAD` und die lokale Referenz `origin/main` waren identisch, Arbeitsbaum anfangs sauber.
- Keine Branchwechsel, Übernahmen fremder PRs, Commits oder Pushes. Lieferung als lokaler Diff inklusive neuer Dateien. Keine neuen App-/SwiftPM-Abhängigkeiten.
- Im ausgecheckten Repository wurden keine `AGENTS.md`, `CLAUDE.md` oder `CONTRIBUTING.md` gefunden. Die mitgelieferten Repository-Regeln wurden berücksichtigt.
- Der Versuch, Issue #3 mit Kommentaren und offene PRs über `gh` zu lesen, wurde durch die Harness-Berechtigungen abgelehnt. Grundlage ist deshalb der vollständige vom Auftraggeber mitgelieferte Issue-Text. Zusätzliche Kommentare, aktuelle Remote-Änderungen und offene PR-Abhängigkeiten sind **nicht verifiziert**. Keine bekannte Code-Abhängigkeit von einem offenen PR.
- Die abschließende Auftragsvorgabe verbietet Commit, Push und Branch-Erstellung und hat Vorrang vor der ursprünglichen Draft-PR-Lieferung. Kein PR angelegt, kein Merge, Release oder Deployment.

## Verbindliche Akzeptanzkriterien

Die strukturierte Issue-Fassung legt den eigenen Recorder ohne Paket und die bisherigen ⌃⌥-Standards fest. Die ursprünglichen offenen Fragen sind damit beantwortet. AC-5 bedeutet die bisherigen Modifier und Aktionen; die ausdrücklich gewünschte Z-Auflösung ersetzt den alten zusätzlichen Y-Hotkey. Layout-/Workspace-Gruppen behalten ihre physischen Zifferntasten, nicht zwingend das unmodifizierte Zeichen „1…9“ auf AZERTY.

| AC | Umsetzung | Nachweis / verbleibende Abnahme |
|---|---|---|
| 1 | Codable-Modell in SnaplineCore, UserDefaults-Persistenz, synchrone Änderungsbenachrichtigung; alte Carbon-Registrierungen werden vor neuen entfernt, alte Callback-IDs gelöscht | Modell-Rundreisetest geschrieben; sofortige Wirkung, Freigabe alter Taste und Neustart auf Mac prüfen |
| 2 | Registrierungs- und Event-Handler-Fehler erscheinen oben im Statusmenü mit Aktion, Kürzel und OSStatus; Klick öffnet Recorder | Rectangle-Konflikt und Warnungsaktion auf Mac prüfen |
| 3 | Recorder validiert Kandidaten vor Speicherung; Duplikate einschließlich aller neun Gruppentasten und fehlende Modifier werden mit Begründung abgelehnt | Swift-Testing-Regressionstests geschrieben; Recorder auf Mac prüfen |
| 4 | `.disabled` entfernt die Registrierung; keine Registrierung/Warnung für deaktivierte Aktionen | Codable-/Deaktivierungstests geschrieben; Löschen auf Mac prüfen |
| 5 | Zurücksetzen je Aktion und vollständig; Einzelreset wird bei internem Konflikt abgelehnt, vollständiger Reset stellt alle Standards wieder her | Standard-/Resettests geschrieben; UI auf Mac prüfen |
| 6 | TIS/UCKeyTranslate erzeugt Legenden und findet die unmodifizierte Z-Taste; Standard-Z wird beim Eingabequellenwechsel neu registriert, Fallback physisch ANSI-Z; aufgenommene Kürzel bleiben physisch | Core-Test mit QWERTZ-/AZERTY-Z-Keycodes geschrieben; echte Eingabequellenprüfung offen |
| 7 | Gemeinsame Anzeige für Menü, Layout-Editor-Seitenleiste/Hinweis und Recorder; deaktivierte Gruppen ohne Editor-Kürzel/Hinweis | Statischer Diff-Review; Menüanzeigen stehen als Text am Eintrag statt als zusätzliche AppKit-Key-Equivalents, um doppelte Auslösung zu vermeiden |
| 8 | Alle festen Kürzeltexte auf `%@` umgestellt, 24 neue Schlüssel in allen zehn Sprachen; Syntax-Fallback für Linux ohne `plutil` | `bash scripts/check-localizations.sh` erfolgreich: 10 Sprachen, je 121 Schlüssel, Syntax und Platzhalter konsistent |

## Testgetriebenes Vorgehen und ausgeführte QS

1. Zuerst `Tests/SnaplineCoreTests/ShortcutTests.swift` mit sieben `@Test`-Fällen erstellt.
2. Vor dem Modell-Fix in `Sources/` nach den getesteten Typen gesucht: `ShortcutSettings`, `ShortcutModifiers`, `ShortcutBinding` waren nicht vorhanden. Die Tests referenzierten damit nachweislich fehlende APIs.
3. **Keine ausgeführte Swift-Red-Phase und kein Swift-Green-Nachweis:** Der Server ist Linux ohne Swift/Xcode/AppKit. Gemäß Auftrag wurden weder App noch Swift-Tests gebaut oder ausgeführt. Der statische Befund ersetzt keinen tatsächlich fehlschlagenden Regressionstest.
4. Modell, Persistenz, Registrierung, Recorder und Anzeigen implementiert; anschließend Übersetzungen/Dokumentation ergänzt.
5. Lokalisierungsprüfung zunächst fehlgeschlagen: `plutil: command not found`. Schlüssel-/Platzhaltervergleich meldete keine Unterschiede. Für AC-8 wurde `scripts/lint-strings.py` als Python-Standardbibliothek-Syntaxfallback ergänzt; macOS nutzt weiterhin `plutil`.
6. Erfolgreich: `bash scripts/check-localizations.sh`, `bash -n scripts/check-localizations.sh`, `git diff --check`.
7. Python-Syntaxfallback separat geprüft: gültige Kommentare/escapte Zeichen akzeptiert, fünf fehlerhafte Tabellen (fehlendes Semikolon, fehlendes Gleichzeichen, offener Kommentar/String, ungültiger Escape) abgelehnt.
8. Manueller statischer Review der neuen Swift-Dateien und des Integrationsdiffs; keine Swift-Kompilation bestätigt.

## macOS-Abnahme vor Freigabe

Mit Xcode/Swift einschließlich Swift Testing auf macOS:

```bash
swift test --filter ShortcutTests
swift build
bash scripts/check-localizations.sh
```

- Rectangle mit überlappenden Standard-Hotkeys starten, Snapline starten: Warnung nennt Aktion und Kürzel, Klick öffnet Recorder. Konflikt beheben und erneut registrieren (z. B. Kürzel neu speichern).
- Links-Kürzel aufnehmen: nur neue Taste löst aus, alte Taste frei. App neu starten: neue Belegung bleibt.
- Bereits belegte Richtung sowie eine Taste der Layout-/Workspace-Gruppe aufnehmen: Ablehnung ohne Änderung. Taste ohne Modifier ebenfalls ablehnen; Caps Lock/Fn zählen nicht als Modifier.
- Kürzel löschen: Aktion ohne Hotkey und ohne Warnung. Einzelreset und Gesamtreset prüfen, einschließlich Konflikt eines Einzelresets mit anderer angepasster Belegung.
- Gruppenkürzel aufnehmen: Modifier gemeinsam drücken und nacheinander loslassen. Die gesamte Kombination bleibt erhalten; alle neun Tasten prüfen.
- Aufnahme mit Esc/Button abbrechen, Fenster schließen oder andere App fokussieren: Hotkeys wieder aktiv. Während Aufnahme keine Snapline-Aktion.
- Deutsch/QWERTZ und Französisch/AZERTY aktivieren: Standard-Flyout über die mit Z beschriftete Taste; alte Standard-Taste frei. Selbst aufgenommenes Flyout bleibt physisch, Legende ändert sich.
- Menüanzeigen, Recorder sowie bereits offener Layout-Editor folgen Änderungen/Eingabequelle. Gruppen deaktivieren: keine irreführenden Editor-Kürzel oder Aktivierungshinweise.
- Recorder in langen Übersetzungssprachen visuell prüfen; Fensterbreite berücksichtigt die intrinsische Breite der lokalisierten Buttons.
- Fehler nach einem Layoutwechsel, der einen internen Konflikt des Standard-Z mit einer aufgenommenen Taste erzeugt, erscheinen als Registrierungswarnung; durch Änderung/Löschen oder Gesamtreset auflösen.

AC-1 bis AC-7 sind implementiert, aber auf diesem Server nicht zur Laufzeit abgenommen. AC-8 ist hier erfolgreich geprüft. Vollständiger Issue-/PR-Review und die macOS-Nachweise bleiben ausdrücklich offen.
