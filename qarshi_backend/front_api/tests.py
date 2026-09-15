"""Тесты Telegram-бота филиала, упаковок товара и приёма данных из 1С."""
import uuid
from decimal import Decimal

from django.contrib.auth.models import User
from django.core.cache import cache
from django.test import TestCase, override_settings
from rest_framework.authtoken.models import Token
from rest_framework_simplejwt.tokens import RefreshToken

from front_api.bot import api, handlers, polling
from sync_1c.views import item_package_pk
from front_api.models import CartItem, TelegramAccount
from sync_1c.models import (
    Item, ItemImage, ItemPackage, ItemStock, ItemType, Organization,
    OrderItem, PriceList, PriceType, UserProfile,
)

TG_ID = 999000111


class TelegramBotTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.org = Organization.objects.create(
            inn="123456789", name="Тестовый магазин", prefix="shop",
            support_phone="+998901234567", telegram_bot_token="123:FAKE",
            unregistered_notice="Вы ещё не подтверждены как контрагент.",
        )
        PriceType.objects.create(name="Розница", organization=cls.org, is_default=True)

    def setUp(self):
        self.sent = []
        # Перехватываем весь Bot API: тесты не должны ходить в сеть
        self._real_call = api.call
        api.call = lambda token, method, payload=None: (
            self.sent.append((method, payload)) or {"ok": True}
        )

    def tearDown(self):
        api.call = self._real_call

    # --- хелперы ---
    def update(self, **overrides):
        message = {
            "chat": {"id": TG_ID, "type": "private"},
            "from": {"id": TG_ID, "first_name": "Иван", "last_name": "Петров",
                     "username": "ivan", "language_code": "ru"},
        }
        message.update(overrides)
        return {"message": message}

    def last_message(self):
        _, payload = self.sent[-1]
        keyboard = payload.get("reply_markup", {}).get("keyboard", [])
        buttons = [button for row in keyboard for button in row]
        return payload["text"], buttons

    def last_markup(self):
        _, payload = self.sent[-1]
        return payload.get("reply_markup", {})

    def contact(self, user_id=TG_ID, phone="+998 (90) 123-45-67"):
        return self.update(contact={"user_id": user_id, "phone_number": phone})

    # --- сценарии ---
    def test_start_without_phone_asks_contact(self):
        handlers.handle_update(self.org, self.update(text="/start"))
        text, buttons = self.last_message()

        self.assertIn("оптовый заказ через Telegram", text)
        # Единственная кнопка бота — запрос телефона, навигацию он не дублирует
        self.assertEqual(len(buttons), 1)
        self.assertTrue(buttons[0].get("request_contact"))

        account = TelegramAccount.objects.get(telegram_id=TG_ID)
        self.assertEqual(account.user.username, f"tg_{TG_ID}")
        self.assertTrue(UserProfile.objects.filter(user=account.user, organization=self.org).exists())

    def test_own_contact_saves_normalized_phone_and_reports_pending(self):
        handlers.handle_update(self.org, self.contact())
        text, buttons = self.last_message()

        self.assertEqual(TelegramAccount.objects.get(telegram_id=TG_ID).phone, "998901234567")
        self.assertIn("+998901234567 принят", text)
        self.assertIn("заявка передана менеджеру", text)
        self.assertIn("Вы ещё не подтверждены как контрагент.", text)
        self.assertIn("+998901234567", text.split("Вопросы: ")[-1])
        # Номер получен — клавиатура с запросом телефона убирается
        self.assertEqual(buttons, [])
        self.assertTrue(self.last_markup().get("remove_keyboard"))

    def test_linked_partner_gets_contract_price_message(self):
        handlers.handle_update(self.org, self.update(text="/start"))
        profile = UserProfile.objects.get(user__telegram_account__telegram_id=TG_ID, organization=self.org)
        profile.guid_partner1c = "guid-123"
        profile.name = "ООО «Ромашка»"
        profile.save()

        handlers.handle_update(self.org, self.contact())
        text, _ = self.last_message()

        self.assertIn("Ваш контрагент: ООО «Ромашка»", text)
        self.assertIn("по вашему договору", text)

    def test_foreign_contact_rejected(self):
        handlers.handle_update(self.org, self.contact(user_id=TG_ID + 1))
        text, buttons = self.last_message()

        self.assertIn("контакт другого пользователя", text)
        self.assertTrue(any(b.get("request_contact") for b in buttons))
        self.assertFalse(TelegramAccount.objects.get(telegram_id=TG_ID).phone)

    def test_start_with_known_phone_has_no_keyboard(self):
        handlers.handle_update(self.org, self.contact())
        handlers.handle_update(self.org, self.update(text="/start"))
        text, buttons = self.last_message()

        self.assertIn("Вы авторизованы как Иван", text)
        self.assertEqual(buttons, [])
        self.assertTrue(self.last_markup().get("remove_keyboard"))

    def test_free_text_reminds_about_button(self):
        handlers.handle_update(self.org, self.update(text="привет"))
        text, buttons = self.last_message()
        self.assertIn("принимает только номер телефона", text)
        self.assertTrue(any(b.get("request_contact") for b in buttons))

        handlers.handle_update(self.org, self.contact())
        handlers.handle_update(self.org, self.update(text="а есть масло 5w30?"))
        text, buttons = self.last_message()
        self.assertIn("внутри приложения", text)
        self.assertEqual(buttons, [])

    def test_blocked_profile_gets_support_phone(self):
        handlers.handle_update(self.org, self.update(text="/start"))
        UserProfile.objects.filter(organization=self.org).update(is_blocked=True)

        handlers.handle_update(self.org, self.update(text="/start"))
        _, payload = self.sent[-1]
        self.assertIn("закрыт менеджером", payload["text"])
        self.assertIn("+998901234567", payload["text"])
        self.assertTrue(payload["reply_markup"].get("remove_keyboard"))

    def test_group_chats_and_non_messages_ignored(self):
        handlers.handle_update(self.org, {"message": {"chat": {"id": 1, "type": "group"},
                                                     "from": {"id": TG_ID}, "text": "/start"}})
        handlers.handle_update(self.org, {"my_chat_member": {}})
        self.assertEqual(self.sent, [])
        self.assertFalse(TelegramAccount.objects.exists())


class TelegramWebhookViewTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.org = Organization.objects.create(
            inn="123456789", name="Тестовый магазин", prefix="shop",
            telegram_bot_token="123:FAKE",
        )
        PriceType.objects.create(name="Розница", organization=cls.org, is_default=True)
        cls.url = "/api/v1/shop/telegram/webhook/"
        cls.update = {"message": {"chat": {"id": TG_ID, "type": "private"},
                                  "from": {"id": TG_ID, "first_name": "Иван"}, "text": "/start"}}

    def setUp(self):
        self._real_call = api.call
        api.call = lambda token, method, payload=None: {"ok": True}

    def tearDown(self):
        api.call = self._real_call

    def post(self, url=None, secret=None):
        headers = {} if secret is None else {"HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN": secret}
        return self.client.post(url or self.url, data=self.update,
                                content_type="application/json", **headers)

    def test_valid_secret_accepted(self):
        response = self.post(secret=api.webhook_secret("shop"))
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["ok"])
        self.assertTrue(TelegramAccount.objects.filter(telegram_id=TG_ID).exists())

    def test_wrong_or_missing_secret_rejected(self):
        self.assertEqual(self.post(secret="wrong").status_code, 403)
        self.assertEqual(self.post().status_code, 403)
        self.assertFalse(TelegramAccount.objects.exists())

    def test_unknown_org_prefix_is_404(self):
        response = self.post(url="/api/v1/nosuchorg/telegram/webhook/",
                             secret=api.webhook_secret("nosuchorg"))
        self.assertEqual(response.status_code, 404)


