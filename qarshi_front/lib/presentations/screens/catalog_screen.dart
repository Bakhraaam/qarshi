// import 'dart:async';

// import 'package:flutter/material.dart';
// import 'package:flutter_screenutil/flutter_screenutil.dart';
// import 'package:go_router/go_router.dart';
// import 'package:intl/intl.dart';
// import 'package:qarshi/core/data/api/api_django.dart';
// import 'package:qarshi/core/data/models.dart';
// import 'package:qarshi/core/utils/formatters.dart';
// import 'package:qarshi/core/utils/responsive.dart';
// import 'package:qarshi/presentations/widgets/filter_sheet.dart';

// class CatalogScreen extends StatefulWidget {
//   const CatalogScreen({super.key});

//   @override
//   State<CatalogScreen> createState() => _CatalogScreenState();
// }

// class _CatalogScreenState extends State<CatalogScreen> {
//   final DjangoApi _api = DjangoApi();
//   final ScrollController _scrollController = ScrollController();

//   List<ProductCategory> _categories = [];
//   List<Product> _products = [];
//   final Map<String, num> _cartQuantities =
//       {}; // Перенесено наверх для правильной видимости

//   String? _selectedCategoryId;
//   bool _isFirstLoad = true;
//   bool _isLoadingMore = false;
//   int _currentPage = 1;
//   bool _hasNextPage = true;
//   double? _minPrice;
//   double? _maxPrice;
//   String? _searchQuery; // Переменная для хранения текста поиска
//   Timer? _debounce; // Таймер для предотвращения частых запросов при вводе
//   final TextEditingController _searchController =
//       TextEditingController(); // Контроллер для поля поиска
//   late final FocusNode _searchFocusNode;
//   // Динамический геттер для отслеживания активности фильтров
//   bool get hasActiveFilters =>
//       _selectedCategoryId != null ||
//       _minPrice != null ||
//       _maxPrice != null ||
//       (_searchQuery != null && _searchQuery!.isNotEmpty);

//   @override
//   void initState() {
//     super.initState();
//     _loadInitialDataAndCart();
//     _scrollController.addListener(_scrollListener);
//     _searchFocusNode = FocusNode();
//   }

//   @override
//   void dispose() {
//     _scrollController.dispose();
//     _searchController.dispose();
//     _debounce?.cancel();
//     _searchFocusNode.dispose();
//     super.dispose();
//   }

//   // Загружаем одновременно товары, категории и текущую корзину с сервера Django
//   Future<void> _loadInitialDataAndCart() async {
//     setState(() {
//       _isFirstLoad = true;
//       _currentPage = 1;
//       _hasNextPage = true;
//       _products.clear();
//     });

//     try {
//       // Параллельно запрашиваем категории и состояние корзины
//       final categoriesFuture = _api.getCategories();
//       final cartFuture = _api.getCartQuantities();
//       final productsFuture = _api.getProducts(
//         categoryId: _selectedCategoryId,
//         page: _currentPage,
//         minPrice: _minPrice,
//         maxPrice: _maxPrice,
//         query: _searchQuery,
//       );

//       final results = await Future.wait([
//         categoriesFuture,
//         cartFuture,
//         productsFuture,
//       ]);

//       _categories = results[0] as List<ProductCategory>;
//       _cartQuantities.addAll(results[1] as Map<String, num>);

//       final paginatedData = results[2] as PaginatedProducts?;
//       if (paginatedData != null) {
//         _products = paginatedData.results;
//         _hasNextPage = paginatedData.nextUrl != null;
//       }
//     } catch (e) {
//       print('Ошибка инициализации каталога: $e');
//     }

//     setState(() => _isFirstLoad = false);
//   }

//   void _scrollListener() {
//     if (_scrollController.position.pixels >=
//         _scrollController.position.maxScrollExtent - 200) {
//       if (!_isLoadingMore && _hasNextPage) {
//         _loadNextPage();
//       }
//     }
//   }

//   Future<void> _loadNextPage() async {
//     setState(() => _isLoadingMore = true);

//     int nextPage = _currentPage + 1;
//     final paginatedData = await _api.getProducts(
//       categoryId: _selectedCategoryId,
//       page: nextPage,
//       minPrice: _minPrice,
//       maxPrice: _maxPrice,
//       query: _searchQuery,
//     );

