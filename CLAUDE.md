# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This is a monorepo (not a git repo yet) for a **multi-tenant B2B ordering platform**. A single backend serves many organizations ("филиалы"/branches). Catalog, prices, stock, and orders originate in the client's **1C ERP** and sync into the backend, which exposes an ordering API to a Flutter client (web + Telegram WebApp). Code and comments are largely in Russian.

- `qarshi_backend/` — Django 4.2 + DRF backend. **Has its own detailed [CLAUDE.md](qarshi_backend/CLAUDE.md) — read it before touching backend code.** Two apps: `sync_1c` (owns all core models, 1C↔backend ingestion) and `front_api` (tenant-facing API for the Flutter client).
- `qarshi_front/` — Flutter app (`package: qarshi`), primarily a web/Telegram-WebApp target.

The two halves are coupled by a shared HTTP contract; see "The frontend↔backend contract" below.

## Frontend (`qarshi_front/`)

### Commands
```bash
flutter pub get                    # install deps
flutter run -d chrome              # run in browser (primary target)
flutter run                        # run on a connected device/emulator
flutter analyze                    # lint (uses flutter_lints via analysis_options.yaml)
flutter test                       # run all tests
flutter test test/widget_test.dart # run a single test file
flutter build web                  # production web build
```

### Architecture
- **Layering** (`lib/`): `core/` holds cross-cutting infrastructure — `data/api/` (Dio clients), `data/models.dart` (all JSON models + `fromJson`), `data/constants.dart` (global mutable app state), `router/` (go_router), `theme/`, `utils/`. `presentations/` holds `screens/` and `widgets/`. There is no state-management library; screens hold local state and call the API clients directly.
- **Global app state lives in `core/data/constants.dart`** as top-level mutable globals: `tokenAccess` (in-memory JWT), `currentUser`, `domain` (API base host), `AppName`. These are read directly across the app — grep for them before changing auth/tenancy behavior. Note the router gates on the in-memory `tokenAccess`, not the persisted token, so a fresh load routes to `/login` even though `AuthTokenManager` persisted a token to `SharedPreferences`.
- **Routing** (`core/router/app_router.dart`): go_router with a global `redirect` that sends unauthenticated users to `/login`. Routes: `/`, `/login`, `/catalog`, `/cart`, `/orders`. `setPathUrlStrategy()` in `main.dart` removes the URL hash for web.
- **API clients**: `DjangoApi` (`core/data/api/api_django.dart`) is the real client — login (password + Telegram), catalog, cart, orders. It attaches `Authorization: Bearer $tokenAccess` per-request (no shared Dio interceptor). Base URL comes from `DomainResolver.getBaseApiUrl()`. `Api1c` (`api_1c.dart`) is a stub pointed at a placeholder host — not wired into real flows.
- **Tenancy resolution** (`core/utils/domain_resolver.dart`): on web, reads the browser subdomain and builds the base URL as `{domain}/api/v1/{subdomain}/`. That trailing path segment is the org prefix the backend uses to resolve the tenant (see below). No subdomain ⇒ `{domain}/api/v1/`.
- **Sizing**: `ScreenUtilInit` (design size 375×812) — use `.w`/`.h`/`.sp` for responsive sizing; also see `core/utils/responsive.dart`.
- **Telegram WebApp**: login via the `telegram_web_app` package passes `init_data` to `auth/telegram/`; much of the Telegram request-contact flow in `screens/login.dart` is currently commented out.

## The frontend↔backend contract

Understanding these two conventions is essential when changing either side:

1. **Tenancy is carried in the URL path**, not a header or subdomain-on-the-server. The frontend derives an org prefix from its subdomain and calls `/api/v1/<org_prefix>/...`; the backend's `front_api` base views read `<org_prefix>` from the URL and scope every queryset to that `Organization`. Changing the URL shape breaks tenant isolation.
2. **Two auth schemes.** Frontend endpoints (`auth/login`, `auth/register`, `auth/telegram`) issue **SimpleJWT** access/refresh tokens; the client stores the access token and sends it as a Bearer header. The `sync_1c` (1C machine-to-machine) endpoints use DRF `TokenAuthentication` with a static `API_TOKEN`. Don't cross the wires.

For everything about models, sync/upsert semantics, order lifecycle, pricing, and the Telegram-signature-verification caveat, defer to [qarshi_backend/CLAUDE.md](qarshi_backend/CLAUDE.md).
