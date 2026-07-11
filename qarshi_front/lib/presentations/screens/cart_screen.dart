// import 'package:flutter/material.dart';
// import 'package:flutter_screenutil/flutter_screenutil.dart';
// import 'package:go_router/go_router.dart';
// import 'package:qarshi/core/data/api/api_django.dart';
// import 'package:qarshi/core/data/constants.dart';
// import 'package:qarshi/core/data/models.dart';
// import 'package:qarshi/core/utils/formatters.dart';
// import 'package:qarshi/core/utils/responsive.dart';
// // import '../../core/utils/responsive.dart';

// class CartScreen extends StatefulWidget {
//   const CartScreen({super.key});

//   @override
//   State<CartScreen> createState() => _CartScreenState();
// }

// class _CartScreenState extends State<CartScreen> {
//   final DjangoApi _api = DjangoApi();
//   List<CartItem> _cartItems = [];
//   bool _isLoading = true;
//   bool _isCheckingOut = false;

//   @override
//   void initState() {
//     super.initState();
//     _loadCart();
//   }

//   Future<void> _loadCart() async {
//     setState(() => _isLoading = true);
//     final items = await _api.getCart();
//     setState(() {
//       _cartItems = items;
//       _isLoading = false;
//     });
//   }

//   // Изменение количества внутри корзины
//   Future<void> _changeQuantity(CartItem item, num newQuantity) async {
//     if (newQuantity <= 0) {
//       final success = await _api.updateCartItem(item.product.id, 0);
//       if (success) setState(() => _cartItems.remove(item));
//     } else {
//       final success = await _api.updateCartItem(item.product.id, newQuantity);
//       if (success) {
//         setState(() => item.quantity = newQuantity);
//       }
//     }
//   }

//   // Главная логика оформления заказа
//   Future<void> _handleCheckout() async {
//     if (_cartItems.isEmpty || _isCheckingOut) return;

//     setState(() => _isCheckingOut = true);
//     final String? orderNumber = await _api.createOrder();
//     setState(() => _isCheckingOut = false);

//     if (orderNumber != null) {
//       setState(() => _cartItems.clear());
//       if (mounted) _showSuccessDialog(orderNumber);
//     } else {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Ошибка оформления заказа. Попробуйте позже.'),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//     }
//   }

//   // Окно успешного оформления в премиальном b2b-стиле
//   void _showSuccessDialog(String orderNumber) {
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       // ИСПРАВЛЕНО: переименовали аргумент в dialogContext, чтобы убрать затенение
//       builder: (dialogContext) => AlertDialog(
//         backgroundColor: Colors.white,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
//         content: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             const SizedBox(height: 12),
//             Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: const Color(0xFF10B981).withOpacity(0.1),
//                 shape: BoxShape.circle,
//               ),
//               child: const Icon(
//                 Icons.check_circle_rounded,
//                 color: Color(0xFF10B981),
//                 size: 54,
//               ),
//             ),
//             const SizedBox(height: 20),
//             Text(
//               'Заказ успешно оформлен!',
//               textAlign: TextAlign.center,
//               style: TextStyle(
//                 fontSize: 18.sp,
//                 fontWeight: FontWeight.bold,
//                 color: const Color(0xFF0F172A),
//               ),
//             ),
//             const SizedBox(height: 8),
//             Text(
//               'Документ передан в 1С для формирования отгрузки.',
//               textAlign: TextAlign.center,
//               style: TextStyle(fontSize: 12.sp, color: const Color(0xFF64748B)),
//             ),
//             const SizedBox(height: 16),

//             // Номер заказа из 1С на контрастном фоне
//             Container(
//               width: double.infinity,
//               padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
//               decoration: BoxDecoration(
//                 color: const Color(0xFFF1F5F9),
//                 borderRadius: BorderRadius.circular(10),
//               ),
//               child: Column(
//                 children: [
//                   Text(
//                     'НОМЕР ДОКУМЕНТА',
//                     style: TextStyle(
//                       fontSize: 10.sp,
//                       color: const Color(0xFF64748B),
//                       fontWeight: FontWeight.bold,
//                       letterSpacing: 0.5,
//                     ),
//                   ),
//                   const SizedBox(height: 4),
//                   Text(
//                     orderNumber,
//                     style: TextStyle(
//                       fontSize: 16.sp,
//                       fontWeight: FontWeight.bold,
//                       color: const Color(0xFF2563EB),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(height: 24),

//             // Кнопка возврата в главное меню
//             SizedBox(
//               width: double.infinity,
//               height: 42.h,
//               child: ElevatedButton(
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: const Color(0xFF0F172A),
//                   foregroundColor: Colors.white,
//                   elevation: 0,
//                   shape: RoundedRectangleBorder(
//                     borderRadius: BorderRadius.circular(10),
//                   ),
//                 ),
//                 onPressed: () {
//                   // ИСПРАВЛЕНО: обращаемся к роутеру через очищенный dialogContext
//                   dialogContext.pop();
//                   dialogContext.go('/');
//                 },
//                 child: Text(
//                   'В главное меню',
//                   style: TextStyle(
//                     fontSize: 13.sp,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   double get _totalPrice =>
//       _cartItems.fold(0, (sum, item) => sum + item.totalWithItem);

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF8FAFC),
//       appBar: AppBar(
//         title: const Text('Корзина заказа'),
//         scrolledUnderElevation: 0,
//         backgroundColor: Colors.transparent,
//       ),
//       body: _isLoading
//           ? const Center(child: CircularProgressIndicator())
//           : _cartItems.isEmpty
//           ? const Center(
//               child: Text(
//                 'Ваша корзина пуста',
//                 style: TextStyle(color: Colors.grey),
//               ),
//             )
//           : Responsive(
//               mobile: _buildMobileLayout(),
//               desktop: _buildDesktopLayout(),
//             ),
//     );
//   }

