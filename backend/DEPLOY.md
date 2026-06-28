# Деплой Klio Backend на VPS

## Требования к серверу
- Ubuntu 22.04+ / Debian 12
- 1 GB RAM минимум
- Docker + Docker Compose v2
- Домен с A-записью, направленной на IP сервера

## 1. Установить Docker

```bash
curl -fsSL https://get.docker.com | sh
```

## 2. Загрузить код на сервер

```bash
git clone <your-repo-url> /opt/klio
cd /opt/klio/backend
```

## 3. Создать .env из примера

```bash
cp .env.example .env
nano .env
```

Заполнить все значения `CHANGE_ME`:
- `POSTGRES_PASSWORD` — придумать надёжный пароль
- `DATABASE_URL` — обновить с тем же паролем
- `SECRET_KEY` — сгенерировать: `python3 -c "import secrets; print(secrets.token_hex(64))"`
- `ANTHROPIC_API_KEY` — вставить ключ
- `GOOGLE_CLIENT_ID` — вставить

## 4. Прописать домен в Caddyfile

```bash
nano Caddyfile
```

Заменить `api.yourdomain.com` на свой домен.

## 5. Применить миграции

```bash
docker compose -f docker-compose.prod.yml run --rm api alembic upgrade head
```

## 6. Запустить

```bash
docker compose -f docker-compose.prod.yml up -d
```

Проверить что всё поднялось:
```bash
docker compose -f docker-compose.prod.yml ps
curl https://api.yourdomain.com/health
```

## 7. Обновление в будущем

```bash
git pull
docker compose -f docker-compose.prod.yml build api
docker compose -f docker-compose.prod.yml up -d --no-deps api
# Если были миграции:
docker compose -f docker-compose.prod.yml run --rm api alembic upgrade head
```

## Логи

```bash
docker compose -f docker-compose.prod.yml logs api -f
```
