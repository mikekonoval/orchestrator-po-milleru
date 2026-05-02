#!/usr/bin/env bash
# Smoke-тест: каждый промт начинается с унифицированного preamble «Контекст проекта»
# и ссылается на все четыре источника правды (CLAUDE.md, idea/, architecture/, plans/).
#
# Цель — поймать дрейф: если кто-то в будущем удалит ссылку на idea/ или architecture/
# из любого промта, агент потеряет привязку к источникам и начнёт выдумывать.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROMPTS_DIR="$SKILL_DIR/prompts"

PASS=0
FAIL=0

# Все промты, которые должны иметь preamble.
PROMPTS=(
  "errors_find" "errors_prove" "errors_apply"
  "missing_find" "missing_prove" "missing_apply"
  "review_find" "review_prove" "review_apply"
  "security_find" "security_prove" "security_apply"
  "final_check"
  "phase_generate"
)

# Якоря, которые должны быть в каждом промте.
ANCHORS=(
  "Контекст проекта"
  "CLAUDE.md"
  "idea/"
  "architecture/"
  "plans/"
)

for name in "${PROMPTS[@]}"; do
  file="$PROMPTS_DIR/${name}.md"
  echo "→ $name.md"

  if [[ ! -f "$file" ]]; then
    echo "  ✗ файла нет: $file"
    FAIL=$((FAIL + 1))
    continue
  fi

  for anchor in "${ANCHORS[@]}"; do
    if grep -qF "$anchor" "$file"; then
      echo "  ✓ ссылается на: $anchor"
      PASS=$((PASS + 1))
    else
      echo "  ✗ НЕТ ссылки на: $anchor"
      FAIL=$((FAIL + 1))
    fi
  done
done

echo
echo "Итого: $PASS прошло, $FAIL упало"
[[ "$FAIL" -eq 0 ]] || exit 1
