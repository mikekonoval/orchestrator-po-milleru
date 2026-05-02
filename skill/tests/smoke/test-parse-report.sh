#!/usr/bin/env bash
# Smoke-тест парсера маркеров отчётов. Прогоняет fixture-файлы через хелперы
# из lib/parse-report.sh и проверяет, что они возвращают ожидаемые коды выхода.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../scripts/lib/parse-report.sh
source "$SKILL_DIR/scripts/lib/parse-report.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

assert() {
  local expected="$1"  # 0 = should succeed, 1 = should fail
  local label="$2"
  shift 2
  local actual=0
  "$@" || actual=$?
  if [[ "$actual" == "$expected" ]]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label — ждали exit=$expected, получили exit=$actual"
    FAIL=$((FAIL + 1))
  fi
}

# --- fixture 1: FOUND пусто --------------------------------------------------
F1="$TMP/empty.md"
cat > "$F1" <<'EOF'
## FOUND: пусто
EOF

echo "fixture: FOUND: пусто"
assert 0 "found_empty распознаёт '## FOUND: пусто'"           found_empty "$F1"
assert 1 "has_real на пустом файле возвращает false"          has_real "$F1"
assert 1 "has_escalate на пустом файле возвращает false"      has_escalate "$F1"

# --- fixture 2: FOUND непустой, PROVEN c реальными ---------------------------
F2="$TMP/with_real.md"
cat > "$F2" <<'EOF'
## FOUND
1. foo.js:42 — null может прийти из getX()
2. bar.js:10 — off-by-one в цикле

## PROVEN
1. foo.js:42 — РЕАЛЬНАЯ — если кэш пуст, getX() вернёт null и тут же .id упадёт
2. bar.js:10 — ПАРАНОЙЯ — массив всегда непустой по конструктору
EOF

echo
echo "fixture: FOUND непустой, PROVEN с одной реальной"
assert 1 "found_empty НЕ срабатывает на непустом FOUND"        found_empty "$F2"
assert 0 "has_real ловит 'РЕАЛЬНАЯ' в PROVEN"                 has_real "$F2"
assert 1 "has_escalate отсутствует — false"                   has_escalate "$F2"

# --- fixture 3: ESCALATE в APPLIED -------------------------------------------
F3="$TMP/escalate.md"
cat > "$F3" <<'EOF'
## FOUND
1. ...

## PROVEN
1. РЕАЛЬНАЯ — нужен редизайн авторизации

## APPLIED
ESCALATE: фикс требует переезда на JWT, не точечный diff
EOF

echo
echo "fixture: ESCALATE в APPLIED"
assert 0 "has_escalate ловит ESCALATE"                        has_escalate "$F3"

# --- fixture 4: final_check pass + clean -------------------------------------
F4="$TMP/final_pass.md"
cat > "$F4" <<'EOF'
## REGRESSION
чисто

## SMOKE
pass — npm test зелёный, файл dist/output.json есть
EOF

echo
echo "fixture: final_check pass + clean"
assert 0 "smoke_passed ловит 'pass'"                          smoke_passed "$F4"
assert 0 "regression_clean ловит 'чисто'"                     regression_clean "$F4"

# --- fixture 5: final_check fail + dirty -------------------------------------
F5="$TMP/final_fail.md"
cat > "$F5" <<'EOF'
## REGRESSION
1. сломали обработку пустого ввода в form.js
2. потеряли логирование в handler.js

## SMOKE
fail — `npm test` падает на 3 тестах
EOF

echo
echo "fixture: final_check fail + dirty"
assert 1 "smoke_passed НЕ срабатывает на 'fail'"              smoke_passed "$F5"
assert 1 "regression_clean НЕ срабатывает при наличии регрессий" regression_clean "$F5"

# --- fixture 6: PROVEN без реальных (только паранойя) ------------------------
F6="$TMP/all_paranoia.md"
cat > "$F6" <<'EOF'
## FOUND
1. что-то

## PROVEN
1. ПАРАНОЙЯ — теоретически, но не в нашем продукте
2. ПАРАНОЙЯ — масштаб не тот
EOF

echo
echo "fixture: PROVEN — только паранойя"
assert 1 "has_real НЕ срабатывает когда все ПАРАНОЙЯ"          has_real "$F6"

# --- summary -----------------------------------------------------------------
echo
echo "Итого: $PASS прошло, $FAIL упало"
[[ "$FAIL" -eq 0 ]] || exit 1
