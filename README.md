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

Каждый «прогон» — это **именованный план**. Папка `plans/<plan-name>/` хранит план фаз, отчёты и state. Можно держать несколько планов параллельно (например, `auth-rewrite` и `billing`) и переключаться между ними.

### Создать план и запустить

```bash
cd <project-root>

# 1. Один раз на план: создать структуру и активировать
bash ~/.claude/skills/orchestrator-po-milleru/scripts/init-project.sh auth-rewrite

# 2. Описать фазы в plans/auth-rewrite/plan.md строками вида
#    '- [ ] Фаза N: краткое описание' (формат строгий)

# 3. Запустить
bash ~/.claude/skills/orchestrator-po-milleru/scripts/run-phase.sh 1   # одну фазу
bash ~/.claude/skills/orchestrator-po-milleru/scripts/run-all.sh        # все открытые
```

### Раскладка файлов

```
<project>/plans/
├── .active                          ← имя активного плана
└── auth-rewrite/
    ├── plan.md                      ← фазы и их резюме
    ├── state.json                   ← состояние оркестратора для этого плана
    ├── promts/phase1.md             ← промт фазы (генерируется при первом запуске)
    └── phase1/                      ← отчёты блоков
        ├── errors.md
        ├── missing.md
        ├── review.md
        ├── security.md
        └── final_check.md
```

На каждой успешно закрытой фазе оркестратор делает один git-коммит и вставляет блок резюме в `plan.md`.

### Переключение между планами

```bash
bash ~/.claude/skills/orchestrator-po-milleru/scripts/activate-plan.sh billing       # переключить
bash ~/.claude/skills/orchestrator-po-milleru/scripts/activate-plan.sh               # показать текущий и список
```

State у каждого плана свой — оборванная фаза сохранится, пока не возобновишь.

## Поведение

- **Чистое git-дерево обязательно** перед стартом фазы (или флаг `--allow-dirty`).
- **Autocommit на закрытии фазы** — один коммит со всеми правками + резюме в плане. Опт-аут: `--no-commit`.
- **ESCALATE** — суб-агент решил, что нужен архитектурный редизайн → пайплайн останавливается (exit 2), смотри `plans/<plan>/phase{N}/<block>.md` секцию `## APPLIED`.
- **SMOKE fail** — deliverable не выполняется → фаза не закрывается (exit 3), смотри `plans/<plan>/phase{N}/final_check.md`.
- **Autocommit failed** — сама фаза прошла (`[x]` стоит, резюме в плане), но `git commit` упал — типично из-за гонки на `.git/index.lock` (IDE, watch-скрипт, параллельный git). Скрипт делает 3 попытки с экспоненциальной паузой; если не помогло — `state.json: status=done, commit=failed, error=autocommit failed`, exit 5. Файлы фазы остаются staged, нужно закоммитить руками. Повторный запуск той же фазы отскочит сразу («уже done») — переходи к следующей.
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
    │   ├── run-all.sh             # цикл по фазам активного плана
    │   ├── init-project.sh        # bootstrap нового плана
    │   ├── activate-plan.sh       # переключение между планами
    │   └── lib/                   # plan, state, parse-report, git, summary
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