//     setState(() {
//       if (paginatedData != null) {
//         _currentPage = nextPage;
//         _products.addAll(paginatedData.results);
//         _hasNextPage = paginatedData.nextUrl != null;
//       }
//       _isLoadingMore = false;
//     });
//   }

//   // Логика отслеживания ввода текста (Debounce)
//   void _onSearchChanged(String query) {
//     if (_debounce?.isActive ?? false) _debounce!.cancel();

//     _debounce = Timer(const Duration(milliseconds: 800), () {
//       setState(() {
//         _searchQuery = query.trim().isEmpty ? null : query.trim();
//       });
//       _applyNewFilters();

//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         if (mounted) {
//           _searchFocusNode.requestFocus();
//         }
//       });
//     });
//   }

//   // Обновление количества товара с отправкой запросов на бэкенд
//   Future<void> _updateCartQuantity(Product product, num newQuantity) async {
//     if (newQuantity < 0) return;

//     if (newQuantity == 0) {
//       final success = await _api.updateCartItem(product.id, 0);
//       if (success) {
//         setState(() => _cartQuantities.remove(product.id));
//       }
//     } else {
//       // if (newQuantity > product.stock) {
//       //   ScaffoldMessenger.of(context).showSnackBar(
//       //     SnackBar(
//       //       content: Text(
//       //         'Доступно только ${product.stock.toStringAsFixed(0)} шт.',
//       //       ),
//       //     ),
//       //   );
//       //   return;
//       // }

//       final success = await _api.updateCartItem(product.id, newQuantity);
//       if (success) {
//         setState(() => _cartQuantities[product.id] = newQuantity);
//       }
//     }
//   }

//   Future<void> _applyNewFilters() async {
//     setState(() {
//       _isFirstLoad = true;
//       _currentPage = 1;
//       _hasNextPage = true;
//       _products.clear();
//     });

//     final paginatedData = await _api.getProducts(
//       categoryId: _selectedCategoryId,
//       page: _currentPage,
//       minPrice: _minPrice,
//       maxPrice: _maxPrice,
//       query: _searchQuery,
//     );

//     setState(() {
//       if (paginatedData != null) {
//         _products = paginatedData.results;
//         _hasNextPage = paginatedData.nextUrl != null;
//       }
//       _isFirstLoad = false;
//     });
//   }

//   void _showFilterSheet() async {
//     final result = await showModalBottomSheet<Map<String, dynamic>>(
//       context: context,
//       isScrollControlled: true,
//       shape: const RoundedRectangleBorder(
//         borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
//       ),
//       builder: (context) => FilterSheet(
//         categories: _categories,
//         initialCategoryId: _selectedCategoryId,
//         initialMinPrice: _minPrice,
//         initialMaxPrice: _maxPrice,
//       ),
//     );

//     if (result != null) {
//       setState(() {
//         _selectedCategoryId = result['category'];
//         _minPrice = result['minPrice'];
//         _maxPrice = result['maxPrice'];
//       });
//       _applyNewFilters();
//     }
//   }

