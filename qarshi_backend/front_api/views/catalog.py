import hashlib

from rest_framework.viewsets import ReadOnlyModelViewSet
from rest_framework.pagination import PageNumberPagination
from rest_framework.filters import SearchFilter
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework_simplejwt.authentication import JWTAuthentication
from django_filters.rest_framework import DjangoFilterBackend
from django.conf import settings
from django.core.cache import cache
import django_filters


# Читаем данные напрямую из sync_1c
from sync_1c.models import Item, ItemType
from front_api.serializers.catalog import (
    FrontendCategorySerializer,
    FrontendProductListSerializer,
    FrontendProductDetailSerializer,
)
from front_api.views.base import BaseFrontendReadOnlyModelViewSet
from front_api.cache import get_catalog_version


class FrontApiPagination(PageNumberPagination):
    """Пагинация для бесконечного скролла во Flutter"""
    page_size = 20
    page_size_query_param = 'page_size'
    max_page_size = 100


class FrontendCategoryViewSet(BaseFrontendReadOnlyModelViewSet):

    serializer_class = FrontendCategorySerializer
    permission_classes = []
    authentication_classes = []

    def get_queryset(self):
        # Недействительные категории на сайте не показываем — как и их товары
        return ItemType.objects.filter(
            organization=self.current_organization,
            is_invalid=False,
        ).distinct().order_by('name')


class FrontendSearchFilter(SearchFilter):
    """Переопределяет стандартный параметр ?search= на ?query="""
    search_param = 'query'


class ProductFilter(django_filters.FilterSet):
    """
    Связывает параметр ?category= из URL
    с полем item_type_id (категорией) в базе данных
    """
    category = django_filters.UUIDFilter(field_name='item_type_id')

    class Meta:
        model = Item
        fields = ['category']


class FrontendProductViewSet(BaseFrontendReadOnlyModelViewSet):
    """
    Эндпоинт товаров с поддержкой поиска, фильтра по категориям
    и умного диапазона цен (от - до) под конкретного пользователя.
    """
    # JWT разрешаем, но не требуем: с токеном B2B-клиент увидит свою цену, без токена — розницу.
    permission_classes = [AllowAny]
    authentication_classes = [JWTAuthentication]
    pagination_class = FrontApiPagination

    filter_backends = [DjangoFilterBackend, FrontendSearchFilter]
    filterset_class = ProductFilter
    search_fields = ['name', 'articul', 'code']  # Глобальный поиск (/?search=смартфон)

    def _resolve_price_type(self):
        """Один раз определяем нужный вид цены: B2B под пользователя, иначе розница филиала."""
        user = self.request.user
        if user and user.is_authenticated:
            profile = user.profile.filter(organization=self.current_organization).first()
            if profile and profile.price_type:
                return profile.price_type
        # У Organization нет поля price_type — розничный fallback берём по is_default.
        return self.current_organization.default_price_type

    def get_queryset(self):
        # На сайте показываем только товары, которые реально можно заказать:
        #  * сам товар не помечен в 1С как недействительный (is_invalid);
        #  * его категория тоже не помечена недействительной;
        #  * есть положительный остаток на складе этого филиала.
        # Остаток хранится в ItemStock с unique (item, organization), поэтому join
        # не размножает строки и .distinct() здесь не нужен.
        # Категорию отсекаем через exclude, а не filter(is_invalid=False): так товар
        # без категории остаётся в выдаче, а не отсеивается join'ом.
        # prefetch stocks добавлен: get_stock читает из памяти без N+1
        queryset = Item.objects.filter(
            organization=self.current_organization,
            is_invalid=False,
            stocks__organization=self.current_organization,
            stocks__stock__gt=0,
        ).exclude(item_type__is_invalid=True) \
            .select_related('item_type') \
            .prefetch_related('images', 'packages', 'prices__price_type', 'stocks') \
            .order_by('name')

        price_from = self.request.query_params.get('price_from')
        price_to = self.request.query_params.get('price_to')

        if price_from or price_to:
            target_price_type = self._resolve_price_type()
            price_conditions = {'prices__price_type': target_price_type}
            if price_from:
                price_conditions['prices__price__gte'] = price_from
            if price_to:
                price_conditions['prices__price__lte'] = price_to
            queryset = queryset.filter(**price_conditions).distinct()

        return queryset

    def get_serializer_class(self):
        # Карточка товара (GET products/<id>/) отдаёт галерею картинок и все реквизиты,
        # сетка каталога — облегчённый формат.
        if self.action == 'retrieve':
            return FrontendProductDetailSerializer
        return FrontendProductListSerializer

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context['view'] = self
        # Резолвим вид цены ОДИН раз на запрос (не на каждый товар) и кладём id в контекст
        price_type = self._resolve_price_type()
        context['price_type_id'] = price_type.id if price_type else None
        return context

    def _catalog_cache_key(self, request, price_type_id):
        """Ключ включает версию каталога организации (для мгновенной инвалидации),
        вид цены (цена зависит от него) и все параметры запроса (страница/поиск/фильтр)."""
        org = self.current_organization
        version = get_catalog_version(org.id)
        raw = f"{request.get_full_path()}|pt={price_type_id}|host={request.get_host()}"
        digest = hashlib.md5(raw.encode('utf-8')).hexdigest()
        return f"catalog:{org.id}:v{version}:{digest}"

    def list(self, request, *args, **kwargs):
        # Кэшируем готовый ответ каталога в Redis. Инвалидация — по версии организации
        # (bump_catalog_version при синхронизации из 1С), плюс страховочный TTL.
        price_type_id = self.get_serializer_context().get('price_type_id')
        cache_key = self._catalog_cache_key(request, price_type_id)

        cached = cache.get(cache_key)
        if cached is not None:
            return Response(cached)

        response = super().list(request, *args, **kwargs)
        cache.set(cache_key, response.data, getattr(settings, 'CATALOG_CACHE_TTL', 300))
        return response