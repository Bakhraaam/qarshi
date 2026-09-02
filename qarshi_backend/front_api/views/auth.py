import json
import urllib
from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from rest_framework.response import Response
from rest_framework import status
from sync_1c.models import UserProfile, PriceType
from front_api.serializers.profile import UserAuthSerializer, TelegramAuthInputSerializer
from rest_framework_simplejwt.tokens import RefreshToken
from django.db import transaction
from front_api.models import TelegramAccount
from front_api.views.base import BaseFrontendAPIView
from front_api.bot.accounts import ensure_profile, upsert_telegram_account
from front_api.utils import normalize_phone, verify_telegram_webapp_data


class TelegramAuthView(BaseFrontendAPIView):
    """
    Эндпоинт бесшовного автоматического входа/регистрации через Telegram WebApp.
    Поддерживает мульти-аккаунты организаций и сквозное отслеживание статусов.
    URL: POST /api/v1/<str:org_prefix>/auth/telegram/
    """
    permission_classes = []
    authentication_classes = []

    def post(self, request, *args, **kwargs):
        # 1. Валидация входящего JSON через входной сериализатор
        input_serializer = TelegramAuthInputSerializer(data=request.data)
        if not input_serializer.is_valid():
            return Response({"ok": False, "errors": input_serializer.errors}, status=status.HTTP_400_BAD_REQUEST)

        init_data = input_serializer.validated_data.get('init_data')
        raw_phone = input_serializer.validated_data.get('phone')

        # Криптографически проверяем подпись initData по токену бота организации.
        # verify_telegram_webapp_data возвращает распарсенный dict пользователя либо None.
        user_data = verify_telegram_webapp_data(self.current_organization, init_data)
        if not user_data or not user_data.get('id'):
            return Response({
                "ok": False,
                "message": "Не удалось подтвердить подпись Telegram. Проверьте настройку telegram_bot_token у организации."
            }, status=status.HTTP_403_FORBIDDEN)

        # 3. ШАГ №1: глобальный TelegramAccount по telegram_id — создаём при первом
        # входе, иначе синхронизируем данные из Telegram. Та же логика используется
        # вебхуком бота (front_api/bot/accounts.py), поэтому вынесена в общий хелпер.
        try:
            tg_account = upsert_telegram_account(user_data, phone=raw_phone)
        except Exception as parse_err:
            print(f"Критическая ошибка при создании аккаунта: {str(parse_err)}")
            return Response({
                "ok": False,
                "message": f"Критическая ошибка при создании аккаунта: {str(parse_err)}"
            }, status=status.HTTP_400_BAD_REQUEST)

        # 4. ШАГ №2: B2B-профиль для ТЕКУЩЕЙ ОРГАНИЗАЦИИ.
        # При первом входе создаётся с видом цены по умолчанию (is_default=True).
        user = tg_account.user
        profile = ensure_profile(user, self.current_organization)

        # 5. ПРОВЕРКА СТАТУСА БЛОКИРОВКИ
        # Телефон поддержки филиала добавляем в текст, если он заполнен.
        support_phone = (getattr(self.current_organization, 'support_phone', '') or '').strip()
        contact_suffix = f" Телефон поддержки: {support_phone}" if support_phone else ""

        # Глобальная блокировка учётной записи Django
        if not user.is_active:
            return Response({
                "ok": False,
                "account_status": "blocked",
                "support_phone": support_phone,
                "message": "Вход запрещен. Ваш аккаунт заблокирован или отменен менеджером." + contact_suffix
            }, status=status.HTTP_403_FORBIDDEN)

        # Блокировка профиля в ТЕКУЩЕЙ организации (is_blocked в UserProfile)
        if profile and profile.is_blocked:
            return Response({
                "ok": False,
                "account_status": "blocked",
                "support_phone": support_phone,
                "message": "Вход запрещен. Ваш аккаунт заблокирован или отменен менеджером в этой организации." + contact_suffix
            }, status=status.HTTP_403_FORBIDDEN)

        # 6. ГЕНЕРАЦИЯ JWT-ТОКЕНОВ САЙТА
        refresh = RefreshToken.for_user(user)

        # 7. СБОРКА JSON ЧЕРЕЗ СЕРИАЛИЗАТОР
        # Передаем контекст, чтобы сериализатор мог рассчитать цены на основе организации
        # profile_serializer = UserProfileSerializer(profile, context={'request': request, 'view': self,})
        auth_serializer = UserAuthSerializer(user, context={'request': request, 'view': self})

        # print(f'user_data: {auth_serializer.data}')

        return Response({
            "ok": True,
            "tokens": {
                "access": str(refresh.access_token),
                "refresh": str(refresh),
            },
            "user": auth_serializer.data  # Полный красивый JSON профиля для Flutter
        }, status=status.HTTP_200_OK)


