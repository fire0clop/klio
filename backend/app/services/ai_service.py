import json
import re
from typing import Optional

import anthropic
import httpx

from app.config import settings

_http_client = (
    httpx.AsyncClient(proxy=settings.ANTHROPIC_PROXY_URL, timeout=120.0)
    if settings.ANTHROPIC_PROXY_URL
    else None
)

client = anthropic.AsyncAnthropic(
    api_key=settings.ANTHROPIC_API_KEY,
    **({"http_client": _http_client} if _http_client else {}),
)


_LANG_NAMES = {"ru": "русском", "en": "English", "es": "español"}


def _lang_directive(lang: str | None) -> str:
    name = _LANG_NAMES.get((lang or "ru"), "русском")
    return (
        f"\n\nКРИТИЧЕСКИ ВАЖНО: ВСЕ свои тексты для пользователя (вопросы, названия, "
        f"подписи, summary, реакции) пиши ТОЛЬКО на языке: {name}. Технические ключи "
        f"(kind, icon, key и т.п.) оставляй как есть на латинице."
    )


def _extract_json(text: str) -> dict | list:
    text = text.strip()
    match = re.search(r"```(?:json)?\s*([\s\S]+?)```", text)
    if match:
        text = match.group(1).strip()
    start = next((i for i, c in enumerate(text) if c in "{["), 0)
    text = text[start:]
    text = re.sub(r",\s*([}\]])", r"\1", text)
    return json.loads(text)


