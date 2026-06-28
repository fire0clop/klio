# Backend Roadmap — FastAPI + PostgreSQL

## Стек
- **Python 3.12+** + **FastAPI**
- **PostgreSQL** — основная БД
- **SQLAlchemy 2.0** (async) + **Alembic** — ORM и миграции
- **Pydantic v2** — валидация данных
- **JWT** — аутентификация
- **Claude API / OpenAI API** — AI для анализа целей и генерации инсайтов
- **Docker + Docker Compose** — окружение

---

## Фаза 1 — Фундамент (неделя 1–2)

### 1.1 Инициализация проекта
- [ ] Структура папок: `app/`, `migrations/`, `tests/`, `docker/`
- [ ] `pyproject.toml` / `requirements.txt`
- [ ] `.env` конфиг (DATABASE_URL, SECRET_KEY, AI_API_KEY и т.д.)
- [ ] Docker Compose: сервисы `api` + `postgres`
- [ ] Health-check эндпоинт `GET /health`

### 1.2 База данных — core схема

**`users`**
- id, email, password_hash, created_at

**`user_profiles`**
- user_id, age, gender, height_cm, weight_kg, created_at, updated_at
- Только эти 4 параметра — больше не запрашиваем

**`goals`**
- id, user_id, title (свободный текст пользователя)
- frequency_type: `daily` / `every_n_days` / `weekdays` / `times_per_week`
- frequency_value: JSON — `{"n": 2}` / `{"days": [1,3,5]}` / `{"times": 3}`
- ai_context: JSON — ответы на уточняющие вопросы AI
- ai_effect_trajectory: JSON — сгенерированный AI план эффектов по дням
- started_at, is_active, created_at

**`goal_questions`**
- id, goal_id, question_text, answer_text, order_index
- История диалога при создании цели

**`goal_entries`**
- id, goal_id, date, completed (bool), note
- Создаётся только для плановых дней (по расписанию цели)

**`daily_logs`**
- id, user_id, date, weight_kg, sleep_hours, energy (1–10), mood (1–10)
- Универсальные метрики — один лог в день на пользователя

**`goal_metrics`**
- id, goal_id, metric_name, unit — метрики специфичные для цели, предложенные AI
- Пример: goal "бегать" → metric "пульс после", unit "bpm"

**`goal_metric_entries`**
- id, goal_metric_id, date, value — значения этих метрик по дням

### 1.3 Аутентификация
- [ ] `POST /auth/register`
- [ ] `POST /auth/login` — JWT access + refresh токены
- [ ] `POST /auth/refresh`
- [ ] Middleware для проверки JWT

---

## Фаза 2 — Профиль и онбординг (неделя 3)

### 2.1 Профиль
- [ ] `GET /profile`
- [ ] `PUT /profile` — возраст, пол, рост, вес
- [ ] Флаг `onboarding_completed` — чтобы фронт знал показывать ли онбординг

### 2.2 Постепенный разогрев
- [ ] Сервис `OnboardingProgressService` — отслеживает что пользователь уже заполнил
- [ ] Логика подсказок: после 3 дней без weight_kg в `daily_logs` → отправить hint пуш "добавь вес — увидишь динамику"

---

## Фаза 3 — Цели с AI-диалогом (неделя 4–5)

### 3.1 Создание цели — AI flow
- [ ] `POST /goals/start` — принимает title, возвращает первый вопрос от AI
- [ ] `POST /goals/{id}/answer` — принимает ответ, возвращает следующий вопрос или `{done: true}`
- [ ] AI логика (промпт):
  - Анализирует свободный текст цели
  - Генерирует 2–4 уточняющих вопроса специфичных для этой цели
  - После всех ответов: генерирует `ai_effect_trajectory` и список `goal_metrics`
  - Примеры вопросов:
    - "не курить" → что курите, как давно, сколько в день, бросаете сразу или постепенно
    - "бегать" → бегали раньше, какая цель (похудеть / выносливость / здоровье)
    - "читать книги" → сколько сейчас читаете, какой жанр предпочитаете
    - "мыться каждый день" → AI понимает контекст, задаёт минимум вопросов
- [ ] `POST /goals/{id}/confirm` — финализирует цель, сохраняет trajectory и metrics

### 3.2 Расписание целей
- [ ] `frequency_type` + `frequency_value` — гибкое расписание
- [ ] Сервис `GoalScheduleService` — для любой цели и даты возвращает: плановый день или нет
- [ ] Streak считается только по плановым дням (пропуск в не-плановый день не ломает серию)

### 3.3 CRUD целей
- [ ] `GET /goals` — список активных целей с текущим streak
- [ ] `GET /goals/{id}` — детали + ai_context
- [ ] `DELETE /goals/{id}` — архивирует, не удаляет

---

## Фаза 4 — Ежедневные отметки (неделя 6)

### 4.1 Check-in
- [ ] `GET /checkin/today` — возвращает только цели у которых сегодня плановый день
- [ ] `POST /checkin` — принимает массив `[{goal_id, completed, note}]` + daily_log
- [ ] Логика: если сегодня уже был check-in — возвращает его для редактирования
- [ ] Валидация: нельзя отметить цель в не-плановый день

### 4.2 Метрики целей
- [ ] `POST /goals/{id}/metrics` — записать значение специфической метрики за день
- [ ] Предлагаются только метрики релевантных целей

---

## Фаза 5 — Аналитика и AI-инсайты (неделя 7–9)

### 5.1 Streak и статистика
- [ ] Сервис `StreakService`:
  - Текущий streak (непрерывная серия плановых дней)
  - Best streak
  - % выполнения за 7 / 30 / 90 дней
- [ ] `GET /analytics/goals/{id}/streak`

### 5.2 Прогресс эффектов
- [ ] `GET /analytics/goals/{id}/effects` — текущие эффекты на основе streak
- [ ] Логика: берём `ai_effect_trajectory`, находим ближайший milestone по текущему streak, возвращаем проценты
- [ ] Если streak прерывался — небольшой откат процентов (не обнуление)

### 5.3 Корреляционные инсайты (AI)
- [ ] Сервис `InsightService` — раз в неделю анализирует данные пользователя:
  - Сравнивает energy/mood в дни выполнения vs невыполнения целей
  - Сравнивает динамику weight_kg с выполнением релевантных целей
  - Генерирует 2–3 текстовых инсайта
- [ ] `GET /analytics/insights` — последние инсайты
- [ ] Инсайты кешируются, не генерируются на каждый запрос

### 5.4 Графики
- [ ] `GET /analytics/goals/{id}/timeline` — история выполнения по дням (для heatmap)
- [ ] `GET /analytics/daily-log/timeline` — динамика weight/energy/mood по датам

---

## Фаза 6 — Уведомления (неделя 10)

- [ ] Интеграция APNs
- [ ] Таблица `device_tokens`
- [ ] `POST /devices/token`
- [ ] Ежедневное напоминание о check-in (время настраивается в профиле)
- [ ] Мотивационные пуши при достижении milestone (7 дней, 30 дней)
- [ ] Hint-пуши от `OnboardingProgressService` (добавь вес и т.д.)

---

## Фаза 7 — Тесты и деплой (неделя 11–12)

- [ ] Unit-тесты: `StreakService`, `GoalScheduleService`, `InsightService`
- [ ] Integration-тесты: все API эндпоинты
- [ ] CI/CD: GitHub Actions
- [ ] Деплой: Docker на VPS / Railway
- [ ] Rate limiting, CORS, логирование, SSL
