from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from django.db import transaction, IntegrityError

from .models import Organization, ItemType, Item, ItemImage, ItemPackage, PriceType, PriceList, UserProfile, ItemStock
from rest_framework.parsers import MultiPartParser, FormParser, JSONParser
from django.contrib.auth.models import User
from django.contrib.auth.hashers import make_password
from django.utils.dateparse import parse_datetime  # Правильно парсит строки в дату
from django.utils import timezone                  # Работает с временными зонами
from .models import Order, OrderItem
from .serializers import Order1COutputSerializer, Sync1cDirectTelegramUserSerializer, UserProfileSyncSerializer
from rest_framework.authentication import TokenAuthentication
from rest_framework.permissions import IsAuthenticated
import uuid
import base64
from decimal import Decimal, InvalidOperation
from django.core.files.base import ContentFile

from front_api.models import CartItem, TelegramAccount
from front_api.cache import bump_catalog_version

# from django.utils.dateparse import parse_datetime
from django.utils.timezone import is_naive, make_aware, now
from datetime import timedelta
from django.db.models import Q
# from rest_framework.views import APIView
# from rest_framework.response import Response
# from rest_framework import status

# from .serializers import Sync1cDirectTelegramUserSerializer


# Размер пачки для bulk_create/bulk_update. Даже если 1С пришлёт один большой
# payload, SQL внутри режется на части — нет гигантских запросов и пиков памяти.
SYNC_BATCH_SIZE = 500


class Base1cAPIView(APIView):
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]


