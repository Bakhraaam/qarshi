import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
// import 'package:intl/intl.dart';
import 'package:qarshi/core/data/api/api_django.dart';
import 'package:qarshi/core/data/constants.dart';
import 'package:qarshi/core/data/models.dart';
import 'package:qarshi/core/utils/formatters.dart';
import 'package:qarshi/presentations/widgets/filter_sheet.dart';
// import 'package:qarshi/core/utils/formatters.dart';
// import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CatalogScreen extends StatefulWidget {
  final bool embedded;
  final Map<String, num>? cartQuantities;
  const CatalogScreen({super.key, this.embedded = false, this.cartQuantities});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final DjangoApi _api = DjangoApi();
  final ScrollController _scrollController = ScrollController();

  List<ProductCategory> _categories = [];
  List<Product> _products = [];
  late Map<String, num> _cartQuantities =
      {}; // Перенесено наверх для правильной видимости

  String? _selectedCategoryId;
  bool _isFirstLoad = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasNextPage = true;
  double? _minPrice;
  double? _maxPrice;
  String? _searchQuery; // Переменная для хранения текста поиска
  Timer? _debounce; // Таймер для предотвращения частых запросов при вводе
  final TextEditingController _searchController =
      TextEditingController(); // Контроллер для поля поиска
  late final FocusNode _searchFocusNode;
  // Динамический геттер для отслеживания активности фильтров
  bool get hasActiveFilters =>
      _selectedCategoryId != null ||
      _minPrice != null ||
      _maxPrice != null ||
      (_searchQuery != null && _searchQuery!.isNotEmpty);

  @override
  void initState() {
    _cartQuantities = widget.cartQuantities ?? {};
    super.initState();
    _loadInitialDataAndCart();
    _scrollController.addListener(_scrollListener);
    _searchFocusNode = FocusNode();
    // Слушаем глобальную корзину: если количества изменили на другом экране
    // (например, в /cart), синхронизируем карточки каталога.
    cartNotifier.addListener(_onGlobalCartChanged);
  }

  @override
  void dispose() {
    cartNotifier.removeListener(_onGlobalCartChanged);
    _scrollController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onGlobalCartChanged() {
    if (!mounted) return;
    // Защита от лишних ребилдов при собственной записи (данные уже совпадают).
    if (mapEquals(_cartQuantities, cartNotifier.value)) return;
    setState(() {
      _cartQuantities = Map<String, num>.from(cartNotifier.value);
    });
  }

  // Загружаем одновременно товары, категории и текущую корзину с сервера Django
  Future<void> _loadInitialDataAndCart() async {
    setState(() {
      _isFirstLoad = true;
      _currentPage = 1;
      _hasNextPage = true;
      _products.clear();
    });

    try {
      // Параллельно запрашиваем категории и состояние корзины
      final categoriesFuture = _api.getCategories();
      final cartFuture = _api.getCartQuantities();
      final productsFuture = _api.getProducts(
        categoryId: _selectedCategoryId,
        page: _currentPage,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
        query: _searchQuery,
      );

      final results = await Future.wait([
        categoriesFuture,
        cartFuture,
        productsFuture,
      ]);

      _categories = results[0] as List<ProductCategory>;
      _cartQuantities.addAll(results[1] as Map<String, num>);
      // Публикуем актуальную корзину с сервера в глобальный источник (бейдж/др. экраны).
      cartNotifier.value = Map<String, num>.from(_cartQuantities);

      final paginatedData = results[2] as PaginatedProducts?;
      if (paginatedData != null) {
        _products = paginatedData.results;
        _hasNextPage = paginatedData.nextUrl != null;
      }
    } catch (e) {
      print('Ошибка инициализации каталога: $e');
    }

    setState(() => _isFirstLoad = false);
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasNextPage) {
        _loadNextPage();
      }
    }
  }

  Future<void> _loadNextPage() async {
    setState(() => _isLoadingMore = true);

    int nextPage = _currentPage + 1;
    final paginatedData = await _api.getProducts(
      categoryId: _selectedCategoryId,
      page: nextPage,
      minPrice: _minPrice,
      maxPrice: _maxPrice,
      query: _searchQuery,
    );

    setState(() {
      if (paginatedData != null) {
        _currentPage = nextPage;
        _products.addAll(paginatedData.results);
        _hasNextPage = paginatedData.nextUrl != null;
      }
      _isLoadingMore = false;
    });
  }

  // Логика отслеживания ввода текста (Debounce)
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 800), () {
      setState(() {
        _searchQuery = query.trim().isEmpty ? null : query.trim();
      });
      _applyNewFilters();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    });
  }

  // Обновление количества товара с отправкой запросов на бэкенд
  Future<void> _updateCartQuantity(Product product, num newQuantity) async {
    if (newQuantity < 0) return;

    if (newQuantity == 0) {
      final success = await _api.updateCartItem(product.id, 0);
      if (success) {
        setState(() => _cartQuantities.remove(product.id));
        setCartQuantityLocal(product.id, 0);
      }
    } else {
      // if (newQuantity > product.stock) {
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     SnackBar(
      //       content: Text(
      //         'Доступно только ${product.stock.toStringAsFixed(0)} шт.',
      //       ),
      //     ),
      //   );
      //   return;
      // }

      final success = await _api.updateCartItem(product.id, newQuantity);
      if (success) {
        setState(() => _cartQuantities[product.id] = newQuantity);
        setCartQuantityLocal(product.id, newQuantity);
      }
    }
  }

  Future<void> _applyNewFilters() async {
    setState(() {
      _isFirstLoad = true;
      _currentPage = 1;
      _hasNextPage = true;
      _products.clear();
    });

    final paginatedData = await _api.getProducts(
      categoryId: _selectedCategoryId,
      page: _currentPage,
      minPrice: _minPrice,
      maxPrice: _maxPrice,
      query: _searchQuery,
    );

    setState(() {
      if (paginatedData != null) {
        _products = paginatedData.results;
        _hasNextPage = paginatedData.nextUrl != null;
      }
      _isFirstLoad = false;
    });
  }

  void _showFilterSheet() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => FilterSheet(
        categories: _categories,
        initialCategoryId: _selectedCategoryId,
        initialMinPrice: _minPrice,
        initialMaxPrice: _maxPrice,
      ),
    );

    if (result != null) {
      setState(() {
        _selectedCategoryId = result['category'];
        _minPrice = result['minPrice'];
        _maxPrice = result['maxPrice'];
      });
      _applyNewFilters();
    }
  }

  Widget _buildSearchAndFilterBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;

        final search = SizedBox(
          height: 46,
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {});
              _onSearchChanged(value);
            },
            focusNode: _searchFocusNode,
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
            decoration: InputDecoration(
              hintText: 'Поиск товара, кода, артикула...',
              hintStyle: const TextStyle(
                fontSize: 13,
                color: Color(0xFF94A3B8),
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Color(0xFF94A3B8),
                size: 20,
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(
                        Icons.cancel_rounded,
                        color: Color(0xFF94A3B8),
                        size: 18,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = null);
                        _applyNewFilters();
                      },
                    ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Theme.of(context).primaryColor),
              ),
            ),
          ),
        );

        final filterButton = SizedBox(
          height: 46,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: hasActiveFilters
                  ? Theme.of(context).primaryColor
                  : const Color(0xFF334155),
              side: BorderSide(
                color: hasActiveFilters
                    ? Theme.of(context).primaryColor
                    : const Color(0xFFE2E8F0),
              ),
              padding: EdgeInsets.symmetric(horizontal: isNarrow ? 13 : 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _showFilterSheet,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tune_rounded, size: 20),
                if (!isNarrow) ...[
                  const SizedBox(width: 8),
                  Text(hasActiveFilters ? 'Фильтры активны' : 'Фильтры'),
                ],
              ],
            ),
          ),
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 10),
              filterButton,
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip({
    required String label,
    required VoidCallback onDeleted,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InputChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        deleteIcon: const Icon(Icons.close, size: 14),
        onDeleted: onDeleted,
        backgroundColor: const Color(0xFFF1F5F9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: !(widget.embedded)
          ? AppBar(
              title: const Text('Каталог товаров'),
              backgroundColor: Colors.transparent,
              scrolledUnderElevation: 0,
              actions: [
                IconButton(
                  icon: Badge(
                    label: Text('${_cartQuantities.length}'),
                    isLabelVisible: _cartQuantities.isNotEmpty,
                    backgroundColor: const Color(0xFF2563EB),
                    child: const Icon(
                      Icons.shopping_cart,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  onPressed: () => context.push('/cart'),
                ),
                const SizedBox(width: 8),
              ],
            )
          : null,
      body: _isFirstLoad
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSearchAndFilterBar(),
                  if (hasActiveFilters)
                    SizedBox(
                      height: 42,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        children: [
                          if (_searchQuery != null && _searchQuery!.isNotEmpty)
                            _buildFilterChip(
                              label: 'Поиск: "$_searchQuery"',
                              onDeleted: () {
                                _searchController.clear();
                                setState(() => _searchQuery = null);
                                _applyNewFilters();
                              },
                            ),
                          if (_selectedCategoryId != null &&
                              _categories.isNotEmpty)
                            _buildFilterChip(
                              label: _categories
                                  .firstWhere(
                                    (c) => c.id == _selectedCategoryId,
                                    orElse: () =>
                                        ProductCategory(id: '', name: ''),
                                  )
                                  .name,
                              onDeleted: () {
                                setState(() => _selectedCategoryId = null);
                                _applyNewFilters();
                              },
                            ),
                          if (_minPrice != null || _maxPrice != null)
                            _buildFilterChip(
                              label:
                                  'Цена: ${_minPrice?.toStringAsFixed(0) ?? '0'} – ${_maxPrice?.toStringAsFixed(0) ?? '...'}',
                              onDeleted: () {
                                setState(() {
                                  _minPrice = null;
                                  _maxPrice = null;
                                });
                                _applyNewFilters();
                              },
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: _buildProductGrid(),
                    ),
                  ),
                  if (_isLoadingMore)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildProductGrid() {
    if (_products.isEmpty) {
      return const Center(child: Text('Товары не найдены'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        const minCardWidth = 330.0;

        int columns =
            ((constraints.maxWidth + spacing) / (minCardWidth + spacing))
                .floor();
        columns = columns.clamp(1, 4);

        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final compactCard = cardWidth < 380;
        final cardHeight = compactCard ? 174.0 : 184.0;

        return GridView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _products.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: cardHeight,
          ),
          itemBuilder: (context, index) {
            final product = _products[index];
            final quantity = _cartQuantities[product.id] ?? 0;

            return _ProductCard(
              product: product,
              quantity: quantity,
              compact: compactCard,
              onQuantityChanged: (value) => _updateCartQuantity(product, value),
            );
          },
        );
      },
    );
  }
}

class _ProductCard extends StatefulWidget {
  final Product product;
  final num quantity;
  final bool compact;
  final ValueChanged<num> onQuantityChanged;

  const _ProductCard({
    required this.product,
    required this.quantity,
    required this.compact,
    required this.onQuantityChanged,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  late final TextEditingController _quantityController;
  late final FocusNode _quantityFocusNode;

  bool _isEditingQuantity = false;

  @override
  void initState() {
    super.initState();

    _quantityController = TextEditingController(
      text: _formatQuantity(widget.quantity),
    );

    _quantityFocusNode = FocusNode();
    _quantityFocusNode.addListener(_handleQuantityFocus);
  }

  @override
  void didUpdateWidget(covariant _ProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_quantityFocusNode.hasFocus && oldWidget.quantity != widget.quantity) {
      _quantityController.text = _formatQuantity(widget.quantity);
    }
  }

  @override
  void dispose() {
    _quantityFocusNode.removeListener(_handleQuantityFocus);
    _quantityFocusNode.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _handleQuantityFocus() {
    if (!_quantityFocusNode.hasFocus && _isEditingQuantity) {
      _submitQuantity();
    }

    if (mounted) {
      setState(() {
        _isEditingQuantity = _quantityFocusNode.hasFocus;
      });
    }
  }

  void _startQuantityEditing() {
    setState(() => _isEditingQuantity = true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _quantityFocusNode.requestFocus();
      _quantityController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _quantityController.text.length,
      );
    });
  }

  void _submitQuantity() {
    final normalized = _quantityController.text.trim().replaceAll(',', '.');

    final parsed = num.tryParse(normalized);

    if (parsed == null || parsed < 0) {
      _quantityController.text = _formatQuantity(widget.quantity);
      return;
    }

    final num value;

    if (parsed is double && parsed == parsed.roundToDouble()) {
      value = parsed.toInt();
    } else {
      value = parsed;
    }

    _quantityController.text = _formatQuantity(value);
    widget.onQuantityChanged(value);
  }

  String _formatQuantity(num value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final quantity = widget.quantity;
    final imageWidth = widget.compact ? 108.0 : 124.0;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: imageWidth,
            height: double.infinity,
            child: ColoredBox(
              color: const Color(0xFFF8FAFC),
              child: Image.network(
                product.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return const Center(
                    child: Icon(
                      Icons.image_not_supported_rounded,
                      color: Colors.grey,
                    ),
                  );
                },
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    product.categoryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Остаток: ${product.stock.toStringAsFixed(0)} '
                    '${product.unit}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  if (product.articul.isNotEmpty)
                    Text(
                      'Арт.: ${product.articul}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    formatPrice(product.price),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 36,
                    child: quantity == 0
                        ? ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () {
                              widget.onQuantityChanged(1);
                            },
                            child: const Text(
                              'В корзину',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                              border: _isEditingQuantity
                                  ? Border.all(
                                      color: const Color(0xFF2563EB),
                                      width: 1.2,
                                    )
                                  : null,
                            ),
                            child: Row(
                              children: [
                                _CounterButton(
                                  icon: Icons.remove,
                                  onPressed: () {
                                    widget.onQuantityChanged(quantity - 1);
                                  },
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _startQuantityEditing,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 3,
                                      ),
                                      child: _isEditingQuantity
                                          ? TextField(
                                              controller: _quantityController,
                                              focusNode: _quantityFocusNode,
                                              autofocus: true,
                                              textAlign: TextAlign.center,
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              inputFormatters: [
                                                FilteringTextInputFormatter.allow(
                                                  RegExp(r'[0-9.,]'),
                                                ),
                                              ],
                                              textInputAction:
                                                  TextInputAction.done,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF0F172A),
                                              ),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                border: InputBorder.none,
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                              onSubmitted: (_) {
                                                _submitQuantity();
                                                _quantityFocusNode.unfocus();
                                              },
                                            )
                                          : Text(
                                              '${_formatQuantity(quantity)} '
                                              '${product.unit}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                                _CounterButton(
                                  icon: Icons.add,
                                  onPressed: () {
                                    widget.onQuantityChanged(quantity + 1);
                                  },
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _CounterButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 34,
      child: IconButton(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: 17, color: const Color(0xFF334155)),
      ),
    );
  }
}
