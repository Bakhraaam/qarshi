from django.urls import path, include
from rest_framework.routers import SimpleRouter
from .views.catalog import FrontendCategoryViewSet, FrontendProductViewSet
from .views.auth import FrontendLoginView, FrontendRegisterView, TelegramAuthView
from .views.cart import FrontendCartViewSet
from .views.orders import FrontendOrderViewSet
from .views.reports import ActReconciliationView

router = SimpleRouter()
router.register('categories', FrontendCategoryViewSet, basename='front-categories')
router.register('products', FrontendProductViewSet, basename='front-products')
router.register('cart', FrontendCartViewSet, basename='front-cart')
router.register('orders', FrontendOrderViewSet, basename='front-orders')

urlpatterns = [
    path('', include(router.urls)),

    path('auth/register/', FrontendRegisterView.as_view(), name='frontend_register'),
    path('auth/login/', FrontendLoginView.as_view(), name='frontend_login'),
    path('auth/telegram/', TelegramAuthView.as_view(), name='frontend_login'),

    path('reports/act/', ActReconciliationView.as_view(), name='frontend_act'),
]