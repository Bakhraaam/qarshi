from rest_framework import viewsets, status, mixins
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django.db import transaction

# Импортируем модели строго по вашей структуре
from sync_1c.models import Order, OrderItem, UserProfile
from front_api.models import CartItem

# Импортируем ваши новые сериализаторы
from front_api.serializers.orders import OrderListSerializer, OrderDetailSerializer
from front_api.serializers.catalog import resolve_item_price

from rest_framework_simplejwt.authentication import JWTAuthentication
from front_api.views.base import BaseFrontendGenericViewSet


class FrontendOrderViewSet(mixins.CreateModelMixin,
                           mixins.ListModelMixin,
                           mixins.RetrieveModelMixin,
                           BaseFrontendGenericViewSet):
    """
    Эндпоинт для работы с заказами авторизованного пользователя во Flutter.

    POST /api/v1/orders/     — Создать новый заказ из текущей корзины
    GET  /api/v1/orders/     — Получить список всех своих заказов (легкий формат)
    GET  /api/v1/orders/<id>/ — Получить полную карточку конкретного заказа со всеми товарами
    """
    permission_classes = [IsAuthenticated]
    authentication_classes = [JWTAuthentication]

    def get_queryset(self):
        # Пользователь видит строго только свои заказы
        qs = Order.objects.filter(user=self.request.user, organization=self.current_organization)
        # Тяжёлый prefetch (картинки/цены/остатки товаров) нужен только для карточки заказа.
        # Для списка достаточно самих позиций — там считается только items_count.
        if self.action == 'retrieve':
            qs = qs.prefetch_related(
                'items__item__images',
                'items__item__prices__price_type',
                'items__item__item_type',
                'items__item__stocks',
            )
        else:
            qs = qs.prefetch_related('items')
        return qs

    def get_serializer_class(self):
        # Если запрашивают конкретный заказ — отдаем полную детализацию, иначе — легкий список
        if self.action == 'retrieve':
            return OrderDetailSerializer
        return OrderListSerializer

    def _resolve_price_type(self):
        profile = UserProfile.objects.filter(
            user=self.request.user, organization=self.current_organization
        ).first()
        if profile and profile.price_type:
            return profile.price_type
        return self.current_organization.price_type

    def get_serializer_context(self):
        context = super().get_serializer_context()
        price_type = self._resolve_price_type()
        context['price_type_id'] = price_type.id if price_type else None
        return context

    def create(self, request, *args, **kwargs):
        """Оформление заказа: перенос товаров из корзины текущего субдомена в новый заказ"""
        user = request.user

        # 1. Достаем товары из корзины текущего филиала (+ prefetch цен против N+1)
        cart_items = CartItem.objects.filter(
            user=user,
            organization=self.current_organization
        ).select_related('item').prefetch_related('item__prices__price_type')

        if not cart_items.exists():
            return Response(
                {"ok": False,
                 "message": f"Невозможно оформить заказ. Ваша корзина для филиала {self.current_organization.name} пуста."},
                status=status.HTTP_400_BAD_REQUEST
            )

        total_order_amount = 0
        order_items_to_create = []

        # Определяем B2B тип цен пользователя один раз (B2B под профиль, иначе розница филиала)
        price_type = self._resolve_price_type()
        price_type_id = price_type.id if price_type else None

        # 2. ЭТАП ВАЛИДАЦИИ И РАСЧЕТА ЦЕН (До записи в базу данных)
        for cart_item in cart_items:
            product = cart_item.item
            # Единая логика цены из подгруженных данных (без запроса на каждый товар)
            price = resolve_item_price(product, price_type_id)

            # 🔥 ЖЕСТКАЯ ПРОВЕРКА: Если цена отсутствует или равна 0.0
            if price <= 0:
                return Response(
                    {
                        "ok": False,
                        "message": f"Товар '{product.name}' (Артикул: {product.articul or 'нет'}) не имеет настроенной цены в филиале {self.current_organization.name}. Оформление заказа невозможно, обратитесь в поддержку."
                    },
                    status=status.HTTP_400_BAD_REQUEST
                )

            # Если цена есть, спокойно считаем сумму строки
            item_total_amount = price * cart_item.quantity
            total_order_amount += item_total_amount

            # Собираем объекты позиций заказа в память (пока без привязки к order)
            order_items_to_create.append(
                OrderItem(
                    item=product,
                    quantity=cart_item.quantity,
                    price=price,
                    total_amount=item_total_amount
                )
            )

        # 3. ЭТАП ЗАПИСИ В БАЗУ ДАННЫХ (Запускается, только если ВСЕ товары имеют цены)
        with transaction.atomic():
            # Создаем шапку заказа
            order = Order.objects.create(
                user=user,
                organization=self.current_organization
            )

            # Проставляем созданный order_id во все позиции в памяти
            for order_item in order_items_to_create:
                order_item.order = order

            # Пакетно сохраняем позиции заказа в БД
            OrderItem.objects.bulk_create(order_items_to_create)

            # Записываем финальную сумму
            order.total_amount = total_order_amount
            order.save()

            # Очищаем корзину этого филиала
            cart_items.delete()

        # 4. Возвращаем созданный заказ во Flutter
        return_serializer = OrderDetailSerializer(order, context=self.get_serializer_context())
        return Response({
            "ok": True,
            "message": "Заказ успешно оформлен",
            "order_number": order.order_number if hasattr(order, 'order_number') else order.id,
            "result": return_serializer.data
        }, status=status.HTTP_200_OK)