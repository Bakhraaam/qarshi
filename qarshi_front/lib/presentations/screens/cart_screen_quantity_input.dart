import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qarshi/core/data/api/api_django.dart';
import 'package:qarshi/core/data/constants.dart';
import 'package:qarshi/core/data/models.dart';
import 'package:qarshi/core/utils/formatters.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final DjangoApi _api = DjangoApi();

  List<CartItem> _cartItems = [];
  bool _isLoading = true;
  bool _isCheckingOut = false;
  DateTime? _deliveryDate;
  String _paymentMethod = 'cashless';
  double _discountPercent = 0;
  final TextEditingController _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCart();
  }

  Future<void> _loadCart() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final items = await _api.getCart();

      if (!mounted) return;

      setState(() {
        _cartItems = items;
        _isLoading = false;
      });

      // Синхронизируем глобальную корзину (бейдж/каталог) с сервером.
      cartNotifier.value = {
        for (final it in items) it.product.id: it.quantity,
      };
    } catch (e) {
      debugPrint('Ошибка загрузки корзины: $e');

      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить корзину')),
      );
    }
  }

  Future<void> _changeQuantity(CartItem item, num newQuantity) async {
    if (newQuantity < 0) return;

    final previousQuantity = item.quantity;

    setState(() {
      if (newQuantity == 0) {
        _cartItems.remove(item);
      } else {
        item.quantity = newQuantity;
      }
    });

    final success = await _api.updateCartItem(item.product.id, newQuantity);

    if (!success && mounted) {
      setState(() {
        if (newQuantity == 0) {
          _cartItems.add(item);
        }
        item.quantity = previousQuantity;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось изменить количество')),
      );
      return;
    }

    // Успех — обновляем глобальную корзину, чтобы бейдж и каталог совпадали.
    setCartQuantityLocal(item.product.id, newQuantity);
  }

  Future<void> _handleCheckout() async {
    if (_cartItems.isEmpty || _isCheckingOut) return;

    // final isWide = MediaQuery.sizeOf(context).width >= 760;
    // if (isWide && _deliveryDate == null) {
    //   ScaffoldMessenger.of(
    //     context,
    //   ).showSnackBar(const SnackBar(content: Text('Выберите дату доставки')));
    //   return;
    // }

    setState(() => _isCheckingOut = true);

    final orderNumber = await _api.createOrder();

    if (!mounted) return;

    setState(() => _isCheckingOut = false);

    if (orderNumber != null) {
      setState(() => _cartItems.clear());
      // Заказ оформлен — корзина пуста и на всех экранах.
      cartNotifier.value = <String, num>{};
      _showSuccessDialog(orderNumber);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ошибка оформления заказа. Попробуйте позже.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _showMobileCheckoutSheet() async {
    FocusScope.of(context).unfocus();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: keyboardInset),
              child: DraggableScrollableSheet(
                initialChildSize: 0.9,
                minChildSize: 0.62,
                maxChildSize: 0.96,
                expand: false,
                builder: (context, scrollController) {
                  return Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCBD5E1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                            child: _CheckoutFormContent(
                              totalPrice: _totalPrice,
                              finalPrice: _finalPrice,
                              discountAmount: _discountAmount,
                              totalItems: _totalItems,
                              deliveryDateText: _formatDate(_deliveryDate),
                              paymentMethod: _paymentMethod,
                              commentController: _commentController,
                              isCheckingOut: _isCheckingOut,
                              onDeliveryDateTap: () async {
                                await _selectDeliveryDate();
                                setSheetState(() {});
                              },
                              onPaymentChanged: (value) {
                                if (value == null) return;
                                setState(() => _paymentMethod = value);
                                setSheetState(() {});
                              },
                              onCheckout: () async {
                                final success = await _confirmAndCheckout(
                                  parentContext: sheetContext,
                                );
                                if (success && sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                }
                              },
                              compact: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _confirmAndCheckout({BuildContext? parentContext}) async {
    if (_deliveryDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Выберите дату доставки')));
      return false;
    }

    final confirmed = await showDialog<bool>(
      context: parentContext ?? context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Подтвердить заказ?',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ConfirmationRow(
                label: 'Дата доставки',
                value: _formatDate(_deliveryDate),
              ),
              const SizedBox(height: 10),
              _ConfirmationRow(
                label: 'Оплата',
                value: _paymentMethodLabel(_paymentMethod),
              ),
              const SizedBox(height: 10),
              _ConfirmationRow(label: 'Позиций', value: '$_totalItems'),
              const SizedBox(height: 10),
              _ConfirmationRow(
                label: 'Итого',
                value: formatPrice(_finalPrice),
                emphasize: true,
              ),
              if (_commentController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _commentController.text.trim(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Подтвердить'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return false;

    await _handleCheckout();
    return _cartItems.isEmpty;
  }

  String _paymentMethodLabel(String value) {
    switch (value) {
      case 'cash':
        return 'Наличные';
      case 'transfer':
        return 'Перевод';
      case 'deferred':
        return 'Отсрочка платежа';
      case 'cashless':
      default:
        return 'Безналичный расчет';
    }
  }

  void _showSuccessDialog(String orderNumber) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final dialogWidth = MediaQuery.sizeOf(dialogContext).width;

        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: dialogWidth < 500 ? 20 : 40,
            vertical: 24,
          ),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Color(0xFF16A34A),
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Заказ оформлен',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Заказ передан в 1С для дальнейшей обработки.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'НОМЕР ЗАКАЗА',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          orderNumber,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF2563EB),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        dialogContext.pop();
                        dialogContext.go('/');
                      },
                      child: const Text(
                        'Вернуться в каталог',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _selectDeliveryDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _deliveryDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      helpText: 'Дата доставки',
      cancelText: 'Отмена',
      confirmText: 'Выбрать',
    );

    if (selected != null && mounted) {
      setState(() => _deliveryDate = selected);
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Выберите дату';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  double get _discountAmount => _totalPrice * (_discountPercent / 100);

  double get _finalPrice =>
      (_totalPrice - _discountAmount).clamp(0, double.infinity).toDouble();

  double get _totalPrice {
    return _cartItems.fold<double>(0, (sum, item) => sum + item.totalWithItem);
  }

  int get _totalItems {
    return _cartItems.fold<int>(0, (sum, item) => sum + item.quantity.toInt());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 1,
        elevation: 0,
        title: const Text(
          'Корзина',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _cartItems.isEmpty
          ? const _EmptyCart()
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;

                if (width < 760) {
                  return _buildMobileLayout();
                }

                return _buildWideLayout(
                  maxContentWidth: width >= 1400 ? 1280 : 1120,
                );
              },
            ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            itemCount: _cartItems.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              return _CartItemCard(
                item: _cartItems[index],
                onDecrease: () => _changeQuantity(
                  _cartItems[index],
                  _cartItems[index].quantity - 1,
                ),
                onIncrease: () => _changeQuantity(
                  _cartItems[index],
                  _cartItems[index].quantity + 1,
                ),
                onQuantityChanged: (value) => _changeQuantity(
                  _cartItems[index],
                  value,
                ),
                onRemove: () => _changeQuantity(_cartItems[index], 0),
              );
            },
          ),
        ),
        _CheckoutBottomBar(
          totalPrice: _totalPrice,
          totalItems: _totalItems,
          isCheckingOut: _isCheckingOut,
          onCheckout: _showMobileCheckoutSheet,
        ),
      ],
    );
  }

  Widget _buildWideLayout({required double maxContentWidth}) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: ListView.separated(
                  itemCount: _cartItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return _CartItemCard(
                      item: _cartItems[index],
                      wide: true,
                      onDecrease: () => _changeQuantity(
                        _cartItems[index],
                        _cartItems[index].quantity - 1,
                      ),
                      onIncrease: () => _changeQuantity(
                        _cartItems[index],
                        _cartItems[index].quantity + 1,
                      ),
                      onQuantityChanged: (value) => _changeQuantity(
                        _cartItems[index],
                        value,
                      ),
                      onRemove: () => _changeQuantity(_cartItems[index], 0),
                    );
                  },
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 330,
                child: _CheckoutPanel(
                  totalPrice: _totalPrice,
                  finalPrice: _finalPrice,
                  discountAmount: _discountAmount,
                  discountPercent: _discountPercent,
                  totalItems: _totalItems,
                  deliveryDateText: _formatDate(_deliveryDate),
                  paymentMethod: _paymentMethod,
                  commentController: _commentController,
                  isCheckingOut: _isCheckingOut,
                  onDeliveryDateTap: _selectDeliveryDate,
                  onPaymentChanged: (value) {
                    if (value != null) {
                      setState(() => _paymentMethod = value);
                    }
                  },
                  onDiscountChanged: (value) {
                    setState(() => _discountPercent = value);
                  },
                  onCheckout: _confirmAndCheckout,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  final CartItem item;
  final bool wide;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final ValueChanged<num> onQuantityChanged;
  final VoidCallback onRemove;

  const _CartItemCard({
    required this.item,
    required this.onDecrease,
    required this.onIncrease,
    required this.onQuantityChanged,
    required this.onRemove,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final imageSize = wide ? 104.0 : 84.0;

    return Container(
      padding: EdgeInsets.all(wide ? 16 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProductImage(imageUrl: item.product.imageUrl, size: imageSize),
          SizedBox(width: wide ? 16 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.product.name,
                        maxLines: wide ? 2 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF0F172A),
                          fontSize: wide ? 15 : 14,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Удалить',
                      onPressed: onRemove,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 34,
                        minHeight: 34,
                      ),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFF94A3B8),
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${formatPrice(item.product.price)} / ${item.product.unit}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
                SizedBox(height: wide ? 18 : 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(
                      formatPrice(item.totalWithItem),
                      style: TextStyle(
                        color: const Color(0xFF2563EB),
                        fontSize: wide ? 17 : 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    _QuantityControl(
                      quantity: item.quantity,
                      unit: item.product.unit,
                      onDecrease: onDecrease,
                      onIncrease: onIncrease,
                      onQuantityChanged: onQuantityChanged,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final String imageUrl;
  final double size;

  const _ProductImage({required this.imageUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFFF1F5F9),
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return const Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                color: Color(0xFF94A3B8),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _QuantityControl extends StatefulWidget {
  final num quantity;
  final String unit;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final ValueChanged<num> onQuantityChanged;

  const _QuantityControl({
    required this.quantity,
    required this.unit,
    required this.onDecrease,
    required this.onIncrease,
    required this.onQuantityChanged,
  });

  @override
  State<_QuantityControl> createState() => _QuantityControlState();
}

class _QuantityControlState extends State<_QuantityControl> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _formatQuantity(widget.quantity),
    );
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _QuantityControl oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_focusNode.hasFocus && oldWidget.quantity != widget.quantity) {
      _controller.text = _formatQuantity(widget.quantity);
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus && _isEditing) {
      _submit();
    }

    if (mounted) {
      setState(() => _isEditing = _focusNode.hasFocus);
    }
  }

  void _startEditing() {
    setState(() => _isEditing = true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _submit() {
    final normalized = _controller.text.trim().replaceAll(',', '.');
    final parsed = num.tryParse(normalized);

    if (parsed == null || parsed < 0) {
      _controller.text = _formatQuantity(widget.quantity);
      return;
    }

    final value = parsed is double && parsed == parsed.roundToDouble()
        ? parsed.toInt()
        : parsed;

    _controller.text = _formatQuantity(value);
    widget.onQuantityChanged(value);
  }

  String _formatQuantity(num value) {
    if (value is int) return value.toString();
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: _isEditing
            ? Border.all(
                color: const Color(0xFF2563EB),
                width: 1.2,
              )
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QuantityButton(
            icon: Icons.remove_rounded,
            onTap: widget.onDecrease,
          ),
          GestureDetector(
            onTap: _startEditing,
            behavior: HitTestBehavior.opaque,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 66,
                maxWidth: 110,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _isEditing
                    ? TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.,]'),
                          ),
                        ],
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (_) {
                          _submit();
                          _focusNode.unfocus();
                        },
                      )
                    : Text(
                        '${_formatQuantity(widget.quantity)} ${widget.unit}',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
          _QuantityButton(
            icon: Icons.add_rounded,
            onTap: widget.onIncrease,
          ),
        ],
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _QuantityButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 38,
        height: 38,
        child: Icon(icon, size: 18, color: const Color(0xFF334155)),
      ),
    );
  }
}

class _CheckoutBottomBar extends StatelessWidget {
  final double totalPrice;
  final int totalItems;
  final bool isCheckingOut;
  final VoidCallback onCheckout;

  const _CheckoutBottomBar({
    required this.totalPrice,
    required this.totalItems,
    required this.isCheckingOut,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 12,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$totalItems поз.',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatPrice(totalPrice),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    disabledBackgroundColor: const Color(0xFF93C5FD),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: isCheckingOut ? null : onCheckout,
                  child: isCheckingOut
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Оформить',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckoutPanel extends StatelessWidget {
  final double totalPrice;
  final double finalPrice;
  final double discountAmount;
  final double discountPercent;
  final int totalItems;
  final String deliveryDateText;
  final String paymentMethod;
  final TextEditingController commentController;
  final bool isCheckingOut;
  final VoidCallback onDeliveryDateTap;
  final ValueChanged<String?> onPaymentChanged;
  final ValueChanged<double> onDiscountChanged;
  final VoidCallback onCheckout;

  const _CheckoutPanel({
    required this.totalPrice,
    required this.finalPrice,
    required this.discountAmount,
    required this.discountPercent,
    required this.totalItems,
    required this.deliveryDateText,
    required this.paymentMethod,
    required this.commentController,
    required this.isCheckingOut,
    required this.onDeliveryDateTap,
    required this.onPaymentChanged,
    required this.onDiscountChanged,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: SingleChildScrollView(
        child: _CheckoutFormContent(
          totalPrice: totalPrice,
          finalPrice: finalPrice,
          discountAmount: discountAmount,
          totalItems: totalItems,
          deliveryDateText: deliveryDateText,
          paymentMethod: paymentMethod,
          commentController: commentController,
          isCheckingOut: isCheckingOut,
          onDeliveryDateTap: onDeliveryDateTap,
          onPaymentChanged: onPaymentChanged,
          onCheckout: onCheckout,
        ),
      ),
    );
  }
}

class _CheckoutFormContent extends StatelessWidget {
  final double totalPrice;
  final double finalPrice;
  final double discountAmount;
  final int totalItems;
  final String deliveryDateText;
  final String paymentMethod;
  final TextEditingController commentController;
  final bool isCheckingOut;
  final VoidCallback onDeliveryDateTap;
  final ValueChanged<String?> onPaymentChanged;
  final VoidCallback onCheckout;
  final bool compact;

  const _CheckoutFormContent({
    required this.totalPrice,
    required this.finalPrice,
    required this.discountAmount,
    required this.totalItems,
    required this.deliveryDateText,
    required this.paymentMethod,
    required this.commentController,
    required this.isCheckingOut,
    required this.onDeliveryDateTap,
    required this.onPaymentChanged,
    required this.onCheckout,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          compact ? 'Оформление заказа' : 'Оформление заказа',
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),
        const _FieldLabel('Дата доставки'),
        const SizedBox(height: 7),
        _PickerField(
          icon: Icons.calendar_month_outlined,
          value: deliveryDateText,
          placeholder: deliveryDateText == 'Выберите дату',
          onTap: onDeliveryDateTap,
        ),
        const SizedBox(height: 16),
        const _FieldLabel('Способ оплаты'),
        const SizedBox(height: 7),
        DropdownButtonFormField<String>(
          value: paymentMethod,
          isExpanded: true,
          decoration: _checkoutInputDecoration(
            prefixIcon: Icons.account_balance_wallet_outlined,
          ),
          items: const [
            DropdownMenuItem(value: 'cashless', child: Text('Безналичный')),
            DropdownMenuItem(value: 'cash', child: Text('Наличные')),
          ],
          onChanged: onPaymentChanged,
        ),
        const SizedBox(height: 16),
        const _FieldLabel('Комментарий'),
        const SizedBox(height: 7),
        TextField(
          controller: commentController,
          minLines: compact ? 2 : 3,
          maxLines: compact ? 4 : 5,
          maxLength: 300,
          decoration: _checkoutInputDecoration(
            hintText: 'Например: доставить до 15:00',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        const Divider(color: Color(0xFFE2E8F0)),
        const SizedBox(height: 12),
        _SummaryRow(label: 'Количество', value: '$totalItems поз.'),
        const SizedBox(height: 10),
        _SummaryRow(label: 'Сумма товаров', value: formatPrice(totalPrice)),
        if (discountAmount > 0) ...[
          const SizedBox(height: 10),
          _SummaryRow(
            label: 'Скидка',
            value: '− ${formatPrice(discountAmount)}',
            valueColor: const Color(0xFF16A34A),
          ),
        ],
        const SizedBox(height: 12),
        const Divider(color: Color(0xFFE2E8F0)),
        const SizedBox(height: 12),
        _SummaryRow(
          label: 'Итого',
          value: formatPrice(finalPrice),
          emphasize: true,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              disabledBackgroundColor: const Color(0xFF93C5FD),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: isCheckingOut ? null : onCheckout,
            icon: isCheckingOut
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.check_circle_outline_rounded, size: 19),
            label: Text(
              isCheckingOut ? 'Оформление...' : 'Продолжить',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

InputDecoration _checkoutInputDecoration({
  IconData? prefixIcon,
  String? hintText,
  bool? alignLabelWithHint,
}) {
  return InputDecoration(
    hintText: hintText,
    alignLabelWithHint: alignLabelWithHint,
    prefixIcon: prefixIcon == null
        ? null
        : Icon(prefixIcon, size: 20, color: const Color(0xFF64748B)),
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.4),
    ),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );
}

class _ConfirmationRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _ConfirmationRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: const Color(0xFF0F172A),
              fontSize: emphasize ? 16 : 13,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF334155),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  final IconData icon;
  final String value;
  final bool placeholder;
  final VoidCallback onTap;

  const _PickerField({
    required this.icon,
    required this.value,
    required this.placeholder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF64748B)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    color: placeholder
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF0F172A),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  final Color? valueColor;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: emphasize
                  ? const Color(0xFF0F172A)
                  : const Color(0xFF64748B),
              fontSize: emphasize ? 14 : 13,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: valueColor ?? const Color(0xFF0F172A),
              fontSize: emphasize ? 18 : 13,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            children: [
              Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(
                  Icons.shopping_cart_outlined,
                  color: Color(0xFF2563EB),
                  size: 42,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Корзина пуста',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Добавьте товары из каталога, чтобы оформить заказ.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 46,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.grid_view_rounded, size: 18),
                  label: const Text(
                    'Перейти в каталог',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
