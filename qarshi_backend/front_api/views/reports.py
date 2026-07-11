import base64

from rest_framework.response import Response
from rest_framework import status
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.permissions import IsAuthenticated

from front_api.views.base import BaseFrontendAPIView


def _build_demo_pdf(title: str, period: str, org_name: str) -> bytes:
    """
    Генерирует минимальный валидный PDF без внешних библиотек.
    ВРЕМЕННО: заглушка вместо реального акта из 1С.
    TODO: заменить на запрос акта сверки в 1С (вернёт готовый PDF/base64),
    здесь останется только отдать его во фронт.
    """
    def esc(s):
        return s.replace('\\', r'\\').replace('(', r'\(').replace(')', r'\)')

    lines = [
        f"BT /F1 20 Tf 60 780 Td ({esc(title)}) Tj ET",
        f"BT /F1 12 Tf 60 750 Td (Организация: {esc(org_name)}) Tj ET",
        f"BT /F1 12 Tf 60 732 Td (Период: {esc(period)}) Tj ET",
        "BT /F1 11 Tf 60 700 Td (Демо-документ. Реальный акт придёт из 1С.) Tj ET",
    ]
    content = "\n".join(lines).encode("latin-1", "replace")

    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] "
        b"/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length " + str(len(content)).encode() + b" >>\nstream\n" + content + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]

    pdf = bytearray(b"%PDF-1.4\n")
    offsets = []
    for i, obj in enumerate(objects, start=1):
        offsets.append(len(pdf))
        pdf += f"{i} 0 obj\n".encode() + obj + b"\nendobj\n"

    xref_pos = len(pdf)
    pdf += f"xref\n0 {len(objects) + 1}\n".encode()
    pdf += b"0000000000 65535 f \n"
    for off in offsets:
        pdf += f"{off:010d} 00000 n \n".encode()
    pdf += (
        b"trailer\n<< /Size " + str(len(objects) + 1).encode() +
        b" /Root 1 0 R >>\nstartxref\n" + str(xref_pos).encode() + b"\n%%EOF"
    )
    return bytes(pdf)


class ActReconciliationView(BaseFrontendAPIView):
    """
    POST /api/v1/<org_prefix>/reports/act/
    Тело: {"date_from": "2026-01-01", "date_to": "2026-01-31"}
    Ответ: {"ok": true, "filename": "...", "pdf_base64": "..."}
    """
    authentication_classes = [JWTAuthentication]
    permission_classes = [IsAuthenticated]

    def post(self, request, *args, **kwargs):
        date_from = str(request.data.get("date_from", "")).strip()
        date_to = str(request.data.get("date_to", "")).strip()
        if not date_from or not date_to:
            return Response(
                {"ok": False, "message": "Укажите период: date_from и date_to"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        period = f"{date_from} — {date_to}"
        org_name = getattr(self.current_organization, "name", "")

        # TODO: здесь вызвать 1С за реальным актом сверки контрагента за период.
        pdf_bytes = _build_demo_pdf("Акт сверки", period, org_name)
        pdf_b64 = base64.b64encode(pdf_bytes).decode("ascii")

        return Response(
            {
                "ok": True,
                "filename": f"act_{date_from}_{date_to}.pdf",
                "pdf_base64": pdf_b64,
            },
            status=status.HTTP_200_OK,
        )
