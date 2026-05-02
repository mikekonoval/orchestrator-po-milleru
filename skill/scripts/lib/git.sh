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

# Делает один коммит по итогам фазы. Все аргументы — ссылки на отчёты для тела коммита.
# Использование: git_commit_phase <phase> <plan_file>
git_commit_phase() {
  local phase="$1"
  local plan_file="$2"
  local desc
  desc="$(phase_description "$plan_file" "$phase")"
  [[ -z "$desc" ]] && desc="(без описания в плане)"

  local title="phase $phase: $desc"
  # Ограничиваем заголовок 72 символами — конвенция git.
  if [[ ${#title} -gt 72 ]]; then
    title="${title:0:69}..."
  fi

  local body
  body="$(cat <<EOF
$title

Reports:
- errors_phase${phase}.md
- missing_phase${phase}.md
- review_phase${phase}.md
- security_phase${phase}.md
- final_check_phase${phase}.md

Plan: $(basename "$plan_file")
EOF
)"

  git -C "$PROJECT_DIR" add -A
  git -C "$PROJECT_DIR" commit -m "$body" >/dev/null
  echo "$(git -C "$PROJECT_DIR" rev-parse --short HEAD)"
}
