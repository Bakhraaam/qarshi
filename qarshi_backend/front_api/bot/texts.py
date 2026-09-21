"""
Тексты Telegram-бота (деловой тон, только русский).

Все сообщения собираются здесь, чтобы правки формулировок не задевали логику
в handlers.py. Единственная кнопка бота — запрос номера телефона; всё остальное
происходит в Mini App, поэтому тексты никуда не ведут, кроме приложения.
"""

BTN_SHARE_PHONE = "📱 Отправить номер телефона"


def _join(*parts) -> str:
    """Склеивает непустые абзацы через пустую строку."""
    return "\n\n".join(p.strip() for p in parts if p and p.strip())


def format_phone(phone: str) -> str:
    """Нормализованные цифры -> вид для сообщения: 998901234567 -> +998901234567"""
    digits = (phone or "").strip()
    return f"+{digits}" if digits and not digits.startswith("+") else digits


def _hello(organization, first_name: str) -> str:
    who = (first_name or "").strip()
    return f"{organization.name}. Здравствуйте, {who}!" if who else f"{organization.name}."


def start_ask_phone(organization, first_name: str) -> str:
    """/start, номера ещё нет."""
    return _join(
        _hello(organization, first_name),
        "Оптовый заказ через Telegram: каталог, актуальные цены и остатки, "
        "история заказов и акт сверки — в одном окне.",
        "Отправьте номер телефона: по нему менеджер найдёт вас среди контрагентов "
        "и откроет оптовые цены. Нажмите кнопку ниже — номер подставит сам Telegram, "
        "вводить вручную не нужно.",
    )


def start_with_phone(organization, first_name: str) -> str:
    """/start, номер уже есть."""
    return _join(
        _hello(organization, first_name),
        "Откройте приложение кнопкой «Открыть» у этого бота или через меню вложений: "
        "каталог, цены, остатки, заказы и акт сверки — там.",
    )


def phone_still_needed() -> str:
    """Клиент без номера написал текст вместо нажатия кнопки."""
    return _join(
        "Бот принимает только номер телефона — нажмите кнопку ниже.",
        "Заказы и переписка с менеджером — внутри приложения.",
    )


def phone_taken(organization) -> str:
    """Номер уже закреплён за другим аккаунтом Telegram."""
    support = (organization.support_phone or "").strip()
    return _join(
        "Этот номер уже привязан к другому аккаунту Telegram. "
        "Если это ваш номер, обратитесь к менеджеру — он перенесёт привязку.",
        f"Телефон менеджера: {support}" if support else "",
    )


def contact_linked(phone: str, partner_name: str) -> str:
    """Телефон получен, профиль привязан к контрагенту 1С."""
    partner = (partner_name or "").strip()
    head = f"Номер {format_phone(phone)} принят."
    if partner:
        head = f"{head} Ваш контрагент: {partner}."
    return _join(head, "Цены отображаются по вашему договору. Приятной работы.")


def contact_unlinked(organization, phone: str) -> str:
    """Телефон получен, привязки к контрагенту 1С пока нет."""
    support = (organization.support_phone or "").strip()
    notice = (organization.unregistered_notice or "").strip()
    return _join(
        f"Номер {format_phone(phone)} принят, заявка передана менеджеру.",
        notice,
        "Каталог и цены уже доступны для просмотра — оформление заказов "
        "откроется после подтверждения менеджером.",
        f"Вопросы: {support}" if support else "",
    )


def open_app(organization) -> str:
    """Любое сообщение боту: переписку ведём не здесь."""
    support = (organization.support_phone or "").strip()
    return _join(
        "Бот не ведёт переписку: заказы, цены и остатки — в приложении. "
        "Откройте его кнопкой «Открыть» у бота.",
        f"Связаться с менеджером: {support}" if support else "",
    )


def foreign_contact() -> str:
    """Прислали чужой контакт."""
    return (
        "Принимаем только ваш собственный номер. Нажмите кнопку ниже — Telegram "
        "отправит его сам. Карточку из адресной книги, созданный вручную контакт "
        "или пересланное сообщение бот не примет."
    )


def blocked(organization) -> str:
    """Доступ закрыт менеджером (заблокирован пользователь или профиль филиала)."""
    support = (organization.support_phone or "").strip()
    tail = f"Обратитесь в поддержку: {support}" if support else "Обратитесь к вашему менеджеру."
    return f"Доступ к {organization.name} закрыт менеджером. {tail}"


def _period(date_from, date_to) -> str:
    return f"{date_from.strftime('%d.%m.%Y')} — {date_to.strftime('%d.%m.%Y')}"


def act_ready_caption(date_from, date_to) -> str:
    """Подпись к файлу акта, отправленному в чат."""
    return f"Ваш акт сверки за период {_period(date_from, date_to)} готов."


def act_ready_without_file(date_from, date_to) -> str:
    """Файл не удалось отправить в чат (слишком большой, сбой сети) — зовём в приложение."""
    return _join(
        f"Ваш акт сверки за период {_period(date_from, date_to)} готов.",
        "Откройте приложение, раздел «Акт сверки», — документ можно посмотреть и скачать там.",
    )


def act_failed(date_from, date_to, message: str) -> str:
    """1С не смогла построить акт за период."""
    return _join(
        f"Не удалось сформировать акт сверки за период {_period(date_from, date_to)}.",
        (message or "").strip(),
        "Попробуйте другой период или обратитесь к менеджеру.",
    )
