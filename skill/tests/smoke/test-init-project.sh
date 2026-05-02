#!/usr/bin/env bash
# Smoke-тест init-project.sh: проверяет, что в чистой директории появляется
# ожидаемая структура для именованного плана и идемпотентность повторного запуска.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"

PLAN_NAME="auth-rewrite"

echo "первый запуск init-project.sh $PLAN_NAME в $TMP"
bash "$SKILL_DIR/scripts/init-project.sh" "$PLAN_NAME" > /dev/null

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
check_exists "plans/.active"
check_exists "plans/$PLAN_NAME/"
check_exists "plans/$PLAN_NAME/promts/"
check_exists "plans/$PLAN_NAME/plan.md"
check_exists "plans/$PLAN_NAME/state.json"
check_exists "architecture/"

# .active содержит имя плана
ACTIVE_NAME="$(cat plans/.active 2>/dev/null | tr -d '[:space:]')"
if [[ "$ACTIVE_NAME" == "$PLAN_NAME" ]]; then
  echo "  ✓ plans/.active содержит '$PLAN_NAME'"
  PASS=$((PASS + 1))
else
  echo "  ✗ plans/.active = '$ACTIVE_NAME' (ждали '$PLAN_NAME')"
  FAIL=$((FAIL + 1))
fi

# state.json валидный JSON
if jq -e . "plans/$PLAN_NAME/state.json" > /dev/null 2>&1; then
  echo "  ✓ state.json — валидный JSON"
  PASS=$((PASS + 1))
else
  echo "  ✗ state.json не парсится как JSON"
  FAIL=$((FAIL + 1))
fi

# идемпотентность: второй запуск не должен ничего сломать
echo
echo "второй запуск init-project.sh $PLAN_NAME (идемпотентность)"
INITIAL_STATE=$(cat "plans/$PLAN_NAME/state.json")
bash "$SKILL_DIR/scripts/init-project.sh" "$PLAN_NAME" > /dev/null
SECOND_STATE=$(cat "plans/$PLAN_NAME/state.json")

if [[ "$INITIAL_STATE" == "$SECOND_STATE" ]]; then
  echo "  ✓ state.json не перезаписан"
  PASS=$((PASS + 1))
else
  echo "  ✗ state.json изменился между запусками"
  FAIL=$((FAIL + 1))
fi

# второй план — параллельно
echo
echo "второй план в том же проекте"
PLAN2="billing"
bash "$SKILL_DIR/scripts/init-project.sh" "$PLAN2" > /dev/null

check_exists "plans/$PLAN2/plan.md"
check_exists "plans/$PLAN2/state.json"

# .active должен переключиться на второй план
ACTIVE2="$(cat plans/.active 2>/dev/null | tr -d '[:space:]')"
if [[ "$ACTIVE2" == "$PLAN2" ]]; then
  echo "  ✓ plans/.active переключен на '$PLAN2'"
  PASS=$((PASS + 1))
else
  echo "  ✗ plans/.active = '$ACTIVE2' (ждали '$PLAN2')"
  FAIL=$((FAIL + 1))
fi

# первый план не должен пострадать
check_exists "plans/$PLAN_NAME/plan.md"
check_exists "plans/$PLAN_NAME/state.json"

# валидация имени плана: с пробелом — отказ
echo
echo "валидация имени плана"
if bash "$SKILL_DIR/scripts/init-project.sh" "плохое имя" > /dev/null 2>&1; then
  echo "  ✗ принял имя с пробелом и кириллицей (не должен)"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ отказался от имени с пробелом и кириллицей"
  PASS=$((PASS + 1))
fi

# Без аргумента — usage и exit 1
if bash "$SKILL_DIR/scripts/init-project.sh" > /dev/null 2>&1; then
  echo "  ✗ не упал без аргумента"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ без аргумента — exit != 0"
  PASS=$((PASS + 1))
fi

echo
echo "Итого: $PASS прошло, $FAIL упало"
[[ "$FAIL" -eq 0 ]] || exit 1