# Единый системный промпт: ИИ парсит цель в структуру (таксономия из docs/GOAL_DESIGN.md)
# и задаёт ТОЛЬКО реально недостающие вопросы. Один вызов делает и разбор, и диалог.
_SYSTEM_GOAL = """
Ты — ассистент постановки личных целей. По формулировке цели и ответам пользователя
ты должен разобрать цель в структуру и задать ТОЛЬКО реально недостающие вопросы.
Сначала извлеки из текста максимум сам. НЕ задавай вопрос, если ответ уже есть в
формулировке или очевиден из здравого смысла.

ОСИ ЦЕЛИ:
1. horizon — "eternal" (вечная, без конца: зарядка, читать) | "situational" (есть
   конечная точка — дата/условие/значение: бросить курить, похудеть до 75, летом не есть сладкое).
2. measure — "fact" (только сделал/не сделал, числа нет: зарядка, душ, медитация)
   | "quantitative" (есть числовая метрика: страницы, км, сигареты, кг, минуты).
   ВАЖНО про отказ/воздержание: «бросить курить», «бросить пить», «не курить»,
   «не есть сладкое», «не сидеть в телефоне» и подобные — это ПО УМОЛЧАНИЮ ежедневная
   отметка «воздержался» → measure="fact" (да/нет), БЕЗ числа, БЕЗ target, БЕЗ лимита.
   НЕ придумывай лимит («≤15 затяжек») сам. Quantitative + direction="down" ставь
   ТОЛЬКО если в формулировке ЯВНО есть число-лимит («не более 5 сигарет в день»,
   «меньше 2 часов в телефоне»). Слово «бросить»/«не <делать>» без числа = всегда fact.
3. direction (только quantitative) — "up" (хотим больше: страницы, км) | "down"
   (хотим меньше: сигареты, сладкое) | "target" (попасть в значение: вес 75).
   ОПРЕДЕЛЯЙ САМ из формулировки, у пользователя НЕ спрашивай.
4. controllability (только quantitative) — "direct" (метрика и есть действие, под полным
   контролем: страницы, км, отжимания, сигареты) | "indirect" (метрика это результат,
   на который влияешь косвенно, он запаздывает: вес, % жира, пульс покоя).

ПОЛЯ ДЛЯ quantitative:
- baseline: текущий уровень (сколько сейчас). Для "down" и для разгона "up" к большой
  цели это КРИТИЧНО — если не ясно из текста, СПРОСИ.
- target: целевое значение. Для situational и "target" обязательно. Для eternal "up"
  можно null (растём от факта).
- unit: единица ("страниц", "км", "сигарет", "кг", "мин").
- growing: true, если метрику в принципе осмысленно наращивать (велосипед, чтение — true;
  душ, чистка зубов — false).
- metric_has_ceiling: true, если у метрики есть смысловой предел, после которого логичнее
  менять метрику, а не цифру (отжимания — true; страницы — false).
- horizon_days: если baseline и target РАЗЛИЧАЮТСЯ и нужен ПЛАВНЫЙ переход — задай, за
  сколько дней мягко дойти от baseline к target. Это КЛЮЧЕВО для целей снижения: «не более
  2 часов в телефоне» при текущих 4 часах — НЕ ставь лимит 2 сразу, задай baseline=4,
  target=2 и horizon_days (обычно 1–4 недели), чтобы лимит снижался плавно. Постепенный
  отказ от курения 20→0 — тоже ramp. Резкий отказ / сразу к цели = 1. Если baseline==target
  или плавность не нужна — null.

ПОЛЯ ДЛЯ situational:
- end_condition: при каком условии цель закрывается (дата / событие / достижение значения).
- horizon_days: за сколько дней РЕАЛИСТИЧНО дойти от baseline до target. Оцени по домену
  (нельзя 20→200 кг за неделю). Если пользователь задал нереальный срок — мягко предложи
  реалистичный в вопросе.

cadence: как часто отслеживать — "daily" | "weekly" | "weekdays". Выводи из формулировки
("2 раза в день" — это daily; явного расписания нет — daily). НЕ задавай отдельный вопрос
про частоту, если она ясна или по умолчанию daily.

ПРАВИЛА ВОПРОСОВ:
- Максимум 3 вопроса, по одному за раз, конкретные и дружелюбные.
- Спрашивай ТОЛЬКО критично недостающее (чаще всего: baseline и темп для целей снижения;
  baseline для разгона к большой цели; конечная точка, если её вообще нет).
- Для простых fact-целей (зарядка, душ, медитация) вопросов обычно 0.
- Если цель явно нереалистична по сроку — уточни/предложи реалистичный вариант.

ОТВЕЧАЙ ТОЛЬКО JSON, ровно в одном из двух форматов.

Нужен ещё вопрос:
{"status": "question", "question": "текст вопроса"}

Всё собрано:
{"status": "ready", "goal": {
  "horizon": "eternal" | "situational",
  "measure": "fact" | "quantitative",
  "direction": "up" | "down" | "target" | null,
  "controllability": "direct" | "indirect" | null,
  "baseline": number | null,
  "target": number | null,
  "unit": string | null,
  "growing": true | false,
  "metric_has_ceiling": true | false,
  "end_condition": string | null,
  "horizon_days": number | null,
  "cadence": "daily" | "weekly" | "weekdays",
  "icon": "имя SF Symbol для плитки цели (см. список ниже)",
  "title": "короткая чистая формулировка цели",
  "summary": "1-2 фразы: что ты понял про цель, по-человечески",
  "effects": [
    {"name": "Название", "icon": "icon_name",
     "milestones": [{"day": 7, "percent": 20, "description": "Краткое описание"}]}
  ]
}}

icon — подбери максимально подходящий SF Symbol под смысл цели, СТРОГО из списка:
figure.run, figure.walk, figure.strengthtraining.traditional, dumbbell.fill, figure.cooldown,
figure.yoga, sportscourt.fill, bicycle, book.fill, character.book.closed.fill, pencil.and.scribble,
graduationcap.fill, brain.head.profile, drop.fill, cup.and.saucer.fill, fork.knife, carrot.fill,
leaf.fill, bed.double.fill, moon.stars.fill, nosign, lungs.fill, heart.fill, pills.fill,
iphone, gamecontroller.fill, rublesigncircle.fill, dollarsign.circle.fill, briefcase.fill,
paintbrush.fill, music.note, camera.fill, hands.and.sparkles.fill, shower.fill, toothbrush.fill,
sun.max.fill, flame.fill, target, checkmark.seal.fill. Если ничего не подходит — "target".

effects — 2-4 мотивационных (не медицинских) эффекта, milestone дни из 3,7,14,30,60,90,
иконки строго из: lungs, heart, skin, brain, energy, sleep, mood, weight, clock, money.
"""


