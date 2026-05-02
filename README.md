# Orchestrator po Milleru

Bash-оркестратор многофазного review-workflow для Claude Code. Каждая фаза проходит 5 блоков (ERRORS → MISSING → REVIEW → SECURITY → FINAL CHECK) по паттерну «найти → доказать в контексте проекта → применить». Запустил — ушёл — вернулся.

**Особенность:** оркестрация в bash, не в LLM. Каждый шаг — отдельный `claude -p` со свежим контекстом, что снимает проблему переполнения, ломающую наивных LLM-оркестраторов.

**Подписка Claude Max.** API-ключ не нужен.

## Установка

```bash
git clone https://github.com/mikekonoval/orchestrator-po-milleru.git
cd orchestrator-po-milleru

bash install.sh --global              # ~/.claude/skills/ — для всех проектов
bash install.sh --local <project-dir> # .claude/skills/ — только для одного проекта
bash install.sh --uninstall global    # удалить
```

## Использование

Оркестратор пристёгивается к зрелому проекту. Предполагается, что у тебя уже есть:

- `CLAUDE.md` — продукт, аудитория, приоритеты
- `architecture/*.md` — техническая документация и инварианты
- `idea/*.md` (или аналогичная папка) — продуктовое видение и принципы
- черновик плана фаз в `plans/*.md` со строками вида `- [ ] Фаза N: краткое описание` — **строго в этом формате**, иначе скрипт фазы не увидит

Запуск из корня проекта:

```bash
bash ~/.claude/skills/orchestrator-po-milleru/scripts/run-phase.sh 1   # одну фазу
bash ~/.claude/skills/orchestrator-po-milleru/scripts/run-all.sh        # все открытые фазы плана
```

Скрипт пишет отчёты `errors_phase{N}.md`, `missing_phase{N}.md`, `review_phase{N}.md`, `security_phase{N}.md`, `final_check_phase{N}.md` в корень проекта. На каждой успешно закрытой фазе делает один git-коммит и вставляет блок резюме в план.

### Если проект пустой

Только для случая, когда оркестратор используется на проекте без `plans/`, `architecture/` и `state.json` — запусти один раз:

```bash
bash ~/.claude/skills/orchestrator-po-milleru/scripts/init-project.sh
```

Создаст недостающие папки, пустой `state.json` и шаблон плана. Существующее не трогает.

## Поведение

- **Чистое git-дерево обязательно** перед стартом фазы (или флаг `--allow-dirty`).
- **Autocommit на закрытии фазы** — один коммит со всеми правками + резюме в плане. Опт-аут: `--no-commit`.
- **ESCALATE** — суб-агент решил, что нужен архитектурный редизайн → пайплайн останавливается (exit 2), смотри `*_phase{N}.md` секцию `## APPLIED`.
- **SMOKE fail** — deliverable не выполняется → фаза не закрывается (exit 3), смотри `final_check_phase{N}.md`.
- **`--dry-run`** — симуляция без вызовов `claude -p` и без коммитов.

## Архитектура репозитория

```
.
├── README.md
├── install.sh             # дистрибутивный installer
└── skill/                 # канонический источник скилла
    ├── SKILL.md
    ├── scripts/
    │   ├── run-phase.sh           # одна фаза × 5 блоков
    │   ├── run-all.sh             # цикл по фазам
    │   ├── init-project.sh        # bootstrap проекта
    │   └── lib/                   # state, parse-report, git, summary
    ├── prompts/                   # 13 шагов + phase_generate
    ├── templates/                 # state.json, plan.md
    └── tests/smoke/               # 6 тестов, 143 ассерта
```

## Зависимости

- macOS / Linux (Windows — через WSL)
- bash 4+, `jq`
- `claude` CLI ([Claude Code](https://docs.claude.com/en/docs/claude-code)) с подпиской Claude Max
- `git` (опционально)

## Лицензия

MIT — см. [LICENSE](LICENSE).

## Источники идей

- [aaddrick/claude-pipeline](https://github.com/aaddrick/claude-pipeline) — bash-first оркестрация
- [reshashi/claude-orchestrator](https://github.com/reshashi/claude-orchestrator) — state-машина с branch-guards
- [Ilyas Ibrahim — solving context amnesia](https://medium.com/@ilyas.ibrahim/how-i-made-claude-code-agents-coordinate-100-and-solved-context-amnesia-5938890ea825)
- [anthropics/claude-code#24677 — compaction death spiral](https://github.com/anthropics/claude-code/issues/24677)
