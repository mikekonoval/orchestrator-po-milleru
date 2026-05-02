#!/usr/bin/env bash
# Smoke-тест run-phase.sh в режиме --dry-run.
# Не вызывает claude -p, проверяет, что bash-логика проходит весь пайплайн без падений.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"

PLAN_NAME="testplan"
bash "$SKILL_DIR/scripts/init-project.sh" "$PLAN_NAME" > /dev/null

PLAN_FILE="plans/$PLAN_NAME/plan.md"
# Прописываем фазу 1 в план, чтобы было что закрывать.
cat > "$PLAN_FILE" <<'EOF'
# План фаз

## Фазы

- [ ] Фаза 1: тестовая фаза для smoke
EOF

echo "запуск run-phase.sh 1 --dry-run в $TMP (план: $PLAN_NAME)"
echo "----"
if bash "$SKILL_DIR/scripts/run-phase.sh" 1 --dry-run 2>&1 | tee dry-run.log; then
  RC=0
else
  RC=$?
fi
echo "----"

PASS=0
FAIL=0

assert_log_contains() {
  local needle="$1"
  if grep -q "$needle" dry-run.log; then
    echo "  ✓ лог содержит: $needle"
    PASS=$((PASS + 1))
  else
    echo "  ✗ лог НЕ содержит: $needle"
    FAIL=$((FAIL + 1))
  fi
}

if [[ "$RC" -eq 0 ]]; then
  echo "  ✓ run-phase.sh завершился с кодом 0"
  PASS=$((PASS + 1))
else
  echo "  ✗ run-phase.sh завершился с кодом $RC"
  FAIL=$((FAIL + 1))
fi

assert_log_contains "блок errors: поиск"
assert_log_contains "блок missing: поиск"
assert_log_contains "блок review: поиск"
assert_log_contains "блок security: поиск"
assert_log_contains "финальная проверка"
assert_log_contains "dry-run прошёл"
assert_log_contains "активный план: $PLAN_NAME"

# state.json должен быть в финальном состоянии dry-run-completed
STATE_FILE="plans/$PLAN_NAME/state.json"
STATUS=$(jq -r '.status' "$STATE_FILE" 2>/dev/null || echo "?")
if [[ "$STATUS" == "dry-run-completed" ]]; then
  echo "  ✓ state.json.status == dry-run-completed"
  PASS=$((PASS + 1))
else
  echo "  ✗ state.json.status == $STATUS (ждали dry-run-completed)"
  FAIL=$((FAIL + 1))
fi

# В dry-run отчётов не должно быть (мы их не создавали)
PHASE_DIR="plans/$PLAN_NAME/phase1"
for f in errors.md missing.md review.md security.md final_check.md; do
  if [[ ! -f "$PHASE_DIR/$f" ]]; then
    echo "  ✓ отчёт не создан: $PHASE_DIR/$f (ожидаемо в dry-run)"
    PASS=$((PASS + 1))
  else
    echo "  ✗ отчёт создан: $PHASE_DIR/$f (не должен быть)"
    FAIL=$((FAIL + 1))
  fi
done

# Без активного плана run-phase.sh должен отказаться
echo
echo "проверка ошибки при отсутствии активного плана"
TMP2="$(mktemp -d)"
cd "$TMP2"
if bash "$SKILL_DIR/scripts/run-phase.sh" 1 --dry-run > /dev/null 2>&1; then
  echo "  ✗ не упал без plans/.active"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ exit != 0 без активного плана"
  PASS=$((PASS + 1))
fi
rm -rf "$TMP2"

echo
echo "Итого: $PASS прошло, $FAIL упало"
[[ "$FAIL" -eq 0 ]] || exit 1
