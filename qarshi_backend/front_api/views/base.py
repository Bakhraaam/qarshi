from rest_framework.views import APIView
from rest_framework.viewsets import ViewSet, ReadOnlyModelViewSet, GenericViewSet
from rest_framework.exceptions import APIException, NotFound
from sync_1c.models import Organization


# 1. Создаем кастомное исключение для ошибки 400 Bad Request
class SubdomainValidationError(APIException):
    status_code = 400
    default_detail = 'Ошибка валидации субдомена.'
    default_code = 'invalid_subdomain'


class BaseFrontendGenericViewSet(GenericViewSet):
    """
    Базовый GenericViewSet для фронтенда (заказы, профили).
    Автоматически определяет организацию по субдомену.
    """
    current_organization = None
    org_prefix = None

    def initial(self, request, *args, **kwargs):
        super().initial(request, *args, **kwargs)

        # host = request.get_host().split(':')[0]
        # host_parts = host.split('.')
        # self.org_prefix = host_parts[0] if len(host_parts) > 1 else None
        self.org_prefix = self.kwargs.get('org_prefix')

        if not self.org_prefix:
            raise SubdomainValidationError({
                "ok": False,
                "message": "Доступ разрешен только через субдомен организации (например, avto.myshop.uz)"
            })

        self.current_organization = Organization.objects.filter(prefix=self.org_prefix).first()
        if not self.current_organization:
            raise NotFound({
                "ok": False,
                "message": f"Филиал '{self.org_prefix}' не найден в системе"
            })


class BaseFrontendReadOnlyModelViewSet(ReadOnlyModelViewSet):
    """
    Базовый ViewSet для каталогов и списков на фронтенде.
    Автоматически определяет организацию по субдомену.
    """
    current_organization = None
    org_prefix = None

    def initial(self, request, *args, **kwargs):
        super().initial(request, *args, **kwargs)

        self.org_prefix = self.kwargs.get('org_prefix')
        # host = request.get_host().split(':')[0]
        # host_parts = host.split('.')
        # self.org_prefix = host_parts[0] if len(host_parts) > 1 else None

        if not self.org_prefix:
            raise SubdomainValidationError({
                "ok": False,
                "message": "Доступ разрешен только через субдомен организации (например, avto.myshop.uz)"
            })

        self.current_organization = Organization.objects.filter(prefix=self.org_prefix).first()
        if not self.current_organization:
            raise NotFound({
                "ok": False,
                "message": f"Филиал '{self.org_prefix}' не найден в системе"
            })

class BaseFrontendAPIView(APIView):
    """
    Базовый класс для всего фронтенда сайта.
    Автоматически находит организацию по субдомену.
    """
    current_organization = None
    org_prefix = None

    # ИСПРАВЛЕНО: Вместо dispatch используем метод initial
    def initial(self, request, *args, **kwargs):
        # Сначала обязательно запускаем стандартную инициализацию DRF (auth, permissions)
        super().initial(request, *args, **kwargs)

        # Получаем чистый хост (например, "avto.localhost")
        # host = request.get_host().split(':')[0]
        # host_parts = host.split('.')
        # breakpoint()
        # Первая часть адреса — это наш субдомен
        self.org_prefix = self.kwargs.get('org_prefix')

        if not self.org_prefix:
            # Вместо return Response выбрасываем кастомное исключение 400
            raise SubdomainValidationError({
                "ok": False,
                "message": "Доступ разрешен только через субдомен организации (например, avto.myshop.uz)"
            })

        # Ищем организацию в базе
        self.current_organization = Organization.objects.filter(prefix=self.org_prefix).first()

        if not self.current_organization:
            # Вместо return Response выбрасываем встроенное исключение 404
            raise NotFound({
                "ok": False,
                "message": f"Филиал '{self.org_prefix}' не зарегистрирован в системе"
            })


class BaseFrontendViewSet(ViewSet):
    """
    Базовый класс для всего фронтенда сайта.
    Автоматически находит организацию по субдомену.
    """
    current_organization = None
    org_prefix = None

    # ИСПРАВЛЕНО: Вместо dispatch используем метод initial
    def initial(self, request, *args, **kwargs):
        # Сначала обязательно запускаем стандартную инициализацию DRF (auth, permissions)
        super().initial(request, *args, **kwargs)

        # Получаем чистый хост (например, "avto.localhost")
        # host = request.get_host().split(':')[0]
        # host_parts = host.split('.')
        #
        # # Первая часть адреса — это наш субдомен
        # self.org_prefix = host_parts[0] if len(host_parts) > 1 else None

        # Если зашли просто на localhost или главный домен без субдомена
        self.org_prefix = self.kwargs.get('org_prefix')

        if not self.org_prefix:
            # Вместо return Response выбрасываем кастомное исключение 400
            raise SubdomainValidationError({
                "ok": False,
                "message": "Доступ разрешен только через субдомен организации (например, avto.myshop.uz)"
            })

        # Ищем организацию в базе
        self.current_organization = Organization.objects.filter(prefix=self.org_prefix).first()

        if not self.current_organization:
            # Вместо return Response выбрасываем встроенное исключение 404
            raise NotFound({
                "ok": False,
                "message": f"Филиал '{self.org_prefix}' не зарегистрирован в системе"
            })