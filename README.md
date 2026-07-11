# Qarshi — B2B ordering platform

Мультитенантная B2B-платформа заказов. Один backend обслуживает много организаций
(«филиалы»). Каталог, цены, остатки и заказы приходят из **1С**, синхронизируются в
backend, который отдаёт API для Flutter-клиента (web + Telegram WebApp).

## Структура (монорепо)

- **`qarshi_backend/`** — Django 5 + DRF. Два приложения:
  - `sync_1c` — модели (источник истины) и m2m-эндпоинты синхронизации с 1С.
  - `front_api` — API для Flutter-клиента (каталог, корзина, заказы, auth), мультитенантность по префиксу в URL.
- **`qarshi_front/`** — Flutter-приложение (web / Telegram WebApp).

Детальная документация по архитектуре — в [`CLAUDE.md`](CLAUDE.md) и
[`qarshi_backend/CLAUDE.md`](qarshi_backend/CLAUDE.md).

## Backend — запуск

```bash
cd qarshi_backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env          # заполнить реальными значениями
python manage.py migrate
python manage.py createsuperuser
python manage.py runserver 0.0.0.0:8000
```

Требуется PostgreSQL и Redis. Секреты — в `.env` (в git не коммитится): `SECRET_KEY`,
`DEBUG`, `ALLOWED_HOSTS`, `DB_*`, `API_TOKEN`, `BOT_TOKEN`.

## Frontend — запуск

```bash
cd qarshi_front
flutter pub get
flutter run -d chrome                       # dev
flutter build web --wasm --pwa-strategy=none # прод-сборка
```

Base URL API берётся из `DomainResolver` (same-origin) или переопределяется:
`--dart-define=API_DOMAIN=https://api.example.com`.

## Деплой (прод)

- Backend: `DEBUG=False`, задать `ALLOWED_HOSTS`, gunicorn/uwsgi за nginx.
- Раздача Flutter web: nginx (статика `build/web` + fallback на `index.html`),
  API `/api`, `/admin`, `/sync_1c` — в Django. Один origin.
- У каждой организации в БД должен быть задан `telegram_bot_token` для Telegram WebApp.
