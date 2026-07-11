// import 'dart:js_interop_unsafe';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_screenutil/flutter_screenutil.dart';
// import 'package:go_router/go_router.dart';
// import 'package:qarshi/core/data/api/api_django.dart';
// import 'package:qarshi/core/data/constants.dart';
// import 'package:qarshi/core/data/models.dart';
// import 'package:qarshi/core/utils/formatters.dart';
// import 'package:qarshi/core/utils/responsive.dart';
// import 'dart:js_interop' as js;

// import 'package:qarshi/presentations/screens/catalog_screen.dart';
// import 'package:qarshi/presentations/screens/catalog_screen_responsive.dart';

// // Предполагаем, что CatalogScreen импортируется отсюда:
// // import 'package:qarshi/features/catalog/catalog_screen.dart';

// @js.JS('window')
// external js.JSObject get _window;

// extension WindowExtension on js.JSObject {
//   @js.JS('open')
//   external js.JSObject? open(js.JSString url, js.JSString target);
// }

// class HomeScreen extends StatefulWidget {
//   const HomeScreen({super.key});

//   @override
//   State<HomeScreen> createState() => _HomeScreenState();
// }

// class _HomeScreenState extends State<HomeScreen> {
//   final DjangoApi _api = DjangoApi();
//   double _cartTotalSum = 0.0;
//   bool _isLoading = true;

//   // Хранит индекс текущей активной вкладки для ПК версии
//   int _activeDesktopTab = 0;

//   @override
//   void initState() {
//     super.initState();
//     _loadCartSummary();
//   }

//   Future<void> _loadCartSummary() async {
//     if (!mounted) return;
//     setState(() => _isLoading = true);
//     try {
//       final List<CartItem> cartItems = await _api.getCart();
//       _cartTotalSum = cartItems.fold(
//         0,
//         (sum, item) => sum + (item.product.price * item.quantity),
//       );
//     } catch (e) {
//       debugPrint('Ошибка корзины на Главной: $e');
//       _cartTotalSum = 0.0;
//     }
//     setState(() => _isLoading = false);
//   }

//   void _handleSupportAction() {
//     final tgUsername = currentUser?.support.tgUsername;
//     final phone = currentUser?.support.phone;

//     if (tgUsername != null && tgUsername.trim().isNotEmpty) {
//       final cleanUsername = tgUsername.replaceAll('@', '').trim();
//       final String webUrl = 'https://t.me/$cleanUsername';
//       if (kIsWeb) {
//         _window.open(webUrl.toJS, '_blank'.toJS);
//       }
//     } else if (phone != null && phone.trim().isNotEmpty) {
//       final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
//       if (kIsWeb) {
//         _window.open('tel:$cleanPhone'.toJS, '_self'.toJS);
//       }
//     } else {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Контакты службы поддержки недоступны')),
//       );
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF8FAFC),
//       body: Responsive(
//         mobile: Stack(
//           children: [
//             _BuildMobileHome(
//               cartTotalSum: _cartTotalSum,
//               onSupportTap: _handleSupportAction,
//             ),
//             if (_cartTotalSum > 0)
//               Positioned(
//                 bottom: 16.h,
//                 left: 16.w,
//                 right: 16.w,
//                 child: _FloatingCartBar(totalSum: _cartTotalSum),
//               ),
//           ],
//         ),
//         desktop: _BuildDesktopHome(
//           cartTotalSum: _cartTotalSum,
//           activeTab: _activeDesktopTab,
//           onTabChanged: (index) {
//             if (index == 2) {
//               // Если нажали на "Помощь"
//               _handleSupportAction();
//             } else {
//               setState(() => _activeDesktopTab = index);
//             }
//           },
//         ),
//       ),
//     );
//   }
// }

// // ==========================================
// // 1. ДЕСТКОП ВЕРСИЯ (ИНТЕГРИРОВАННЫЙ DASHBOARD)
// // ==========================================
// class _BuildDesktopHome extends StatelessWidget {
//   final double cartTotalSum;
//   final int activeTab;
//   final ValueChanged<int> onTabChanged;

//   const _BuildDesktopHome({
//     required this.cartTotalSum,
//     required this.activeTab,
//     required this.onTabChanged,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       children: [
//         Expanded(
//           child: Column(
//             children: [
//               // Верхняя панель навигации (Заменяет громоздкие плитки)
//               Container(
//                 color: Colors.white,
//                 padding: const EdgeInsets.symmetric(
//                   horizontal: 32,
//                   vertical: 16,
//                 ),
//                 // border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
//                 child: Row(
//                   children: [
//                     _buildUserAvatar(isDesktop: true),
//                     const SizedBox(width: 16),
//                     Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         const Text(
//                           'Личный кабинет',
//                           style: TextStyle(color: Colors.grey, fontSize: 12),
//                         ),
//                         Text(
//                           currentUser?.getName() ?? '',
//                           style: const TextStyle(
//                             fontWeight: FontWeight.bold,
//                             fontSize: 16,
//                           ),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(width: 64),
//                     // Кнопки переключения разделов
//                     _DesktopTabButton(
//                       title: 'Каталог товаров',
//                       icon: Icons.grid_view_rounded,
//                       isActive: activeTab == 0,
//                       onTap: () => onTabChanged(0),
//                     ),
//                     _DesktopTabButton(
//                       title: 'Акт сверки 1С',
//                       icon: Icons.description_rounded,
//                       isActive: activeTab == 1,
//                       onTap: () => onTabChanged(1),
//                     ),
//                     _DesktopTabButton(
//                       title: 'Помощь',
//                       icon: Icons.support_agent_rounded,
//                       isActive: activeTab == 2,
//                       onTap: () => onTabChanged(2),
//                     ),
//                     const Spacer(),
//                     // Интегрированная мини-корзина справа в шапке на ПК
//                     if (cartTotalSum > 0)
//                       _DesktopMiniCart(totalSum: cartTotalSum),
//                   ],
//                 ),
//               ),

