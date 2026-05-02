#!/usr/bin/env bash
# plan.sh — хелперы для работы с активным планом.
# Подключается через `source`. Ожидает PROJECT_DIR в окружении.
#
# Раскладка:
#   $PROJECT_DIR/plans/.active           — файл с именем активного плана (одна строка)
#   $PROJECT_DIR/plans/<name>/plan.md    — сам план
#   $PROJECT_DIR/plans/<name>/state.json — state машины оркестратора для этого плана
#   $PROJECT_DIR/plans/<name>/promts/    — промты фаз
#   $PROJECT_DIR/plans/<name>/phaseN/    — отчёты фазы N (errors.md, missing.md, …)

ACTIVE_FILE_NAME=".active"

# Имя плана валидно как имя папки и не путает bash.
plan_name_valid() {
  local name="$1"
  [[ -n "$name" ]] || return 1
  [[ "${#name}" -le 64 ]] || return 1
  [[ "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]]
}

# Возвращает имя активного плана из plans/.active. Если файла нет — пусто.
active_plan_name() {
  local f="$PROJECT_DIR/plans/$ACTIVE_FILE_NAME"
  [[ -f "$f" ]] || return 1
  # tr -d '\n' и одновременно отрезание возможных пробелов
  local name
  name="$(head -n1 "$f" | tr -d '[:space:]')"
  [[ -n "$name" ]] || return 1
  echo "$name"
}

# Записывает имя активного плана в plans/.active (создаёт plans/, если нужно).
set_active_plan() {
  local name="$1"
  mkdir -p "$PROJECT_DIR/plans"
  printf '%s\n' "$name" > "$PROJECT_DIR/plans/$ACTIVE_FILE_NAME"
}

# Возвращает абсолютный путь к директории активного плана.
# Использование: PLAN_DIR="$(active_plan_dir)" || die "..."
active_plan_dir() {
  local name
  name="$(active_plan_name)" || return 1
  echo "$PROJECT_DIR/plans/$name"
}

# Возвращает путь к state.json активного плана.
active_state_file() {
  local d
  d="$(active_plan_dir)" || return 1
  echo "$d/state.json"
}

# Список существующих планов (имена папок в plans/, кроме служебных).
list_plans() {
  local plans_dir="$PROJECT_DIR/plans"
  [[ -d "$plans_dir" ]] || return 0
  local entry
  for entry in "$plans_dir"/*/; do
    [[ -d "$entry" ]] || continue
    basename "$entry"
  done
}

# Существует ли план с таким именем (директория есть).
plan_exists() {
  local name="$1"
  [[ -d "$PROJECT_DIR/plans/$name" ]]
}

# Находит главный plan.md внутри plan-папки.
# Если plan.md есть — возвращает его. Иначе — первый *.md в корне папки плана
# (без рекурсии, исключая promts/, phaseN/), для совместимости со старыми проектами.
plan_md_for() {
  local name="$1"
  local dir="$PROJECT_DIR/plans/$name"
  [[ -d "$dir" ]] || return 1
  if [[ -f "$dir/plan.md" ]]; then
    echo "$dir/plan.md"
    return 0
  fi
  # fallback: первый *.md в корне папки
  local f
  f="$(find "$dir" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort | head -n1)"
  [[ -n "$f" ]] || return 1
  echo "$f"
}
