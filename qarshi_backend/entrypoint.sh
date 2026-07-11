#!/bin/sh
set -e

# Ждём БД (db поднимается healthcheck'ом, но подстрахуемся)
echo "Applying migrations..."
python manage.py migrate --noinput

echo "Collecting static..."
python manage.py collectstatic --noinput

# Запускаем переданную команду (gunicorn из CMD)
exec "$@"
