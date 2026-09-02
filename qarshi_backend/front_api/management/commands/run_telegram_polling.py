"""
Запуск бота в режиме long polling (без вебхука).

    python manage.py run_telegram_polling                 # все филиалы с токеном, по потоку на каждый
    python manage.py run_telegram_polling --org bot1      # один филиал
    python manage.py run_telegram_polling --org bot1 --once   # один цикл опроса (для проверки)

Процесс долгоживущий: в Docker поднимается отдельным сервисом `bot`
(`docker compose --profile polling up -d bot`).
"""
import threading

from django.core.management.base import BaseCommand

from front_api.bot import polling
from sync_1c.models import Organization


class Command(BaseCommand):
    help = "Опрашивает Telegram (getUpdates) и обрабатывает сообщения бота филиала"

    def add_arguments(self, parser):
        parser.add_argument('--org', dest='org', default=None,
                            help='Префикс одного филиала (по умолчанию — все с токеном бота)')
        parser.add_argument('--timeout', dest='timeout', type=int, default=polling.LONG_POLL_TIMEOUT,
                            help='Таймаут long polling в секундах (по умолчанию 25)')
        parser.add_argument('--once', action='store_true',
                            help='Один цикл опроса и выход — для диагностики')

    def handle(self, *args, **options):
        queryset = Organization.objects.exclude(telegram_bot_token='').exclude(telegram_bot_token=None)
        if options['org']:
            queryset = queryset.filter(prefix=options['org'])

        organizations = list(queryset.order_by('prefix'))
        if not organizations:
            self.stdout.write(self.style.WARNING(
                "Не найдено ни одной организации с заполненным telegram_bot_token."))
            return

        timeout = options['timeout']

        if options['once']:
            for organization in organizations:
                offset, processed = polling.poll_once(
                    organization, polling.get_offset(organization), timeout, log=self._log)
                self.stdout.write(self.style.SUCCESS(
                    f"{organization.prefix}: обработано {processed}, offset={offset}"))
            return

        if len(organizations) == 1:
            self._run(organizations[0], timeout)
            return

        # Несколько ботов — по потоку на каждого: getUpdates держит соединение открытым
        threads = [threading.Thread(target=self._run, args=(organization, timeout),
                                    name=f"tg-{organization.prefix}", daemon=True)
                   for organization in organizations]
        for thread in threads:
            thread.start()
        self.stdout.write(self.style.SUCCESS(
            f"Запущен опрос для филиалов: {', '.join(o.prefix for o in organizations)}"))
        try:
            while any(t.is_alive() for t in threads):
                for thread in threads:
                    thread.join(timeout=1)
        except KeyboardInterrupt:
            self.stdout.write("Остановлено.")

    def _run(self, organization, timeout):
        try:
            polling.run_forever(organization, timeout, log=self._log)
        except KeyboardInterrupt:
            self.stdout.write(f"[{organization.prefix}] остановлено.")

    def _log(self, message):
        self.stdout.write(str(message))