//   Widget _buildSearchAndFilterBar() {
//     final double barHeight = 46.h;
//     return Padding(
//       padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
//       child: Row(
//         children: [
//           // Поле текстового поиска
//           Expanded(
//             child: Container(
//               decoration: BoxDecoration(
//                 color: Colors.white,
//                 borderRadius: BorderRadius.circular(10),
//                 border: Border.all(color: const Color(0xFFE2E8F0)),
//               ),
//               child: TextField(
//                 controller: _searchController,
//                 onChanged: _onSearchChanged,
//                 focusNode: _searchFocusNode,
//                 // ПРИНУДИТЕЛЬНОЕ ЦЕНТРИРОВАНИЕ ТЕКСТА ПО ВЕРТИКАЛИ:
//                 textAlignVertical: TextAlignVertical.center,
//                 style: TextStyle(
//                   fontSize: 14.sp,
//                   color: const Color(0xFF0F172A),
//                 ),
//                 decoration: InputDecoration(
//                   hintText: 'Поиск товара, кода, артикула...',
//                   hintStyle: TextStyle(
//                     fontSize: 13.sp,
//                     color: const Color(0xFF94A3B8),
//                   ),
//                   // Ограничиваем высоту полей внутри самого инпута
//                   constraints: BoxConstraints(
//                     maxHeight: barHeight,
//                     minHeight: barHeight,
//                   ),
//                   prefixIcon: const Icon(
//                     Icons.search_rounded,
//                     color: Color(0xFF94A3B8),
//                     size: 20,
//                   ),
//                   suffixIcon: _searchController.text.isNotEmpty
//                       ? IconButton(
//                           padding: EdgeInsets.zero,
//                           icon: const Icon(
//                             Icons.cancel_rounded,
//                             color: Color(0xFF94A3B8),
//                             size: 18,
//                           ),
//                           onPressed: () {
//                             _searchController.clear();
//                             setState(() => _searchQuery = null);
//                             _applyNewFilters();
//                           },
//                         )
//                       : null,
//                   border: InputBorder.none,
//                   // Настраиваем симметричные отступы, чтобы текст не прижимался к краям
//                   contentPadding: EdgeInsets.symmetric(horizontal: 12.w),
//                 ),
//               ),
//             ),
//           ),
//           SizedBox(width: 10.w),
//           SizedBox(
//             height: barHeight,
//             child: OutlinedButton.icon(
//               style: OutlinedButton.styleFrom(
//                 foregroundColor: hasActiveFilters
//                     ? Theme.of(context).primaryColor
//                     : Colors.black87,
//                 side: BorderSide(
//                   color: hasActiveFilters
//                       ? Theme.of(context).primaryColor
//                       : Colors.grey[300]!,
//                 ),
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(10),
//                 ),
//               ),
//               onPressed: _showFilterSheet,
//               icon: Icon(Icons.tune_rounded, size: 20.w),
//               label: Text(hasActiveFilters ? 'Фильтры (Активны)' : 'Фильтры'),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildFilterChip({
//     required String label,
//     required VoidCallback onDeleted,
//   }) {
//     return Padding(
//       padding: EdgeInsets.only(right: 6.w),
//       child: InputChip(
//         label: Text(label, style: TextStyle(fontSize: 12.sp)),
//         deleteIcon: Icon(Icons.close, size: 14.w),
//         onDeleted: onDeleted,
//         backgroundColor: Colors.grey[100],
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF8FAFC),
//       appBar: AppBar(
//         title: const Text('Каталог товаров'),
//         backgroundColor: Colors.transparent,
//         scrolledUnderElevation: 0,
//         actions: [
//           // Кнопка перехода в корзину с красивым Badge-индикатором
//           IconButton(
//             icon: Badge(
//               label: Text('${_cartQuantities.length}'),
//               isLabelVisible: _cartQuantities.isNotEmpty,
//               backgroundColor: const Color(0xFF2563EB),
//               child: const Icon(Icons.shopping_cart, color: Color(0xFF0F172A)),
//             ),
//             onPressed: () => context.push('/cart'),
//           ),
//           SizedBox(width: 12.w),
//         ],
//       ),
//       body: _isFirstLoad
//           ? const Center(child: CircularProgressIndicator())
//           : Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 // Панель фильтров выведена в тело над контентом
//                 _buildSearchAndFilterBar(),

//                 // Активные теги выбранных фильтров
//                 if (hasActiveFilters)
//                   Padding(
//                     padding: EdgeInsets.symmetric(
//                       horizontal: 16.w,
//                       vertical: 4.h,
//                     ),
//                     child: SizedBox(
//                       height: 35.h,
//                       child: ListView(
//                         scrollDirection: Axis.horizontal,
//                         children: [
//                           if (_searchQuery != null && _searchQuery!.isNotEmpty)
//                             _buildFilterChip(
//                               label: 'Поиск: "$_searchQuery"',
//                               onDeleted: () {
//                                 _searchController.clear();
//                                 setState(() => _searchQuery = null);
//                                 _applyNewFilters();
//                               },
//                             ),
//                           if (_selectedCategoryId != null &&
//                               _categories.isNotEmpty)
//                             _buildFilterChip(
//                               label: _categories
//                                   .firstWhere(
//                                     (c) => c.id == _selectedCategoryId,
//                                     orElse: () =>
//                                         ProductCategory(id: '', name: ''),
//                                   )
//                                   .name,
//                               onDeleted: () {
//                                 setState(() => _selectedCategoryId = null);
//                                 _applyNewFilters();
//                               },
//                             ),
//                           if (_minPrice != null || _maxPrice != null)
//                             _buildFilterChip(
//                               label:
//                                   'Цена: ${_minPrice?.toStringAsFixed(0) ?? '0'} - ${_maxPrice?.toStringAsFixed(0) ?? '...'}',
//                               onDeleted: () {
//                                 setState(() {
//                                   _minPrice = null;
//                                   _maxPrice = null;
//                                 });
//                                 _applyNewFilters();
//                               },
//                             ),
//                         ],
//                       ),
//                     ),
//                   ),

