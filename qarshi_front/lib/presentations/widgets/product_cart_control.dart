import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qarshi/core/data/models.dart';

/// Кнопка «В корзину» / счётчик количества с ручным вводом.
///
/// Один и тот же элемент используется и в карточке каталога, и на экране товара,
/// поэтому логика ввода количества живёт здесь, а не в конкретном экране.
class ProductCartControl extends StatefulWidget {
  final Product product;
  final num quantity;
  final ValueChanged<num> onQuantityChanged;

  /// Компактный размер для сетки каталога; false — крупный для экрана товара.
  final bool dense;

  const ProductCartControl({
    super.key,
    required this.product,
    required this.quantity,
    required this.onQuantityChanged,
    this.dense = true,
  });

  @override
  State<ProductCartControl> createState() => _ProductCartControlState();
}

class _ProductCartControlState extends State<ProductCartControl> {
  late final TextEditingController _quantityController;
  late final FocusNode _quantityFocusNode;

  bool _isEditingQuantity = false;

  @override
  void initState() {
    super.initState();

    _quantityController = TextEditingController(
      text: formatQuantity(widget.quantity),
    );

    _quantityFocusNode = FocusNode();
    _quantityFocusNode.addListener(_handleQuantityFocus);
  }

  @override
  void didUpdateWidget(covariant ProductCartControl oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_quantityFocusNode.hasFocus && oldWidget.quantity != widget.quantity) {
      _quantityController.text = formatQuantity(widget.quantity);
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
      _quantityController.text = formatQuantity(widget.quantity);
      return;
    }

    final num value;

    if (parsed is double && parsed == parsed.roundToDouble()) {
      value = parsed.toInt();
    } else {
      value = parsed;
    }

    _quantityController.text = formatQuantity(value);
    widget.onQuantityChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final quantity = widget.quantity;
    final height = widget.dense ? 36.0 : 48.0;

    return SizedBox(
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
              onPressed: () => widget.onQuantityChanged(1),
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
                    onPressed: () => widget.onQuantityChanged(quantity - 1),
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
                                '${formatQuantity(quantity)} '
                                '${widget.product.unit}',
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
                    onPressed: () => widget.onQuantityChanged(quantity + 1),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Целое количество показываем без «.0» — «3 шт», а не «3.0 шт».
String formatQuantity(num value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }

  return value.toString();
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
        icon: Icon(
          icon,
          size: dense ? 17 : 21,
          color: const Color(0xFF334155),
        ),
      ),
    );
  }
}
