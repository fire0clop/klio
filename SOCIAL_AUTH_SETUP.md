# Настройка Sign in with Apple и Sign in with Google

Полная инструкция: получить ключи/идентификаторы, прописать их в проекте, проверить, что вход работает. Все имена файлов и плейсхолдеры, которые надо заменить, перечислены в конце.

---

## Часть 1. Sign in with Apple

Apple для **iOS-приложения** ничего отдельного выдавать не надо — нужна только включённая capability в Developer-аккаунте и правильно собранные entitlements в Xcode. Никаких ключей в `.env` для проверки токенов на iOS не требуется (мы проверяем подпись по публичному JWKS).

### 1.1. Включить capability в Apple Developer Portal

1. Зайди на <https://developer.apple.com/account>.
2. **Certificates, Identifiers & Profiles → Identifiers**.
3. Найди идентификатор `com.klio.diary` (или создай, если ещё не существует).
4. В списке capabilities включи **Sign In with Apple**, нажми **Save**.
5. Подтверди, что Team ID совпадает с тем, что в `frontend/Klio.xcodeproj` (`DEVELOPMENT_TEAM = Z3PM3LR5FF`).

### 1.2. Пересоздать профиль провизии

После включения capability:
- Xcode → Settings → Accounts → Manage Certificates → пересоздай или дай Xcode подтянуть.
- Или вручную: Developer Portal → **Profiles** → пересоздать App Store + Development profiles для `com.klio.diary`.

### 1.3. Проверить entitlements в проекте

Файл `frontend/Sources/App/Klio.entitlements` уже создан и содержит:
```xml
<key>com.apple.developer.applesignin</key>
<array><string>Default</string></array>
```
В `project.yml` уже прописана ссылка `CODE_SIGN_ENTITLEMENTS: Sources/App/Klio.entitlements`.

После любых изменений `project.yml` пересобери проект:
```bash
cd frontend
xcodegen generate
```

### 1.4. Бэкенд

`APPLE_CLIENT_ID` в `.env` бэкенда **должен совпадать с iOS bundle ID** (`com.klio.diary`) — Apple использует bundle ID как `aud`-claim в `identity_token`. По умолчанию в `app/config.py` так и стоит, но если ты захочешь добавить отдельный Service ID для web-входа, надо будет принимать обе аудиенции (массив).

В `.env` добавь (или оставь дефолт):
```
APPLE_CLIENT_ID=com.klio.diary
```

**Готово.** Sign in with Apple должен работать на реальном устройстве (на симуляторе с пустым iCloud — не работает; используй настоящий iCloud-аккаунт).

---

## Часть 2. Sign in with Google

Google требует создать **OAuth 2.0 iOS Client ID** в Google Cloud Console. Это бесплатно, лимиты огромные.

### 2.1. Создать проект и включить API

1. Зайди в <https://console.cloud.google.com/>.
2. Сверху создай новый проект, назови, например, `Klio-iOS`. Подожди, пока создастся, и выбери его в шапке.
3. Слева **APIs & Services → OAuth consent screen**:
   - User Type: **External**, Create.
   - App name: `Klio` (или как хочешь).
   - User support email: твой почтовый адрес.
   - Developer contact: твой email.
   - Scopes: добавлять не нужно — `openid email profile` идут by default.
   - Test users: пока в режиме *Testing* добавь свой Google-аккаунт, иначе никто не сможет войти. (При публикации перевести в *Production*.)
   - Save.

### 2.2. Создать OAuth 2.0 iOS Client ID

1. **APIs & Services → Credentials → Create credentials → OAuth client ID**.
2. **Application type: iOS**.
3. Name: `Klio iOS`.
4. **Bundle ID**: `com.klio.diary` (ровно как в Xcode).
5. Create.

Google покажет:
- **Client ID**: `1234567890-abcdefghijklmn.apps.googleusercontent.com`
- **iOS URL scheme** (reversed): `com.googleusercontent.apps.1234567890-abcdefghijklmn`

Оба значения тебе понадобятся.

### 2.3. Прописать в iOS-приложении

**А. `frontend/Sources/App/Core/Config/AppConfig.swift`** — замени плейсхолдеры:

```swift
static let googleClientID = "1234567890-abcdefghijklmn.apps.googleusercontent.com"
static let googleReversedClientID = "com.googleusercontent.apps.1234567890-abcdefghijklmn"
```

**Б. `frontend/Sources/App/Info.plist`** — найди узел `CFBundleURLSchemes`, замени:

```xml
<string>com.googleusercontent.apps.REPLACE_ME</string>
```
на свой reversed Client ID:
```xml
<string>com.googleusercontent.apps.1234567890-abcdefghijklmn</string>
```

