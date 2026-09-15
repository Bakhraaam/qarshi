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
/// единицы. Каждая единица — отдельная строка корзины: переключив «Коробка» на
/// «шт», клиент видит количество строки штук или кнопку «В корзину», если штуками
/// товар ещё не брали. Выбранную единицу хранит родитель ([package]), потому что
/// от неё зависит и цена в карточке.
///
/// Наружу количество ВСЕГДА уходит в базовых единицах товара: цена в прайсе за
/// базовую единицу, и бэкенд хранит корзину так же.
class ProductCartControl extends StatefulWidget {
  final Product product;

  /// Выбранная единица (null — базовая).
  final ItemPackage? package;

  /// Количество строки выбранной единицы в базовых единицах (0 — строки нет).
  final num quantity;

  /// Новое количество строки выбранной единицы — тоже в базовых единицах.
  final ValueChanged<num> onQuantityChanged;

  /// Клиент переключил единицу. Корзину это не меняет.
  final ValueChanged<ItemPackage?>? onPackageChanged;

  /// Компактный размер для сетки каталога; false — крупный для экрана товара.
  final bool dense;

  const ProductCartControl({
    super.key,
    required this.product,
    required this.quantity,
    required this.onQuantityChanged,
    this.package,
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

  /// Сколько базовых единиц в одном шаге счётчика.
  num get _step => widget.package?.quantity ?? 1;

  /// Количество в выбранной единице: 50 шт при коробке по 10 — это 5 коробок.
  num get _displayQuantity => widget.quantity / _step;

  String get _unitLabel => widget.product.unitLabelFor(widget.package);

  @override
  void initState() {
    super.initState();

    _quantityController = TextEditingController(
      text: formatNumber(_displayQuantity),
    );

    _quantityFocusNode = FocusNode();
    _quantityFocusNode.addListener(_handleQuantityFocus);
  }

  @override
  void didUpdateWidget(covariant ProductCartControl oldWidget) {
    super.didUpdateWidget(oldWidget);

    final unitChanged = oldWidget.package?.id != widget.package?.id;
    if (unitChanged && _quantityFocusNode.hasFocus) {
      // Сменили единицу посреди ввода — недописанное число к новой строке не относится.
      _quantityFocusNode.unfocus();
    }
    if (unitChanged || oldWidget.quantity != widget.quantity) {
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
          package: widget.package,
          dense: widget.dense,
          onChanged: (package) => widget.onPackageChanged?.call(package),
        ),
        SizedBox(height: widget.dense ? 6 : 10),
        counter,
      ],
    );
  }
}

/// Выбор единицы товара: базовая (шт, л) и упаковки из 1С (блок, коробка).
///
/// Выбор меняет цену в карточке (за коробку она больше) и строку корзины, которую
/// показывает счётчик. В прайсе цена по-прежнему за базовую единицу.
class PackageSelector extends StatelessWidget {
  final Product product;
  final ItemPackage? package;
  final ValueChanged<ItemPackage?> onChanged;
  final bool dense;

  const PackageSelector({
    super.key,
    required this.product,
    required this.package,
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

    // Значение списка — id упаковки; '' — базовая единица. null в DropdownButton
    // означал бы «ничего не выбрано», а базовая единица — полноценный вариант.
    final value = package == null ? '' : package!.id;

    return Container(
      height: dense ? 28 : 40,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
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
          dropdownColor: Colors.white,
          items: [
            DropdownMenuItem<String>(
              value: '',
              child: Text(
                label(product, null),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final item in product.packages)
              DropdownMenuItem<String>(
                value: item.id,
                child: Text(
                  label(product, item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) {
            if (id == null) return;
            onChanged(id.isEmpty ? null : product.packageById(id));
          },
        ),
      ),
    );
  }
}

/// Цена за выбранную единицу с подписью единицы: «120 USD / Коробка».
///
/// Одна строка на карточку каталога и экран товара, чтобы цена везде считалась
/// одинаково: цена базовой единицы из прайса, умноженная на вместимость упаковки.
class UnitPriceText extends StatelessWidget {
  final Product product;
  final ItemPackage? package;
  final double fontSize;

  const UnitPriceText({
    super.key,
    required this.product,
    required this.package,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final unit = product.unitLabelFor(package);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: formatPrice(product.priceFor(package))),
          if (unit.isNotEmpty)
            TextSpan(
              text: ' / $unit',
              style: TextStyle(
                fontSize: fontSize * 0.62,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        color: const Color(0xFF0F172A),
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
