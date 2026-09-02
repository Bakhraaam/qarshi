"""Тесты Telegram-бота филиала (вебхук + сценарии сообщений)."""
from django.core.cache import cache
from django.test import TestCase, override_settings

from front_api.bot import api, handlers, polling
from front_api.models import TelegramAccount
from sync_1c.models import Organization, PriceType, UserProfile

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