@override_settings(CACHES={"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}})
class TelegramPollingTests(TestCase):
    """Long polling — запасной способ доставки, когда Telegram не может достучаться вебхуком."""

    @classmethod
    def setUpTestData(cls):
        cls.org = Organization.objects.create(
            inn="123456789", name="Тестовый магазин", prefix="bot1",
            telegram_bot_token="123:FAKE",
        )
        PriceType.objects.create(name="Розница", organization=cls.org, is_default=True)

    def setUp(self):
        cache.clear()
        self.calls = []
        self.responses = []
        self._real_call = api.call

        def fake_call(token, method, payload=None, timeout=None):
            self.calls.append((method, payload))
            if method == "getUpdates" and self.responses:
                return self.responses.pop(0)
            return {"ok": True, "result": []}

        api.call = fake_call

    def tearDown(self):
        api.call = self._real_call

    def update(self, update_id, text="/start"):
        return {"update_id": update_id,
                "message": {"chat": {"id": TG_ID, "type": "private"},
                            "from": {"id": TG_ID, "first_name": "Иван"}, "text": text}}

    def test_updates_are_processed_and_offset_advances(self):
        self.responses = [{"ok": True, "result": [self.update(10), self.update(11)]}]

        offset, processed = polling.poll_once(self.org, None, log=lambda m: None)

        self.assertEqual((offset, processed), (12, 2))
        self.assertEqual(polling.get_offset(self.org), 12)
        self.assertTrue(TelegramAccount.objects.filter(telegram_id=TG_ID).exists())
        self.assertIn("sendMessage", [method for method, _ in self.calls])

    def test_offset_is_sent_back_to_telegram(self):
        polling.set_offset(self.org, 42)
        polling.poll_once(self.org, polling.get_offset(self.org), log=lambda m: None)

        method, payload = self.calls[0]
        self.assertEqual(method, "getUpdates")
        self.assertEqual(payload["offset"], 42)
        self.assertEqual(payload["allowed_updates"], ["message"])

    def test_failing_update_still_advances_offset(self):
        """Апдейт, роняющий обработчик, не должен блокировать очередь навсегда."""
        self.responses = [{"ok": True, "result": [self.update(7)]}]
        real_handle = polling.handle_update
        polling.handle_update = lambda org, upd: (_ for _ in ()).throw(RuntimeError("боом"))
        try:
            offset, processed = polling.poll_once(self.org, None, log=lambda m: None)
        finally:
            polling.handle_update = real_handle

        self.assertEqual((offset, processed), (8, 1))

    def test_active_webhook_conflict_is_resolved(self):
        self.responses = [{"ok": False, "description":
                           "Conflict: can't use getUpdates method while webhook is active"}]

        offset, processed = polling.poll_once(self.org, 5, log=lambda m: None)

        self.assertEqual((offset, processed), (5, 0))
        self.assertIn("deleteWebhook", [method for method, _ in self.calls])


class ItemPackageFlowTests(TestCase):
    """Упаковки товара: синхронизация из 1С, корзина и перенос в заказ.

    Ключевой инвариант: цена в прайсе за БАЗОВУЮ единицу, поэтому и корзина,
    и позиция заказа хранят количество в базовых единицах, а упаковка — только
    множитель и подпись.
    """

    @classmethod
    def setUpTestData(cls):
        cls.org = Organization.objects.create(
            inn="987654321", name="Склад", prefix="wh",
        )
        cls.price_type = PriceType.objects.create(
            name="Розница", organization=cls.org, is_default=True,
        )
        cls.item_type = ItemType.objects.create(name="Масла", organization=cls.org)
        cls.item = Item.objects.create(
            id=uuid.uuid4(), item_type=cls.item_type, name="Масло 1л",
            unit="л", organization=cls.org, articul="M1",
        )
        PriceList.objects.create(
            item=cls.item, price_type=cls.price_type, price=Decimal("12.00"),
            organization=cls.org,
        )
        ItemStock.objects.create(item=cls.item, organization=cls.org, stock=Decimal("500"))
        cls.box_guid = uuid.uuid4()
        cls.box = ItemPackage.objects.create(
            id=item_package_pk(cls.item.id, cls.box_guid), guid_1c=cls.box_guid,
            item=cls.item, name="Коробка", quantity=Decimal("10"),
        )

    def setUp(self):
        # Каталог кэшируется по версии организации, а LocMemCache живёт дольше
        # одного теста — иначе соседний тест отдал бы свой закэшированный ответ.
        cache.clear()
        self.user = User.objects.create_user(username="wh_client", password="x")
        UserProfile.objects.create(
            user=self.user, name="Клиент", price_type=self.price_type,
            organization=self.org, guid_partner1c="p-1",
        )
        # Фронтовые эндпоинты авторизуются SimpleJWT, а не сессией.
        access = RefreshToken.for_user(self.user).access_token
        self.auth = {"HTTP_AUTHORIZATION": f"Bearer {access}"}

    def api(self, path):
        return f"/api/v1/{self.org.prefix}/{path}"

    def test_catalog_exposes_packages(self):
        response = self.client.get(self.api("products/"), **self.auth)
        self.assertEqual(response.status_code, 200)
        product = response.json()["results"][0]
        self.assertEqual(product["unit"], "л")
        self.assertEqual(
            product["packages"],
            [{"id": str(self.box.id), "name": "Коробка", "quantity": 10.0, "is_default": False}],
        )

    def test_invalid_image_is_hidden_from_catalog(self):
        ItemImage.objects.create(id=uuid.uuid4(), item=self.item, image_path="products/a.jpg",
                                 is_main=True)
        hidden = ItemImage.objects.create(id=uuid.uuid4(), item=self.item,
                                          image_path="products/b.jpg")

        product = self.client.get(self.api("products/"), **self.auth).json()["results"][0]
        self.assertEqual(len(product["images"]), 2)

        hidden.is_invalid = True
        hidden.save(update_fields=["is_invalid"])
        cache.clear()  # каталог кэшируется по версии организации

        product = self.client.get(self.api("products/"), **self.auth).json()["results"][0]
        self.assertEqual(len(product["images"]), 1)
        self.assertIn("a.jpg", product["images"][0])

    def test_cart_keeps_base_units_and_remembers_package(self):
        # Три коробки по 10 л = 30 л базовых единиц.
        response = self.client.post(self.api("cart/"), {
            "item_id": str(self.item.id), "quantity": 30, "package_id": str(self.box.id),
        }, content_type="application/json", **self.auth)
        self.assertEqual(response.status_code, 200)

        cart = self.client.get(self.api("cart/"), **self.auth).json()
        position = cart["results"][0]
        self.assertEqual(position["quantity"], 30.0)
        self.assertEqual(position["package_id"], str(self.box.id))
        # Цена за базовую единицу, сумма — по базовым единицам.
        self.assertEqual(position["price"], 12.0)
        self.assertEqual(position["total"], 360.0)

    def test_foreign_package_is_rejected(self):
        other_item = Item.objects.create(id=uuid.uuid4(), item_type=self.item_type,
                                         name="Другой", unit="шт", organization=self.org)
        foreign_guid = uuid.uuid4()
        foreign = ItemPackage.objects.create(
            id=item_package_pk(other_item.id, foreign_guid), guid_1c=foreign_guid,
            item=other_item, name="Блок", quantity=Decimal("5"))

        response = self.client.post(self.api("cart/"), {
            "item_id": str(self.item.id), "quantity": 5, "package_id": str(foreign.id),
        }, content_type="application/json", **self.auth)

        # Подмена на базовую единицу влила бы чужие блоки в строку литров.
        self.assertEqual(response.status_code, 400)
        self.assertFalse(CartItem.objects.exists())

    def put_line(self, quantity, package=None):
        return self.client.post(self.api("cart/"), {
            "item_id": str(self.item.id), "quantity": quantity,
            "package_id": str(package.id) if package else None,
        }, content_type="application/json", **self.auth)

    def test_same_product_in_two_units_is_two_lines(self):
        # 5 коробок по 10 л и отдельно 3 л.
        self.assertEqual(self.put_line(50, self.box).status_code, 200)
        self.assertEqual(self.put_line(3).status_code, 200)

        lines = self.client.get(self.api("cart/"), **self.auth).json()["results"]
        by_unit = {line["package_id"]: line for line in lines}
        self.assertEqual(len(lines), 2)
        self.assertEqual(by_unit[str(self.box.id)]["quantity"], 50.0)
        self.assertEqual(by_unit[str(self.box.id)]["package"],
                         {"id": str(self.box.id), "name": "Коробка", "quantity": 10.0})
        self.assertEqual(by_unit[None]["quantity"], 3.0)
        self.assertIsNone(by_unit[None]["package"])

    def test_changing_one_line_leaves_the_other(self):
        self.put_line(50, self.box)
        self.put_line(3)

        self.put_line(7)  # меняем только штучную строку
        self.assertEqual(CartItem.objects.get(package=self.box).quantity, Decimal("50"))
        self.assertEqual(CartItem.objects.get(package__isnull=True).quantity, Decimal("7"))

        self.put_line(0, self.box)  # удаляем только коробки
        self.assertEqual(list(CartItem.objects.values_list('package_id', flat=True)), [None])

    def test_order_keeps_one_row_per_unit(self):
        self.put_line(50, self.box)
        self.put_line(3)

        response = self.client.post(self.api("orders/"), {}, content_type="application/json",
                                    **self.auth)
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["created_at"])

        rows = {row.package_name: row for row in OrderItem.objects.all()}
        self.assertEqual(set(rows), {"Коробка", ""})
        self.assertEqual(rows["Коробка"].package_count, Decimal("5.000"))
        self.assertEqual(rows[""].quantity, Decimal("3.00"))
        self.assertEqual(response.json()["result"]["total_amount"], "636.00")  # (50 + 3) * 12

    def test_unregistered_user_is_refused_then_allowed_after_linking(self):
        """Сценарий из жизни: заказ отклонён, 1С привязала контрагента, повтор без перезахода."""
        profile = UserProfile.objects.get(user=self.user)
        profile.guid_partner1c = ""
        profile.save(update_fields=["guid_partner1c"])
        self.put_line(3)

        refused = self.client.post(self.api("orders/"), {}, content_type="application/json",
                                   **self.auth)
        self.assertEqual(refused.status_code, 403)
        self.assertEqual(refused.json()["code"], "unregistered")
        self.assertTrue(CartItem.objects.exists())  # корзина не тронута

        me = self.client.get(self.api("auth/me/"), **self.auth).json()
        self.assertIsNone(me["user"]["profile"]["guid_partner1c"])

        # 1С привязала профиль — токен тот же, заново входить не нужно.
        profile.guid_partner1c = "p-777"
        profile.save(update_fields=["guid_partner1c"])

        me = self.client.get(self.api("auth/me/"), **self.auth).json()
        self.assertEqual(me["user"]["profile"]["guid_partner1c"], "p-777")

        accepted = self.client.post(self.api("orders/"), {}, content_type="application/json",
                                    **self.auth)
        self.assertEqual(accepted.status_code, 200)

    def order(self, **body):
        return self.client.post(self.api("orders/"), body, content_type="application/json",
                                **self.auth)

    def test_checkout_details_are_saved_and_sent_to_1c(self):
        from datetime import timedelta
        from django.utils import timezone
        self.put_line(3)
        tomorrow = timezone.localdate() + timedelta(days=1)

        response = self.order(delivery_date=tomorrow.isoformat(), payment_method="cash",
                              comment="  Доставить до 15:00  ")
        self.assertEqual(response.status_code, 200)

        order = OrderItem.objects.get().order
        self.assertEqual(order.delivery_date, tomorrow)
        self.assertEqual(order.payment_method, "cash")
        self.assertEqual(order.comment, "Доставить до 15:00")

        detail = response.json()["result"]
        self.assertEqual(detail["delivery_date"], tomorrow.isoformat())
        self.assertEqual(detail["payment_method_display"], "Наличные")

        # Та же информация уходит в 1С при выгрузке новых заказов.
        token = Token.objects.create(user=User.objects.create_user(username="1c", password="x"))
        pulled = self.client.get(f"/sync_1c/orders/pull/?prefix={self.org.prefix}",
                                 HTTP_AUTHORIZATION=f"Token {token.key}").json()["result"][0]
        self.assertEqual(pulled["delivery_date"], tomorrow.isoformat())
        self.assertEqual(pulled["payment_method"], "cash")
        self.assertEqual(pulled["payment_method_display"], "Наличные")
        self.assertEqual(pulled["comment"], "Доставить до 15:00")

    def test_checkout_details_are_optional(self):
        self.put_line(3)
        self.assertEqual(self.order().status_code, 200)
        order = OrderItem.objects.get().order
        self.assertIsNone(order.delivery_date)
        self.assertEqual((order.payment_method, order.comment), ("", ""))

    def test_invalid_checkout_details_are_rejected_before_touching_cart(self):
        from datetime import timedelta
        from django.utils import timezone
        self.put_line(3)
        yesterday = (timezone.localdate() - timedelta(days=1)).isoformat()
        for body in ({"delivery_date": yesterday},
                     {"delivery_date": "20.09.2026"},
                     {"payment_method": "bitcoin"},
                     {"comment": "x" * 301}):
            response = self.order(**body)
            self.assertEqual(response.status_code, 400, body)
            self.assertFalse(response.json()["ok"])
        self.assertFalse(OrderItem.objects.exists())
        self.assertTrue(CartItem.objects.exists())

    def test_auth_me_requires_token(self):
        self.assertEqual(self.client.get(self.api("auth/me/")).status_code, 401)

    def test_order_stores_package_snapshot(self):
        self.client.post(self.api("cart/"), {
            "item_id": str(self.item.id), "quantity": 30, "package_id": str(self.box.id),
        }, content_type="application/json", **self.auth)

        response = self.client.post(self.api("orders/"), {}, content_type="application/json",
                                    **self.auth)
        self.assertEqual(response.status_code, 200)

        order_item = OrderItem.objects.get()
        self.assertEqual(order_item.quantity, Decimal("30.00"))
        self.assertEqual(order_item.package_id, self.box_guid)
        self.assertEqual(order_item.package_name, "Коробка")
        self.assertEqual(order_item.package_ratio, Decimal("10.000"))
        self.assertEqual(order_item.package_count, Decimal("3.000"))
        self.assertEqual(order_item.total_amount, Decimal("360.00"))


class Sync1cPackagesAndImagesTests(TestCase):
    """Приём упаковок и пометок картинок из 1С."""

    @classmethod
    def setUpTestData(cls):
        cls.org = Organization.objects.create(inn="111", name="Филиал", prefix="br")
        cls.item_type = ItemType.objects.create(name="Тип", organization=cls.org)
        cls.item = Item.objects.create(id=uuid.uuid4(), item_type=cls.item_type,
                                       name="Товар", unit="шт", organization=cls.org)

    def setUp(self):
        self.user = User.objects.create_user(username="1c", password="x")
        self.token = Token.objects.create(user=self.user)
        self.auth = {"HTTP_AUTHORIZATION": f"Token {self.token.key}"}

    def post(self, path, payload):
        return self.client.post(f"/sync_1c/{path}", payload,
                                content_type="application/json", **self.auth)

    def test_packages_are_upserted_and_stale_ones_removed(self):
        box_id, block_id = uuid.uuid4(), uuid.uuid4()
        row = {
            "id": str(self.item.id), "organization_id": str(self.org.id),
            "item_type": str(self.item_type.id), "name": "Товар", "unit": "шт",
            "packages": [
                {"id": str(box_id), "name": "Коробка", "quantity": "10", "is_default": True},
                {"id": str(block_id), "name": "Блок", "quantity": 5},
            ],
        }
        self.assertEqual(self.post("items/", [row]).status_code, 200)
        self.assertEqual(ItemPackage.objects.count(), 2)
        box_pk = item_package_pk(self.item.id, box_id)
        self.assertTrue(ItemPackage.objects.get(id=box_pk).is_default)

        # Повторная выгрузка без «Блока»: он исчезает, «Коробка» переименовывается.
        row["packages"] = [{"id": str(box_id), "name": "Ящик", "quantity": "12"}]
        self.assertEqual(self.post("items/", [row]).status_code, 200)
        self.assertEqual([p.name for p in ItemPackage.objects.all()], ["Ящик"])
        self.assertEqual(ItemPackage.objects.get(id=box_pk).quantity, Decimal("12.000"))

    def test_same_1c_unit_shared_by_several_items(self):
        """1С шлёт ОДИН GUID «Канистра 4л» сразу у всех четырёхлитровых товаров.

        Раньше это был первичный ключ, и такой пакет ронял обмен ошибкой Postgres
        «ON CONFLICT DO UPDATE command cannot affect row a second time».
        """
        second = Item.objects.create(id=uuid.uuid4(), item_type=self.item_type,
                                     name="Второй", unit="л", organization=self.org)
        shared_guid = uuid.uuid4()
        rows = [
            {"id": str(item.id), "organization_id": str(self.org.id),
             "item_type": str(self.item_type.id), "name": item.name, "unit": "л",
             "packages": [{"id": str(shared_guid), "name": "Канистра 4л", "quantity": 4}]}
            for item in (self.item, second)
        ]

        self.assertEqual(self.post("items/", rows).status_code, 200)

        # Две отдельные упаковки — по одной на товар, обе с одним GUID из 1С.
        self.assertEqual(ItemPackage.objects.count(), 2)
        self.assertEqual(ItemPackage.objects.filter(guid_1c=shared_guid).count(), 2)
        self.assertEqual(
            set(ItemPackage.objects.values_list('item_id', flat=True)),
            {self.item.id, second.id},
        )

        # Повторная выгрузка того же пакета обновляет, а не плодит строки.
        self.assertEqual(self.post("items/", rows).status_code, 200)
        self.assertEqual(ItemPackage.objects.count(), 2)

    def test_duplicate_package_inside_one_item_is_collapsed(self):
        guid = uuid.uuid4()
        row = {
            "id": str(self.item.id), "organization_id": str(self.org.id),
            "item_type": str(self.item_type.id), "name": "Товар", "unit": "шт",
            "packages": [
                {"id": str(guid), "name": "Коробка", "quantity": 10},
                {"id": str(guid), "name": "Коробка", "quantity": 10},
            ],
        }
        self.assertEqual(self.post("items/", [row]).status_code, 200)
        self.assertEqual(ItemPackage.objects.count(), 1)

    def test_removed_package_merges_cart_line_into_base_unit(self):
        client_user = User.objects.create_user(username="buyer", password="x")
        guid = uuid.uuid4()
        box = ItemPackage.objects.create(id=item_package_pk(self.item.id, guid), guid_1c=guid,
                                         item=self.item, name="Коробка", quantity=Decimal("10"))
        CartItem.objects.create(user=client_user, item=self.item, organization=self.org,
                                package=box, quantity=Decimal("20"))
        CartItem.objects.create(user=client_user, item=self.item, organization=self.org,
                                quantity=Decimal("3"))

        row = {"id": str(self.item.id), "organization_id": str(self.org.id),
               "item_type": str(self.item_type.id), "name": "Товар", "unit": "шт",
               "packages": []}
        # Без слияния SET_NULL дал бы две базовые строки и обмен упал бы на уникальности.
        self.assertEqual(self.post("items/", [row]).status_code, 200)

        self.assertFalse(ItemPackage.objects.exists())
        line = CartItem.objects.get(user=client_user)
        self.assertIsNone(line.package_id)
        self.assertEqual(line.quantity, Decimal("23"))

    def test_packages_untouched_when_key_absent(self):
        guid = uuid.uuid4()
        ItemPackage.objects.create(id=item_package_pk(self.item.id, guid), guid_1c=guid,
                                   item=self.item, name="Коробка", quantity=Decimal("10"))
        row = {"id": str(self.item.id), "organization_id": str(self.org.id),
               "item_type": str(self.item_type.id), "name": "Товар", "unit": "шт"}
        self.assertEqual(self.post("items/", [row]).status_code, 200)
        self.assertEqual(ItemPackage.objects.count(), 1)

    def test_image_validity_endpoint_toggles_flag(self):
        image = ItemImage.objects.create(id=uuid.uuid4(), item=self.item,
                                         image_path="products/a.jpg")

        response = self.post("images/validity/", [{"id": str(image.id), "is_invalid": "Истина"}])
        self.assertEqual(response.status_code, 200)
        image.refresh_from_db()
        self.assertTrue(image.is_invalid)

        # Файл на месте — 1С может вернуть картинку обратно одним флагом.
        self.post("images/validity/", [{"id": str(image.id), "is_invalid": False}])
        image.refresh_from_db()
        self.assertFalse(image.is_invalid)
        self.assertEqual(image.image_path.name, "products/a.jpg")

    def test_images_accept_objects_with_flags(self):
        row = {
            "id": str(self.item.id), "organization_id": str(self.org.id),
            "item_type": str(self.item_type.id), "name": "Товар", "unit": "шт",
            "images": [
                {"path": "products/a.jpg", "is_main": True},
                {"path": "products/b.jpg", "is_invalid": True},
            ],
        }
        self.assertEqual(self.post("items/", [row]).status_code, 200)
        self.assertEqual(ItemImage.objects.filter(is_invalid=True).count(), 1)
        self.assertEqual(ItemImage.objects.filter(is_main=True).count(), 1)


class Sync1cUserProfileListFilterTests(TestCase):
    """Выгрузка профилей в 1С с фильтром по организации."""

    @classmethod
    def setUpTestData(cls):
        cls.org_a = Organization.objects.create(inn="1", name="Филиал А", prefix="a")
        cls.org_b = Organization.objects.create(inn="2", name="Филиал Б", prefix="b")
        pt_a = PriceType.objects.create(name="Розница", organization=cls.org_a, is_default=True)
        pt_b = PriceType.objects.create(name="Розница", organization=cls.org_b, is_default=True)

        def profile(username, org, price_type, guid=None):
            user = User.objects.create_user(username=username, password="x")
            return UserProfile.objects.create(user=user, name=username, organization=org,
                                              price_type=price_type, guid_partner1c=guid)

        cls.a_linked = profile("a_linked", cls.org_a, pt_a, guid="p-1")
        cls.a_unlinked = profile("a_unlinked", cls.org_a, pt_a)
        cls.b_unlinked = profile("b_unlinked", cls.org_b, pt_b)

    def setUp(self):
        user = User.objects.create_user(username="1c", password="x")
        self.auth = {"HTTP_AUTHORIZATION": f"Token {Token.objects.create(user=user).key}"}

    def get(self, path, **params):
        return self.client.get(f"/sync_1c/{path}", params, **self.auth)

    @staticmethod
    def names(response):
        return sorted(row["name"] for row in response.json()["result"])

    def test_without_filter_returns_all_organizations(self):
        response = self.get("user-profiles/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.names(response), ["a_linked", "a_unlinked", "b_unlinked"])
        self.assertIsNone(response.json()["organization_id"])

    def test_filter_by_organization(self):
        response = self.get("user-profiles/", organization_id=str(self.org_a.id))
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(self.names(response), ["a_linked", "a_unlinked"])
        self.assertEqual(body["count"], 2)
        self.assertEqual(body["organization_id"], str(self.org_a.id))

    def test_filter_combines_with_unlinked(self):
        # Отдельный маршрут unlinked/ наследует фильтр.
        response = self.get("user-profiles/unlinked/", organization_id=str(self.org_a.id))
        self.assertEqual(self.names(response), ["a_unlinked"])
        # И флаг в общем маршруте работает так же.
        response = self.get("user-profiles/", organization_id=str(self.org_b.id), only_unlinked=1)
        self.assertEqual(self.names(response), ["b_unlinked"])

    def test_bad_uuid_is_400(self):
        response = self.get("user-profiles/", organization_id="не-uuid")
        self.assertEqual(response.status_code, 400)
        self.assertFalse(response.json()["ok"])

    def test_unknown_organization_is_404_not_empty_list(self):
        response = self.get("user-profiles/", organization_id=str(uuid.uuid4()))
        self.assertEqual(response.status_code, 404)
        self.assertFalse(response.json()["ok"])
