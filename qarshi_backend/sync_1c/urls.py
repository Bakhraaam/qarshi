from django.urls import path
from .views import Sync1cGetNewTelegramUsersView, ItemImageUploadView, Sync1cPullOrdersView, Sync1cUpdateOrdersView, Sync1cUpdateStocksView, Sync1cUpdateOrganizationsView, Sync1cUpdateItemsView, Sync1cUpdatePricelistView, Sync1cUpdateItemTypesView, Sync1cUpdatePriceTypesView, Sync1cUpdateUsersView
urlpatterns = [
    # старый метод
    # path('data/', BulkDataSyncView.as_view(), name='bulk_data_sync'),

    # Маршрут для пользователей:
    path('user-profile/', Sync1cUpdateUsersView.as_view(), name='1c_update_user-profiles'),
    # Маршрут для получения новых пользователей
    path('users/get/', Sync1cGetNewTelegramUsersView.as_view(), name='1c_get_users'),
    # Маршрут для номенклатуры:
    path('items/', Sync1cUpdateItemsView.as_view(), name='1c_update_items'),
    # Маршрут для видов номенклатуры:
    path('item_types/', Sync1cUpdateItemTypesView.as_view(), name='1c_update_item_types'),
    # Маршрут для номенклатуры:
    path('price-types/', Sync1cUpdatePriceTypesView.as_view(), name='1c_update_price_types'),
    # Маршрут для прайс_лист:
    path('price-list/', Sync1cUpdatePricelistView.as_view(), name='1c_update_price_list'),
    # Маршрут для картинки товаров:
    path('image_item_upload/', ItemImageUploadView.as_view(), name='item_item_image_upload'),
    # Маршрут для организаций
    path('organizations/', Sync1cUpdateOrganizationsView.as_view(), name='1c_update_organizations'),
    # Маршрут для получения новых заказов
    path('orders/pull/', Sync1cPullOrdersView.as_view(), name='1c_pull_orders'),
    # Маршрут для обновления состава и статусов заказов
    path('orders/update/', Sync1cUpdateOrdersView.as_view(), name='1c_update_orders'),
    # Маршрут для остатки товаров:
    path('stocks/update/', Sync1cUpdateStocksView.as_view(), name='1c_update_stocks'),

]