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

# --- applied_summary --------------------------------------------------------

# 1. Файл не существует → "—"
echo "applied_summary:"
assert_eq "—" "$(applied_summary "$TMP/no-such-file.md")" "—  для отсутствующего файла"

# 2. Файл с FOUND: пусто → "—"
echo "## FOUND: пусто" > "$TMP/empty.md"
assert_eq "—" "$(applied_summary "$TMP/empty.md")" "—  когда FOUND пусто"

# 3. Файл с APPLIED — извлекает первые строки
cat > "$TMP/has_applied.md" <<'EOF'
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
RESULT="$(applied_summary "$TMP/has_applied.md")"
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

cat > "$TMP/plan.md" <<'EOF'
# План

## Фазы

- [x] Фаза 1: построить базовую структуру
- [ ] Фаза 2: добавить логирование

## Резюме фаз

<!-- РЕЗЮМЕ ФАЗ ВЫШЕ ЭТОЙ СТРОКИ. Не удаляй маркер. -->
EOF

cat > "$TMP/errors_phase1.md"   <<< "## FOUND: пусто"
cat > "$TMP/missing_phase1.md"  <<< "## FOUND: пусто"
cat > "$TMP/review_phase1.md"   <<< "## FOUND: пусто"
cat > "$TMP/security_phase1.md" <<< "## FOUND: пусто"
cat > "$TMP/final_check_phase1.md" <<'EOF'
## REGRESSION
чисто

## SMOKE
pass — npm test зелёный, dist/output.json создан
EOF

echo
echo "phase_summary_block (все блоки пусты, smoke pass):"
BLOCK="$(phase_summary_block 1 "$TMP/plan.md" "$TMP")"

assert_contains "### Фаза 1 — закрыта" "$BLOCK" "заголовок есть с номером и датой"
assert_contains "построить базовую структуру" "$BLOCK" "взял описание из плана"
assert_contains "[errors_phase1.md](errors_phase1.md)" "$BLOCK" "ссылка на errors_phase1"
assert_contains "[final_check_phase1.md](final_check_phase1.md)" "$BLOCK" "ссылка на final_check_phase1"
assert_contains "Smoke:** pass" "$BLOCK" "статус smoke=pass"
assert_contains "npm test зелёный" "$BLOCK" "детали smoke в строке"
assert_contains "errors: —" "$BLOCK" "errors помечен как — (FOUND пусто)"

# --- phase_summary_block: с реальным APPLIED -------------------------------

cat > "$TMP/errors_phase2.md" <<'EOF'
## FOUND
1. ...

## PROVEN
1. РЕАЛЬНАЯ

## APPLIED
1. handler.js:42 — добавил проверку null
EOF
cat > "$TMP/missing_phase2.md"  <<< "## FOUND: пусто"
cat > "$TMP/review_phase2.md"   <<< "## FOUND: пусто"
cat > "$TMP/security_phase2.md" <<< "## FOUND: пусто"
cat > "$TMP/final_check_phase2.md" <<'EOF'
## REGRESSION
чисто

## SMOKE
pass
EOF

# Дописываем фазу 2 в план
cat >> "$TMP/plan.md.tmp" <<EOF
$(cat "$TMP/plan.md")
EOF

echo
echo "phase_summary_block (errors с APPLIED):"
BLOCK2="$(phase_summary_block 2 "$TMP/plan.md" "$TMP")"
assert_contains "добавить логирование" "$BLOCK2" "взял описание фазы 2 из плана"
assert_contains "handler.js:42" "$BLOCK2" "извлёк applied из errors_phase2"

# --- insert_summary_into_plan ----------------------------------------------

echo
echo "insert_summary_into_plan:"
insert_summary_into_plan "$TMP/plan.md" "$BLOCK"

if grep -qF "$SUMMARY_MARKER" "$TMP/plan.md"; then
  echo "  ✓ маркер сохранён после вставки"
  PASS=$((PASS + 1))
else
  echo "  ✗ маркер потерян"
  FAIL=$((FAIL + 1))
fi

if grep -qF "### Фаза 1 — закрыта" "$TMP/plan.md"; then
  echo "  ✓ блок резюме вставлен в план"
  PASS=$((PASS + 1))
else
  echo "  ✗ блок резюме не появился в плане"
  FAIL=$((FAIL + 1))
fi

# Маркер должен быть НИЖЕ блока — проверяем порядок строк
HEADER_LINE="$(grep -n "^### Фаза 1 — закрыта" "$TMP/plan.md" | head -1 | cut -d: -f1)"
MARKER_LINE="$(grep -nF "$SUMMARY_MARKER" "$TMP/plan.md" | head -1 | cut -d: -f1)"
if [[ -n "$HEADER_LINE" && -n "$MARKER_LINE" && "$HEADER_LINE" -lt "$MARKER_LINE" ]]; then
  echo "  ✓ блок резюме вставлен ПЕРЕД маркером (line $HEADER_LINE < $MARKER_LINE)"
  PASS=$((PASS + 1))
else
  echo "  ✗ нарушен порядок: header=$HEADER_LINE, marker=$MARKER_LINE"
  FAIL=$((FAIL + 1))
fi

# Идемпотентность: вставка ещё раз даёт два блока (по дизайну — append)
insert_summary_into_plan "$TMP/plan.md" "$BLOCK2"
COUNT_HEADERS="$(grep -c "^### Фаза [0-9]" "$TMP/plan.md" || true)"
assert_eq "2" "$COUNT_HEADERS" "после двух вставок в плане 2 блока резюме"

# --- smoke fail сценарий ----------------------------------------------------

cat > "$TMP/final_check_phase3.md" <<'EOF'
## REGRESSION
чисто

## SMOKE
fail — тесты падают, 3 ошибки в auth.test.js
EOF
cat > "$TMP/errors_phase3.md"   <<< "## FOUND: пусто"
cat > "$TMP/missing_phase3.md"  <<< "## FOUND: пусто"
cat > "$TMP/review_phase3.md"   <<< "## FOUND: пусто"
cat > "$TMP/security_phase3.md" <<< "## FOUND: пусто"

echo
echo "phase_summary_block (smoke fail):"
BLOCK3="$(phase_summary_block 3 "$TMP/plan.md" "$TMP")"
assert_contains "Smoke:** fail" "$BLOCK3" "статус smoke=fail отражён"
assert_contains "auth.test.js" "$BLOCK3" "детали fail в строке"

# --- summary

echo
echo "Итого: $PASS прошло, $FAIL упало"
[[ "$FAIL" -eq 0 ]] || exit 1
