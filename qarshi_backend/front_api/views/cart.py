from rest_framework.viewsets import ViewSet
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework import status
from rest_framework.decorators import action
from sync_1c.models import Item, ItemPackage
from front_api.serializers.cart import CartItemOutputSerializer
from front_api.models import CartItem
from rest_framework_simplejwt.authentication import JWTAuthentication
from front_api.views.base import BaseFrontendViewSet
from decimal import Decimal, InvalidOperation


class FrontendCartViewSet(BaseFrontendViewSet):
    """
    Управление корзиной для Flutter.
    Доступно только авторизованным пользователям.
    """
    permission_classes = [IsAuthenticated]
    authentication_classes = [JWTAuthentication]

    def list(self, request, *args, **kwargs):
        """GET /api/v1/front/cart/ — Получить содержимое корзины"""
        # Оптимизированный запрос к базе (выбираем всё за один раз, + stocks против N+1)
        cart_items = CartItem.objects.filter(
            user=request.user,
            organization=self.current_organization) \
            .select_related('item', 'item__item_type', 'package') \
            .prefetch_related('item__images', 'item__packages', 'item__prices__price_type', 'item__stocks')

        # Вид цены резолвим один раз и передаём в контекст (B2B под пользователя, иначе розница)
        profile = request.user.profile.filter(organization=self.current_organization).first()
        # У Organization нет поля price_type — розничный fallback берём по is_default.
        price_type = (profile.price_type if profile and profile.price_type
                      else self.current_organization.default_price_type)
        context = {'request': request, 'price_type_id': price_type.id if price_type else None}

        serializer = CartItemOutputSerializer(cart_items, many=True, context=context)

        # Считаем итоговые показатели по точным ключам из сериализатора
        total_cart_price = sum(item['total'] for item in serializer.data)
        total_items_count = sum(item['quantity'] for item in serializer.data)

        return Response({
            "ok": True,
            "total_items_count": total_items_count,
            "total_cart_price": total_cart_price,
            "results": serializer.data
        }, status=status.HTTP_200_OK)

    def create(self, request, *args, **kwargs):
        """
        POST /api/v1/front/cart/ — Добавить товар или изменить его количество.
        Принимает: {"item_id": "UUID", "quantity": 20, "package_id": "UUID" | null}

        `quantity` — ВСЕГДА в базовых единицах товара, даже если клиент набирал коробками:
        цена в прайсе за базовую единицу, поэтому пересчёт делает фронт (он знает множитель
        упаковки из выдачи каталога), а бэкенд хранит одну однозначную величину.
        `package_id` — необязателен, запоминаем его только чтобы показать количество обратно
        в той же упаковке и перенести её в заказ.
        """
        item_id = request.data.get('item_id')
        quantity = request.data.get('quantity')
        package_id = request.data.get('package_id') or None

        if not item_id or quantity is None:
            return Response({"ok": False, "message": "Поля item_id и quantity обязательны"},
                            status=status.HTTP_400_BAD_REQUEST)

        try:
            quantity = Decimal(str(quantity).replace(',', '.'))
        except (InvalidOperation, ValueError):
            return Response({"ok": False, "message": "Количество должно быть числом"},
                            status=status.HTTP_400_BAD_REQUEST)

        if quantity <= 0:
            # Если Flutter прислал 0 или меньше — расцениваем как удаление позиции
            CartItem.objects.filter(
                user=request.user,
                item_id=item_id,
                organization=self.current_organization,
            ).delete()
            return Response({"ok": True, "message": "Товар удален из корзины"}, status=status.HTTP_200_OK)

        if not Item.objects.filter(id=item_id, organization=self.current_organization).exists():
            return Response({"ok": False, "message": "Указанный товар не найден в этом филиале"},
                            status=status.HTTP_404_NOT_FOUND)

        # Упаковка должна принадлежать этому же товару — иначе игнорируем и считаем,
        # что позиция набрана базовыми единицами.
        if package_id and not ItemPackage.objects.filter(id=package_id, item_id=item_id).exists():
            package_id = None

        # Создаем запись или перезаписываем количество (благодаря unique_together)
        cart_item, created = CartItem.objects.update_or_create(
            user=request.user,
            item_id=item_id,
            organization=self.current_organization,
            defaults={'quantity': quantity, 'package_id': package_id}
        )

        msg = "Товар добавлен в корзину" if created else "Количество товара обновлено"
        return Response({"ok": True, "message": msg}, status=status.HTTP_200_OK)

    def destroy(self, request, pk=None, *args, **kwargs):
        """DELETE /api/v1/front/cart/{item_id}/ — Полностью удалить товар из корзины"""
        deleted, _ = CartItem.objects.filter(
            user=request.user,
            item_id=pk,
            organization=self.current_organization
        ).delete()
        if deleted:
            return Response({"ok": True, "message": "Товар полностью удален из корзины"}, status=status.HTTP_200_OK)
        return Response({"ok": False, "message": "Товар не найден в вашей корзине"}, status=status.HTTP_404_NOT_FOUND)

    @action(detail=False, methods=['delete'])
    def clear(self, request, *args, **kwargs):
        """DELETE /api/v1/front/cart/clear/ — Полностью очистить корзину"""
        CartItem.objects.filter(user=request.user, organization=self.current_organization).delete()
        return Response({"ok": True, "message": "Корзина успешно очищена"}, status=status.HTTP_200_OK)