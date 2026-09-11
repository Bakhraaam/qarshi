import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qarshi/core/data/models.dart';
import 'package:qarshi/core/utils/formatters.dart';

/// Кнопка «В корзину» / счётчик количества с ручным вводом.
///
/// Один и тот же элемент используется и в карточке каталога, и на экране товара,
/// поэтому логика ввода количества живёт здесь, а не в конкретном экране.
///
/// Если у товара есть упаковки (блок, коробка), над счётчиком появляется выбор
/// единицы. Наружу количество ВСЕГДА уходит в базовых единицах товара: цена в
/// прайсе за базовую единицу, и бэкенд хранит корзину так же. Упаковка меняет
/// только шаг счётчика и подпись.
class ProductCartControl extends StatefulWidget {
  final Product product;

  /// Количество в базовых единицах товара.
  final num quantity;

  /// Новое количество — тоже в базовых единицах.
  final ValueChanged<num> onQuantityChanged;

  /// Выбранная упаковка (null — базовая единица).
  final String? packageId;

  /// Клиент переключил единицу. Приходит новый id упаковки и пересчитанное
  /// количество в базовых единицах.
  final void Function(String? packageId, num quantity)? onPackageChanged;

  /// Компактный размер для сетки каталога; false — крупный для экрана товара.
  final bool dense;

  const ProductCartControl({
    super.key,
    required this.product,
    required this.quantity,
    required this.onQuantityChanged,
    this.packageId,
    this.onPackageChanged,
    this.dense = true,
  });

  @override
  State<ProductCartControl> createState() => _ProductCartControlState();
}

class _ProductCartControlState extends State<ProductCartControl> {
  late final TextEditingController _quantityController;
  late final FocusNode _quantityFocusNode;

  bool _isEditingQuantity = false;

  /// Упаковка, выбранная клиентом. Пока родитель не хранит выбор сам
  /// (экран товара), держим его здесь.
  String? _packageId;

  ItemPackage? get _package => widget.product.packageById(_packageId);

  /// Сколько базовых единиц в одном шаге счётчика.
  num get _step => _package?.quantity ?? 1;

  /// Количество в выбранной единице: 20 шт при коробке по 10 — это 2 коробки.
  num get _displayQuantity => widget.quantity / _step;

  String get _unitLabel => _package?.name ?? widget.product.unit;

  @override
  void initState() {
    super.initState();

    // Выбор из корзины важнее: он говорит, чем клиент уже набирал эту позицию.
    _packageId = widget.packageId ?? widget.product.defaultPackage?.id;

    _quantityController = TextEditingController(
      text: formatNumber(_displayQuantity),
    );

    _quantityFocusNode = FocusNode();
    _quantityFocusNode.addListener(_handleQuantityFocus);
  }

  @override
  void didUpdateWidget(covariant ProductCartControl oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.packageId != oldWidget.packageId && widget.packageId != null) {
      _packageId = widget.packageId;
    }

    if (!_quantityFocusNode.hasFocus && oldWidget.quantity != widget.quantity) {
      _quantityController.text = formatNumber(_displayQuantity);
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
      _quantityController.text = formatNumber(_displayQuantity);
      return;
    }

    // В поле клиент вводит количество в ВЫБРАННОЙ единице, наружу отдаём базовые.
    final value = _normalize(parsed * _step);

