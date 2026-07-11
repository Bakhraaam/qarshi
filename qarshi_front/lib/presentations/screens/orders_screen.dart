import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:qarshi/core/data/api/api_django.dart';
import 'package:qarshi/core/data/models.dart';
import 'package:qarshi/core/utils/formatters.dart';
import 'package:qarshi/core/utils/responsive.dart';
// import '../../core/utils/responsive.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final DjangoApi _api = DjangoApi();
  List<OrderModel> _orders = [];
  OrderModel?
  _selectedOrderForDesktop; // Хранит выбранный заказ для правой панели на ПК
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    final data = await _api.getOrders();
    setState(() {
      _orders = data;
      if (_orders.isNotEmpty) {
        _selectedOrderForDesktop =
            _orders.first; // По умолчанию открываем первый на ПК
      }
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('История заказов'),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
          ? const Center(child: Text('У вас пока нет оформленных заказов'))
          : Responsive(
              mobile: _buildMobileLayout(),
              desktop: _buildDesktopLayout(),
            ),
    );
  }

  // --- 1. МОБИЛЬНЫЙ ВАРИАНТ (Обычный вертикальный список карт) ---
  Widget _buildMobileLayout() {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        final order = _orders[index];
        return _buildOrderCard(
          order,
          onTap: () => _showOrderDetailsBottomSheet(order),
        );
      },
    );
  }

  // --- 2. ДЕСКТОП ВАРИАНТ (Две колонки: список слева, детали выбранного справа) ---
  Widget _buildDesktopLayout() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Левая половина: Список заказов
          Expanded(
            flex: 1,
            child: ListView.builder(
              itemCount: _orders.length,
              itemBuilder: (context, index) {
                final order = _orders[index];
                final bool isSelected =
                    _selectedOrderForDesktop?.id == order.id;
                return _buildOrderCard(
                  order,
                  isSelected: isSelected,
                  onTap: () => setState(() => _selectedOrderForDesktop = order),
                );
              },
            ),
          ),
          const SizedBox(width: 24),
          // Правая половина: Подробное описание выбранного b2b-заказа
          Expanded(
            flex: 1,
            child: _selectedOrderForDesktop == null
                ? Container()
                : Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: _OrderDetailsContent(
                      order: _selectedOrderForDesktop!,
                      // getStatusColor: _getStatusColor,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // УНИВЕРСАЛЬНЫЙ КОМПОНЕНТ КАРТОЧКИ ЗАКАЗА
  Widget _buildOrderCard(
    OrderModel order, {
    bool isSelected = false,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF2563EB)
                  : const Color(0xFFE2E8F0),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    order.number,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  // Компактный статус-бадж
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10.w,
                      vertical: 4.h,
                    ),
                    decoration: BoxDecoration(
                      color: order.status.color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      order.status.label,
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.bold,
                        color: order.status.color,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              Text(
                'Дата: ${order.date}',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: const Color(0xFF64748B),
                ),
              ),
              SizedBox(height: 12.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Сумма заказа:',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    '${formatPrice(order.totalAmount)}',
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Окно деталей заказа снизу для смартфонов
  void _showOrderDetailsBottomSheet(OrderModel order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.all(20.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              SizedBox(height: 16.h),
              _OrderDetailsContent(
                order: order,
                // getStatusColor: _getStatusColor,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrderDetailsContent extends StatefulWidget {
  final OrderModel order;
  // final Color Function(String) getStatusColor;

  const _OrderDetailsContent({
    // super.key,
    required this.order,
    // required this.getStatusColor,
  });

  @override
  State<_OrderDetailsContent> createState() => _OrderDetailsContentState();
}

class _OrderDetailsContentState extends State<_OrderDetailsContent> {
  final DjangoApi _api = DjangoApi();
  List<OrderItem> _fetchedItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrderItems();
  }

  // Срабатывает, если на ПК пользователь кликает на другой заказ в списке (id меняется)
  @override
  void didUpdateWidget(covariant _OrderDetailsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.id != widget.order.id) {
      _loadOrderItems();
    }
  }

  Future<void> _loadOrderItems() async {
    setState(() => _isLoading = true);
    try {
      // Запрашиваем состав заказа по его уникальному ID
      final items = await _api.getOrderDetails(widget.order.id);
      setState(() {
        _fetchedItems = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Спецификация заказа',
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF0F172A),
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          '${widget.order.number} от ${widget.order.date}',
          style: TextStyle(fontSize: 13.sp, color: const Color(0xFF64748B)),
        ),
        SizedBox(height: 16.h),

        // Показываем лоадер только для списка товаров, шапка и итог остаются видимыми
        Flexible(
          child: _isLoading
              ? Container(
                  height: 150.h,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(strokeWidth: 2.5),
                )
              : _fetchedItems.isEmpty
              ? Container(
                  height: 100.h,
                  alignment: Alignment.center,
                  child: Text(
                    'Состав заказа пуст или не загружен',
                    style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                  ),
                )
              : Container(
                  constraints: BoxConstraints(
                    maxHeight: 300.h,
                  ), // Защита от переполнения экрана на мобилках
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _fetchedItems.length,
                    separatorBuilder: (c, i) =>
                        const Divider(color: Color(0xFFE2E8F0)),
                    itemBuilder: (context, index) {
                      final item = _fetchedItems[index];
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 4.h),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              // Изменили на структуру item.productName (или item.product.name в зависимости от вашей модели)
                              item.product.name,
                              style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${item.quantity} ${item.product.unit} × ${formatPrice(item.price)}',
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                                Text(
                                  '${formatPrice(item.totalAmount)}',
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
        const Divider(color: Color(0xFF0F172A), thickness: 1),
        SizedBox(height: 8.h),

        // Итоговая сумма (берется из шапки документа)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Итого по документу:',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              '${formatPrice(widget.order.totalAmount)}',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF2563EB),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
