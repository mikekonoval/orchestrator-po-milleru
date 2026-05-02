#!/usr/bin/env bash
# git.sh — хелперы для автокоммита по фазам.
# Подключается через `source`. Ожидает PROJECT_DIR в окружении.

# В git-репо ли мы и доступен ли git?
# Возвращает строго 0 (да) или 1 (нет), не пробрасывает 128 от `git rev-parse`.
git_available() {
  command -v git >/dev/null 2>&1 || return 1
  git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1
  return 0
}

# Чистое ли рабочее дерево? (нет staged/unstaged/untracked файлов)
git_tree_clean() {
  git_available || return 0  # не git-репо → считаем «чисто», не блокируем
  [[ -z "$(git -C "$PROJECT_DIR" status --porcelain)" ]]
}

# Извлекает описание фазы из плана: "- [ ] Фаза N: <описание>" → "<описание>".
# Игнорирует [x] vs [ ] и работает на уже закрытых фазах.
phase_description() {
  local plan_file="$1"
  local phase="$2"
  [[ -f "$plan_file" ]] || { echo ""; return; }
  grep -oE "^- \[[ x]\] Фаза $phase: .*" "$plan_file" 2>/dev/null \
    | head -n1 \
    | sed -E "s/^- \[[ x]\] Фаза $phase: //"
}

# Делает один коммит по итогам фазы.
# Использование: git_commit_phase <phase> <plan_file> [<plan_name>]
# <plan_name>  — для тела коммита; если пусто, попробуем извлечь из пути plan_file.
git_commit_phase() {
  local phase="$1"
  local plan_file="$2"
  local plan_name="${3:-}"
  local desc
  desc="$(phase_description "$plan_file" "$phase")"
  [[ -z "$desc" ]] && desc="(без описания в плане)"

  # Если имя плана не передано — попробуем извлечь из пути plan_file:
  # ожидается что plan_file = .../plans/<plan_name>/plan.md
  if [[ -z "$plan_name" && "$plan_file" == */plans/*/* ]]; then
    plan_name="$(basename "$(dirname "$plan_file")")"
  fi

  local title_prefix="phase $phase"
  [[ -n "$plan_name" ]] && title_prefix="[$plan_name] phase $phase"

  local title="$title_prefix: $desc"
  # Ограничиваем заголовок 72 символами — конвенция git.
  if [[ ${#title} -gt 72 ]]; then
    title="${title:0:69}..."
  fi

  local plan_rel
  if [[ -n "$plan_name" ]]; then
    plan_rel="plans/$plan_name"
  else
    plan_rel="plans"
  fi

  local body
  body="$(cat <<EOF
$title

Reports:
- $plan_rel/phase${phase}/errors.md
- $plan_rel/phase${phase}/missing.md
- $plan_rel/phase${phase}/review.md
- $plan_rel/phase${phase}/security.md
- $plan_rel/phase${phase}/final_check.md

Plan: $(basename "$plan_file")
EOF
)"

  git -C "$PROJECT_DIR" add -A
  git -C "$PROJECT_DIR" commit -m "$body" >/dev/null
  echo "$(git -C "$PROJECT_DIR" rev-parse --short HEAD)"
}