//   Widget _buildMobileLayout() {
//     return Column(
//       children: [
//         Expanded(
//           child: ListView.builder(
//             padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
//             itemCount: _cartItems.length,
//             itemBuilder: (context, index) => _buildCartCard(_cartItems[index]),
//           ),
//         ),
//         _buildCheckoutSummary(isMobile: true),
//       ],
//     );
//   }

//   Widget _buildDesktopLayout() {
//     return Padding(
//       padding: const EdgeInsets.all(24.0),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Expanded(
//             flex: 2,
//             child: ListView.builder(
//               itemCount: _cartItems.length,
//               itemBuilder: (context, index) =>
//                   _buildCartCard(_cartItems[index]),
//             ),
//           ),
//           const SizedBox(width: 24),
//           Expanded(flex: 1, child: _buildCheckoutSummary(isMobile: false)),
//         ],
//       ),
//     );
//   }

//   Widget _buildCartCard(CartItem item) {
//     return Container(
//       margin: EdgeInsets.only(bottom: 12.h),
//       padding: EdgeInsets.all(12.w),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: const Color(0xFFE2E8F0)),
//       ),
//       child: Row(
//         children: [
//           Container(
//             width: 80.w,
//             height: 80.w,
//             decoration: BoxDecoration(
//               color: Colors.grey[100],
//               borderRadius: BorderRadius.circular(10),
//             ),
//             child: ClipRRect(
//               borderRadius: BorderRadius.circular(10),
//               child: Image.network(
//                 item.product.imageUrl,
//                 fit: BoxFit.cover,
//                 errorBuilder: (c, e, s) => const Icon(
//                   Icons.image_not_supported_rounded,
//                   color: Colors.grey,
//                 ),
//               ),
//             ),
//           ),
//           SizedBox(width: 16.w),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   item.product.name,
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                   style: TextStyle(
//                     fontSize: 14.sp,
//                     fontWeight: FontWeight.bold,
//                     color: const Color(0xFF0F172A),
//                   ),
//                 ),
//                 SizedBox(height: 4.h),
//                 Text(
//                   '${formatPrice(item.product.price)} / ${item.product.unit}',
//                   style: TextStyle(
//                     fontSize: 12.sp,
//                     color: const Color(0xFF64748B),
//                   ),
//                 ),
//                 SizedBox(height: 10.h),
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     Text(
//                       formatPrice(item.totalWithItem),
//                       style: TextStyle(
//                         fontSize: 14.sp,
//                         fontWeight: FontWeight.bold,
//                         color: Theme.of(context).primaryColor,
//                       ),
//                     ),
//                     Container(
//                       height: 32.h,
//                       decoration: BoxDecoration(
//                         color: const Color(0xFFF1F5F9),
//                         borderRadius: BorderRadius.circular(8),
//                       ),
//                       child: Row(
//                         children: [
//                           IconButton(
//                             padding: EdgeInsets.zero,
//                             icon: const Icon(Icons.remove, size: 16),
//                             onPressed: () =>
//                                 _changeQuantity(item, item.quantity - 1),
//                           ),
//                           Text(
//                             '${item.quantity}',
//                             style: TextStyle(
//                               fontSize: 13.sp,
//                               fontWeight: FontWeight.bold,
//                             ),
//                           ),
//                           IconButton(
//                             padding: EdgeInsets.zero,
//                             icon: const Icon(Icons.add, size: 16),
//                             onPressed: () =>
//                                 _changeQuantity(item, item.quantity + 1),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildCheckoutSummary({required bool isMobile}) {
//     final content = Container(
//       padding: EdgeInsets.all(20.w),
//       decoration: BoxDecoration(
//         color: const Color(0xFF0F172A),
//         borderRadius: isMobile
//             ? const BorderRadius.vertical(top: Radius.circular(20))
//             : BorderRadius.circular(16),
//       ),
//       child: SafeArea(
//         top: false,
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       'Общая сумма к оплате',
//                       style: TextStyle(color: Colors.white60, fontSize: 12.sp),
//                     ),
//                     SizedBox(height: 4.h),
//                     Text(
//                       '${formatPrice(_totalPrice)}',
//                       style: TextStyle(
//                         color: Colors.white,
//                         fontSize: 18.sp,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                   ],
//                 ),
//                 ElevatedButton(
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: const Color(0xFF2563EB),
//                     foregroundColor: Colors.white,
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(10),
//                     ),
//                     padding: EdgeInsets.symmetric(
//                       horizontal: 24.w,
//                       vertical: 12.h,
//                     ),
//                     elevation: 0,
//                   ),
//                   onPressed: _isCheckingOut ? null : _handleCheckout,
//                   child: _isCheckingOut
//                       ? SizedBox(
//                           width: 20.w,
//                           height: 20.w,
//                           child: const CircularProgressIndicator(
//                             color: Colors.white,
//                             strokeWidth: 2,
//                           ),
//                         )
//                       : const Text(
//                           'Оформить заказ',
//                           style: TextStyle(
//                             fontSize: 14,
//                             fontWeight: FontWeight.bold,
//                           ),
//                         ),
//                 ),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );

//     return isMobile
//         ? content
//         : Align(alignment: Alignment.topCenter, child: content);
//   }
// }
