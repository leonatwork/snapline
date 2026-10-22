#!/usr/bin/env bash
# Checks the UI translations in Resources/<lang>.lproj/Localizable.strings:
#   - every language exists and passes `plutil -lint`
#   - every language has exactly the keys of en.lproj (nothing missing, nothing extra)
#   - format placeholders (%@, %d) match en.lproj, so String(format:) can't crash
#   - every key used as L10n.tr("…") in Sources/ exists in en.lproj
set -euo pipefail
cd "$(dirname "$0")/.."

LANGS=(en de fr es it pt-BR nl ja zh-Hans ko)
BASE=Resources/en.lproj/Localizable.strings
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failed=0

# "key" = "value";  →  key<TAB>value (one entry per line, as the files are written)
entries() { sed -n 's/^"\([^"]*\)"[[:space:]]*=[[:space:]]*"\(.*\)";[[:space:]]*$/\1	\2/p' "$1"; }
placeholders() { grep -o '%[0-9$]*[@dDiuxXfs]' <<<"$1" | sort | tr -d '\n' || true; }
lint_strings() {
    if command -v plutil >/dev/null 2>&1; then
        plutil -lint -s "$1"
    else
        # Linux has no Apple plutil. Validate OpenStep string-table syntax with stdlib Python.
        python3 scripts/lint-strings.py "$1"
    fi
}

for lang in "${LANGS[@]}"; do
    file="Resources/$lang.lproj/Localizable.strings"
    if [ ! -f "$file" ]; then
        echo "✗ $lang: $file is missing"; failed=1; continue
    fi
    if ! lint_strings "$file"; then
        echo "✗ $lang: string-table syntax check failed"; failed=1
    fi
    entries "$file" | sort > "$WORK/$lang.tsv"
    # Every entry line must have been parsed (guards against odd formatting).
    declared=$(grep -c '^"' "$file" || true)
    parsed=$(wc -l < "$WORK/$lang.tsv" | tr -d ' ')
    if [ "$declared" != "$parsed" ]; then
        echo "✗ $lang: $declared entries, but only $parsed in the expected \"key\" = \"value\"; form"; failed=1
    fi
    dupes=$(cut -f1 "$WORK/$lang.tsv" | uniq -d)
    if [ -n "$dupes" ]; then
        echo "✗ $lang: duplicate keys: $dupes"; failed=1
    fi
done

cut -f1 "$WORK/en.tsv" > "$WORK/en.keys"
for lang in "${LANGS[@]}"; do
    [ -f "$WORK/$lang.tsv" ] || continue
    cut -f1 "$WORK/$lang.tsv" > "$WORK/$lang.keys"
    missing=$(comm -23 "$WORK/en.keys" "$WORK/$lang.keys")
    extra=$(comm -13 "$WORK/en.keys" "$WORK/$lang.keys")
    [ -n "$missing" ] && { echo "✗ $lang: missing keys:"; sed 's/^/    /' <<<"$missing"; failed=1; }
    [ -n "$extra" ] && { echo "✗ $lang: keys not in en:"; sed 's/^/    /' <<<"$extra"; failed=1; }
    [ "$lang" = en ] && continue
    while IFS=$'\t' read -r key value; do
        en_value=$(awk -F'\t' -v k="$key" '$1 == k { print $2 }' "$WORK/en.tsv")
        if [ "$(placeholders "$value")" != "$(placeholders "$en_value")" ]; then
            echo "✗ $lang: placeholders of \"$key\" differ from en"; failed=1
        fi
    done < "$WORK/$lang.tsv"
done

# Keys used in code must exist (layout.<id> names fall back to the built-in name).
grep -rhoE 'L10n\.tr\("[^"]+"' Sources | sed 's/^L10n\.tr("//; s/"$//' | sort -u > "$WORK/used.keys"
grep -rhoE 'descriptionKey: "[^"]+"' Sources | sed 's/^descriptionKey: "//; s/"$//' | sort -u >> "$WORK/used.keys"
unknown=$(sort -u "$WORK/used.keys" | comm -23 - "$WORK/en.keys")
[ -n "$unknown" ] && { echo "✗ keys used in Sources/ but missing in en.lproj:"; sed 's/^/    /' <<<"$unknown"; failed=1; }

if [ "$failed" -ne 0 ]; then
    echo "Localization check failed."
    exit 1
fi
echo "✓ ${#LANGS[@]} languages, $(wc -l < "$WORK/en.keys" | tr -d ' ') keys each, all files lint OK, placeholders match."
