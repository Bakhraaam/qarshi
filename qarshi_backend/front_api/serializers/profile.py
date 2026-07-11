from rest_framework import serializers
# from front_api.models import TelegramAccount
from sync_1c.serializers import  PriceTypeSyncSerializer
from sync_1c.models import UserProfile
from django.contrib.auth.models import User


class UserAuthSerializer(serializers.ModelSerializer):
    """
    Глобальный сериализатор авторизации для Flutter.
    Строится вокруг гарантированного объекта User.
    Динамически подтягивает b2b-профиль организации, если он существует.
    """
    profile = serializers.SerializerMethodField()
    support = serializers.SerializerMethodField()
    telegram_account = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ['id', 'profile', 'support', 'telegram_account']

    @staticmethod
    def _price_type_dict(price_type):
        """Безопасно сериализует вид цены; None -> None (у организации может быть не задан)."""
        if not price_type:
            return None
        return {
            "id": str(price_type.id),
            "name": price_type.name,
            "currency": price_type.currency,
        }

    @staticmethod
    def _resolve_price_type(profile, organization):
        """
        Определяет вид цены по приоритету:
        1) вид цены профиля контрагента (если задан);
        2) вид цены по умолчанию у организации (Organization.price_type);
        3) любой вид цены филиала с is_default=True (как при регистрации).
        Возвращает объект PriceType или None, если у филиала вообще нет типов цен.
        """
        if profile and profile.price_type:
            return profile.price_type
        if not organization:
            return None
        # У Organization нет поля price_type — розничный fallback берём по is_default.
        return organization.default_price_type

    def get_profile(self, obj):
        """
        Ищет b2b профиль текущего юзера для конкретного филиала.
        Если 1С еще не выгрузила профиль — отдает безопасные гостевые данные.
        """
        # Достаем View и текущую организацию из контекста запроса
        view = self.context.get('view')
        current_organization = getattr(view, 'current_organization', None)

        # Ищем профиль пользователя строго в рамках текущей организации
        profile = None
        if current_organization:
            profile = UserProfile.objects.filter(user=obj, organization=current_organization).first()

        price_type = self._resolve_price_type(profile, current_organization)

        # 🚫 СЦЕНАРИЙ: Профиля из 1С еще нет (Клиент — Гость).
        # Отдаём вид цены по умолчанию филиала (is_default=True), если он настроен.
        if not profile:
            return {
                "id": None,
                "name": "",
                "inn": None,
                "is_blocked": False,
                "price_type": self._price_type_dict(price_type),
            }

        # ✅ СЦЕНАРИЙ: Профиль уже подтвержден/изменен в 1С
        return {
            "id": str(profile.id),
            "name": profile.name,
            "inn": profile.inn,
            "is_blocked": profile.is_blocked,
            "price_type": self._price_type_dict(price_type),
        }

    def get_support(self, obj):
        """Возвращает контакты техподдержки из текущей организации (филиала)"""
        view = self.context.get('view')
        current_organization = getattr(view, 'current_organization', None)

        if current_organization:
            return {
                "phone": getattr(current_organization, 'support_phone', '') or getattr(current_organization, 'phone',
                                                                                       ''),
                "telegram_username": getattr(current_organization, 'support_telegram', '') or getattr(
                    current_organization, 'telegram_username', ''),
                "instagram": getattr(current_organization, 'instagram', '') or ''
            }
        return {"phone": "", "telegram_username": "", "instagram": ""}

    def get_telegram_account(self, obj):
        """Возвращает глобальные данные телеграм аккаунта"""
        # Так как мы строим от User, связь telegram_account доступна напрямую через related_name
        tg_acc = getattr(obj, 'telegram_account', None)

        if tg_acc:
            return {
                "id": tg_acc.telegram_id,
                "username": tg_acc.telegram_username,
                "phone": tg_acc.phone,
                "first_name": tg_acc.tg_first_name,
                "last_name": tg_acc.tg_last_name,
                "photo_url": tg_acc.tg_photo_url,
                "language_code": tg_acc.tg_language_code
            }
        return {}


# class UserProfileSerializer(serializers.ModelSerializer):
#     """
#     Сериализатор Б2Б Профиля для Flutter.
#     Формирует строго заданную вложенную структуру данных пользователя.
#     """
#     # Переопределяем корневой id, чтобы он отдавал id из таблицы django User
#     id = serializers.IntegerField(source='user.id', read_only=True)
#
#     # Объявляем вложенные кастомные объекты
#     profile = serializers.SerializerMethodField()
#     support = serializers.SerializerMethodField()
#     telegram_account = serializers.SerializerMethodField()
#
#     class Meta:
#         model = UserProfile
#         fields = ['id', 'profile', 'support', 'telegram_account']
#
#     def get_profile(self, obj):
#         """Возвращает b2b данные текущего профиля организации"""
#         # --- ЕСЛИ ПРОФИЛЯ НЕТ (ГОСТЬ) ---
#         if obj is None:
#             # Пытаемся достать текущую организацию из контекста
#             org = self.context.get('current_organization')
#             # В вашей модели это поле называется price_type
#             org_price_type = getattr(org, 'price_type', None) if org else None
#
#             return {
#                 "id": None,
#                 "name": None,
#                 "inn": None,
#                 "price_type": PriceTypeSyncSerializer(org_price_type).data,
#                 "is_blocked": False,  # Для гостей всегда False
#             }
#
#         return {
#             "id": str(obj.id),
#             "name": obj.name,
#             "inn": obj.inn,
#             "price_type": PriceTypeSyncSerializer(obj.price_type).data if obj.price_type else {
#                 "name": "Розничная",
#                 "currency": "UZS"
#             },
#             "is_blocked": obj.is_blocked,
#         }
#
#     def get_support(self, obj):
#         """Возвращает контакты техподдержки из текущей организации (филиала)"""
#         org = obj.organization
#         if org:
#             return {
#                 # Подставляем поля техподдержки из твоей модели организации
#                 "phone": getattr(org, 'support_phone', '') or getattr(org, 'phone', ''),
#                 "telegram_username": getattr(org, 'support_telegram', '') or getattr(org, 'telegram_username', '')
#             }
#         return {"phone": "", "telegram_username": ""}
#
#     def get_telegram_account(self, obj):
#         """Возвращает глобальные данные телеграм аккаунта, привязанного к юзеру"""
#         # Безопасно ищем OneToOne связь с TelegramAccount через модель User
#         tg_acc = getattr(obj.user, 'telegram_account', None)
#
#         if tg_acc:
#             return {"telegram_id": tg_acc.telegram_id,
#                 "telegram_username": tg_acc.telegram_username,
#                 "phone": tg_acc.phone,
#                 "tg_first_name": tg_acc.tg_first_name,
#                 "tg_last_name": tg_acc.tg_last_name,
#                 "tg_photo_url": tg_acc.tg_photo_url,
#                 "tg_language_code": tg_acc.tg_language_code
#             }
#         return {}


class TelegramAuthInputSerializer(serializers.Serializer):
    """
    Входной сериализатор для валидации данных от Telegram.
    """
    init_data = serializers.CharField(
        required=True,
        error_messages={"required": "Строка init_data является обязательной для авторизации."}
    )
    phone = serializers.CharField(
        required=False,
        allow_blank=True,
        allow_null=True
    )