//               // Основной контент подстраивается под выбранный пункт
//               Expanded(
//                 child: IndexedStack(
//                   index: activeTab,
//                   children: [
//                     const CatalogScreen(),
//                     const Center(
//                       child: Text('Здесь рендерится: Экран актов / отчетности'),
//                     ),
//                     const SizedBox.shrink(), // Для вкладки "Помощь", которая вызывает триггер url
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }

// class _DesktopTabButton extends StatelessWidget {
//   final String title;
//   final IconData icon;
//   final bool isActive;
//   final VoidCallback onTap;

//   const _DesktopTabButton({
//     required this.title,
//     required this.icon,
//     required this.isActive,
//     required this.onTap,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.only(right: 8.0),
//       child: TextButton(
//         // Используем стандартный TextButton вместо старого класса
//         onPressed: onTap,
//         style: TextButton.styleFrom(
//           backgroundColor: isActive
//               ? const Color(0xFF1E3A8A)
//               : Colors.transparent,
//           foregroundColor: isActive ? Colors.white : const Color(0xFF64748B),
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(12),
//           ),
//           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
//         ),
//         child: Row(
//           children: [
//             Icon(icon, size: 18),
//             const SizedBox(width: 8),
//             Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _DesktopMiniCart extends StatelessWidget {
//   final double totalSum;
//   const _DesktopMiniCart({required this.totalSum});

//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       onTap: () => context.push('/cart'),
//       borderRadius: BorderRadius.circular(12),
//       child: Container(
//         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
//         decoration: BoxDecoration(
//           color: const Color(0xFF0F172A),
//           borderRadius: BorderRadius.circular(12),
//         ),
//         child: Row(
//           children: [
//             const Icon(
//               Icons.shopping_bag_rounded,
//               color: Colors.white,
//               size: 18,
//             ),
//             const SizedBox(width: 12),
//             Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 const Text(
//                   'Корзина',
//                   style: TextStyle(color: Colors.white60, fontSize: 10),
//                 ),
//                 Text(
//                   formatPrice(totalSum),
//                   style: const TextStyle(
//                     color: Colors.white,
//                     fontWeight: FontWeight.bold,
//                     fontSize: 13,
//                   ),
//                 ),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// // ==========================================
// // 2. МОБИЛЬНАЯ ВЕРСИЯ (ЧИСТЫЙ КОМПАКТНЫЙ ХАБ)
// // ==========================================
// class _BuildMobileHome extends StatelessWidget {
//   final double cartTotalSum;
//   final VoidCallback onSupportTap;

//   const _BuildMobileHome({
//     required this.cartTotalSum,
//     required this.onSupportTap,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF8FAFC),
//       appBar: AppBar(
//         backgroundColor: Colors.transparent,
//         scrolledUnderElevation: 0,
//         title: Row(
//           children: [
//             _buildUserAvatar(isDesktop: false),
//             SizedBox(width: 12.w),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     'Добро пожаловать,',
//                     style: TextStyle(color: Colors.grey[500], fontSize: 11.sp),
//                   ),
//                   Text(
//                     currentUser?.getName() ?? '',
//                     style: TextStyle(
//                       color: Colors.black87,
//                       fontSize: 16.sp,
//                       fontWeight: FontWeight.bold,
//                     ),
//                     maxLines: 1,
//                     overflow: TextOverflow.ellipsis,
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//       body: SafeArea(
//         child: SingleChildScrollView(
//           padding: EdgeInsets.only(
//             left: 16.w,
//             right: 16.w,
//             top: 12.h,
//             bottom: cartTotalSum > 0 ? 100.h : 20.h,
//           ),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 'Панель управления',
//                 style: TextStyle(
//                   fontSize: 18.sp,
//                   fontWeight: FontWeight.bold,
//                   color: const Color(0xFF0F172A),
//                 ),
//               ),
//               SizedBox(height: 16.h),
//               _MobileMenuGrid(onSupportTap: onSupportTap),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _MobileMenuGrid extends StatelessWidget {
//   final VoidCallback onSupportTap;
//   const _MobileMenuGrid({required this.onSupportTap});

