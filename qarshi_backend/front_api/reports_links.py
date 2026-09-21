"""Подписанные ссылки на готовый акт сверки.

Файл нельзя отдавать просто из /media/: это финансовый документ конкретного
контрагента. JWT для такой ссылки не годится — её открывают обычным переходом
(новая вкладка, кнопка в Telegram), а заголовок Authorization туда не подставить.
Поэтому в ссылку кладём подпись Django (TimestampSigner) с ограниченным сроком.
"""
from django.core import signing

SALT = 'front_api.act_reconciliation'

# Сутки. Ссылку больше никуда не рассылаем: её получает только открытый экран акта
# сразу после входа, а в Telegram уходит сам файл. Дольше жить ей незачем.
LINK_MAX_AGE_SECONDS = 24 * 60 * 60


def sign_request_id(request_id) -> str:
    return signing.TimestampSigner(salt=SALT).sign(str(request_id))


def unsign_request_id(token: str) -> str | None:
    """Возвращает id заявки или None, если подпись битая или просрочена."""
    try:
        return signing.TimestampSigner(salt=SALT).unsign(
            token, max_age=LINK_MAX_AGE_SECONDS
        )
    except (signing.BadSignature, signing.SignatureExpired):
        return None


def build_file_url(act_request, request=None) -> str:
    """Абсолютная ссылка на скачивание готового акта."""
    path = (f"/api/v1/{act_request.organization.prefix}/reports/act/"
            f"{act_request.id}/file/?t={sign_request_id(act_request.id)}")
    if request is not None:
        return request.build_absolute_uri(path)

    # Вне HTTP-запроса (уведомление в Telegram) берём домен Mini App филиала.
    from front_api.bot import api as bot_api
    return f"{bot_api.webapp_base_url(act_request.organization)}{path}"