    _quantityController.text = formatNumber(value / _step);
    widget.onQuantityChanged(value);
  }

  /// Убираем «.0» у целых, чтобы 3.0000000000000004 не утекало в запрос.
  num _normalize(num value) {
    final rounded = num.parse(value.toStringAsFixed(3));
    if (rounded == rounded.roundToDouble()) return rounded.toInt();
    return rounded;
  }

  void _changeBy(int steps) {
    final next = _normalize(widget.quantity + _step * steps);
    widget.onQuantityChanged(next < 0 ? 0 : next);
  }

  void _selectPackage(String? packageId) {
    if (packageId == _packageId) return;

    final package = widget.product.packageById(packageId);
    final ratio = package?.quantity ?? 1;

    // Дробные упаковки не показываем: набранное количество округляем ВВЕРХ до
    // целого числа новых единиц, иначе после переключения появлялось «0.5 коробки».
    num quantity = widget.quantity;
    if (quantity > 0) {
      quantity = _normalize((quantity / ratio).ceil() * ratio);
    }

    setState(() => _packageId = packageId);

    if (widget.onPackageChanged != null) {
      widget.onPackageChanged!(packageId, quantity);
    } else if (quantity != widget.quantity) {
      widget.onQuantityChanged(quantity);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quantity = widget.quantity;
    final height = widget.dense ? 36.0 : 48.0;

    final counter = SizedBox(
      width: double.infinity,
      height: height,
      child: quantity == 0
          ? ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(widget.dense ? 8 : 12),
                ),
              ),
              // Первое нажатие кладёт ровно одну выбранную единицу — одну штуку
              // или одну коробку.
              onPressed: () => widget.onQuantityChanged(_normalize(_step)),
              child: Text(
                'В корзину',
                style: TextStyle(
                  fontSize: widget.dense ? 11 : 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(widget.dense ? 8 : 12),
                border: _isEditingQuantity
                    ? Border.all(color: const Color(0xFF2563EB), width: 1.2)
                    : null,
              ),
              child: Row(
                children: [
                  _CounterButton(
                    icon: Icons.remove,
                    dense: widget.dense,
                    onPressed: () => _changeBy(-1),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _startQuantityEditing,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
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
                                textInputAction: TextInputAction.done,
                                style: TextStyle(
                                  fontSize: widget.dense ? 13 : 16,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF0F172A),
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
                                '${formatNumber(_displayQuantity)} $_unitLabel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: widget.dense ? 12 : 16,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                      ),
                    ),
                  ),
                  _CounterButton(
                    icon: Icons.add,
                    dense: widget.dense,
                    onPressed: () => _changeBy(1),
                  ),
                ],
              ),
            ),
    );

    if (widget.product.packages.isEmpty) return counter;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PackageSelector(
          product: widget.product,
          packageId: _packageId,
          dense: widget.dense,
          onChanged: _selectPackage,
        ),
        SizedBox(height: widget.dense ? 6 : 10),
        counter,
      ],
    );
  }
}

/// Выбор единицы товара: базовая (шт, л) и упаковки из 1С (блок, коробка).
///
/// Цена не зависит от выбора — она всегда за базовую единицу. Выбор влияет
/// только на то, чем клиент набирает количество.
class PackageSelector extends StatelessWidget {
  final Product product;
  final String? packageId;
  final ValueChanged<String?> onChanged;
  final bool dense;

  const PackageSelector({
    super.key,
    required this.product,
    required this.packageId,
    required this.onChanged,
    this.dense = true,
  });

  /// Подпись упаковки с её вместимостью: «Коробка · 10 шт».
  static String label(Product product, ItemPackage? package) {
    if (package == null) return product.unit.isEmpty ? 'ед.' : product.unit;
    final unit = product.unit.isEmpty ? '' : ' ${product.unit}';
    return '${package.name} · ${formatNumber(package.quantity)}$unit';
  }

  @override
  Widget build(BuildContext context) {
    if (product.packages.isEmpty) return const SizedBox.shrink();

    final selected = product.packageById(packageId);

    return Container(
      height: dense ? 28 : 40,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: selected?.id,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(8),
          padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 12),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: dense ? 16 : 20,
            color: const Color(0xFF64748B),
          ),
          style: TextStyle(
            fontSize: dense ? 11 : 14,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
          // Фон делаем отдельно: DropdownButton сам по себе прозрачный.
          dropdownColor: Colors.white,
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                label(product, null),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final package in product.packages)
              DropdownMenuItem<String?>(
                value: package.id,
                child: Text(
                  label(product, package),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  final IconData icon;
  final bool dense;
  final VoidCallback onPressed;

  const _CounterButton({
    required this.icon,
    required this.onPressed,
    this.dense = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: dense ? 38 : 48,
      height: dense ? 34 : 46,
      child: IconButton(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: dense ? 17 : 21, color: const Color(0xFF334155)),
      ),
    );
  }
}