class Sync1cUpdateOrganizationsView(Base1cAPIView):

    def post(self, request):
        orgs_data = request.data

        if not isinstance(orgs_data, list):
            return Response(
                {"ok": False, "message": "Ожидается массив JSON в теле запроса (список организаций)"},
                status=status.HTTP_400_BAD_REQUEST
            )

        if not orgs_data:
            return Response({"ok": True, "message": "Массив organizations пуст"}, status=status.HTTP_200_OK)

        # price_type у Organization необязателен (nullable). Проверяем, какие виды цен реально
        # есть в БД, и неизвестную ссылку обнуляем, а не валим весь пакет по FK.
        # pt_ids = {org.get("price_type") for org in orgs_data if org.get("price_type")}
        # valid_pt_ids = {str(p) for p in PriceType.objects.filter(id__in=pt_ids).values_list('id', flat=True)}

        orgs_to_upsert = []
        skipped = 0
        for org in orgs_data:
            if not org.get("id"):
                skipped += 1
                continue
            # pt_id = org.get("price_type")
            # if pt_id and str(pt_id) not in valid_pt_ids:
            #     pt_id = None  # вид цены ещё не загружен — не роняем организацию из-за этого
            orgs_to_upsert.append(
                Organization(id=org.get("id"),
                             inn=org.get("inn", ""),
                             name=org.get("name", ""),
                             prefix=org.get("prefix", ""),
                            #  price_type_id=pt_id,
                             support_phone=org.get("support_phone", ""),
                             telegram_bot_token=org.get("telegram_bot_token", ""),
                             instagram=org.get("instagram", ""),
                             unregistered_notice=org.get("unregistered_notice", ""))
            )

        try:
            if orgs_to_upsert:
                with transaction.atomic():
                    Organization.objects.bulk_create(
                        orgs_to_upsert, update_conflicts=True,
                        unique_fields=['id'], update_fields=['inn', 'name', 'prefix', 'support_phone', 'telegram_bot_token', 'instagram', 'unregistered_notice'],
                        batch_size=SYNC_BATCH_SIZE,
                    )
        except IntegrityError:
            return Response(
                {"ok": False, "message": "Ошибка целостности данных. Возможен дубликат префикса (prefix) организации."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if skipped:
            return Response(
                {"ok": False,
                 "message": f"Обработано организаций: {len(orgs_to_upsert)}. Пропущено (нет id): {skipped}"},
                status=status.HTTP_400_BAD_REQUEST
            )
        return Response(
            {"ok": True, "message": f"Успешно обработано организаций: {len(orgs_to_upsert)}"},
            status=status.HTTP_200_OK
        )


def parse_1c_bool(value):
    """Булево из 1С: она шлёт то true/false, то 1/0, то строку («Истина», «true», «да»).
    Всё, что не распознано (в том числе None — ключа нет), считаем False."""
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        return value.strip().lower() in ('true', '1', 'да', 'истина', 'yes')
    return False


def parse_1c_decimal(value, default=Decimal('0')):
    """Число из 1С: приходит то числом, то строкой, то с запятой вместо точки."""
    if value is None or value == '':
        return default
    try:
        return Decimal(str(value).strip().replace(',', '.'))
    except (InvalidOperation, ValueError):
        return default


def build_item_images(item_id, raw_images):
    """Картинки товара из массива `images` в строке 1С.

    Элемент — либо строка (путь к файлу, старый формат), либо объект
    {"id", "path"/"url"/"image_path", "is_main", "is_invalid"}: так 1С может
    прислать свой GUID картинки и пометку «недействительна», не перезаливая файл.
    """
    images = []
    for index, raw in enumerate(raw_images or []):
        if isinstance(raw, dict):
            path = raw.get('path') or raw.get('url') or raw.get('image_path')
            if not path:
                continue
            image_id = raw.get('id') or uuid.uuid4()
            is_main = parse_1c_bool(raw['is_main']) if 'is_main' in raw else (index == 0)
            is_invalid = parse_1c_bool(raw.get('is_invalid'))
        else:
            path = raw
            if not path:
                continue
            image_id = uuid.uuid4()
            is_main = (index == 0)
            is_invalid = False
        images.append(
            ItemImage(
                id=image_id,
                item_id=item_id,
                image_path=path,
                is_main=is_main,
                is_invalid=is_invalid,
            )
        )
    return images


# Пространство имён для ключей упаковок. Фиксированное: от него зависит, что
# повторная выгрузка той же упаковки обновит строку, а не создаст новую.
ITEM_PACKAGE_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_URL, 'qarshi:item-package')


def item_package_pk(item_id, guid_1c):
    """Ключ упаковки — из пары (товар, GUID единицы измерения из 1С).

    В 1С «Канистра 4л» это одна общая единица измерения, и её GUID приходит сразу
    у всех четырёхлитровых товаров. Если писать его в первичный ключ, все они
    схлопываются в одну строку, а INSERT ... ON CONFLICT падает с
    «cannot affect row a second time». Детерминированный uuid5 разводит их по
    строкам и при этом оставляет апсерт идемпотентным.
    """
    return uuid.uuid5(ITEM_PACKAGE_NAMESPACE, f"{item_id}:{guid_1c}")


def build_item_packages(item_id, raw_packages):
    """Упаковки товара из массива `packages` в строке 1С.

    Элемент — объект {"id", "name", "quantity", "is_default", "is_invalid"}, где
    `id` — GUID единицы измерения в 1С, а quantity — сколько БАЗОВЫХ единиц товара
    в одной упаковке. Строки без id или с неположительным quantity пропускаем:
    такая упаковка ничего не умножает.
    """
    packages = {}
    for raw in raw_packages or []:
        if not isinstance(raw, dict):
            continue
        guid_1c = raw.get('id')
        quantity = parse_1c_decimal(raw.get('quantity'))
        if not guid_1c or quantity <= 0:
            continue
        try:
            guid_1c = uuid.UUID(str(guid_1c))
        except (ValueError, AttributeError, TypeError):
            continue
        # Ключом словаря гасим повтор одной и той же упаковки внутри одного товара:
        # в один INSERT дважды один ключ отдавать нельзя.
        pk = item_package_pk(item_id, guid_1c)
        packages[pk] = ItemPackage(
            id=pk,
            guid_1c=guid_1c,
            item_id=item_id,
            name=(raw.get('name') or '').strip() or 'Упаковка',
            quantity=quantity,
            is_default=parse_1c_bool(raw.get('is_default')),
            is_invalid=parse_1c_bool(raw.get('is_invalid')),
        )
    return list(packages.values())



def release_cart_lines(package_ids):
    """Переводит строки корзины с удаляемых упаковок на базовую единицу.

    Корзина хранит по строке на пару «товар + единица», и строка базовой единицы у
    товара может уже существовать. Если просто дать сработать SET_NULL, получатся две
    базовые строки и ограничение уникальности уронит всю синхронизацию. Поэтому
    количество сливаем в существующую базовую строку, а если её нет — переводим строку
    на базовую единицу. Количество уже в базовых единицах, пересчитывать не нужно.
    """
    lines = list(CartItem.objects.filter(package_id__in=package_ids))
    for line in lines:
        base = CartItem.objects.filter(
            user_id=line.user_id,
            item_id=line.item_id,
            organization_id=line.organization_id,
            package__isnull=True,
        ).first()
        if base:
            base.quantity += line.quantity
            base.save(update_fields=['quantity', 'updated_at'])
            line.delete()
        else:
            line.package = None
            line.save(update_fields=['package', 'updated_at'])


class Sync1cUpdateItemsView(Base1cAPIView):

    def post(self, request):
        payload = request.data

        if not isinstance(payload, list):
            return Response(
                {"ok": False, "message": "Ожидается массив JSON в теле запроса (список товаров)"},
                status=status.HTTP_400_BAD_REQUEST
            )

        if not payload:
            return Response({"ok": True, "message": "Массив пуст"}, status=status.HTTP_200_OK)


        items_to_upsert = []
        images_to_create = []
        item_ids_with_images = []  # только товары, для которых 1С прислала ключ "images"
        packages_to_upsert = []
        item_ids_with_packages = []  # только товары, для которых 1С прислала ключ "packages"
        skipped = 0

        # Кэширование категорий и организаций для быстрой проверки (по одному запросу)
        valid_item_type_ids = {str(uid) for uid in ItemType.objects.values_list('id', flat=True)}
        org_ids = {r.get("organization_id") for r in payload if r.get("organization_id")}
        valid_org_ids = {str(oid) for oid in Organization.objects.filter(id__in=org_ids).values_list('id', flat=True)}

        # Твой цикл теперь перебирает элементы чистого массива
        for item_row in payload:
            item_id = item_row.get("id")
            if not item_id:
                skipped += 1
                continue

            # Ищем ID организации внутри самого товара
            org_id = item_row.get("organization_id")

            # Нет организации или её нет на сайте — пропускаем строку, а не валим весь пакет
            if not org_id or str(org_id) not in valid_org_ids:
                skipped += 1
                continue

            item_type_id = item_row.get("item_type")
            if item_type_id and str(item_type_id) not in valid_item_type_ids:
                item_type_id = None

            items_to_upsert.append(
                Item(
                    id=item_id,
                    item_type_id=item_type_id,
                    articul=item_row.get("articul"),
                    code=item_row.get("code"),
                    name=item_row.get("name", ""),
                    unit=item_row.get("unit"),
                    organization_id=org_id,
                    # 1С может прислать булево, число или строку ("true"/"Истина"/"1") —
                    # приводим к bool. Ключа нет → товар считаем действительным.
                    is_invalid=parse_1c_bool(item_row.get("is_invalid")),
                )
            )

            # Картинки трогаем только если ключ "images" реально присутствует в строке.
            # Пустой список images=[] означает «очистить картинки товара»,
            # а отсутствие ключа — «не трогать картинки вообще».
            if "images" in item_row:
                item_ids_with_images.append(item_id)
                images_to_create.extend(build_item_images(item_id, item_row["images"]))

            # Упаковки — по той же логике, что и картинки: ключа нет — не трогаем,
            # пустой список означает «у товара остаётся только базовая единица».
            if "packages" in item_row:
                item_ids_with_packages.append(item_id)
                packages_to_upsert.extend(build_item_packages(item_id, item_row["packages"]))

        # Запускаем транзакцию для записи в БД
        try:
            with transaction.atomic():
                if items_to_upsert:
                    # Пакетный Upsert товаров
                    Item.objects.bulk_create(
                        items_to_upsert, update_conflicts=True,
                        unique_fields=['id'],
                        update_fields=['item_type_id', 'articul', 'code', 'name', 'unit', 'organization_id',
                                       'is_invalid', 'updated_at'],
                        batch_size=SYNC_BATCH_SIZE,
                    )

                    # Картинки-ссылки (image_path строками) пересобираем только для тех товаров,
                    # у которых 1С реально прислала массив images. Товары без ключа "images"
                    # в этом пакете не трогаем — иначе каждая синхронизация стирала бы картинки,
                    # загруженные отдельно через ItemImageUploadView (base64/multipart).
                    if item_ids_with_images:
                        ItemImage.objects.filter(item_id__in=item_ids_with_images).delete()
                        if images_to_create:
                            ItemImage.objects.bulk_create(images_to_create, batch_size=SYNC_BATCH_SIZE)

                    # Упаковки не пересоздаём, а апсертим по ключу (товар + GUID из 1С):
                    # на них ссылаются корзины, и пересоздание молча обнулило бы
                    # выбранную клиентом упаковку. Пропавшие из пакета удаляем —
                    # CartItem.package это SET_NULL, а в заказах упаковка лежит копией,
                    # поэтому история не пострадает.
                    if item_ids_with_packages:
                        kept_ids = {p.id for p in packages_to_upsert}
                        stale = ItemPackage.objects.filter(item_id__in=item_ids_with_packages) \
                            .exclude(id__in=kept_ids)
                        stale_ids = list(stale.values_list('id', flat=True))
                        if stale_ids:
                            release_cart_lines(stale_ids)
                            ItemPackage.objects.filter(id__in=stale_ids).delete()
                        if packages_to_upsert:
                            ItemPackage.objects.bulk_create(
                                packages_to_upsert, update_conflicts=True,
                                unique_fields=['id'],
                                update_fields=['guid_1c', 'item_id', 'name', 'quantity',
                                               'is_default', 'is_invalid'],
                                batch_size=SYNC_BATCH_SIZE,
                            )
        except IntegrityError:
            return Response(
                {"ok": False, "message": "Ошибка целостности данных. Убедитесь, что организации и виды номенклатуры уже загружены на сайт."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if items_to_upsert:
            bump_catalog_version(valid_org_ids)  # каталог изменился — сбрасываем кэш этих организаций

        if skipped:
            return Response(
                {"ok": False,
                 "message": f"Обработано товаров: {len(items_to_upsert)}. "
                            f"Пропущено (нет id или неизвестная организация): {skipped}"},
                status=status.HTTP_400_BAD_REQUEST
            )
        return Response(
            {"ok": True, "message": f"Успешно обработано товаров: {len(items_to_upsert)}"},
            status=status.HTTP_200_OK
        )


class Sync1cUpdateItemTypesView(Base1cAPIView):

    def post(self, request):
        payload = request.data

        if not isinstance(payload, list):
            return Response(
                {"ok": False, "message": "Ожидается массив JSON в теле запроса"},
                status=status.HTTP_400_BAD_REQUEST
            )

        if not payload:
            return Response({"ok": True, "message": "Массив пуст"}, status=status.HTTP_200_OK)

        # Заранее подгружаем существующие организации одним запросом, чтобы не ловить
        # IntegrityError по FK и не отдавать 1С огромный HTML-трейсбек.
        org_ids = {t.get("organization_id") for t in payload if t.get("organization_id")}
        valid_org_ids = {str(oid) for oid in Organization.objects.filter(id__in=org_ids).values_list('id', flat=True)}

        types_to_upsert = []
        skipped = 0
        for t in payload:
            if not t.get("id"):
                skipped += 1
                continue
            org_id = t.get("organization_id")
            if not org_id or str(org_id) not in valid_org_ids:
                # Организации нет на сайте — пропускаем строку (иначе весь пакет упадёт по FK)
                skipped += 1
                continue
            types_to_upsert.append(
                ItemType(
                    id=t.get("id"),
                    name=t.get("name", ""),
                    organization_id=org_id,
                    # Ключа нет → категория считается действительной (обратная совместимость)
                    is_invalid=parse_1c_bool(t.get("is_invalid")),
                )
            )

        try:
            if types_to_upsert:
                with transaction.atomic():
                    ItemType.objects.bulk_create(
                        types_to_upsert,
                        update_conflicts=True,
                        unique_fields=['id'],  # ИСПРАВЛЕНО: ищем конфликт строго по первичному ключу id
                        # Обновляем, если изменилось имя, фирма или пометка недействительности
                        update_fields=['name', 'organization_id', 'is_invalid'],
                        batch_size=SYNC_BATCH_SIZE,
                    )
        except IntegrityError:
            return Response(
                {"ok": False, "message": "Ошибка целостности данных. Убедитесь, что организации уже загружены на сайт."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if types_to_upsert:
            bump_catalog_version(valid_org_ids)  # категории влияют на каталог — сбрасываем кэш

        if skipped:
            return Response(
                {"ok": False,
                 "message": f"Обработано видов номенклатуры: {len(types_to_upsert)}. "
                            f"Пропущено (нет id или неизвестная организация): {skipped}"},
                status=status.HTTP_400_BAD_REQUEST
            )
        return Response(
            {"ok": True, "message": f"Успешно обработано видов номенклатуры: {len(types_to_upsert)}"},
            status=status.HTTP_200_OK
        )


class Sync1cUpdatePriceTypesView(Base1cAPIView):

    def post(self, request):
        payload = request.data

        if not isinstance(payload, list):
            return Response(
                {"ok": False, "message": "Ожидается массив JSON в теле запроса"},
                status=status.HTTP_400_BAD_REQUEST
            )

        if not payload:
            return Response({"ok": True, "message": "Массив пуст"}, status=status.HTTP_200_OK)


        # Проверяем существование организаций одним запросом
        org_ids = {pt.get("organization_id") for pt in payload if pt.get("organization_id")}
        valid_org_ids = {str(oid) for oid in Organization.objects.filter(id__in=org_ids).values_list('id', flat=True)}

        pt_to_upsert = []
        skipped = 0
        for pt in payload:
            if not pt.get("id"):
                skipped += 1
                continue
            org_id = pt.get("organization_id")
            if not org_id or str(org_id) not in valid_org_ids:
                skipped += 1
                continue
            pt_to_upsert.append(
                PriceType(
                    id=pt.get("id"),
                    code=pt.get("code"),
                    name=pt.get("name", ""),
                    currency=pt.get("currency", "UZS"),
                    organization_id=org_id,
                    is_default=pt.get("is_default", False),
                )
            )

        try:
            if pt_to_upsert:
                with transaction.atomic():
                    PriceType.objects.bulk_create(
                        pt_to_upsert,
                        update_conflicts=True,
                        unique_fields=['id'],
                        update_fields=['code', 'name', 'currency', 'organization_id', 'is_default'],
                        batch_size=SYNC_BATCH_SIZE,
                    )
        except IntegrityError:
            return Response(
                {"ok": False, "message": "Ошибка целостности данных. Убедитесь, что организации уже загружены на сайт."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if skipped:
            return Response(
                {"ok": False,
                 "message": f"Обработано видов цен: {len(pt_to_upsert)}. "
                            f"Пропущено (нет id или неизвестная организация): {skipped}"},
                status=status.HTTP_400_BAD_REQUEST
            )
        return Response(
            {"ok": True, "message": f"Успешно обработано видов цен: {len(pt_to_upsert)}"},
            status=status.HTTP_200_OK
        )


class Sync1cUpdateUsersView(Base1cAPIView):

    def post(self, request):
        payload = request.data

        if not isinstance(payload, list):
            return Response(
                {"ok": False, "message": "Ожидается массив JSON в теле запроса"},
                status=status.HTTP_400_BAD_REQUEST
            )

        if not payload:
            return Response({"ok": True, "message": "Массив пуст"}, status=status.HTTP_200_OK)

        # --- 1. Разбираем и валидируем строки (без запросов к БД) ---
        # Дедуп по login: если 1С прислала одного контрагента дважды в пакете,
        # берём последнюю запись, иначе bulk_create по User упадёт на дубле username.
        rows_by_login = {}
        skipped = 0
        for u in payload:
            profile_id = u.get("id")
            login = u.get("login")
            if not profile_id or not login:
                skipped += 1
                continue
            rows_by_login[login] = u

        if not rows_by_login:
            return Response(
                {"ok": False, "message": f"Нет валидных строк (нет id или логина). Пропущено: {skipped}"},
                status=status.HTTP_400_BAD_REQUEST
            )

        logins = list(rows_by_login.keys())
        price_type_ids = {u.get("price_type") for u in rows_by_login.values() if u.get("price_type")}
        org_ids = {u.get("organization_id") for u in rows_by_login.values() if u.get("organization_id")}
        profile_ids = [u["id"] for u in rows_by_login.values()]

        # --- 2. Предзагрузка справочников одним запросом на каждый (вместо N запросов) ---
        price_types = {str(pt.id): pt for pt in PriceType.objects.filter(id__in=price_type_ids)}
        valid_org_ids = {str(oid) for oid in Organization.objects.filter(id__in=org_ids).values_list('id', flat=True)}
        existing_users = {u.username: u for u in User.objects.filter(username__in=logins)}
        existing_profile_ids = set(
            str(pid) for pid in UserProfile.objects.filter(id__in=profile_ids).values_list('id', flat=True)
        )

        users_to_create = []
        users_to_update = []

        for login, u in rows_by_login.items():
            password = u.get("password")
            is_active = u.get("is_active", True)
            existing = existing_users.get(login)

            if existing:
                existing.is_active = is_active
                if password:
                    existing.password = make_password(password)
                users_to_update.append(existing)
            else:
                # Нет пароля от 1С → ставим неиспользуемый пароль (make_password(None)):
                # войти нельзя, пока 1С не пришлёт реальный. Без удалённого make_random_password().
                users_to_create.append(User(
                    username=login,
                    password=make_password(password) if password else make_password(None),
                    is_active=is_active,
                ))

        # --- 3. Пакетная запись пользователей + профилей в одной транзакции ---
        try:
            with transaction.atomic():
                if users_to_update:
                    User.objects.bulk_update(users_to_update, ['is_active', 'password'], batch_size=SYNC_BATCH_SIZE)
                if users_to_create:
                    User.objects.bulk_create(users_to_create, batch_size=SYNC_BATCH_SIZE)

                # Полная карта login→user.id (включая только что созданных) одним запросом.
                user_id_by_login = dict(User.objects.filter(username__in=logins).values_list('username', 'id'))

                profiles_to_upsert = []
                for login, u in rows_by_login.items():
                    org_id = u.get("organization_id")
                    # Организация у профиля обязательна (FK not null) — без неё пропускаем строку
                    if not org_id or str(org_id) not in valid_org_ids:
                        skipped += 1
                        continue

                    pt = price_types.get(str(u.get("price_type"))) if u.get("price_type") else None
                    # price_type должен принадлежать той же организации
                    if pt and str(pt.organization_id) != str(org_id):
                        pt = None
                    # price_type у профиля тоже обязателен (FK not null) — без него пропускаем
                    if pt is None:
                        skipped += 1
                        continue

                    profiles_to_upsert.append(UserProfile(
                        id=u["id"],
                        user_id=user_id_by_login[login],
                        name=u.get("name", ""),
                        inn=u.get("inn", ""),
                        price_type=pt,
                        organization_id=org_id,
                        guid_partner1c=u.get("guid_partner1c", ""),
                    ))

                if profiles_to_upsert:
                    UserProfile.objects.bulk_create(
                        profiles_to_upsert,
                        update_conflicts=True,
                        unique_fields=['id'],
                        update_fields=['user', 'name', 'inn', 'price_type', 'organization', 'guid_partner1c'],
                        batch_size=SYNC_BATCH_SIZE,
                    )
        except IntegrityError:
            return Response(
                {"ok": False, "message": "Ошибка целостности данных. Убедитесь, что организации и виды цен уже загружены на сайт."},
                status=status.HTTP_400_BAD_REQUEST
            )

        created_counter = sum(1 for p in profiles_to_upsert if str(p.id) not in existing_profile_ids)
        updated_counter = len(profiles_to_upsert) - created_counter

        if skipped:
            return Response(
                {"ok": False,
                 "message": (f"Пользователей создано: {created_counter}, обновлено: {updated_counter}. "
                             f"Пропущено (нет id/логина, или неизвестная организация/вид цены): {skipped}")},
                status=status.HTTP_400_BAD_REQUEST
            )
        return Response(
            {"ok": True,
             "message": f"Синхронизация успешна. Пользователей создано: {created_counter}, обновлено: {updated_counter}"},
            status=status.HTTP_200_OK
        )


class Sync1cGetNewTelegramUsersView(APIView):
    """
    Глобальный эндпоинт для 1С (GET).
    Возвращает список созданных/измененных Telegram-пользователей БЕЗ привязки к UserProfile.
    Фильтр по дате: ?date_from=2026-06-03 15:30:00
    """
    # Здесь можно подключить ваши классы аутентификации для 1С
    # permission_classes = [Is1CManager]

    def get(self, request, *args, **kwargs):
        # 1. Читаем query-параметр даты из URL
        date_from_param = request.query_params.get('date_from')

        # 2. Формируем базовый QuerySet со связью на системного юзера
        queryset = TelegramAccount.objects.all().select_related('user')

        if date_from_param:
            # Парсим пришедшую строку в datetime объект
            parsed_date = parse_datetime(date_from_param)
            if not parsed_date:
                return Response({
                    "ok": False,
                    "message": "Неверный формат даты. Используйте формат YYYY-MM-DD HH:MM:SS"
                }, status=status.HTTP_400_BAD_REQUEST)

            # Если дата пришла без таймзоны, делаем её aware под настройки Django
            if is_naive(parsed_date):
                parsed_date = make_aware(parsed_date)

            # 🔥 ФИЛЬТРАЦИЯ: Выбираем аккаунты, созданные ИЛИ измененные после этой даты
            queryset = queryset.filter(
                Q(created_at__gte=parsed_date) | Q(updated_at__gte=parsed_date)
            )
        else:
            # Если 1С не передала дату, отдаем пользователей, созданных за последние 24 часа (дефолтное поведение)
            day_ago = now() - timedelta(days=1)
            queryset = queryset.filter(created_at__gte=day_ago)

        # Сортируем по порядку создания
        queryset = queryset.order_by('created_at')

        # 3. Пропускаем данные через сериализатор
        serializer = Sync1cDirectTelegramUserSerializer(queryset, many=True)

        # 4. Отдаем стандартизированный ответ
        return Response({
            "ok": True,
            "filter_date_from": date_from_param if date_from_param else "Не задан (авто-выгрузка за последние 24 часа)",
            "count": queryset.count(),
            "result": serializer.data
        }, status=status.HTTP_200_OK)


# class Sync1cGetNewUsersView(APIView):  # Или твой Base1cAPIView
#     """
#     Эндпоинт для 1С (GET).
#     Забирает пользователей конкретного филиала со статусами 'new' и 'changed'.
#     """
#
#     # Обязательно добавляем *args, **kwargs для поддержки параметров из URL (org_prefix)
#     def get(self, request, *args, **kwargs):
#         # 1. Вытаскиваем префикс организации из ссылки (например, 'avto')
#         org_prefix = self.kwargs.get('org_prefix')
#
#         if not org_prefix:
#             return Response({"ok": False, "message": "Не указан префикс организации в URL"},
#                             status=status.HTTP_400_BAD_REQUEST)
#
#         # 2. Так как мы регистрируем пользователей с username вида "avto_tg_123456",
#         # мы можем легко отфильтровать пользователей, принадлежащих именно этому филиалу
#         username_prefix = f"{org_prefix}_tg_"
#
#         # 3. Делаем выборку: только этот филиал + только статусы NEW и CHANGED
#         profiles = UserProfile.objects.filter(
#             user__username__startswith=username_prefix,
#             status__in=[UserProfile.Status.NEW, UserProfile.Status.CHANGED]
#         ).select_related('user')
#
#         # 4. Пропускаем через технический сериализатор 1С
#         serializer = UserProfileSerializer(profiles, many=True)
#
#         # 5. Возвращаем чистый стандартизированный ответ
#         return Response({
#             "ok": True,
#             "organization": org_prefix,
#             "count": profiles.count(),
#             "result": serializer.data
#         }, status=status.HTTP_200_OK)


class Sync1cUpdatePricelistView(Base1cAPIView):

    def post(self, request):
        payload = request.data

        # Защита: проверяем, что пришел именно словарь (объект)
        if isinstance(payload, dict):
            price_type_id = payload.get("price_type")
            items_data = payload.get("items", [])
            organization_id = payload.get("organization_id") or payload.get("organization")

            if not price_type_id:
                return Response(
                    {"ok": False, "message": "Поле 'price_type' (UUID) обязательно внутри price_list"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if not organization_id:
                return Response(
                    {"ok": False, "message": "Поле 'organization_id' (UUID) обязательно внутри price_list"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            # Проверяем, что организация и вид цены реально существуют на сайте
            if not Organization.objects.filter(id=organization_id).exists():
                return Response(
                    {"ok": False, "message": "Организация не найдена. Сначала загрузите организации на сайт."},
                    status=status.HTTP_400_BAD_REQUEST
                )
            if not PriceType.objects.filter(id=price_type_id).exists():
                return Response(
                    {"ok": False, "message": "Вид цены не найден. Сначала загрузите виды цен на сайт."},
                    status=status.HTTP_400_BAD_REQUEST
                )

            # Предзагружаем id существующих товаров из пакета, чтобы пропустить неизвестные,
            # а не валить весь прайс по FK
            requested_item_ids = {r.get("item") for r in items_data if r.get("item")}
            valid_item_ids = {str(iid) for iid in Item.objects.filter(id__in=requested_item_ids).values_list('id', flat=True)}

            prices_to_upsert = []
            skipped = 0

            # Перебираем товары внутри прайс-листа
            for item_row in items_data:
                item_id = item_row.get("item")  # <-- Изменено: ищем строго ключ "item"
                price_val = item_row.get("price")

                if not item_id or str(item_id) not in valid_item_ids:
                    skipped += 1
                    continue
                # item_period_raw = item_row.get("period")
                # --- УМНАЯ ОБРАБОТКА ВРЕМЕННОЙ ЗОНЫ ДЛЯ 1С ---
                # cleaned_period = None
                # if item_period_raw:
                #     # Превращаем строку в объект datetime
                #     parsed_dt = parse_datetime(str(item_period_raw))
                #     if parsed_dt:
                #         # Если дата пришла без часового пояса (наивная), делаем её aware
                #         if timezone.is_naive(parsed_dt):
                #             cleaned_period = timezone.make_aware(parsed_dt)
                #         else:
                #             cleaned_period = parsed_dt

                prices_to_upsert.append(
                    PriceList(
                        item_id=item_id,
                        price_type_id=price_type_id,
                        price=price_val if price_val is not None else 0.00,
                        # period=cleaned_period,
                        organization_id=organization_id,
                    )
                )

            # Пакетное сохранение / обновление цен в БД
            try:
                if prices_to_upsert:
                    # Запускаем транзакцию для записи в БД
                    with transaction.atomic():
                        PriceList.objects.bulk_create(
                            prices_to_upsert,
                            update_conflicts=True,
                            unique_fields=['item', 'price_type', 'organization'],
                            update_fields=['price', 'updated_at'],
                            batch_size=SYNC_BATCH_SIZE,
                        )
            except IntegrityError:
                return Response(
                    {"ok": False, "message": "Ошибка целостности данных. Убедитесь, что товары, организация и вид цены уже загружены на сайт."},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if prices_to_upsert:
                bump_catalog_version(organization_id)  # цены изменились — сбрасываем кэш каталога

            if skipped:
                return Response(
                    {"ok": False,
                     "message": f"Обработано цен: {len(prices_to_upsert)}. "
                                f"Пропущено (нет товара на сайте): {skipped}"},
                    status=status.HTTP_400_BAD_REQUEST
                )
            return Response(
                {"ok": True, "message": f"Успешно обработано цен для товаров: {len(prices_to_upsert)}"},
                status=status.HTTP_200_OK
            )

        else:
            return Response(
                {"ok": False, "message": "Формат 'price_list' должен быть объектом (dict)"},
                status=status.HTTP_400_BAD_REQUEST
            )


class ItemImageUploadView(Base1cAPIView):
    parser_classes = (MultiPartParser, FormParser, JSONParser)

    def post(self, request):
        image_id = request.data.get('id')
        item_id = request.data.get('item')
        image_file = request.data.get('image')
        custom_name = request.data.get('name')

        if not image_id:
            return Response({"ok": False, "message": "Поле 'id' обязательно"}, status=status.HTTP_400_BAD_REQUEST)

        # Логика удаления (остается без изменений)
        if image_file is None or image_file == '' or image_file == 'null':
            try:
                img_obj = ItemImage.objects.select_related('item').get(id=image_id)
                org_id = img_obj.item.organization_id
                img_obj.delete()
                bump_catalog_version(org_id)  # картинка удалена — сбрасываем кэш каталога
                return Response({"ok": True, "message": f"Картинка с ID {image_id} успешно удалена"},
                                status=status.HTTP_200_OK)
            except ItemImage.DoesNotExist:
                return Response({"ok": False, "message": "Картинка не найдена"}, status=status.HTTP_404_NOT_FOUND)

        if not item_id:
            return Response({"ok": False, "message": "Поле 'item' обязательно"}, status=status.HTTP_400_BAD_REQUEST)

        try:
            item_obj = Item.objects.get(id=item_id)
        except Item.DoesNotExist:
            return Response({"ok": False, "message": "Товар не найден"}, status=status.HTTP_404_NOT_FOUND)

        # 🔥 АВТОДЕКОДЕР БАЗЫ64 ДЛЯ 1С (Решает проблему битых файлов)
        # Оптимизация: сначала читаем только «голову» файла (64 байта), чтобы понять,
        # base64 это или обычный бинарник. Полностью в память тянем ТОЛЬКО base64-текст,
        # а настоящие бинарные картинки Django стримит на диск сам — не грузим их в RAM.
        if image_file and hasattr(image_file, 'read'):
            try:
                head = image_file.read(64)
                image_file.seek(0)

                base64_clean_data = None
                if b';base64,' in head:
                    # data:image/jpeg;base64,... — префикс с HTML-обёрткой
                    base64_clean_data = image_file.read().split(b';base64,')[-1]
                    image_file.seek(0)
                elif head.startswith((b'/9j/', b'iVBORw0K', b'R0lGODlh')):
                    # Чистый Base64-текст (jpeg/png/gif)
                    base64_clean_data = image_file.read()
                    image_file.seek(0)

                if base64_clean_data:
                    # Чистим от кавычек/пробелов/переносов, которые могла добавить 1С, и декодируем
                    decoded_bytes = base64.b64decode(base64_clean_data.strip(b'"\' \n\r'))
                    filename = getattr(image_file, 'name', 'image.jpg') or 'image.jpg'
                    image_file = ContentFile(decoded_bytes, name=filename)
            except Exception:
                # Если что-то пошло не так — сбрасываем указатель и сохраняем как есть
                if hasattr(image_file, 'seek'):
                    image_file.seek(0)

        # Защита расширения файла
        if hasattr(image_file, 'name'):
            ext = image_file.name.split('.')[-1] if '.' in image_file.name else 'jpg'
            if custom_name:
                image_file.name = f"{custom_name}.{ext}"

        try:
            with transaction.atomic():
                existing = ItemImage.objects.filter(id=image_id).first()
                old_file = existing.image_path if existing else None

                # is_main НЕ трогаем при обновлении (иначе повторная заливка снимает флаг «главная»).
                # Для новой картинки: главная = если у товара ещё нет ни одной картинки.
                if existing:
                    is_main = existing.is_main
                else:
                    is_main = not ItemImage.objects.filter(item=item_obj).exists()

                defaults = {
                    'item': item_obj,
                    'image_path': image_file,
                    'is_main': is_main,
                }
                # Пометку «недействительна» трогаем только если 1С её реально прислала:
                # старые версии обмена про это поле не знают и не должны его сбрасывать.
                if 'is_invalid' in request.data:
                    defaults['is_invalid'] = parse_1c_bool(request.data.get('is_invalid'))

                item_image, created = ItemImage.objects.update_or_create(
                    id=image_id,
                    defaults=defaults,
                )

            # Удаляем старый файл с диска, если при обновлении имя файла изменилось —
            # иначе media/products/ засоряется осиротевшими файлами при каждом ре-синке.
            if old_file and old_file.name and old_file.name != item_image.image_path.name:
                old_file.delete(save=False)
        except IntegrityError:
            return Response(
                {"ok": False, "message": "Ошибка целостности данных при сохранении картинки."},
                status=status.HTTP_400_BAD_REQUEST
            )

        bump_catalog_version(item_obj.organization_id)  # картинка изменилась — сбрасываем кэш каталога

        action_word = "загружена" if created else "обновлена"
        return Response(
            {"ok": True, "message": f"Картинка {action_word} и привязана к товару '{item_obj.name}'"},
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK
        )



class Sync1cUpdateImagesValidityView(Base1cAPIView):
    """1С помечает картинки действительными/недействительными, не перезаливая файлы.

    Тело — массив [{"id": "<GUID картинки>", "is_invalid": true}, ...].
    Недействительная картинка исчезает из каталога, но остаётся в базе: чтобы вернуть
    её обратно, достаточно прислать is_invalid=false. Для полного удаления вместе с
    файлом по-прежнему используется image_item_upload/ с пустым полем `image`.
    """

    def post(self, request):
        payload = request.data

        if not isinstance(payload, list):
            return Response(
                {"ok": False, "message": "Ожидается массив JSON в теле запроса (список картинок)"},
                status=status.HTTP_400_BAD_REQUEST
            )

        if not payload:
            return Response({"ok": True, "message": "Массив пуст"}, status=status.HTTP_200_OK)

        # Собираем два списка id: что скрыть и что вернуть в каталог.
        to_invalid, to_valid, skipped = [], [], 0
        for row in payload:
            if not isinstance(row, dict) or not row.get("id"):
                skipped += 1
                continue
            (to_invalid if parse_1c_bool(row.get("is_invalid")) else to_valid).append(row["id"])

        updated = 0
        affected_org_ids = set()
        with transaction.atomic():
            for ids, flag in ((to_invalid, True), (to_valid, False)):
                if not ids:
                    continue
                qs = ItemImage.objects.filter(id__in=ids)
                # Организации собираем до update — после него выборка уже не нужна,
                # но кэш каталога сбросить надо именно у затронутых филиалов.
                affected_org_ids.update(qs.values_list('item__organization_id', flat=True))
                updated += qs.update(is_invalid=flag)

        bump_catalog_version(affected_org_ids)

        if skipped:
            return Response(
                {"ok": False, "message": f"Обновлено картинок: {updated}. Пропущено (нет id): {skipped}"},
                status=status.HTTP_400_BAD_REQUEST
            )
        return Response(
            {"ok": True, "message": f"Успешно обновлено картинок: {updated}"},
            status=status.HTTP_200_OK
        )


class Sync1cPullOrdersView(Base1cAPIView):
    """
    1С забирает новые заказы (статус 'new').
    Опциональный фильтр по организации: ?prefix=<org_prefix>.
    Без параметра — все новые заказы (в каждом есть organization_prefix).
    """

    def get(self, request, *args, **kwargs):
        org_prefix = request.query_params.get('prefix') or self.kwargs.get('org_prefix')

        orders = (Order.objects.filter(status='new')
                  .select_related('organization', 'user')
                  .prefetch_related('items__item'))
        if org_prefix:
            orders = orders.filter(organization__prefix=org_prefix)

        serializer = Order1COutputSerializer(orders, many=True)
        return Response({
            "ok": True,
            "count": orders.count(),
            "result": serializer.data
        }, status=status.HTTP_200_OK)


class Sync1cUpdateOrdersView(Base1cAPIView):

    def post(self, request):
        """
        1С присылает обновленные данные по заказам (изменения, удаления, статусы)
        """
        # ИСПРАВЛЕНО: Так как JSON прилетает напрямую массивом [], читаем request.data
        orders_data = request.data

        if not orders_data or not isinstance(orders_data, list):
            return Response(
                {"ok": False, "message": "Ожидался прямой JSON-массив заказов"},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Открываем безопасную транзакцию
        try:
            with transaction.atomic():
                for order_row in orders_data:
                    order_id = order_row.get("id")
                    if not order_id:
                        continue

                    try:
                        # Ищем этот заказ в Django
                        order = Order.objects.get(id=order_id)
                    except Order.DoesNotExist:
                        # Если заказ не найден, пропускаем шаг
                        continue

                    # 1. Обновляем «шапку» заказа данными из 1С
                    order.status = order_row.get("status", order.status)
                    order.total_amount = order_row.get("total_amount", order.total_amount)

                    # ИСПРАВЛЕНО: Безопасно вытаскиваем номер 1С (учитывая возможную кириллицу/латиницу в букве 'с')
                    number_1c = order_row.get("order_number_1с") or order_row.get("order_number_1c")
                    if number_1c:
                        order.order_number_1c = number_1c

                    order.save()

                    # 2. Обновляем «табличную часть» (состав товаров)
                    items_data = order_row.get("items", [])
                    if items_data:
                        # Сносим старый состав подчистую
                        OrderItem.objects.filter(order=order).delete()

                        items_to_create = []
                        for item_row in items_data:
                            items_to_create.append(
                                OrderItem(
                                    order=order,
                                    item_id=item_row.get("product_id"),  # UUID товара из 1С
                                    quantity=item_row.get("quantity"),
                                    price=item_row.get("price"),
                                    total_amount=item_row.get("total_amount"),

                                    # ИСПРАВЛЕНО: Теперь новые поля из JSON успешно пишутся в базу
                                    discount=item_row.get("discount", 0.00),
                                    is_canceled=item_row.get("is_cancelled", False),
                                    # учитываем "is_cancelled" с двумя 'l' из JSON
                                    cancellation_reason=item_row.get("cancellation_reason", "")
                                )
                            )
                        # Пакетно пишем актуальный состав, который прислала 1С
                        OrderItem.objects.bulk_create(items_to_create, batch_size=SYNC_BATCH_SIZE)
        except IntegrityError:
            return Response(
                {"ok": False, "message": "Ошибка целостности данных заказа. Убедитесь, что товары из состава заказа есть на сайте."},
                status=status.HTTP_400_BAD_REQUEST
            )

        return Response({
            "ok": True,
            "message": f"Успешно синхронизировано заказов: {len(orders_data)}"
        }, status=status.HTTP_200_OK)


class Sync1cUpdateStocksView(Base1cAPIView):

    def post(self, request):
        """
        1С присылает актуальные остатки товаров по организациям.
        Принимает прямой JSON-массив.
        """
        stocks_data = request.data

        if not stocks_data or not isinstance(stocks_data, list):
            return Response(
                {"ok": False, "message": "Ожидался прямой JSON-массив остатков"},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Подготавливаем списки для пакетной обработки
        items_to_sync = []
        affected_orgs = set()

        try:
            for row in stocks_data:
                item_id = row.get("item")
                org_id = row.get("organization_id")
                quantity = row.get("quantity", 0.00)

                if not item_id or not org_id:
                    continue  # Пропускаем битые строки, если нет ID

                affected_orgs.add(org_id)
                # Собираем объекты в памяти (запросы к БД здесь НЕ происходят)
                items_to_sync.append(
                    ItemStock(
                        item_id=item_id,  # Пишем UUID товара напрямую в Foreign Key
                        organization_id=org_id,  # Пишем UUID организации напрямую в Foreign Key
                        stock=quantity
                    )
                )

            if items_to_sync:
                # Открываем безопасную транзакцию
                with transaction.atomic():
                    # Пакетный супер-апсерт (создание или обновление при конфликте уникальности)
                    ItemStock.objects.bulk_create(
                        items_to_sync,
                        update_conflicts=True,
                        unique_fields=['item', 'organization'],  # Поля из unique_together в модели
                        update_fields=['stock', 'updated_at'],  # Что перезаписать, если запись уже существует
                        batch_size=SYNC_BATCH_SIZE,
                    )
                bump_catalog_version(affected_orgs)  # остатки изменились — сбрасываем кэш каталога

            return Response({
                "ok": True,
                "message": f"Успешно обновлено позиций остатков: {len(items_to_sync)}"
            }, status=status.HTTP_200_OK)

        except Exception as e:
            # Если 1С прислала UUID товара или организации, которых вообще нет на сайте,
            # база данных выбросит ошибку целостности (IntegrityError). Ловим её:
            return Response({
                "ok": False,
                "message": f"Ошибка импорта. Убедитесь, что все товары и организации уже созданы на сайте. Текст ошибки: {str(e)}"
            }, status=status.HTTP_400_BAD_REQUEST)

class Sync1cUserProfileListView(Base1cAPIView):
    """
    GET: список профилей контрагентов для 1С.
    ?only_unlinked=1 — только непривязанные (пустой guid_partner1c).
    ?organization_id=<uuid> — только профили этой организации (филиала).
    """
    only_unlinked = False

    def get(self, request):
        qs = (UserProfile.objects
              .select_related('user', 'user__telegram_account', 'price_type', 'organization')
              .all())

        # Без параметра — профили всех филиалов, как и раньше. С параметром отвечаем
        # ошибкой на кривой или неизвестный UUID, а не пустым списком: иначе 1С
        # решила бы, что у филиала просто нет клиентов.
        organization_id = (request.query_params.get('organization_id') or '').strip()
        if organization_id:
            try:
                organization_id = uuid.UUID(organization_id)
            except ValueError:
                return Response(
                    {"ok": False, "message": "Параметр 'organization_id' должен быть UUID"},
                    status=status.HTTP_400_BAD_REQUEST
                )
            if not Organization.objects.filter(id=organization_id).exists():
                return Response(
                    {"ok": False, "message": f"Организация {organization_id} не найдена"},
                    status=status.HTTP_404_NOT_FOUND
                )
            qs = qs.filter(organization_id=organization_id)

        flag = request.query_params.get('only_unlinked')
        want_unlinked = self.only_unlinked or (str(flag).lower() in ('1', 'true', 'yes'))
        if want_unlinked:
            qs = qs.filter(Q(guid_partner1c__isnull=True) | Q(guid_partner1c=''))

        qs = qs.order_by('name', 'id')
        serializer = UserProfileSyncSerializer(qs, many=True)
        return Response({
            "ok": True,
            "only_unlinked": want_unlinked,
            "organization_id": str(organization_id) if organization_id else None,
            "count": len(serializer.data),
            "result": serializer.data,
        }, status=status.HTTP_200_OK)


class Sync1cUserProfileUnlinkedView(Sync1cUserProfileListView):
    """GET: только непривязанные профили (пустой guid_partner1c)."""
    only_unlinked = True


class Sync1cUserProfileUpsertView(Base1cAPIView):
    """
    POST: создание/обновление профилей контрагентов из 1С.
    Принимает объект или массив объектов вида:
      {"id": "<uuid профиля>", "guid_partner1c": "...", "name": "...",
       "inn": "...", "price_type": "<uuid>", "is_blocked": false}
    Обновляются существующие профили (по id): привязка guid_partner1c и полей.
    Профиль должен существовать (создаётся при само-регистрации через Telegram
    или эндпоинтом /user-profile/). Несуществующие id пропускаются.
    """

    def post(self, request):
        payload = request.data
        rows = payload if isinstance(payload, list) else [payload]

        # Дедуп по id (последняя запись побеждает)
        rows_by_id = {}
        skipped = 0
        for r in rows:
            pid = r.get("id")
            if not pid:
                skipped += 1
                continue
            rows_by_id[str(pid)] = r

        if not rows_by_id:
            return Response(
                {"ok": False, "message": f"Нет валидных строк (нет id). Пропущено: {skipped}"},
                status=status.HTTP_400_BAD_REQUEST
            )

        profiles = {
            str(p.id): p
            for p in UserProfile.objects.select_related('organization').filter(id__in=list(rows_by_id.keys()))
        }

        # Предзагрузка видов цен, если 1С прислала их
        price_type_ids = {r.get("price_type") for r in rows_by_id.values() if r.get("price_type")}
        price_types = {str(pt.id): pt for pt in PriceType.objects.filter(id__in=price_type_ids)}

        to_update = []
        update_fields = set()
        not_found = 0

        for pid, r in rows_by_id.items():
            profile = profiles.get(pid)
            if not profile:
                not_found += 1
                continue

            if "guid_partner1c" in r:
                profile.guid_partner1c = r.get("guid_partner1c") or ""
                update_fields.add("guid_partner1c")
            if "name" in r:
                profile.name = r.get("name") or ""
                update_fields.add("name")
            if "inn" in r:
                profile.inn = r.get("inn") or ""
                update_fields.add("inn")
            if "is_blocked" in r:
                profile.is_blocked = bool(r.get("is_blocked"))
                update_fields.add("is_blocked")
            if r.get("price_type"):
                pt = price_types.get(str(r.get("price_type")))
                # Вид цены должен принадлежать организации профиля
                if pt and str(pt.organization_id) == str(profile.organization_id):
                    profile.price_type = pt
                    update_fields.add("price_type")

            to_update.append(profile)

        if to_update and update_fields:
            with transaction.atomic():
                UserProfile.objects.bulk_update(to_update, list(update_fields), batch_size=SYNC_BATCH_SIZE)

        return Response({
            "ok": not_found == 0 and skipped == 0,
            "updated": len(to_update),
            "not_found": not_found,
            "skipped": skipped,
            "message": f"Обновлено профилей: {len(to_update)}. Не найдено по id: {not_found}. Пропущено (нет id): {skipped}",
        }, status=status.HTTP_200_OK)
