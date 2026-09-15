import 'dart:async';

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

/// Сколько живёт кнопка «Отменить» после удаления строки корзины.
const Duration _undoRemovalWindow = Duration(seconds: 3);

class _CartScreenState extends State<CartScreen> {
  final DjangoApi _api = DjangoApi();

  List<CartItem> _cartItems = [];

  /// Строки, удалённые клиентом, но ещё не удалённые на сервере. Пока идёт таймер,
  /// строка остаётся на своём месте в списке в виде плашки «Удалено · Отменить»,
  /// а в суммы и в заказ уже не входит. Запрос на сервер уходит по истечении таймера.
  final Map<CartItem, Timer> _pendingRemovals = {};
  bool _isLoading = true;
  bool _isCheckingOut = false;
  DateTime? _deliveryDate;
  String _paymentMethod = 'cashless';
  double _discountPercent = 0;
  final TextEditingController _commentController = TextEditingController();

  @override
  void dispose() {
    // Ушли с экрана раньше, чем истёк таймер: удаление подтверждено, отправляем сразу.
    for (final item in _pendingRemovals.keys.toList()) {
      _commitRemoval(item);
    }
    _commentController.dispose();
    super.dispose();
  }

  /// Строки, которые реально лежат в корзине: без тех, что ждут отмены удаления.
  List<CartItem> get _activeItems =>
      _cartItems.where((item) => !_pendingRemovals.containsKey(item)).toList();

  /// Убрать строку с возможностью отмены в течение [_undoRemovalWindow].
  void _scheduleRemoval(CartItem item) {
    if (_pendingRemovals.containsKey(item)) return;
    setState(() {
      _pendingRemovals[item] = Timer(
        _undoRemovalWindow,
        () => _commitRemoval(item),
      );
    });
  }

  void _undoRemoval(CartItem item) {
    final timer = _pendingRemovals.remove(item);
    if (timer == null) return;
    timer.cancel();
    setState(() {});
  }

