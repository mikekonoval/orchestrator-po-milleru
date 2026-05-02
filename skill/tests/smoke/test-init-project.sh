#!/usr/bin/env bash
# Smoke-тест init-project.sh: проверяет, что в чистой директории появляется
# ожидаемая структура и идемпотентность (повторный запуск ничего не ломает).

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"

echo "первый запуск init-project.sh в $TMP"
bash "$SKILL_DIR/scripts/init-project.sh" > /dev/null

PASS=0
FAIL=0

check_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "  ✓ есть: $path"
    PASS=$((PASS + 1))
  else
    echo "  ✗ нет: $path"
    FAIL=$((FAIL + 1))
  fi
}

check_exists "plans/"
check_exists "plans/promts/"
check_exists "architecture/"
check_exists "state.json"

# план называется YYYY-MM-DD-orchestrator.md
PLAN=$(ls plans/*.md 2>/dev/null | head -n1 || true)
if [[ -n "$PLAN" ]]; then
  echo "  ✓ есть план: $PLAN"
  PASS=$((PASS + 1))
else
  echo "  ✗ план в plans/ не создан"
  FAIL=$((FAIL + 1))
fi

# state.json валидный JSON
if jq -e . state.json > /dev/null 2>&1; then
  echo "  ✓ state.json — валидный JSON"
  PASS=$((PASS + 1))
else
  echo "  ✗ state.json не парсится как JSON"
  FAIL=$((FAIL + 1))
fi

# идемпотентность: второй запуск не должен ничего сломать
echo
echo "второй запуск init-project.sh (проверка идемпотентности)"
INITIAL_STATE=$(cat state.json)
bash "$SKILL_DIR/scripts/init-project.sh" > /dev/null
SECOND_STATE=$(cat state.json)

if [[ "$INITIAL_STATE" == "$SECOND_STATE" ]]; then
  echo "  ✓ state.json не перезаписан"
  PASS=$((PASS + 1))
else
  echo "  ✗ state.json изменился между запусками"
  FAIL=$((FAIL + 1))
fi

echo
echo "Итого: $PASS прошло, $FAIL упало"
[[ "$FAIL" -eq 0 ]] || exit 1
