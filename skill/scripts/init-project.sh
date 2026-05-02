#!/usr/bin/env bash
# install.sh — раскладывает структуру оркестратора в текущей директории проекта.
# Идемпотентно: ничего не перезаписывает, только создаёт отсутствующее.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(pwd)"

create_dir() {
  local d="$1"
  if [[ -d "$d" ]]; then
    echo "  уже есть: $d/"
  else
    mkdir -p "$d"
    echo "  создал:   $d/"
  fi
}

copy_template_if_missing() {
  local src="$1"
  local dst="$2"
  if [[ -f "$dst" ]]; then
    echo "  уже есть: $dst"
  else
    cp "$src" "$dst"
    echo "  создал:   $dst"
  fi
}

echo "Установка orchestrator-po-milleru в $PROJECT_DIR"
echo

create_dir "$PROJECT_DIR/plans"
create_dir "$PROJECT_DIR/plans/promts"
create_dir "$PROJECT_DIR/architecture"

# state.json — стартовое состояние
copy_template_if_missing "$SKILL_DIR/templates/state.json" "$PROJECT_DIR/state.json"

# План фаз — кладём только если в plans/ ещё ничего нет.
shopt -s nullglob
existing_plans=("$PROJECT_DIR"/plans/*.md)
shopt -u nullglob
if [[ ${#existing_plans[@]} -eq 0 ]]; then
  TODAY="$(date +%Y-%m-%d)"
  cp "$SKILL_DIR/templates/plan.md" "$PROJECT_DIR/plans/${TODAY}-orchestrator.md"
  echo "  создал:   plans/${TODAY}-orchestrator.md"
else
  echo "  уже есть план: ${existing_plans[0]} (пропускаю)"
fi

echo
echo "Готово. Дальше:"
echo "  1. Опиши архитектуру в architecture/*.md (опционально, но без неё мета-промт фазы будет слабым)."
echo "  2. Заполни план фаз в plans/*.md — список строк '- [ ] Фаза N: краткое описание'."
echo "  3. Запусти первую фазу:"
echo "       bash $SKILL_DIR/scripts/run-phase.sh 1"
echo "     или весь план:"
echo "       bash $SKILL_DIR/scripts/run-all.sh"