  /// Удаляет строку на сервере. Вызывается по таймеру, при уходе с экрана и перед
  /// оформлением заказа — иначе ещё не удалённая на сервере строка попала бы в заказ.
  Future<void> _commitRemoval(CartItem item) async {
    final timer = _pendingRemovals.remove(item);
    if (timer == null) return;
    timer.cancel();

    final success = await _api.updateCartItem(
      item.product.id,
      0,
      packageId: item.packageId,
    );

    if (success) {
      setCartQuantityLocal(item.product.id, item.packageId, 0);
      if (mounted) setState(() => _cartItems.remove(item));
      return;
    }

    // Сервер не удалил — строка остаётся в корзине, показываем её снова.
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Не удалось удалить «${item.product.name}»'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Подтверждает все отложенные удаления и ждёт ответа сервера.
  Future<void> _commitAllRemovals() async {
    await Future.wait(_pendingRemovals.keys.toList().map(_commitRemoval));
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
      // Профиль перечитываем вместе с корзиной: если 1С привязала контрагента,
      // пока приложение было открыто, экран корзины уже узнает об этом.
      final results = await Future.wait<Object>([
        _api.getCart(),
        _api.refreshCurrentUser(),
      ]);
      final items = results[0] as List<CartItem>;

      if (!mounted) return;

      setState(() {
        _cartItems = items;
        _isLoading = false;
      });

      // Синхронизируем глобальную корзину (бейдж/каталог) с сервером.
      cartNotifier.value = {for (final it in items) it.lineKey: it.quantity};
    } catch (e) {
      debugPrint('Ошибка загрузки корзины: $e');

      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить корзину')),
      );
    }
  }

  /// Убираем хвосты вроде 2.9999999999 после умножения/деления на множитель упаковки.
  num _normalizeQuantity(num value) {
    final rounded = num.parse(value.toStringAsFixed(3));
    if (rounded == rounded.roundToDouble()) return rounded.toInt();
    return rounded;
  }

  /// newQuantity — всегда в БАЗОВЫХ единицах товара (цена в прайсе за неё же).
  Future<void> _changeQuantity(CartItem item, num newQuantity) async {
    newQuantity = _normalizeQuantity(newQuantity);
    if (newQuantity < 0) return;

    // До нуля — корзиной, «−» или вводом 0 — это удаление, и его можно отменить.
    if (newQuantity == 0) {
      _scheduleRemoval(item);
      return;
    }

    final previousQuantity = item.quantity;

    setState(() => item.quantity = newQuantity);

    final success = await _api.updateCartItem(
      item.product.id,
      newQuantity,
      packageId: item.packageId,
    );

    if (!success && mounted) {
      setState(() => item.quantity = previousQuantity);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось изменить количество')),
      );
      return;
    }

    // Успех — обновляем глобальную корзину, чтобы бейдж и каталог совпадали.
    setCartQuantityLocal(item.product.id, item.packageId, newQuantity);
  }

  /// Отправляет заказ и ВСЕГДА показывает итог: успех, отказ или ошибку.
  ///
  /// Вызывается только когда все листы и подтверждения уже закрыты. Раньше лист
  /// корзины закрывался командой pop уже после показа окна успеха, и pop закрывал
  /// именно это окно — клиент не видел ни номера заказа, ни ошибки.
  Future<void> _submitOrder() async {
    if (_activeItems.isEmpty || _isCheckingOut) return;

    setState(() => _isCheckingOut = true);
    _showSubmittingDialog();

    // Заказ собирается из серверной корзины, поэтому удалённые, но ещё не
    // отправленные строки сначала действительно удаляем.
    await _commitAllRemovals();
    final result = await _api.createOrder();

    if (!mounted) return;
    // Закрываем окно «Отправляем заказ…». Между его показом и этой строкой ничего
    // не открывается, поэтому pop снимает именно его.
    Navigator.of(context, rootNavigator: true).pop();
    setState(() => _isCheckingOut = false);

    if (result.isSuccess) {
      setState(() => _cartItems.clear());
      // Заказ оформлен — корзина пуста и на всех экранах.
      cartNotifier.value = <String, num>{};
      await _showSuccessDialog(result);
      return;
    }

    if (result.isUnregistered) {
      // Сервер проверил привязку по базе. Обновляем профиль, чтобы и экран знал.
      await _api.refreshCurrentUser();
      if (!mounted) return;
      await _showUnregisteredDialog(message: result.error);
      return;
    }

    await _showResultDialog(
      icon: Icons.error_outline_rounded,
      iconColor: const Color(0xFFDC2626),
      iconBackground: const Color(0xFFFEE2E2),
      title: 'Заказ не отправлен',
      message: result.error ?? 'Ошибка оформления заказа. Попробуйте позже.',
      primaryLabel: 'Понятно',
      onPrimary: (dialogContext) => Navigator.of(dialogContext).pop(),
    );
  }

  void _showSubmittingDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                SizedBox(height: 18),
                Text(
                  'Отправляем заказ…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Проверка привязки к контрагенту перед оформлением.
  ///
  /// Профиль сначала перечитывается с сервера: если 1С привязала аккаунт, пока
  /// корзина была открыта, клиенту не нужно перезагружать страницу.
  Future<bool> _ensureRegistered() async {
    if (!_isRegistered()) {
      setState(() => _isCheckingOut = true);
      await _api.refreshCurrentUser();
      if (!mounted) return false;
      setState(() => _isCheckingOut = false);
    }
    if (_isRegistered()) return true;
    await _showUnregisteredDialog();
    return false;
  }

  /// Оформление с широкого экрана: подтверждение и сразу отправка.
  Future<void> _checkoutFromPanel() async {
    if (_activeItems.isEmpty) return;
    if (!await _ensureRegistered()) return;
    if (!mounted) return;
    if (await _confirmOrder(context)) {
      await _submitOrder();
    }
  }

  Future<void> _showMobileCheckoutSheet() async {
    if (_activeItems.isEmpty) return;
    // Незарегистрированным (нет guid_partner1c) — предупреждение вместо оформления.
    if (!await _ensureRegistered()) return;
    if (!mounted) return;
    FocusScope.of(context).unfocus();

    // Лист возвращает true, когда клиент подтвердил заказ. Отправляем уже ПОСЛЕ
    // закрытия листа, чтобы окно с итогом ничем не перекрывалось и не закрывалось.
    final confirmed = await showModalBottomSheet<bool>(
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
                                final ok = await _confirmOrder(sheetContext);
                                if (ok && sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop(true);
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

    if (confirmed == true && mounted) {
      await _submitOrder();
    }
  }

  // Зарегистрирован ли контрагент в 1С (есть guid_partner1c).
  bool _isRegistered() => currentUser?.userProfile.isRegistered ?? false;

  Future<void> _showUnregisteredDialog({String? message}) async {
    final notice = (currentUser?.support.unregisteredNotice.trim() ?? '');
    final serverText = message?.trim() ?? '';
    final text = serverText.isNotEmpty
        ? serverText
        : notice.isNotEmpty
        ? notice
        : 'Ваш аккаунт ещё не подтверждён. Оформление заказа станет доступно после регистрации у менеджера.';
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFFD97706),
                  size: 38,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Требуется регистрация',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Понятно',
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

  /// Окно «Подтвердить заказ?». Только спрашивает, сам заказ не отправляет.
  Future<bool> _confirmOrder(BuildContext dialogParent) async {
    // Дату доставки и способ оплаты НЕ требуем — оформляем сразу.
    final confirmed = await showDialog<bool>(
      context: dialogParent,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.shopping_bag_rounded,
                    color: Color(0xFF2563EB),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Подтвердить заказ?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Позиций: $_totalItems   •   ${formatPrice(_finalPrice)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Отмена',
                          style: TextStyle(
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Подтвердить',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    return confirmed == true;
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

  Future<void> _showSuccessDialog(OrderSubmitResult result) {
    final date = formatDateTime(result.createdAt);
    return _showResultDialog(
      icon: Icons.check_rounded,
      iconColor: const Color(0xFF16A34A),
      iconBackground: const Color(0xFFDCFCE7),
      title: 'Заказ успешно отправлен',
      message:
          'Заказ передан менеджеру. Статус можно отслеживать в разделе «Мои заказы».',
      highlightLabel: 'НОМЕР ЗАКАЗА',
      highlightValue: result.orderNumber ?? '',
      highlightCaption: date.isEmpty ? null : 'от $date',
      primaryLabel: 'Продолжить покупки',
      onPrimary: (dialogContext) {
        Navigator.of(dialogContext).pop();
        // Корзина пуста — возвращаемся в каталог, чтобы сразу продолжить заказ.
        context.go('/');
      },
      secondaryLabel: 'Мои заказы',
      onSecondary: (dialogContext) {
        Navigator.of(dialogContext).pop();
        context.go('/orders');
      },
    );
  }

  /// Единое окно итога: успех или ошибка. Закрывается только кнопками — итог
  /// заказа нельзя пропустить случайным тапом мимо окна.
  Future<void> _showResultDialog({
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
    required String title,
    required String message,
    required String primaryLabel,
    required void Function(BuildContext dialogContext) onPrimary,
    String? highlightLabel,
    String? highlightValue,
    String? highlightCaption,
    String? secondaryLabel,
    void Function(BuildContext dialogContext)? onSecondary,
  }) {
    return showDialog<void>(
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
                      color: iconBackground,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(icon, color: iconColor, size: 38),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  if (highlightValue != null && highlightValue.isNotEmpty) ...[
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
                          if (highlightLabel != null)
                            Text(
                              highlightLabel,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          const SizedBox(height: 6),
                          SelectableText(
                            highlightValue,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF2563EB),
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (highlightCaption != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              highlightCaption,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => onPrimary(dialogContext),
                      child: Text(
                        primaryLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  if (secondaryLabel != null && onSecondary != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: TextButton(
                        onPressed: () => onSecondary(dialogContext),
                        child: Text(
                          secondaryLabel,
                          style: const TextStyle(
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
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
    return _activeItems.fold<double>(
      0,
      (sum, item) => sum + item.totalWithItem,
    );
  }

  /// Позиций в заказе — строк корзины. «5 коробок» и «3 шт» одного товара — две позиции.
  int get _totalItems => _activeItems.length;

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

  /// Строка корзины или, пока идёт окно отмены, плашка «Удалено · Отменить» на её месте.
  Widget _buildLine(CartItem item, {bool wide = false}) {
    final pending = _pendingRemovals.containsKey(item);
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topCenter,
      child: pending
          ? _RemovedLineStrip(
              key: ValueKey('removed-${item.lineKey}'),
              item: item,
              duration: _undoRemovalWindow,
              onUndo: () => _undoRemoval(item),
            )
          : _CartItemCard(
              key: ValueKey('line-${item.lineKey}'),
              item: item,
              wide: wide,
              onDecrease: () =>
                  _changeQuantity(item, item.quantity - item.step),
              onIncrease: () =>
                  _changeQuantity(item, item.quantity + item.step),
              // В поле клиент вводит количество в выбранной единице.
              onQuantityChanged: (value) =>
                  _changeQuantity(item, value * item.step),
              onRemove: () => _scheduleRemoval(item),
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
            itemBuilder: (context, index) => _buildLine(_cartItems[index]),
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
                  itemBuilder: (context, index) =>
                      _buildLine(_cartItems[index], wide: true),
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
                  onCheckout: _checkoutFromPanel,
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
    super.key,
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
                // Цена за единицу ЭТОЙ строки: за коробку — цена базовой единицы × вместимость.
                Text(
                  '${formatPrice(item.unitPrice)} / ${item.unitLabel}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
                // Строка коробками: поясняем, сколько это базовых единиц и почём базовая.
                if (item.package != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${item.package!.name} = '
                      '${formatNumber(item.package!.quantity)} ${item.product.unit}'
                      ' · итого ${formatNumber(item.quantity)} ${item.product.unit}'
                      ' · ${formatPrice(item.product.price)} / ${item.product.unit}',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                      ),
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
                      quantity: item.displayQuantity,
                      unit: item.unitLabel,
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

/// Плашка на месте удалённой строки: кнопка «Отменить» и полоска оставшегося времени.
class _RemovedLineStrip extends StatelessWidget {
  final CartItem item;
  final Duration duration;
  final VoidCallback onUndo;

  const _RemovedLineStrip({
    super.key,
    required this.item,
    required this.duration,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${item.product.name} · '
                    '${formatNumber(item.displayQuantity)} ${item.unitLabel} удалено',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onUndo,
                  child: const Text(
                    'Отменить',
                    style: TextStyle(
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Полоска тает за время окна отмены — видно, сколько ещё можно вернуть строку.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 1, end: 0),
            duration: duration,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 3,
              backgroundColor: Colors.transparent,
              color: const Color(0xFF2563EB),
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
    _controller = TextEditingController(text: _formatQuantity(widget.quantity));
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
            ? Border.all(color: const Color(0xFF2563EB), width: 1.2)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QuantityButton(icon: Icons.remove_rounded, onTap: widget.onDecrease),
          GestureDetector(
            onTap: _startEditing,
            behavior: HitTestBehavior.opaque,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 66, maxWidth: 110),
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
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
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
          _QuantityButton(icon: Icons.add_rounded, onTap: widget.onIncrease),
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
        // Больше отступ снизу, чтобы подвал не прятался за рамкой/жестами телефона.
        minimum: const EdgeInsets.only(bottom: 24),
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
