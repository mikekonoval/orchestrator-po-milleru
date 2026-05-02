#!/usr/bin/env bash
# run-all.sh [--dry-run]
#
# Идёт по плану активного плана (plans/<active>/plan.md) и для каждой строки
# '- [ ] Фаза N' вызывает run-phase.sh N. Активный план берёт из plans/.active.
# Останавливается на первой фазе, которая упала (exit > 0), и возвращает её код.
# По завершении печатает консолидированную сводку — список закрытых фаз с описанием.

set -euo pipefail

DRY_RUN="${1:-}"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(pwd)"
export PROJECT_DIR

# shellcheck source=lib/plan.sh
source "$SKILL_DIR/scripts/lib/plan.sh"

cd "$PROJECT_DIR"

if ! PLAN_NAME="$(active_plan_name 2>/dev/null)"; then
  echo "ERROR: активный план не задан. Создай: bash $SKILL_DIR/scripts/init-project.sh <name>" >&2
  exit 1
fi

if ! plan_exists "$PLAN_NAME"; then
  echo "ERROR: plans/.active = '$PLAN_NAME', но плана нет в plans/$PLAN_NAME/" >&2
  exit 1
fi

PLAN_DIR="$PROJECT_DIR/plans/$PLAN_NAME"
PLAN_FILE="$(plan_md_for "$PLAN_NAME" || true)"
[[ -n "$PLAN_FILE" ]] || { echo "не нашёл план в $PLAN_DIR/*.md" >&2; exit 1; }

echo "Активный план: $PLAN_NAME"
echo "Файл плана:    $PLAN_FILE"
echo

# Собираем номера фаз, которые ещё не закрыты.
mapfile -t PENDING < <(grep -oE "^- \[ \] Фаза [0-9]+" "$PLAN_FILE" | grep -oE "[0-9]+$")

if [[ ${#PENDING[@]} -eq 0 ]]; then
  echo "Все фазы в $PLAN_FILE уже закрыты ([x])."
  exit 0
fi

echo "Открытые фазы: ${PENDING[*]}"
echo

for phase in "${PENDING[@]}"; do
  echo "=== Фаза $phase ==="
  if [[ -n "$DRY_RUN" ]]; then
    bash "$SKILL_DIR/scripts/run-phase.sh" "$phase" "$DRY_RUN" || rc=$?
  else
    bash "$SKILL_DIR/scripts/run-phase.sh" "$phase" || rc=$?
  fi
  rc="${rc:-0}"
  if [[ "$rc" -ne 0 ]]; then
    echo
    echo "Фаза $phase упала с кодом $rc. Остановка."
    echo "  state.json: $(cat "$PLAN_DIR/state.json" 2>/dev/null || echo 'нет')"
    exit "$rc"
  fi
  echo
done

echo "✓ Все фазы плана $PLAN_FILE завершены."
echo

# Консолидированная сводка по итогам всех фаз — извлекается из секции «Резюме фаз»
# в плане, куда run-phase.sh складывает блоки.
echo "Резюме (из $PLAN_FILE):"
SUMMARIES="$(grep -E "^### Фаза [0-9]+ — закрыта " "$PLAN_FILE" 2>/dev/null || true)"
if [[ -z "$SUMMARIES" ]]; then
  echo "  (резюме фаз в плане не найдено — проверь $PLAN_FILE)"
else
  # Для каждой фазы: заголовок + первая строка «Что сделано» из соответствующего блока.
  awk '
    /^### Фаза [0-9]+ — закрыта/ {
      header = $0
      done = ""
      next_block = 0
      while ((getline line) > 0) {
        if (line ~ /^### /) { next_block = 1; break }
        if (line ~ /^- \*\*Что сделано:\*\*/) {
          sub(/^- \*\*Что сделано:\*\* */, "", line)
          done = line
        }
      }
      sub(/^### /, "", header)
      printf "  %s — %s\n", header, done
      if (next_block) {
        # Возвращаемся к началу следующей итерации с уже прочитанным заголовком
        $0 = line
      }
    }
  ' "$PLAN_FILE"
fi
echo
echo "Подробности — в разделе «Резюме фаз» файла $PLAN_FILE."
