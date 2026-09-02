"""
Вебхук Telegram-бота филиала.

URL: POST /api/v1/<org_prefix>/telegram/webhook/
Организация определяется префиксом в URL (как и весь front_api), токен бота и
тексты берутся из этой организации. Подлинность запроса проверяется заголовком
X-Telegram-Bot-Api-Secret-Token (Telegram присылает его, если он задан в setWebhook).
"""
import hmac

from rest_framework import status
from rest_framework.response import Response

from front_api.bot import api
from front_api.bot.handlers import handle_update
from front_api.views.base import BaseFrontendAPIView

SECRET_HEADER = 'X-Telegram-Bot-Api-Secret-Token'


class TelegramWebhookView(BaseFrontendAPIView):
    authentication_classes = []
    permission_classes = []

    def post(self, request, *args, **kwargs):
        organization = self.current_organization

        provided = request.headers.get(SECRET_HEADER, '')
        expected = api.webhook_secret(organization.prefix or '')
        if not hmac.compare_digest(provided, expected):
            # Частая причина: setWebhook сделали без secret_token или SECRET_KEY на сервере
            # отличается от того, которым секрет считали
            print(f"Telegram webhook '{organization.prefix}': отклонён запрос — "
                  f"заголовок {SECRET_HEADER} "
                  f"{'не совпал с ожидаемым' if provided else 'отсутствует'}")
            return Response({"ok": False, "message": "Неверный секрет вебхука"},
                            status=status.HTTP_403_FORBIDDEN)

        if not (organization.telegram_bot_token or '').strip():
            # Отвечаем 200: Telegram не должен ретраить то, что мы не можем обработать
            print(f"Telegram webhook: у филиала '{organization.prefix}' пуст telegram_bot_token")
            return Response({"ok": False, "message": "У организации не задан telegram_bot_token"},
                            status=status.HTTP_200_OK)

        update = request.data if isinstance(request.data, dict) else {}
        try:
            handle_update(organization, update)
        except Exception as err:
            # Любая ошибка обработки — наша проблема, а не повод для лавины ретраев
            print(f"Telegram webhook '{organization.prefix}': ошибка обработки апдейта — {type(err).__name__}: {err}")

        return Response({"ok": True}, status=status.HTTP_200_OK)
