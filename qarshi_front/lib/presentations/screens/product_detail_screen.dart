import 'package:flutter/material.dart';
import 'package:qarshi/core/data/constants.dart';
import 'package:qarshi/core/data/models.dart';
import 'package:qarshi/core/utils/formatters.dart';
import 'package:qarshi/presentations/widgets/product_cart_control.dart';
import 'package:qarshi/presentations/widgets/product_gallery.dart';

/// Карточка товара: галерея картинок, цена, реквизиты и добавление в корзину.
///
/// Открывается из каталога по нажатию на товар. Количество берётся из глобальной
/// корзины (cartNotifier), а запись идёт через onQuantityChanged каталога —
/// так экран и сетка каталога всегда показывают одно и то же число.
class ProductDetailScreen extends StatelessWidget {
  final Product product;
  final ValueChanged<num> onQuantityChanged;

  /// Единица, которой клиент набирает товар (null — базовая).
  final String? packageId;

  /// Клиент переключил единицу: приходит новая упаковка и пересчитанное
  /// количество в базовых единицах.
  final void Function(String? packageId, num quantity)? onPackageChanged;

  const ProductDetailScreen({
    super.key,
    required this.product,
    required this.onQuantityChanged,
    this.packageId,
    this.onPackageChanged,
  });

  /// Открывает карточку товара поверх текущего экрана.
  static Future<void> open(
    BuildContext context, {
    required Product product,
    required ValueChanged<num> onQuantityChanged,
    String? packageId,
    void Function(String? packageId, num quantity)? onPackageChanged,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          product: product,
          onQuantityChanged: onQuantityChanged,
          packageId: packageId,
          onPackageChanged: onPackageChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Товар'),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: isWide ? _buildWideLayout() : _buildNarrowLayout(),
      ),
    );
  }

  // Десктоп: галерея слева, реквизиты и кнопка справа — без «прилипшей» панели.
  Widget _buildWideLayout() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _galleryCard(showArrows: true),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfo(),
                    const SizedBox(height: 20),
                    _buildCartControl(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Телефон/Telegram: галерея сверху, реквизиты ниже, кнопка закреплена внизу.
  Widget _buildNarrowLayout() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(aspectRatio: 1, child: _galleryCard()),
                const SizedBox(height: 16),
                _buildInfo(),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: _buildCartControl(),
        ),
      ],
    );
  }

  Widget _galleryCard({bool showArrows = false}) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ProductGallery(images: product.gallery, showArrows: showArrows),
    );
  }

  Widget _buildInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatPrice(product.price),
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          product.name,
          style: const TextStyle(
            fontSize: 18,
            height: 1.3,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              if (product.categoryName.isNotEmpty)
                _AttributeRow(label: 'Категория', value: product.categoryName),
              if (product.articul.isNotEmpty)
                _AttributeRow(label: 'Артикул', value: product.articul),
              _AttributeRow(
                label: 'Остаток',
                value: '${product.stock.toStringAsFixed(0)} ${product.unit}',
              ),
              _AttributeRow(label: 'Единица измерения', value: product.unit),
              // Цена всегда за базовую единицу — упаковка только множитель.
              for (final package in product.packages)
                _AttributeRow(
                  label: package.name,
                  value: '${formatNumber(package.quantity)} ${product.unit}',
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCartControl() {
    return ValueListenableBuilder<Map<String, num>>(
      valueListenable: cartNotifier,
      builder: (context, cart, _) {
        return ValueListenableBuilder<Map<String, String>>(
          valueListenable: cartPackageNotifier,
          builder: (context, packages, _) {
            return ProductCartControl(
              product: product,
              quantity: cart[product.id] ?? 0,
              packageId: packages[product.id] ?? packageId,
              onQuantityChanged: onQuantityChanged,
              onPackageChanged: onPackageChanged,
              dense: false,
            );
          },
        );
      },
    );
  }
}

class _AttributeRow extends StatelessWidget {
  final String label;
  final String value;

  const _AttributeRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
