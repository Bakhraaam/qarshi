"""
Инвалидация кэша каталога через версию на организацию.

Идея: страницы каталога кэшируются под ключом, включающим текущую «версию» каталога
организации. Любая правка каталога из 1С (товары/цены/остатки/категории/картинки)
увеличивает версию — старые ключи становятся недостижимы и сами истекают по TTL.
Не нужно перечислять и удалять ключи вручную.
"""
from django.core.cache import cache

_VERSION_KEY = "catalog_ver:{}"


def get_catalog_version(org_id) -> int:
    """Текущая версия каталога организации (создаётся как 1 при первом обращении)."""
    key = _VERSION_KEY.format(org_id)
    version = cache.get(key)
    if version is None:
        cache.set(key, 1, None)  # без TTL — версия живёт постоянно
        return 1
    return version


def bump_catalog_version(org_ids) -> None:
    """Инвалидирует кэш каталога для одной организации или списка организаций."""
    if org_ids is None:
        return
    if not isinstance(org_ids, (list, set, tuple)):
        org_ids = [org_ids]
    for org_id in org_ids:
        if not org_id:
            continue
        key = _VERSION_KEY.format(org_id)
        try:
            cache.incr(key)
        except ValueError:
            # Ключа ещё нет — стартуем со 2, чтобы гарантированно разойтись с дефолтной версией 1
            cache.set(key, 2, None)
