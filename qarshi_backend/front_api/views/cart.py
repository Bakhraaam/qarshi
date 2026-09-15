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
        POST /api/v1/<org>/cart/ — Добавить товар или изменить количество ОДНОЙ строки.
        Принимает: {"item_id": "UUID", "quantity": 20, "package_id": "UUID" | null}

        Строка определяется парой «товар + единица»: один и тот же товар можно положить
        и коробками, и штуками — это две разные строки, и запрос меняет только ту,
        чья единица передана. `package_id` не передан или null — строка базовой единицы.

        `quantity` — ВСЕГДА в базовых единицах товара, даже для строки коробками:
        цена в прайсе за базовую единицу. Пересчёт делает фронт, он знает множитель
        упаковки из выдачи каталога. 0 или меньше — удалить эту строку.
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

        if not Item.objects.filter(id=item_id, organization=self.current_organization).exists():
            return Response({"ok": False, "message": "Указанный товар не найден в этом филиале"},
                            status=status.HTTP_404_NOT_FOUND)

        # Чужую или несуществующую упаковку отклоняем, а не подменяем базовой единицей:
        # теперь это разные строки, и молчаливая подмена влила бы коробки в строку штук.
        if package_id and not ItemPackage.objects.filter(id=package_id, item_id=item_id).exists():
            return Response({"ok": False, "message": "Упаковка не относится к этому товару"},
                            status=status.HTTP_400_BAD_REQUEST)

        line = CartItem.objects.filter(
            user=request.user,
            item_id=item_id,
            organization=self.current_organization,
            package_id=package_id,
        )

        if quantity <= 0:
            line.delete()
            return Response({"ok": True, "message": "Товар удален из корзины"}, status=status.HTTP_200_OK)

        # update_or_create по полному ключу строки. package_id=None здесь превращается
        # в IS NULL, поэтому строка базовой единицы находится так же, как и упаковочная.
        cart_item, created = CartItem.objects.update_or_create(
            user=request.user,
            item_id=item_id,
            organization=self.current_organization,
            package_id=package_id,
            defaults={'quantity': quantity},
        )

        msg = "Товар добавлен в корзину" if created else "Количество товара обновлено"
        return Response({"ok": True, "message": msg}, status=status.HTTP_200_OK)

    def destroy(self, request, pk=None, *args, **kwargs):
        """DELETE /api/v1/<org>/cart/{item_id}/ — удалить товар из корзины во ВСЕХ единицах.
        Одну строку удаляют через POST cart/ с quantity=0 и её package_id."""
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