from django.core.management.base import BaseCommand
from django.db import transaction
from sync_1c.models import PriceList


class Command(BaseCommand):
    help = "Полная и безопасная очистка таблицы PriceList (Цены товаров)"

    def add_arguments(self, parser):
        # Добавляем необязательный флаг, чтобы скрипт не спрашивал подтверждения
        parser.add_argument(
            '--no-input',
            action='store_true',
            help='Удалить данные без подтверждения в терминале',
        )

    def handle(self, *args, **options):
        # ИСПРАВЛЕНО: используем 'no_input' вместо 'no-input'
        if not options['no_input']:
            confirm = input("Вы уверены, что хотите ПОЛНОСТЬЮ очистить все цены товаров? (yes/no): ")
            if confirm.lower() != 'yes':
                self.stdout.write(self.style.WARNING("Очистка отменена."))
                return

        self.stdout.write("Начало очистки таблицы PriceList...")

        try:
            # Оборачиваем в транзакцию, чтобы база данных сработала надежно
            with transaction.atomic():
                # Удаляем все записи и получаем количество удаленных строк
                deleted_count, _ = PriceList.objects.all().delete()

            self.stdout.write(
                self.style.SUCCESS(f"Успешно! Таблица полностью очищена. Удалено записей: {deleted_count}")
            )

        except Exception as e:
            self.stdout.write(
                self.style.ERROR(f"Произошла ошибка при очистке: {str(e)}")
            )