class FrontendLoginView(BaseFrontendAPIView):
    """
    Эндпоинт ручного входа / привязки аккаунта по логину и паролю 1С.
    URL: POST /api/v1/<str:org_prefix>/auth/login/
    """
    permission_classes = []
    authentication_classes = []

    def post(self, request, *args, **kwargs):
        username = request.data.get('username')
        password = request.data.get('password')

        # 🔔 ПРИНИМАЕМ ДАННЫЕ ТГ ДЛЯ РУЧНОЙ СВЯЗКИ (если они переданы со смартфона во Flutter)
        tg_id = request.data.get('telegram_id')
        tg_username = request.data.get('telegram_username')
        tg_first_name = request.data.get('tg_first_name', '')
        tg_last_name = request.data.get('tg_last_name', '')

        if not username or not password:
            return Response({"ok": False, "message": "Логин и пароль обязательны"}, status=status.HTTP_400_BAD_REQUEST)

        # 1. Аутентифицируем по чистому логину (как его создала 1С при выгрузке)
        user = authenticate(username=username, password=password)

        if user is None:
            return Response({"ok": False, "message": "Неверный логин или пароль"}, status=status.HTTP_400_BAD_REQUEST)

        # 2. Проверяем глобальную активность учетной записи Django
        if not user.is_active:
            return Response({"ok": False, "message": "Пользователь полностью заблокирован на сайте."},
                            status=status.HTTP_403_FORBIDDEN)

        # 3. Ищем Б2Б-профиль пользователя конкретно для ТЕКУЩЕЙ организации (филиала)
        profile = UserProfile.objects.filter(user=user, organization=self.current_organization).first()

        # Если профиля вообще нет в этой организации
        if not profile:
            return Response({
                "ok": False,
                "account_status": "no_profile",
                "message": "У вас нет доступа к этой организации (филиалу)."
            }, status=status.HTTP_403_FORBIDDEN)

        # Если профиль есть, но он заблокирован менеджером 1С
        if profile.is_blocked:
            return Response({
                "ok": False,
                "account_status": "blocked",
                "message": "Вход запрещен. Ваш аккаунт заблокирован или отменен менеджером в этой организации."
            }, status=status.HTTP_403_FORBIDDEN)
        
        # 4. 🔔 МАГИЯ РУЧНОЙ ПРИВЯЗКИ К TELEGRAM
        if tg_id:
            with transaction.atomic():
                # Проверяем на безопасность: не занят ли этот telegram_id кем-то другим в базе
                existing_tg = TelegramAccount.objects.filter(telegram_id=tg_id).first()
                if existing_tg and existing_tg.user != user:
                    return Response({
                        "ok": False,
                        "message": f"Этот аккаунт Telegram уже жестко привязан к другому логину ({existing_tg.user.username})."
                    }, status=status.HTTP_400_BAD_REQUEST)

                # Создаем или обновляем глобальную ТГ-карточку, привязывая её к нашему User
                TelegramAccount.objects.update_or_create(
                    user=user,
                    defaults={
                        "telegram_id": tg_id,
                        "telegram_username": tg_username,
                        "tg_first_name": tg_first_name,
                        "tg_last_name": tg_last_name
                    }
                )
                print(f"Успешная ручная привязка Telegram ID {tg_id} к пользователю {user.username}")

        # 5. ГЕНЕРАЦИЯ JWT-ТОКЕНОВ
        refresh = RefreshToken.for_user(user)

        # 6. СБОРКА ИДЕАЛЬНОГО JSON ЧЕРЕЗ СЕРИАЛИЗАТОР USER
        auth_serializer = UserAuthSerializer(user, context={'request': request, 'view': self})

        return Response({
            "ok": True,
            "tokens": {
                "access": str(refresh.access_token),
                "refresh": str(refresh),
            },
            "user": auth_serializer.data  # Структурированный вложенный JSON для Flutter
        }, status=status.HTTP_200_OK)


class FrontendRegisterView(BaseFrontendAPIView):

    permission_classes = []
    authentication_classes = []

    def post(self, request):
        username = request.data.get('username')
        password = request.data.get('password')
        name = request.data.get('name')
        inn = request.data.get('inn', '')  # ИНН необязателен для физлиц

        # Базовая проверка обязательных полей
        if not username or not password or not name:
            return Response(
                {"ok": False, "message": "Поля 'username', 'password' и 'name' обязательны для заполнения"},
                status=status.HTTP_400_BAD_REQUEST
            )

        system_username = f"{self.org_prefix}_{username}"

        # Проверяем, не занят ли логин
        if User.objects.filter(username=system_username).exists():
            return Response(
                {"ok": False, "message": "Пользователь с таким логином уже зарегистрирован"},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Тип цен обязателен (price_type = NOT NULL). Берём RETAIL, иначе любой тип цен
        # этой организации. Проверяем ДО создания пользователя, чтобы не плодить "сирот".
        default_price_type = PriceType.objects.filter(
            is_default=True,
            organization=self.current_organization
        )
        
        if not default_price_type:
            return Response(
                {"ok": False, "message": "В организации не настроен ни один тип цен. Обратитесь в поддержку."},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            with transaction.atomic():
                # 1. Создаем системного пользователя Django (пароль захешируется автоматически)
                user = User.objects.create_user(username=system_username, password=password)

                # 2. Создаем профиль контрагента.
                # UUID для поля 'id' сгенерируется автоматически встроенным в модель uuid.uuid4
                UserProfile.objects.create(
                    user=user,
                    name=name,
                    inn=inn,
                    price_type=default_price_type,
                    organization=self.current_organization,
                )

            return Response(
                {"ok": True, "message": "Регистрация успешна!"},
                status=status.HTTP_201_CREATED
            )
        except Exception as e:
            return Response(
                {"ok": False, "message": f"Ошибка при регистрации: {str(e)}"},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )
