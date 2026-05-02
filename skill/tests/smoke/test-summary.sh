#!/usr/bin/env bash
# Smoke-тест summary.sh: phase_summary_block, applied_summary, insert_summary_into_plan.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PROJECT_DIR="$TMP"
export PROJECT_DIR

# shellcheck source=../../scripts/lib/parse-report.sh
source "$SKILL_DIR/scripts/lib/parse-report.sh"
# shellcheck source=../../scripts/lib/git.sh
source "$SKILL_DIR/scripts/lib/git.sh"
# shellcheck source=../../scripts/lib/summary.sh
source "$SKILL_DIR/scripts/lib/summary.sh"

PASS=0
FAIL=0

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local label="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label — не нашёл '$needle'"
    FAIL=$((FAIL + 1))
  fi
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label"
    echo "      ждали:    $expected"
    echo "      получили: $actual"
    FAIL=$((FAIL + 1))
  fi
}

# Создаём plan-папку
PLAN_NAME="myplan"
PLAN_DIR="$TMP/plans/$PLAN_NAME"
mkdir -p "$PLAN_DIR/phase1" "$PLAN_DIR/phase2" "$PLAN_DIR/phase3"

# --- applied_summary --------------------------------------------------------

# 1. Файл не существует → "—"
echo "applied_summary:"
assert_eq "—" "$(applied_summary "$PLAN_DIR/phase99/errors.md")" "—  для отсутствующего файла"

# 2. Файл с FOUND: пусто → "—"
echo "## FOUND: пусто" > "$PLAN_DIR/phase1/empty.md"
assert_eq "—" "$(applied_summary "$PLAN_DIR/phase1/empty.md")" "—  когда FOUND пусто"

# 3. Файл с APPLIED — извлекает первые строки
cat > "$PLAN_DIR/phase1/has_applied.md" <<'EOF'
## FOUND
1. ...

## PROVEN
1. реальная

## APPLIED
1. fix in foo.js: handle null
2. fix in bar.js: bounds check
3. fix in baz.js: race
4. fix in qux.js: leak
EOF
RESULT="$(applied_summary "$PLAN_DIR/phase1/has_applied.md")"
assert_contains "fix in foo.js" "$RESULT" "извлёк первый пункт APPLIED"
assert_contains "fix in bar.js" "$RESULT" "извлёк второй пункт APPLIED"
assert_contains "fix in baz.js" "$RESULT" "извлёк третий пункт APPLIED"
# Должно быть не больше 3 склеенных строк (head -3)
COUNT="$(echo "$RESULT" | tr ';' '\n' | wc -l | tr -d ' ')"
if [[ "$COUNT" -le 3 ]]; then
  echo "  ✓ ограничено 3 пунктами (получили $COUNT)"
  PASS=$((PASS + 1))
else
  echo "  ✗ должно быть ≤ 3 пунктов, получили $COUNT"
  FAIL=$((FAIL + 1))
fi

# --- phase_summary_block ----------------------------------------------------

cat > "$PLAN_DIR/plan.md" <<'EOF'
# План

## Фазы

- [x] Фаза 1: построить базовую структуру
- [ ] Фаза 2: добавить логирование

## Резюме фаз

<!-- РЕЗЮМЕ ФАЗ ВЫШЕ ЭТОЙ СТРОКИ. Не удаляй маркер. -->
EOF

cat > "$PLAN_DIR/phase1/errors.md"   <<< "## FOUND: пусто"
cat > "$PLAN_DIR/phase1/missing.md"  <<< "## FOUND: пусто"
cat > "$PLAN_DIR/phase1/review.md"   <<< "## FOUND: пусто"
cat > "$PLAN_DIR/phase1/security.md" <<< "## FOUND: пусто"
cat > "$PLAN_DIR/phase1/final_check.md" <<'EOF'
## REGRESSION
чисто

## SMOKE
pass — npm test зелёный, dist/output.json создан
EOF

echo
echo "phase_summary_block (все блоки пусты, smoke pass):"
BLOCK="$(phase_summary_block 1 "$PLAN_DIR/plan.md" "$PLAN_DIR")"

assert_contains "### Фаза 1 — закрыта" "$BLOCK" "заголовок есть с номером и датой"
assert_contains "построить базовую структуру" "$BLOCK" "взял описание из плана"
assert_contains "[errors](phase1/errors.md)" "$BLOCK" "ссылка на errors phase1"
assert_contains "[final_check](phase1/final_check.md)" "$BLOCK" "ссылка на final_check phase1"
assert_contains "Smoke:** pass" "$BLOCK" "статус smoke=pass"
assert_contains "npm test зелёный" "$BLOCK" "детали smoke в строке"
assert_contains "errors: —" "$BLOCK" "errors помечен как — (FOUND пусто)"

# --- phase_summary_block: с реальным APPLIED -------------------------------

cat > "$PLAN_DIR/phase2/errors.md" <<'EOF'
## FOUND
1. ...

## PROVEN
1. РЕАЛЬНАЯ

## APPLIED
1. handler.js:42 — добавил проверку null
EOF
cat > "$PLAN_DIR/phase2/missing.md"  <<< "## FOUND: пусто"
cat > "$PLAN_DIR/phase2/review.md"   <<< "## FOUND: пусто"
cat > "$PLAN_DIR/phase2/security.md" <<< "## FOUND: пусто"
cat > "$PLAN_DIR/phase2/final_check.md" <<'EOF'
## REGRESSION
чисто

## SMOKE
pass
EOF

echo
echo "phase_summary_block (errors с APPLIED):"
BLOCK2="$(phase_summary_block 2 "$PLAN_DIR/plan.md" "$PLAN_DIR")"
assert_contains "добавить логирование" "$BLOCK2" "взял описание фазы 2 из плана"
assert_contains "handler.js:42" "$BLOCK2" "извлёк applied из phase2/errors"

# --- insert_summary_into_plan ----------------------------------------------

echo
echo "insert_summary_into_plan:"
insert_summary_into_plan "$PLAN_DIR/plan.md" "$BLOCK"

if grep -qF "$SUMMARY_MARKER" "$PLAN_DIR/plan.md"; then
  echo "  ✓ маркер сохранён после вставки"
  PASS=$((PASS + 1))
else
  echo "  ✗ маркер потерян"
  FAIL=$((FAIL + 1))
fi

if grep -qF "### Фаза 1 — закрыта" "$PLAN_DIR/plan.md"; then
  echo "  ✓ блок резюме вставлен в план"
  PASS=$((PASS + 1))
else
  echo "  ✗ блок резюме не появился в плане"
  FAIL=$((FAIL + 1))
fi

# Маркер должен быть НИЖЕ блока — проверяем порядок строк
HEADER_LINE="$(grep -n "^### Фаза 1 — закрыта" "$PLAN_DIR/plan.md" | head -1 | cut -d: -f1)"
MARKER_LINE="$(grep -nF "$SUMMARY_MARKER" "$PLAN_DIR/plan.md" | head -1 | cut -d: -f1)"
if [[ -n "$HEADER_LINE" && -n "$MARKER_LINE" && "$HEADER_LINE" -lt "$MARKER_LINE" ]]; then
  echo "  ✓ блок резюме вставлен ПЕРЕД маркером (line $HEADER_LINE < $MARKER_LINE)"
  PASS=$((PASS + 1))
else
  echo "  ✗ нарушен порядок: header=$HEADER_LINE, marker=$MARKER_LINE"
  FAIL=$((FAIL + 1))
fi

# Идемпотентность: вставка ещё раз даёт два блока (по дизайну — append)
insert_summary_into_plan "$PLAN_DIR/plan.md" "$BLOCK2"
COUNT_HEADERS="$(grep -c "^### Фаза [0-9]" "$PLAN_DIR/plan.md" || true)"
assert_eq "2" "$COUNT_HEADERS" "после двух вставок в плане 2 блока резюме"

# --- smoke fail сценарий ----------------------------------------------------

cat > "$PLAN_DIR/phase3/final_check.md" <<'EOF'
## REGRESSION
чисто

## SMOKE
fail — тесты падают, 3 ошибки в auth.test.js
EOF
cat > "$PLAN_DIR/phase3/errors.md"   <<< "## FOUND: пусто"
cat > "$PLAN_DIR/phase3/missing.md"  <<< "## FOUND: пусто"
cat > "$PLAN_DIR/phase3/review.md"   <<< "## FOUND: пусто"
cat > "$PLAN_DIR/phase3/security.md" <<< "## FOUND: пусто"

echo
echo "phase_summary_block (smoke fail):"
BLOCK3="$(phase_summary_block 3 "$PLAN_DIR/plan.md" "$PLAN_DIR")"
assert_contains "Smoke:** fail" "$BLOCK3" "статус smoke=fail отражён"
assert_contains "auth.test.js" "$BLOCK3" "детали fail в строке"

# --- summary

echo
echo "Итого: $PASS прошло, $FAIL упало"
[[ "$FAIL" -eq 0 ]] || exit 1
