# Issue #20: Workflow-Härtung (SHA-Pinning, Rechte je Job, persist-credentials)

## Grundlage und Lieferstand

- Ausgangsstand: sauberer Arbeitsbaum auf `origin/main` (`3c17b64`).
- Grundlage ist das strukturierte Issue-Formular (AC-1 bis AC-7). Die
  `gh`-Aufrufe für Kommentare und offene PRs sind durch die Tool-Rechte
  gesperrt: **Kommentare und offene PRs sind nicht verifiziert** und vor dem
  Review mit GitHub abzugleichen. `AGENTS.md`, `CLAUDE.md` und `CONTRIBUTING.md`
  fehlen im Checkout.
- Lieferung als uncommitteter Patch. Kein Branchwechsel, kein Commit, Push,
  Cherry-Pick oder PR. Es werden keine Abhängigkeiten hinzugefügt.

## Änderungen

- `.github/workflows/ci.yml`: `actions/checkout` ist auf eine Commit-SHA gepinnt
  und nutzt `persist-credentials: false`. Der neue Schritt
  `Check workflow hardening` führt `scripts/check-workflows.py` aus.
- `.github/workflows/release.yml`:
  - Workflow-Rechte `contents: read`, `concurrency: release-${{ github.ref }}`
    ohne `cancel-in-progress`, damit ein laufender Publish nicht abbricht.
  - Job `build` (macOS 15, `contents: read`): Checkout ohne gespeicherte
    Zugangsdaten. Versionsprüfung, Keychain/Signatur, Test, Build,
    Signaturprüfung und Package sind unverändert. Der Schritt `Keep manual build`
    ist unverändert, abgesehen vom SHA-Pin. Bei Tags lädt der Build-Job zusätzlich
    `Snapline-<tag>.zip` und `checksum.txt` als Artefakt `release-package` hoch
    (`retention-days: 1`).
  - Job `publish` (`needs: build`, `if: github.ref_type == 'tag'`,
    `contents: write`, `ubuntu-latest`, 10 Minuten): kein Checkout, keine
    Signatur-Secrets. Er nutzt `download-artifact`, prüft per
    `sha256sum --check` die übernommene Datei gegen `checksum.txt` und ruft
    `gh release create` mit `GH_REPO`. Die Notes-Logik ist unverändert.
  - Zwei `# shellcheck disable=`-Kommentare stehen in bestehenden Skripten
    (gewollte Wortaufteilung bei `security list-keychains`, Backticks im
    `printf`-Format). Damit meldet actionlint keine Fehler. Der Notes-Text bleibt
    unverändert.
- `scripts/check-workflows.py` (nur Standardbibliothek): Regressionstest für
  AC-1 bis AC-5.

Gepinnte Versionen (SHAs per `git ls-remote` ermittelt, Major-Versionen beibehalten):

| Action | Version | SHA |
|---|---|---|
| actions/checkout | v5.1.0 | `fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09` |
| actions/upload-artifact | v4.6.2 | `ea165f8d65b6e75b540449e92b4886f43607fa02` |
| actions/download-artifact | v4.3.0 | `d3f86a106a0bac45b974a628896c90dbdf5c8093` |

## Nachweise (lokal, Linux)

- Vor dem Fix schlägt `python3 scripts/check-workflows.py` mit 26 Fehlern fehl,
  unter anderem bei Pinning, `persist-credentials`, Jobs und `concurrency`.
  Nach dem Fix: `Workflows OK`. Mutationsproben erkennen gezielte Verstöße
  zuverlässig: fehlende Pins, `persist-credentials: true`, fehlendes
  `needs`/`GH_REPO`/`concurrency`, einen Checkout oder Signatur-Secrets im
  Publish-Job.
- AC-6: `rhysd/actionlint:1.7.12` (Docker, mit shellcheck) meldet 0 Fehler.
  Auf `main` gab es vorher 2 shellcheck-Befunde. YAML lässt sich mit PyYAML
  parsen. Die Jobs `build` und `publish` sind korrekt über `needs` verbunden.
- AC-4: Die `run`-, `env`- und `if`-Blöcke aller übernommenen Schritte wurden
  per YAML-Vergleich gegen `main` geprüft und sind identisch. Abweichungen gibt
  es nur bei `GH_REPO` und dem auf Job-Ebene verschobenen `if` in Publish. Eine
  Simulation des Publish-Skripts erzeugte vorher und nachher byteidentische
  `notes.md`. `gh` wurde dafür durch `true` ersetzt.
- Kein macOS-Build und kein Swift-Test möglich. Die Workflows wurden nicht auf
  GitHub ausgeführt.

## Offene Punkte / Bitte an Leon

- **AC-7:** Bitte `Release` per `workflow_dispatch` starten. Erwartet werden das
  Artefakt `Snapline-manual` mit `Snapline-manual.zip`, ein übersprungener Job
  `publish` und keine Veröffentlichung. Der Tag-Pfad wird erst beim nächsten
  Release verifiziert.
- Verhalten bewusst beibehalten: Wie bisher veröffentlicht auch ein
  `workflow_dispatch` auf einer Tag-Ref, ohne Versionsprüfung, weil diese an
  `event_name == 'push'` hängt. Eine Änderung wäre außerhalb des Scopes.
- Der Publish-Job läuft auf `ubuntu-latest` statt macOS, weil er nur `gh`
  braucht und weniger Actions-Minuten kostet.
- Folge-Issue (laut Issue kein Blocker): Dependabot für `github-actions`, um
  die SHA-Pins aktuell zu halten.