//                 // Сетка скролла товаров
//                 Expanded(
//                   child: Padding(
//                     padding: EdgeInsets.symmetric(horizontal: 16.w),
//                     child: Column(
//                       children: [
//                         Expanded(
//                           child: Responsive(
//                             // Передаем РЕАЛЬНОЕ желаемое количество колонок на экране
//                             mobile: _buildProductGrid(gridCols: 1),
//                             tablet: _buildProductGrid(gridCols: 2),
//                             desktop: _buildProductGrid(gridCols: 3),
//                           ),
//                         ),
//                         if (_isLoadingMore)
//                           Padding(
//                             padding: EdgeInsets.symmetric(vertical: 16.h),
//                             child: const Center(
//                               child: CircularProgressIndicator(),
//                             ),
//                           ),
//                       ],
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//     );
//   }

//   Widget _buildProductGrid({required int gridCols}) {
//     if (_products.isEmpty) {
//       return const Center(child: Text('Товары не найдены'));
//     }

//     // Настраиваем пропорции (ширина / высота) в зависимости от кол-ва колонок
//     // Подберите эти цифры экспериментально, если дизайн поплывет
//     double aspectRatio;
//     if (gridCols == 1) {
//       aspectRatio =
//           2.4; // На мобилке (1 колонка) карточка вытянутая, высота примерно в 2.4 раза меньше ширины
//     } else if (gridCols == 2) {
//       aspectRatio = 1.6; // На планшете (2 колонки) карточка повыше
//     } else {
//       aspectRatio =
//           1.4; // На десктопе (3 колонки) карточки еще более "квадратные" по пропорциям
//     }

//     return GridView.builder(
//       controller: _scrollController,
//       physics: const AlwaysScrollableScrollPhysics(),
//       itemCount: _products.length,
//       gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
//         crossAxisCount: gridCols, // Используем напрямую!
//         crossAxisSpacing: 12.w,
//         mainAxisSpacing: 12.h,
//         childAspectRatio: aspectRatio,
//       ),
//       itemBuilder: (context, index) {
//         final product = _products[index];
//         final num quantity = _cartQuantities[product.id] ?? 0;

//         return Card(
//           elevation: 0,
//           color: Colors.white,
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(12),
//             side: const BorderSide(color: Color(0xFFE2E8F0)),
//           ),
//           clipBehavior: Clip.antiAlias,
//           child: Row(
//             children: [
//               // Картинка товара
//               Container(
//                 width: gridCols == 1
//                     ? 110.w
//                     : 130.w, // Адаптивная ширина картинки
//                 height: double.infinity,
//                 color: const Color(0xFFF8FAFC),
//                 child: Image.network(
//                   product.imageUrl,
//                   fit: BoxFit.cover,
//                   errorBuilder: (context, error, stackTrace) {
//                     return const Icon(
//                       Icons.image_not_supported_rounded,
//                       color: Colors.grey,
//                     );
//                   },
//                 ),
//               ),

