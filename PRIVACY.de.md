# Datenschutz

*🇬🇧 [English version](PRIVACY.md)*

Snapline verwaltet Fenster lokal auf deinem Mac. Fensterdaten, Layouts,
Arbeitsbereiche und Diagnosedaten werden nicht über das Netzwerk übertragen.
Es gibt keine Telemetrie, Nutzungsanalyse oder automatische Übermittlung von
Debug-Logs. Links wie **Weitere Apps, die dir gefallen könnten** öffnen sich im
Browser; für den Besuch dieser Websites gelten deren Datenschutzhinweise.

## Lokal verarbeitete und gespeicherte Daten

- **Fensterverwaltung:** Snapline liest laufende Apps, Fenstertitel, Positionen,
  Größen und Bildschirmdaten, um Fenster zu finden, anzuordnen und
  wiederherzustellen. Für Snap-Gesten und Tastenkürzel beobachtet es Maus- sowie
  Tastatur-/Modifier-Ereignisse; ein Verlauf eingegebener Texte wird nicht
  gespeichert.
- **Layouts:** Namen eigener Layouts und Zonen-Geometrie liegen in
  `~/Library/Application Support/Snapline/layouts.json`.
- **Arbeitsbereiche:** Namen gespeicherter Anordnungen, App-Namen und
  Bundle-Kennungen, **Fenstertitel**, Bildschirmkennungen/-indizes und relative
  Fenstergeometrie liegen in
  `~/Library/Application Support/Snapline/workspaces.json`. Titel dienen beim
  Wiederherstellen zur Zuordnung gespeicherter zu geöffneten Fenstern. Snapline
  verschlüsselt diese JSON-Dateien nicht; Titel können Dokumentnamen oder andere
  persönliche Informationen enthalten.
- **Einstellungen:** Funktionsschalter, Abstände, Tastenkürzel, Bundle-Kennungen
  ausgeschlossener Apps und das aktive Layout pro Bildschirm werden über macOS
  UserDefaults gespeichert. Die Domain der installierten App lautet
  `io.github.leonatwork.snapline`; die zugehörige Datei ist normalerweise
  `~/Library/Preferences/io.github.leonatwork.snapline.plist`. macOS verwaltet
  außerdem den Anmeldestart und erteilte Berechtigungen.
- **Live-Vorschauen:** optionale Fenster-Vorschaubilder in Snap Assist werden mit
  ScreenCaptureKit erzeugt und im Arbeitsspeicher zwischengespeichert. Snapline
  speichert diese Bilder nicht auf der Festplatte; beim Beenden wird der
  Arbeitsspeicher-Cache gelöscht.
- **Optionales Debug-Log:** standardmäßig deaktiviert; aktivierbar nur mit
  `defaults write io.github.leonatwork.snapline debugLog -bool true` und einem
  anschließenden App-Neustart. Es enthält Zeitstempel und Snap-Diagnosen, etwa
  Fenstergeometrie/-IDs, Maus-/Ziehzustand, Modifier-Zustand, Layoutnamen und
  Bildschirmnamen. **Fenstertitel, Titel-Hashes und Fensterinhalte** werden nicht
  protokolliert. Dateien: `~/Library/Logs/Snapline/debug.log` und das einzige
  Backup `debug.log.1` im selben Ordner. Bei einem Log-Schreibzugriff erhalten
  neue und bestehende Log-Dateien Lese-/Schreibrechte nur für den Eigentümer
  (`0600`), auch ein bestehendes Backup. Überschreitet das aktuelle Log
  **1 MB (1.000.000 Bytes)**, wird es vor dem nächsten Schreiben nach
  `debug.log.1` verschoben und ersetzt das alte Backup. Genau am Limit wird noch
  ein Eintrag angehängt: Das Log kann das Limit um einen Eintrag überschreiten.
  Es gibt keine zeitgesteuerte Löschung. Logs älterer Versionen können weiterhin
  Titel enthalten; ein Update löscht deren Inhalte nicht und verkleinert ein
  übergroßes Backup nicht rückwirkend.

## Berechtigungen und ihr Zweck

- **Bedienungshilfen** sind erforderlich, um Fensterinformationen zu lesen,
  Fenster anderer Apps zu verschieben und zu skalieren sowie den Event Tap für
  Snapline-Gesten und das Flyout am grünen Knopf bzw. die Unterdrückung des
  nativen Menüs zu verwenden.
- **Bildschirmaufnahme** ist optional und dient ausschließlich den
  Live-Fenstervorschauen in Snap Assist. Ohne diese Berechtigung (oder bei
  deaktivierter Live-Vorschau) kann Snap Assist stattdessen App-Icons und
  Fenstertitel anzeigen.

Du kannst die Berechtigungen unter **Systemeinstellungen → Datenschutz &
Sicherheit → Bedienungshilfen / Bildschirmaufnahme** entziehen. Dadurch werden
gespeicherte Layouts, Arbeitsbereiche und Logs nicht gelöscht.

## Daten löschen

Beende Snapline vor dem Löschen von Dateien oder Zurücksetzen der Einstellungen,
damit die laufende App sie nicht erneut schreibt.

- Lösche einzelne Layouts oder Arbeitsbereiche über Snaplines Menü/Editor oder
  entferne `layouts.json` und/oder `workspaces.json` an den oben genannten Pfaden,
  um alle gespeicherten Einträge zu entfernen. Mit dem Ordner
  `~/Library/Application Support/Snapline/` löschst du beide Dateien.
- Entferne `~/Library/Logs/Snapline/`, um das aktuelle Log und sein Backup zu
  löschen, einschließlich etwaiger Titel aus älteren Versionen. Deaktiviere
  künftige Logs vor dem Neustart mit
  `defaults write io.github.leonatwork.snapline debugLog -bool false`.
  Deaktivieren allein löscht bestehende Logs nicht.
- Setze alle Snapline-Einstellungen bei geschlossener App mit
  `defaults delete io.github.leonatwork.snapline` zurück. Das setzt auch die
  Debug-Log-Aktivierung zurück, löscht aber keine Layouts oder Arbeitsbereiche.
- Schalte **Beim Anmelden starten** in Snapline aus oder entferne den Eintrag
  unter **Systemeinstellungen → Allgemein → Anmeldeobjekte**. Entziehe
  Berechtigungen separat wie oben beschrieben. Falls du **macOS-Kacheln jetzt
  ausschalten …** verwendet hast, kannst du diese Systemoptionen in
  **Schreibtisch & Dock** wieder aktivieren; das Zurücksetzen der
  Snapline-Einstellungen macht Änderungen an macOS' Einstellungen in
  `com.apple.WindowManager` nicht rückgängig.

Das Entfernen von `Snapline.app` allein löscht diese lokalen Dateien nicht. Leere
den Papierkorb, falls du Dateien dorthin verschoben hast. Exportierte, geteilte
oder in System-Backups enthaltene Kopien musst du separat löschen.
