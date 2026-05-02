#!/usr/bin/env bash
# parse-report.sh — grep маркеров секций в файлах отчётов.
# Подключается через `source`. Все функции принимают путь к файлу.

# Извлекает текст одной секции отчёта по имени маркера.
# Использует awk: захватывает строки от "## NAME" до следующей "## " или EOF.
section_body() {
  local file="$1"
  local section="$2"
  [[ ! -f "$file" ]] && return 1
  awk -v s="^## ${section}" '
    $0 ~ s {flag=1; next}
    /^## / && flag {flag=0}
    flag {print}
  ' "$file"
}

# ## FOUND: пусто — суб-агент явно сказал, что нашёл ничего.
# Парсим только первую строку секции FOUND, потому что маркер пишется в её заголовке.
found_empty() {
  local file="$1"
  [[ ! -f "$file" ]] && return 1
  grep -qE "^## FOUND:[[:space:]]*пусто[[:space:]]*$" "$file"
}

# В секции PROVEN есть хоть один пункт, помеченный как реальный.
# Считаем: слово «реальн» (реальный/реальные/реальная) в теле секции.
has_real() {
  local file="$1"
  local body
  body=$(section_body "$file" "PROVEN") || return 1
  echo "$body" | grep -qiE "реальн|^real[[:space:]]|[[:space:]]real[[:space:]]"
}

# Суб-агент в секции APPLIED отказался применять фикс и эскалирует.
has_escalate() {
  local file="$1"
  [[ ! -f "$file" ]] && return 1
  grep -qE "^ESCALATE:|^## APPLIED:[[:space:]]*ESCALATE:" "$file" \
    || section_body "$file" "APPLIED" 2>/dev/null | grep -qE "^ESCALATE:"
}

# В final_check: smoke test прошёл.
smoke_passed() {
  local file="$1"
  local body
  body=$(section_body "$file" "SMOKE") || return 1
  echo "$body" | grep -qiE "^[[:space:]]*pass\b|: pass\b|✓ pass"
}

# В final_check: регрессий не нашли.
regression_clean() {
  local file="$1"
  local body
  body=$(section_body "$file" "REGRESSION") || return 1
  echo "$body" | grep -qiE "чисто|clean|✓ clean|^ничего"
}