def _build_dialog_messages(goal_title: str, qa_pairs: list[dict]) -> list[dict]:
    messages = [{"role": "user", "content": f"Моя цель: {goal_title}"}]
    for qa in qa_pairs:
        messages.append({
            "role": "assistant",
            "content": json.dumps({"status": "question", "question": qa["question"]}, ensure_ascii=False),
        })
        if qa.get("answer"):
            messages.append({"role": "user", "content": qa["answer"]})
    return messages


async def advance_goal_dialog(
    goal_title: str,
    qa_pairs: list[dict],
    user_profile: Optional[dict] = None,
    lang: str = "ru",
) -> dict:
    """Один шаг диалога создания цели.

    Возвращает либо {"status": "question", "question": ...},
    либо {"status": "ready", "goal": {...полная структура...}}.
    """
    profile_note = ""
    if user_profile:
        profile_note = f"\nПрофиль пользователя: {json.dumps(user_profile, ensure_ascii=False)}"

    response = await client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1500,
        system=_SYSTEM_GOAL + profile_note + _lang_directive(lang),
        messages=_build_dialog_messages(goal_title, qa_pairs),
    )
    return _extract_json(response.content[0].text.strip())


async def generate_insights(user_data: dict) -> list[str]:
    system = """
Ты — аналитик приложения для личных целей. На основе данных за месяц
напиши 2-3 персональных инсайта. Конкретно (с цифрами), мотивирующе, честно.

Примеры:
- "В дни когда ты выполнял все цели, твоя энергия была на 38% выше"
- "Твой вес снизился на 1.2 кг за 3 недели — совпадает с отказом от сладкого"

Отвечай JSON массивом: ["инсайт 1", "инсайт 2"]
"""
    response = await client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=512,
        system=system,
        messages=[{"role": "user", "content": json.dumps(user_data, ensure_ascii=False)}],
    )
    return _extract_json(response.content[0].text.strip())


_SYSTEM_DAILY = """
Ты — внимательный личный наставник в приложении целей. Каждый день ты коротко
РЕАГИРУЕШЬ на вчерашний день пользователя и на общую динамику — по-человечески,
тепло, но честно (не подлизываешься, не ругаешь). Обращайся на «ты».

На входе JSON: цели с сериями и процентами за 30 дней, блок yesterday (что вчера
выполнено/пропущено по каждой цели), день недели, энергия/вес если есть.

Дай 3–4 карточки. Каждая — объект:
- kind: одно из
  "reaction" — ПРЯМАЯ реакция на вчерашний день (что получилось и что нет вчера);
  "win" — конкретная победа/прогресс;
  "watch" — на что обратить внимание, мягкое предупреждение о риске (срыв серии и т.п.);
  "tip" — один конкретный совет/шаг на сегодня;
  "trend" — динамика за период с цифрой.
- title: 2–4 слова, ёмкий заголовок.
- text: 1–2 живые фразы, конкретно, с цифрами где они есть.

ПРАВИЛА:
- Ровно одна карточка kind="reaction" и она ПЕРВАЯ.
- Остальные — разные виды (не три "tip" подряд).
- Опирайся на РЕАЛЬНЫЕ данные из yesterday и серий. Каждый день звучи по-новому,
  не повторяй вчерашние формулировки.
- Если данных мало (пользователь только начал) — поддержи и предложи простой шаг.
- Без воды и общих фраз. Никаких медицинских заявлений.

Отвечай ТОЛЬКО JSON-массивом объектов:
[{"kind":"reaction","title":"...","text":"..."}, ...]
"""


async def generate_daily_reactions(user_data: dict, lang: str = "ru") -> list[dict]:
    """Ежедневные структурированные реакции ИИ на вчерашний день и динамику."""
    response = await client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=900,
        system=_SYSTEM_DAILY + _lang_directive(lang),
        messages=[{"role": "user", "content": json.dumps(user_data, ensure_ascii=False)}],
    )
    data = _extract_json(response.content[0].text.strip())
    if not isinstance(data, list):
        return []
    out = []
    for item in data:
        if not isinstance(item, dict):
            continue
        text = (item.get("text") or item.get("content") or "").strip()
        if not text:
            continue
        out.append({
            "kind": (item.get("kind") or "tip").strip().lower(),
            "title": (item.get("title") or "").strip()[:120],
            "text": text,
        })
    return out


_SPHERE_ICONS = "lungs, heart, brain, energy, sleep, mood, weight, skin, clock, money, figure, drop, leaf, flame, bolt"

