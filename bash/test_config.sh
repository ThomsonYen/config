#!/usr/bin/env bash
# test_config.sh — self-contained tests for the bash config loader.
# Runs in a temp dir so it never touches the repo's real config.yaml.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$HERE/.."

PASS=0
FAIL=0
check() { # check <label> <expected> <actual>
    if [[ "$2" == "$3" ]]; then
        echo "  ok: $1"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $1 — expected [$2], got [$3]"
        FAIL=$((FAIL + 1))
    fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$REPO_ROOT/config_default.yaml" "$TMP/config_default.yaml"

source "$HERE/config.sh"

echo "Test 1: create config.yaml on first run, defaults resolve"
[[ -f "$TMP/config.yaml" ]] && { echo "  precondition failed"; exit 1; }
config_load "$TMP" 2>/dev/null
check "config.yaml created" "yes" "$([[ -f "$TMP/config.yaml" ]] && echo yes || echo no)"
check "app.name from defaults" "my-app" "$(config get app.name)"
check "app.workers from defaults" "4" "$(config get app.workers)"
config destroy

echo "Test 2: partial override falls back to defaults for omitted keys"
cat > "$TMP/config.yaml" <<'EOF'
app:
  log_level: debug
EOF
config_load "$TMP" 2>/dev/null
check "overridden log_level" "debug" "$(config get app.log_level)"
check "omitted workers falls back" "4" "$(config get app.workers)"
check "omitted name falls back" "my-app" "$(config get app.name)"
config destroy

echo 'Test 3: ${env:VAR:-default} expansion'
unset DB_PASSWORD
config_load "$TMP" 2>/dev/null
check "db.password uses env default" "changeme" "$(config get database.password)"
config destroy

export DB_PASSWORD="s3cret"
config_load "$TMP" 2>/dev/null
check "db.password uses env when set" "s3cret" "$(config get database.password)"
unset DB_PASSWORD
config destroy

echo
echo "Passed: $PASS  Failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
