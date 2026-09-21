"""Акт сверки: заявка от клиента, готовый файл приходит из 1С.

Сайт не ходит в 1С сам. Клиент создаёт заявку, она ждёт в статусе pending;
1С забирает её через sync_1c/reports/act/pending/, формирует печатную форму и
присылает файл в sync_1c/reports/act/upload/. После этого клиент получает
сообщение в Telegram, а экран акта, если он всё ещё открыт, сам подхватит файл.
"""
import base64

from django.http import FileResponse, Http404
from django.utils.dateparse import parse_date
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework_simplejwt.authentication import JWTAuthentication

from front_api.models import ActReconciliationRequest
from front_api.reports_links import build_file_url, unsign_request_id
from front_api.views.base import BaseFrontendAPIView
from sync_1c.models import UserProfile

# Сколько последних заявок отдаём в списке — экран показывает историю за сеанс.
RECENT_LIMIT = 10
# Разумный предел периода: 1С строит акт долго, а клиенту столько и не нужно.
MAX_PERIOD_DAYS = 366


def serialize_request(act_request, request=None) -> dict:
    """Единый формат заявки для всех ответов клиенту."""
    data = {
        "id": str(act_request.id),
        "status": act_request.status,
        "status_display": act_request.get_status_display(),
        "date_from": act_request.date_from.isoformat(),
        "date_to": act_request.date_to.isoformat(),
        "created_at": act_request.created_at.isoformat(),
        "filename": act_request.filename,
        "message": act_request.message,
        "file_url": None,
    }
    if act_request.status == ActReconciliationRequest.STATUS_READY and act_request.file:
        data["file_url"] = build_file_url(act_request, request)
    return data


class ActReconciliationView(BaseFrontendAPIView):
    """
    POST /api/v1/<org_prefix>/reports/act/ — создать заявку.
        Тело: {"date_from": "2026-01-01", "date_to": "2026-01-31"}
    GET  /api/v1/<org_prefix>/reports/act/ — последние заявки клиента.
    """
    authentication_classes = [JWTAuthentication]
    permission_classes = [IsAuthenticated]

    def get(self, request, *args, **kwargs):
        requests = (ActReconciliationRequest.objects
                    .filter(user=request.user, organization=self.current_organization)
                    .select_related('organization')[:RECENT_LIMIT])
        return Response(
            {"ok": True, "results": [serialize_request(r, request) for r in requests]},
            status=status.HTTP_200_OK,
        )

    def post(self, request, *args, **kwargs):
        date_from = parse_date(str(request.data.get("date_from", "")).strip())
        date_to = parse_date(str(request.data.get("date_to", "")).strip())

        if not date_from or not date_to:
            return Response({"ok": False, "message": "Укажите период: date_from и date_to в формате ГГГГ-ММ-ДД"},
                            status=status.HTTP_400_BAD_REQUEST)
        if date_from > date_to:
            return Response({"ok": False, "message": "Дата начала позже даты окончания"},
                            status=status.HTTP_400_BAD_REQUEST)
        if (date_to - date_from).days > MAX_PERIOD_DAYS:
            return Response({"ok": False, "message": "Период не может быть больше года"},
                            status=status.HTTP_400_BAD_REQUEST)

        # Акт строится по контрагенту 1С, поэтому без привязки его просто не из чего делать.
        profile = UserProfile.objects.filter(
            user=request.user, organization=self.current_organization
        ).first()
        guid = (profile.guid_partner1c or '').strip() if profile else ''
        if not guid:
            notice = (self.current_organization.unregistered_notice or '').strip()
            return Response(
                {
                    "ok": False,
                    "code": "unregistered",
                    "message": notice or "Акт сверки доступен после подтверждения аккаунта менеджером.",
                },
                status=status.HTTP_403_FORBIDDEN,
            )

        # Повторное нажатие за тот же период не плодит заявки: 1С получила бы дубли.
        existing = ActReconciliationRequest.objects.filter(
            user=request.user, organization=self.current_organization,
            date_from=date_from, date_to=date_to,
            status=ActReconciliationRequest.STATUS_PENDING,
        ).first()

        act_request = existing or ActReconciliationRequest.objects.create(
            organization=self.current_organization,
            user=request.user,
            guid_partner1c=guid,
            date_from=date_from,
            date_to=date_to,
        )

        return Response(
            {
                "ok": True,
                "message": "Заявка принята. Акт формируется в 1С — пришлём, как будет готов.",
                "result": serialize_request(act_request, request),
            },
            status=status.HTTP_200_OK,
        )


class ActReconciliationDetailView(BaseFrontendAPIView):
    """GET /api/v1/<org_prefix>/reports/act/<uuid>/ — статус заявки (экран опрашивает его)."""
    authentication_classes = [JWTAuthentication]
    permission_classes = [IsAuthenticated]

    def get(self, request, request_id, *args, **kwargs):
        act_request = ActReconciliationRequest.objects.filter(
            id=request_id, user=request.user, organization=self.current_organization
        ).select_related('organization').first()
        if not act_request:
            return Response({"ok": False, "message": "Заявка не найдена"},
                            status=status.HTTP_404_NOT_FOUND)

        payload = serialize_request(act_request, request)
        # Веб-клиент за пределами браузера (Telegram) может не открыть ссылку —
        # отдаём и сам файл, чтобы экран мог сохранить его сам.
        if request.query_params.get('with_file') and act_request.file:
            act_request.file.open('rb')
            try:
                payload["pdf_base64"] = base64.b64encode(act_request.file.read()).decode('ascii')
            finally:
                act_request.file.close()

        return Response({"ok": True, "result": payload}, status=status.HTTP_200_OK)


class ActReconciliationFileView(BaseFrontendAPIView):
    """
    GET /api/v1/<org_prefix>/reports/act/<uuid>/file/?t=<подпись> — скачать готовый акт.

    Без JWT: ссылку открывают обычным переходом (новая вкладка, сообщение в Telegram),
    заголовок Authorization туда не подставить. Доступ даёт подпись в параметре t.
    """
    authentication_classes = []
    permission_classes = [AllowAny]

    def get(self, request, request_id, *args, **kwargs):
        token = request.query_params.get('t', '')
        if unsign_request_id(token) != str(request_id):
            raise Http404("Ссылка недействительна или устарела")

        act_request = ActReconciliationRequest.objects.filter(
            id=request_id, organization=self.current_organization
        ).first()
        if not act_request or not act_request.file:
            raise Http404("Файл не найден")

        return FileResponse(
            act_request.file.open('rb'),
            as_attachment=True,
            filename=act_request.filename or f"act_{act_request.date_from}_{act_request.date_to}.pdf",
        )