_SYSTEM_ASSIGN_SPHERES = f"""
Ты ведёшь реестр «сфер развития» пользователя — областей тела/психики/навыков,
на которые влияют его цели (например: Лёгкие, Сердце, Выносливость, Острота ума,
Начитанность, Энергия, Сон, Настроение, Кожа, Контроль веса, Дисциплина, Финансы).

На вход: новая цель и СПИСОК уже существующих сфер пользователя.
Определи 1–3 сферы, на которые эта цель РЕАЛЬНО влияет.
- Если подходящая сфера уже есть в списке — ПЕРЕИСПОЛЬЗУЙ её (верни тот же key, new=false).
- Если подходящей нет — создай новую: короткий латинский key (snake_case), человекочитаемое
  русское name, icon из списка. new=true.
- Не плоди дубликаты по смыслу (если есть «Лёгкие» — не создавай «Дыхание»).

icon строго из: {_SPHERE_ICONS}.

Отвечай ТОЛЬКО JSON-массивом:
[{{"key":"lungs","name":"Лёгкие","icon":"lungs","new":false}}, ...]
"""


async def assign_spheres(goal_info: dict, existing_spheres: list[dict], lang: str = "ru") -> list[dict]:
    payload = {"goal": goal_info, "existing_spheres": existing_spheres}
    response = await client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=400,
        system=_SYSTEM_ASSIGN_SPHERES + _lang_directive(lang),
        messages=[{"role": "user", "content": json.dumps(payload, ensure_ascii=False)}],
    )
    data = _extract_json(response.content[0].text.strip())
    if not isinstance(data, list):
        return []
    out = []
    for it in data:
        if not isinstance(it, dict) or not it.get("key"):
            continue
        out.append({
            "key": str(it["key"]).strip().lower().replace(" ", "_")[:40],
            "name": (it.get("name") or it["key"]).strip()[:80],
            "icon": (it.get("icon") or "sparkle").strip().lower()[:40],
            "new": bool(it.get("new", True)),
        })
    return out


_SYSTEM_SPHERE_UPDATE = f"""
Ты моделируешь РЕАЛИСТИЧНУЮ динамику сфер развития человека. У каждой сферы есть
текущее значение 0–100. На вход — сферы с текущими значениями и поведение пользователя
по влияющим целям за последнее время (серия, выполнение за 7 и 30 дней, давность последнего
пропуска/срыва, сколько дней цель существует).

Опираясь на ЗНАНИЕ о том, как реально меняются такие показатели в жизни, определи НОВОЕ
значение каждой сферы и короткую человеческую подпись (1 фраза):
- Стабильное выполнение — плавный рост; физиология восстанавливается медленно, навыки растут
  чуть быстрее, но всё равно постепенно.
- Пропуски/срывы — откат. Масштаб отката определяй сам по природе сферы: возобновление курения
  быстро и сильно отбрасывает «Лёгкие»/«Сердце»; пара пропущенных дней чтения почти не вредит
  «Начитанности». Физиология откатывается ощутимее, навыки — мягче.
- Никаких фиксированных формул и резких необъяснимых скачков вверх. Значение строго 0–100.
- Если по сфере давно нет активности — она медленно проседает (детренированность).

Отвечай ТОЛЬКО JSON-массивом:
[{{"key":"lungs","value":12,"caption":"Срыв на неделю откатил восстановление лёгких"}}]
"""


async def compute_sphere_updates(spheres_payload: list[dict], lang: str = "ru") -> list[dict]:
    response = await client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=900,
        system=_SYSTEM_SPHERE_UPDATE + _lang_directive(lang),
        messages=[{"role": "user", "content": json.dumps(spheres_payload, ensure_ascii=False)}],
    )
    data = _extract_json(response.content[0].text.strip())
    if not isinstance(data, list):
        return []
    out = []
    for it in data:
        if not isinstance(it, dict) or not it.get("key"):
            continue
        try:
            val = max(0, min(100, int(round(float(it.get("value", 0))))))
        except (TypeError, ValueError):
            continue
        out.append({
            "key": str(it["key"]).strip().lower(),
            "value": val,
            "caption": (it.get("caption") or "").strip()[:160],
        })
    return out
