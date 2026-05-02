#!/usr/bin/env bash
# summary.sh — детерминированная генерация и вставка резюме фазы в план.
# Никаких вызовов LLM — всё собирается из существующих отчётов и плана.
#
# Подключается через `source`. Зависит от parse-report.sh (section_body, smoke_passed,
# found_empty) и git.sh (phase_description). Их подключай раньше.
#
# Раскладка отчётов: $PLAN_DIR/phase{N}/{errors,missing,review,security,final_check}.md
# где $PLAN_DIR — папка активного плана ($PROJECT_DIR/plans/<name>/).

# Маркер в plan.md, перед которым вставляется блок резюме.
SUMMARY_MARKER="<!-- РЕЗЮМЕ ФАЗ ВЫШЕ ЭТОЙ СТРОКИ. Не удаляй маркер. -->"

# Извлекает первую содержательную строку из ## APPLIED секции отчёта.
# Возвращает короткий пересказ или "—" если секции нет / она пустая.
applied_summary() {
  local file="$1"
  [[ -f "$file" ]] || { echo "—"; return; }
  if found_empty "$file" 2>/dev/null; then
    echo "—"
    return
  fi
  local body
  body="$(section_body "$file" "APPLIED" 2>/dev/null || true)"
  if [[ -z "$body" ]]; then
    echo "—"
    return
  fi
  # Берём первые 3 непустые строки, склеиваем через '; '.
  local clipped
  clipped="$(printf '%s\n' "$body" | grep -v '^[[:space:]]*$' | head -3 \
             | sed 's/^[[:space:]]*//' | tr '\n' '|' | sed 's/|$//; s/|/; /g')"
  [[ -z "$clipped" ]] && clipped="—"
  echo "$clipped"
}

# Генерирует Markdown-блок резюме одной фазы.
# Args: phase_number, plan_file, plan_dir
# plan_dir — абсолютный путь к папке плана (внутри неё лежат phaseN/*.md).
phase_summary_block() {
  local phase="$1"
  local plan_file="$2"
  local plan_dir="$3"

  local desc
  desc="$(phase_description "$plan_file" "$phase")"
  [[ -z "$desc" ]] && desc="(описание не найдено в плане)"

  local closed_at
  closed_at="$(date +%Y-%m-%d)"

  local phase_dir="$plan_dir/phase${phase}"
  local errors_s missing_s review_s security_s
  errors_s="$(applied_summary "$phase_dir/errors.md")"
  missing_s="$(applied_summary "$phase_dir/missing.md")"
  review_s="$(applied_summary "$phase_dir/review.md")"
  security_s="$(applied_summary "$phase_dir/security.md")"

  local final_file="$phase_dir/final_check.md"
  local smoke_status="?"
  local smoke_detail=""
  if [[ -f "$final_file" ]]; then
    if smoke_passed "$final_file"; then
      smoke_status="pass"
    else
      smoke_status="fail"
    fi
    smoke_detail="$(section_body "$final_file" "SMOKE" 2>/dev/null \
                    | grep -v '^[[:space:]]*$' | head -1 \
                    | sed -E 's/^(pass|fail)[[:space:]]*[—:-]?[[:space:]]*//i')"
  fi

  local smoke_line="$smoke_status"
  [[ -n "$smoke_detail" ]] && smoke_line="$smoke_status — $smoke_detail"

  # Ссылки в резюме — относительные от plan.md, который лежит рядом с папкой phaseN/.
  cat <<EOF
### Фаза $phase — закрыта $closed_at

- **Что сделано:** $desc
- **Ключевые решения:**
  - errors: $errors_s
  - missing: $missing_s
  - review: $review_s
  - security: $security_s
- **Отчёты:** [errors](phase${phase}/errors.md) · [missing](phase${phase}/missing.md) · [review](phase${phase}/review.md) · [security](phase${phase}/security.md) · [final_check](phase${phase}/final_check.md)
- **Smoke:** $smoke_line
EOF
}

# Вставляет блок резюме в план перед SUMMARY_MARKER.
# Если маркера нет — добавляет в конец файла.
insert_summary_into_plan() {
  local plan_file="$1"
  local block="$2"

  local block_file
  block_file="$(mktemp)"
  # trap внутри функции не влияет на родительский — почистим вручную.
  printf '%s\n' "$block" > "$block_file"

  if grep -qF "$SUMMARY_MARKER" "$plan_file"; then
    local tmp
    tmp="$(mktemp)"
    awk -v marker="$SUMMARY_MARKER" -v block_file="$block_file" '
      BEGIN {
        n = 0
        while ((getline line < block_file) > 0) lines[++n] = line
        close(block_file)
      }
      $0 == marker {
        for (i = 1; i <= n; i++) print lines[i]
        print ""
        print
        next
      }
      { print }
    ' "$plan_file" > "$tmp" && mv "$tmp" "$plan_file"
  else
    {
      echo
      cat "$block_file"
    } >> "$plan_file"
  fi

  rm -f "$block_file"
}

# Извлекает все одностроки резюме (заголовки `### Фаза N — закрыта DATE — desc`)
# из плана для финальной сводки в run-all.sh.
list_phase_summaries() {
  local plan_file="$1"
  [[ -f "$plan_file" ]] || return 0
  # Парсим заголовки резюме и подтягиваем "Что сделано" из следующих строк.
  awk '
    /^### Фаза [0-9]+ — закрыта/ {
      header = $0
      # Ищем строку "- **Что сделано:** ..." в пределах блока (до следующего ### или EOF)
      done = ""
      while ((getline line) > 0 && line !~ /^### /) {
        if (line ~ /^- \*\*Что сделано:\*\*/) {
          sub(/^- \*\*Что сделано:\*\* */, "", line)
          done = line
          break
        }
      }
      printf "%s — %s\n", header, done
      if (line ~ /^### /) {
        # Перечитываем эту строку как новый заголовок (повторяем цикл вручную)
        header = line
        # awk сам не позволяет легко "вернуть" строку — упрощаем: просто продолжаем
      }
    }
  ' "$plan_file"
}