//   @override
//   Widget build(BuildContext context) {
//     final List<Map<String, dynamic>> items = [
//       {
//         'title': 'Каталог товаров',
//         'icon': Icons.grid_view_rounded,
//         'desc': 'Покупка и остатки',
//         'route': '/catalog',
//       },
//       {
//         'title': 'Акт сверки 1С',
//         'icon': Icons.description_rounded,
//         'desc': 'Отчеты и док-ты',
//         'route': '/reports',
//       },
//       {
//         'title': 'Помощь',
//         'icon': Icons.support_agent_rounded,
//         'desc': 'Связаться с нами',
//         'route': null,
//       },
//     ];

//     return GridView.builder(
//       shrinkWrap: true,
//       physics: const NeverScrollableScrollPhysics(),
//       itemCount: items.length,
//       gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
//         crossAxisCount: 2,
//         crossAxisSpacing: 12.w,
//         mainAxisSpacing: 12.h,
//         childAspectRatio: 1.3,
//       ),
//       itemBuilder: (context, index) {
//         final item = items[index];
//         return InkWell(
//           onTap: () {
//             if (item['route'] != null) {
//               context.push(item['route']);
//             } else {
//               onSupportTap();
//             }
//           },
//           borderRadius: BorderRadius.circular(16),
//           child: Container(
//             padding: EdgeInsets.all(14.w),
//             decoration: BoxDecoration(
//               color: Colors.white,
//               borderRadius: BorderRadius.circular(16),
//               border: Border.all(color: const Color(0xFFE2E8F0)),
//             ),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 Icon(
//                   item['icon'] as IconData,
//                   color: const Color(0xFF1E3A8A),
//                   size: 24.w,
//                 ),
//                 const Spacer(),
//                 Text(
//                   item['title'] as String,
//                   style: TextStyle(
//                     fontSize: 13.sp,
//                     fontWeight: FontWeight.bold,
//                     color: const Color(0xFF0F172A),
//                   ),
//                 ),
//                 SizedBox(height: 2.h),
//                 Text(
//                   item['desc'] as String,
//                   style: TextStyle(
//                     fontSize: 10.sp,
//                     color: const Color(0xFF64748B),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         );
//       },
//     );
//   }
// }

// // ==========================================
// // ВСПОМОГАТЕЛЬНЫЕ КОМПОНЕНТЫ И ХЕЛПЕРЫ
// // ==========================================
// Widget _buildUserAvatar({required bool isDesktop}) {
//   final photoUrl = currentUser?.telegramAccount?.photoUrl;
//   final double size = isDesktop ? 40 : 48;

//   if (photoUrl != null && photoUrl.trim().isNotEmpty) {
//     return ClipOval(
//       child: SizedBox(
//         width: size,
//         height: size,
//         child: Image.network(
//           photoUrl,
//           fit: BoxFit.cover,
//           errorBuilder: (context, error, stackTrace) =>
//               _buildLetterFallback(size),
//         ),
//       ),
//     );
//   }
//   return _buildLetterFallback(size);
// }

// Widget _buildLetterFallback(double size) {
//   final userName = currentUser?.getName() ?? 'U';
//   final firstLetter = userName.isNotEmpty ? userName[0].toUpperCase() : 'U';

//   return CircleAvatar(
//     radius: size / 2,
//     backgroundColor: const Color(0xFFE2E8F0),
//     child: Text(
//       firstLetter,
//       style: TextStyle(
//         color: const Color(0xFF64748B),
//         fontSize: size * 0.4,
//         fontWeight: FontWeight.bold,
//       ),
//     ),
//   );
// }

// class _FloatingCartBar extends StatelessWidget {
//   final double totalSum;
//   const _FloatingCartBar({required this.totalSum});

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
//       decoration: BoxDecoration(
//         color: const Color(0xFF0F172A),
//         borderRadius: BorderRadius.circular(16),
//       ),
//       child: Row(
//         children: [
//           Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 20.w),
//           SizedBox(width: 12.w),
//           Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Text(
//                 'Итого к оформлению',
//                 style: TextStyle(color: Colors.white60, fontSize: 10.sp),
//               ),
//               Text(
//                 formatPrice(totalSum),
//                 style: TextStyle(
//                   color: Colors.white,
//                   fontSize: 14.sp,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//             ],
//           ),
//           const Spacer(),
//           ElevatedButton(
//             style: ElevatedButton.styleFrom(
//               backgroundColor: const Color(0xFF2563EB),
//               foregroundColor: Colors.white,
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(10),
//               ),
//               padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
//             ),
//             onPressed: () => context.push('/cart'),
//             child: Text(
//               'Оформить',
//               style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// // Прокси-виджет для фикса обратной совместимости кнопок навигации
// class NavigationRawButton extends StatelessWidget {
//   final VoidCallback onPressed;
//   final ButtonStyle style;
//   final Widget child;
//   const NavigationRawButton({
//     super.key,
//     required this.onPressed,
//     required this.style,
//     required this.child,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return TextButton(onPressed: onPressed, style: style, child: child);
//   }
// }