### 2.4. Прописать на бэкенде

В `backend/.env` добавь строку (полный Client ID, **не reversed**):
```
GOOGLE_CLIENT_ID=1234567890-abcdefghijklmn.apps.googleusercontent.com
```

Перезапусти контейнер бэкенда, чтобы он подхватил переменную.

---

## Часть 3. Применить миграцию БД

Добавились поля `apple_sub`, `google_sub` и `password_hash` стал nullable. Применить миграцию:

```bash
cd backend
docker compose exec api alembic upgrade head
```

(или локально, если запускаешь без docker: `alembic upgrade head` из `backend/`).

Установи новую зависимость `httpx` (она уже в `pyproject.toml`):
```bash
cd backend
pip install -e .
# или внутри контейнера: docker compose build api
```

---

## Часть 4. Регенерация Xcode-проекта

После всех правок:
```bash
cd frontend
xcodegen generate
```

Открой `Klio.xcodeproj`, выбери таргет → **Signing & Capabilities** → убедись:
- **Sign in with Apple** включена (если нет — нажми `+ Capability`, добавь).
- **Team** = твой team.
- В **Info** → URL Types есть схема `com.googleusercontent.apps.<reversed>`.

---

## Часть 5. Тестирование

### Apple
- Запускай **на реальном устройстве** или симуляторе с активным iCloud-аккаунтом.
- Жмёшь кнопку «Apple» → системная шторка Apple ID → подтверждение → должно открыться приложение залогиненным.

### Google
- Симулятор подходит.
- Жмёшь «Google» → откроется системный Safari/окно ASWebAuthenticationSession → логин в Google → редирект назад в приложение.
- Первый раз iOS спросит «Klio хочет использовать accounts.google.com для входа» — это нормально.

### Что проверить в логах бэкенда
- Запрос `POST /api/v1/auth/apple` или `/auth/google` → 200 OK.
- В таблице `users` появилась запись с заполненным `apple_sub` / `google_sub`.

---

## Чек-лист «всё ли я заменил»

| Где | Что заменить | На что |
|---|---|---|
| `backend/.env` | (нет ключа) | `GOOGLE_CLIENT_ID=...full client id...` |
| `backend/.env` | (опционально) | `APPLE_CLIENT_ID=com.klio.diary` |
| `frontend/Sources/App/Core/Config/AppConfig.swift` | `REPLACE_ME.apps.googleusercontent.com` | свой Google iOS client ID |
| `frontend/Sources/App/Core/Config/AppConfig.swift` | `com.googleusercontent.apps.REPLACE_ME` | свой reversed client ID |
| `frontend/Sources/App/Info.plist` | `com.googleusercontent.apps.REPLACE_ME` | свой reversed client ID |
| Apple Developer Portal | — | включить **Sign In with Apple** для `com.klio.diary` |
| Google Cloud Console | — | создать OAuth iOS client + добавить себя в Test Users |

---

## Что произойдёт после успешного входа

1. iOS получает `identity_token` (Apple) или `id_token` (Google).
2. Шлёт его на наш бэкенд: `POST /api/v1/auth/apple` или `/auth/google`.
3. Бэкенд:
   - Скачивает публичные ключи Apple/Google (кешируется 1 час).
   - Проверяет подпись JWT, `iss`, `aud`, `exp`.
   - Ищет пользователя по `apple_sub` / `google_sub`. Если нет — ищет по email и связывает с существующим аккаунтом. Если и так нет — создаёт нового.
   - Возвращает наши собственные `access_token` + `refresh_token` (стандартная пара).
4. iOS сохраняет токены в Keychain через `SessionStore` — дальше всё как при обычном email-входе.

---

## Возможные подводные камни

- **Apple отдаёт email только при первом входе.** Поэтому iOS-клиент передаёт `email` и `name` из credential — на бэке мы сохраняем их в профиль.
- **Apple-relay-email** (`xxx@privaterelay.appleid.com`) — это нормальный email, его можно сохранять как есть.
- **Google в режиме Testing** не пускает никого, кроме Test Users. Перед паблик-релизом нажми **Publish App** на странице OAuth consent screen.
- **Несовпадение Bundle ID** — самая частая ошибка. Поле «iOS bundle ID» в Google Console и `PRODUCT_BUNDLE_IDENTIFIER` в Xcode должны совпадать ровно по байту.
- **Apple на симуляторе** без авторизованного iCloud-аккаунта возвращает ошибку `1000`. Это норма — проверяй на реальном устройстве или зайди в Settings симулятора под Apple ID.
