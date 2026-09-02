# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Django 4.2 + Django REST Framework backend for a **multi-tenant B2B ordering platform**. A single Django instance serves many organizations ("филиалы"/branches). Products, prices, stock, and orders originate in the client's **1C ERP** and are pushed into this backend, which then exposes a read/order API to a Flutter frontend (web + Telegram WebApp).

Codebase and comments are in Russian.

## Commands

Standard Django management via `manage.py` (settings module: `qarshi_backend.settings`):

```bash
python manage.py runserver            # dev server
python manage.py migrate              # apply migrations
python manage.py makemigrations       # create migrations after model changes
python manage.py createsuperuser      # admin access
python manage.py test                 # run tests (test files are currently empty stubs)
python manage.py test front_api       # run one app's tests
```

Custom data-maintenance commands (in `sync_1c/management/commands/`), useful for resetting synced data:

```bash
python manage.py clear_item [--no-input]        # wipe all Items
python manage.py clear_pricelist [--no-input]   # wipe all PriceLists
python manage.py clear_itemstock [--no-input]   # wipe all ItemStocks
```

**Environment/setup notes:**
- Requires PostgreSQL. Connection and secrets come from `.env` (loaded via `python-dotenv` in `settings.py`): `SECRET_KEY`, `DEBUG`, `ALLOWED_HOSTS`, `DB_*`, `API_TOKEN`.
- There is **no `requirements.txt`**. The checked-in `venv/` is stale (does not contain the real deps). Dependencies inferred from imports: `django==4.2.5`, `djangorestframework`, `djangorestframework-simplejwt`, `django-filter`, `django-cors-headers`, `python-dotenv`, `psycopg2`. If you add a dep, there is no lockfile to update — flag this to the user.

## Architecture

Two Django apps sit on top of a shared data model. Understanding the split is the key to this codebase:

### `sync_1c` — the source of truth (1C → backend ingestion)
- **Owns all the core models** (`sync_1c/models.py`): `Organization`, `ItemType`, `Item`, `ItemImage`, `PriceType`, `PriceList`, `ItemStock`, `UserProfile`, `Order`, `OrderItem`. `front_api` imports these; it does not redefine them.
- Most primary keys are **UUIDs that come from 1C** (`id = UUIDField`), so upserts key on the 1C-provided id.
- Exposes machine-to-machine endpoints under `/sync_1c/...` (`sync_1c/urls.py`, all logic in the single large `sync_1c/views.py`). Views subclass `Base1cAPIView` (TokenAuth + IsAuthenticated) and use `bulk_create(..., update_conflicts=True)` upserts. Direction is bidirectional: 1C pushes catalog/price/stock/user data in; `orders/pull` and `orders/update` let 1C pull placed orders and write back statuses / 1C order numbers.

### `front_api` — the tenant-facing app API (Flutter frontend)
- Adds only **frontend-specific models** (`front_api/models.py`): `TelegramAccount`, `CartItem` (server-side cart).
- URLs mounted at `/api/v1/<org_prefix>/...` (see root `qarshi_backend/urls.py`). **`<org_prefix>` in the URL path is how tenancy is resolved** — not by subdomain (subdomain logic is commented out).
- `front_api/views/base.py` defines base classes (`BaseFrontendAPIView`, `BaseFrontendViewSet`, `BaseFrontendReadOnlyModelViewSet`, `BaseFrontendGenericViewSet`). Their `initial()` reads `org_prefix` from the URL kwargs, looks up the `Organization`, and stashes it as `self.current_organization` (400 if missing, 404 if unknown). **All frontend querysets must filter by `self.current_organization`** — this is the tenant isolation boundary. New frontend views should extend these base classes.
- Views are split by domain: `catalog.py` (categories/products, paginated, `?query=` search, `?category=` filter), `cart.py`, `orders.py`, `auth.py`. Serializers mirror this split under `front_api/serializers/`.

