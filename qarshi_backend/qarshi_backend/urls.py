import os

from django.contrib import admin
from django.urls import path, re_path, include
from django.conf import settings
from django.conf.urls.static import static
from django.http import FileResponse, Http404

urlpatterns = [
    path('admin/', admin.site.urls),
    path('sync_1c/', include('sync_1c.urls')),
    path('api/v1/<str:org_prefix>/', include('front_api.urls')),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)


# --- Раздача собранного Flutter web (SPA) ---
# Отдаёт файлы из qarshi_front/build/web; для остальных путей — index.html (клиентский роутинг).
# Ставится ПОСЛЕ admin/api/sync/media, поэтому их не перехватывает.
FLUTTER_WEB_DIR = os.path.join(settings.BASE_DIR.parent, 'qarshi_front', 'build', 'web')


# Явные MIME-типы для ассетов Flutter web / wasm-сборки
_FLUTTER_MIME = {
    '.wasm': 'application/wasm',
    '.js': 'text/javascript',
    '.mjs': 'text/javascript',
    '.json': 'application/json',
    '.html': 'text/html',
    '.css': 'text/css',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.ttf': 'font/ttf',
    '.otf': 'font/otf',
    '.wasm.map': 'application/json',
}


def _no_cache(response):
    # Всегда отдаём свежую сборку — иначе браузер держит старый билд (проблема "нет результата")
    response['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response['Pragma'] = 'no-cache'
    return response


def flutter_spa(request, path=''):
    candidate = os.path.normpath(os.path.join(FLUTTER_WEB_DIR, path))
    # Защита от выхода за пределы каталога сборки
    if not candidate.startswith(FLUTTER_WEB_DIR):
        raise Http404()
    ext = os.path.splitext(candidate)[1].lower()
    if path and os.path.isfile(candidate):
        content_type = _FLUTTER_MIME.get(ext)
        return _no_cache(FileResponse(open(candidate, 'rb'), content_type=content_type))
    # Путь похож на файл (есть расширение), но его нет — это 404, а не SPA-маршрут.
    # Иначе отсутствующий ассет (напр. удалённый service worker) получал бы index.html.
    if ext:
        raise Http404()
    index_file = os.path.join(FLUTTER_WEB_DIR, 'index.html')
    if os.path.isfile(index_file):
        return _no_cache(FileResponse(open(index_file, 'rb'), content_type='text/html'))
    raise Http404('Flutter build не найден. Соберите: flutter build web')


urlpatterns += [
    re_path(r'^(?P<path>.*)$', flutter_spa),
]
