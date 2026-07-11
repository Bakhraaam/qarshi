FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Зависимости отдельным слоем для кэша
COPY requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

# Код
COPY . .

# Точка входа: миграции + collectstatic, затем gunicorn
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
CMD ["gunicorn", "qarshi_backend.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "3", "--timeout", "60"]