### Cross-cutting concerns
- **Two auth schemes coexist.** Global default (`settings.REST_FRAMEWORK`) is `TokenAuthentication` + `IsAuthenticated` — this governs the `sync_1c` (1C) endpoints. Frontend auth issues **SimpleJWT** tokens; auth endpoints (`auth/login`, `auth/register`, `auth/telegram`) set `authentication_classes = []` / `permission_classes = []` and return JWT access/refresh pairs (access 1 day, refresh 30 days).
- **User model.** Uses stock `django.contrib.auth.User`. A Django `User` is global; per-organization identity/pricing lives in `UserProfile` (has `organization` + `price_type`). Registration namespaces usernames as `{org_prefix}_{username}`; Telegram signups use `tg_{telegram_id}`.
- **Pricing** is per-organization and per-`PriceType`: `PriceList` is unique on `(item, price_type, organization)`. A user sees prices for their profile's `price_type`; anonymous users fall back to `Organization.price_type`.
- **Telegram WebApp login** (`auth/telegram`): `front_api/utils.py::verify_telegram_webapp_data` validates the HMAC signature against the org's `telegram_bot_token` and checks `auth_date` freshness (`TELEGRAM_AUTH_TTL_SECONDS`, default 24h). Note the `signature` field must stay inside `data_check_string` or the HMAC won't match. Account creation/sync is shared with the bot via `front_api/bot/accounts.py` (`upsert_telegram_account`, `ensure_profile`).
- `front_api.utils.DebugURLMiddleware` (first in the MIDDLEWARE stack) prints every incoming request to stdout; the sync/auth code also `print()`s liberally for debugging.
- `CORS_ALLOW_ALL_ORIGINS = True` is on. `TIME_ZONE = 'Asia/Tashkent'`, `LANGUAGE_CODE = 'ru-ru'`.

### Telegram-бот филиала (`front_api/bot/`)
One bot per organization (token in `Organization.telegram_bot_token`), driven by a **webhook**, not polling:
`POST /api/v1/<org_prefix>/telegram/webhook/` (`front_api/views/telegram_bot.py`). Authenticity is the
`X-Telegram-Bot-Api-Secret-Token` header, compared against `api.webhook_secret(prefix)` — an HMAC of `SECRET_KEY`,
so no extra DB field and nothing to sync with 1C. Anything other than a bad secret answers **200** on purpose:
Telegram must not retry what we cannot process.

- `bot/texts.py` — all wording (business tone, ru only). Edit texts here, never in handlers.
- `bot/api.py` — Bot API client on stdlib `urllib` (no new dependency) + the one keyboard. The bot deliberately does
  **not** duplicate in-app navigation: its only button is the contact request, removed once the number arrives.
  The Mini App is opened by Telegram's own entry points (menu button / "Open" on the bot), not by bot buttons.
- `bot/handlers.py` — `/start`, contact, foreign contact, free text, blocked access.
- `bot/accounts.py` — shared with `TelegramAuthView`.

Phone is **requested, not required**: nothing in the WebApp gates on `TelegramAccount.phone`, the bot just asks once.
There is no way to match a phone to a 1C counterparty on the backend —
`UserProfile` has no phone field — so after a contact arrives the bot only promises "передано менеджеру"; the real
link appears when 1C fills `guid_partner1c`.

Registering the webhook (needs a public HTTPS URL; locally use the ngrok tunnel):
```bash
python manage.py set_telegram_webhook                                  # all orgs with a bot token
python manage.py set_telegram_webhook --org avto                       # one branch
python manage.py set_telegram_webhook --base-url https://x.ngrok-free.app   # local dev
python manage.py set_telegram_webhook --org avto --delete
```
`TELEGRAM_WEBAPP_URL_TEMPLATE` (default `https://{prefix}.qarshi1s.uz`) builds both the WebApp button URLs and, unless
`TELEGRAM_WEBHOOK_BASE_URL` is set, the webhook URL. Tests: `python manage.py test front_api` (Bot API is mocked).

**Delivery is swappable.** Where Telegram cannot reach the server (inbound blocked — the `bot1.qarshi1s.uz` case,
outbound works but Telegram's subnets time out on the way in), run long polling instead: `bot/polling.py` +
`manage.py run_telegram_polling` feed the very same `handle_update`. The two modes are mutually exclusive —
`getUpdates` returns 409 while a webhook is registered, so the command drops the webhook on start (keeping the
queued updates). Offsets live in the cache (`telegram:polling:offset:<prefix>`), so a restart doesn't replay
messages. In Docker it is a separate profiled service: `docker compose --profile polling up -d bot`.

### Order lifecycle
Frontend places an order (`front_api/views/orders.py`) → `Order`/`OrderItem` created (status `new`, human number auto-generated as `ORD-YYYYMMDD-NNNN` in `Order.save()`) → 1C pulls it via `sync_1c` `orders/pull` → 1C writes back `order_number_1c` and status via `orders/update`.