//               // Блок описания и кнопок
//               Expanded(
//                 child: Padding(
//                   padding: EdgeInsets.all(10.w),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     mainAxisAlignment: MainAxisAlignment
//                         .spaceBetween, // Четко фиксирует верх и низ карточки
//                     children: [
//                       // Верхняя часть (Тексты)
//                       Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           Text(
//                             product.name,
//                             maxLines: 2,
//                             overflow: TextOverflow.ellipsis,
//                             style: TextStyle(
//                               fontSize: 13.sp,
//                               fontWeight: FontWeight.bold,
//                               color: const Color(0xFF0F172A),
//                               height: 1.2,
//                             ),
//                           ),
//                           const SizedBox(height: 2),
//                           Text(
//                             '${product.categoryName}',
//                             maxLines: 1,
//                             overflow: TextOverflow.ellipsis,
//                             style: TextStyle(
//                               fontSize: 11.sp,
//                               color: const Color(0xFF64748B),
//                             ),
//                           ),
//                           SizedBox(height: 4.h),
//                           Wrap(
//                             spacing: 6.w,
//                             runSpacing: 2.h,
//                             children: [
//                               Text(
//                                 'Ост: ${product.stock.toStringAsFixed(0)} ${product.unit}',
//                                 style: TextStyle(
//                                   fontSize: 10.sp,
//                                   color: const Color(0xFF64748B),
//                                 ),
//                               ),
//                               if (product.articul.isNotEmpty)
//                                 Text(
//                                   'Арт: ${product.articul}',
//                                   maxLines: 1,
//                                   overflow: TextOverflow.ellipsis,
//                                   style: TextStyle(
//                                     fontSize: 10.sp,
//                                     color: const Color(0xFF64748B),
//                                   ),
//                                 ),
//                             ],
//                           ),
//                         ],
//                       ),

//                       // Нижня часть (Цена и Кнопка)
//                       Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           Text(
//                             formatPrice(product.price),
//                             style: TextStyle(
//                               fontSize: 13.sp,
//                               color: const Color(0xFF0F172A),
//                               fontWeight: FontWeight.bold,
//                             ),
//                           ),
//                           const SizedBox(height: 4),
//                           AnimatedSwitcher(
//                             duration: const Duration(milliseconds: 150),
//                             child: quantity == 0
//                                 ? SizedBox(
//                                     key: const ValueKey('add_btn'),
//                                     width: double.infinity,
//                                     height: 32.h,
//                                     child: ElevatedButton(
//                                       style: ElevatedButton.styleFrom(
//                                         backgroundColor: const Color(
//                                           0xFF2563EB,
//                                         ),
//                                         foregroundColor: Colors.white,
//                                         elevation: 0,
//                                         padding: EdgeInsets.zero,
//                                         shape: RoundedRectangleBorder(
//                                           borderRadius: BorderRadius.circular(
//                                             8,
//                                           ),
//                                         ),
//                                       ),
//                                       onPressed: () =>
//                                           _updateCartQuantity(product, 1),
//                                       child: Text(
//                                         'В корзину',
//                                         style: TextStyle(
//                                           fontSize: 11.sp,
//                                           fontWeight: FontWeight.bold,
//                                         ),
//                                       ),
//                                     ),
//                                   )
//                                 : Container(
//                                     key: const ValueKey('counter_btn'),
//                                     height: 32.h,
//                                     decoration: BoxDecoration(
//                                       color: const Color(0xFFF1F5F9),
//                                       borderRadius: BorderRadius.circular(8),
//                                     ),
//                                     child: Row(
//                                       mainAxisAlignment:
//                                           MainAxisAlignment.spaceBetween,
//                                       children: [
//                                         IconButton(
//                                           padding: EdgeInsets.zero,
//                                           constraints: const BoxConstraints(),
//                                           icon: const Icon(
//                                             Icons.remove,
//                                             size: 16,
//                                             color: Color(0xFF334155),
//                                           ),
//                                           onPressed: () => _updateCartQuantity(
//                                             product,
//                                             quantity - 1,
//                                           ),
//                                         ),
//                                         Text(
//                                           '$quantity ${product.unit}',
//                                           style: TextStyle(
//                                             fontSize: 12.sp,
//                                             fontWeight: FontWeight.bold,
//                                             color: const Color(0xFF0F172A),
//                                           ),
//                                         ),
//                                         IconButton(
//                                           padding: EdgeInsets.zero,
//                                           constraints: const BoxConstraints(),
//                                           icon: const Icon(
//                                             Icons.add,
//                                             size: 16,
//                                             color: Color(0xFF334155),
//                                           ),
//                                           onPressed: () => _updateCartQuantity(
//                                             product,
//                                             quantity + 1,
//                                           ),
//                                         ),
//                                       ],
//                                     ),
//                                   ),
//                           ),
//                         ],
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }
// }
