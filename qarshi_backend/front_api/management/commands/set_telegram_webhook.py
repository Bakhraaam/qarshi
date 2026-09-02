"""
Регистрация (или удаление) вебхука Telegram-бота для филиалов.

Прод (URL берётся из TELEGRAM_WEBAPP_URL_TEMPLATE, т.е. https://<prefix>.qarshi1s.uz):
    python manage.py set_telegram_webhook
    python manage.py set_telegram_webhook --org avto

Локально через ngrok (один туннель на все филиалы):
    python manage.py set_telegram_webhook --base-url https://xxxx.ngrok-free.app

Снять вебхук:
    python manage.py set_telegram_webhook --org avto --delete
"""
from django.core.management.base import BaseCommand
from django.conf import settings

from front_api.bot import api
from sync_1c.models import Organization


class Command(BaseCommand):
    help = "Регистрирует вебхук Telegram-бота для организаций с заполненным telegram_bot_token"

    def add_arguments(self, parser):
        parser.add_argument('--org', dest='org', default=None,
                            help='Префикс одной организации (по умолчанию — все с токеном бота)')
        parser.add_argument('--base-url', dest='base_url', default=None,
                            help='Базовый URL для вебхука, например ngrok-туннель. '
                                 'По умолчанию — TELEGRAM_WEBHOOK_BASE_URL или домен филиала')
        parser.add_argument('--delete', action='store_true',
                            help='Удалить вебхук вместо регистрации')
        parser.add_argument('--drop-pending', action='store_true',
                            help='Отбросить накопившиеся необработанные апдейты')

    def handle(self, *args, **options):
        queryset = Organization.objects.exclude(telegram_bot_token='').exclude(telegram_bot_token=None)
        if options['org']:
            queryset = queryset.filter(prefix=options['org'])

        organizations = list(queryset.order_by('prefix'))
        if not organizations:
            self.stdout.write(self.style.WARNING(
                "Не найдено ни одной организации с заполненным telegram_bot_token."))
            return

        default_base = options['base_url'] or getattr(settings, 'TELEGRAM_WEBHOOK_BASE_URL', '')

        for organization in organizations:
            token = organization.telegram_bot_token.strip()
            prefix = organization.prefix or ''

            if options['delete']:
                result = api.call(token, 'deleteWebhook',
                                  {'drop_pending_updates': options['drop_pending']})
                self._report(f"{prefix}: deleteWebhook", result)
                continue

            base = (default_base or api.webapp_base_url(organization)).rstrip('/')
            webhook_url = f"{base}/api/v1/{prefix}/telegram/webhook/"
            result = api.call(token, 'setWebhook', {
                'url': webhook_url,
                'secret_token': api.webhook_secret(prefix),
                'allowed_updates': ['message'],
                'drop_pending_updates': options['drop_pending'],
            })
            self._report(f"{prefix}: {webhook_url}", result)

    def _report(self, title, result):
        if result.get('ok'):
            self.stdout.write(self.style.SUCCESS(f"OK  {title}"))
        else:
            self.stdout.write(self.style.ERROR(
                f"FAIL {title} — {result.get('description', 'нет описания ошибки')}"))
