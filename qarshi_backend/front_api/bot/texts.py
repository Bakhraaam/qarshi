"""
Тексты Telegram-бота (деловой тон, только русский).

Все сообщения собираются здесь, чтобы правки формулировок не задевали логику
в handlers.py. Номер телефона просим, но не требуем: каталог открывается и без него.
"""

BTN_SHARE_PHONE = "📱 Отправить номер телефона"


def _join(*parts) -> str:
    """Склеивает непустые абзацы через пустую строку."""
    return "\n\n".join(p.strip() for p in parts if p and p.strip())


def format_phone(phone: str) -> str:
    """Нормализованные цифры -> вид для сообщения: 998901234567 -> +998901234567"""
    digits = (phone or "").strip()
    return f"+{digits}" if digits and not digits.startswith("+") else digits


def start_no_phone(organization) -> str:
    """/start, телефона ещё нет."""
    return _join(
        f"{organization.name} — оптовый заказ через Telegram.\n"
        "Каталог, актуальные цены и остатки, история заказов и акт сверки — в одном окне.",

        "Оставьте номер телефона: по нему менеджер найдёт вас среди контрагентов "
        "и откроет оптовые цены. Нажмите кнопку ниже — Telegram отправит номер, "
        "вводить вручную не нужно.",
    )


def start_with_phone(organization, first_name: str) -> str:
    """/start, телефон уже есть."""
    who = (first_name or "").strip()
    return f"{organization.name}. Вы авторизованы как {who}." if who else f"{organization.name}. Вы авторизованы."


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


def text_instead_of_button() -> str:
    """Пользователь без телефона написал текст вместо нажатия кнопки."""
    return _join(
        "Бот принимает только номер телефона — нажмите кнопку ниже.",
        "Заказы и переписка с менеджером — внутри приложения.",
    )


def hint_use_buttons() -> str:
    """Пользователь с телефоном написал что-то боту."""
    return "Заказы и переписка с менеджером — внутри приложения."


def foreign_contact() -> str:
    """Прислали чужой контакт."""
    return (
        "Это контакт другого пользователя. Нужен номер, привязанный к вашему "
        "аккаунту Telegram — нажмите кнопку."
    )


def blocked(organization) -> str:
    """Доступ закрыт менеджером (заблокирован пользователь или профиль филиала)."""
    support = (organization.support_phone or "").strip()
    tail = f"Обратитесь в поддержку: {support}" if support else "Обратитесь к вашему менеджеру."
    return f"Доступ к {organization.name} закрыт менеджером. {tail}"
