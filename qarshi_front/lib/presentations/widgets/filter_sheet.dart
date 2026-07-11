import 'package:flutter/material.dart';
import 'package:qarshi/core/data/constants.dart';
import 'package:qarshi/core/data/models.dart';

class FilterSheet extends StatefulWidget {
  final List<ProductCategory> categories;
  final String? initialCategoryId;
  final double? initialMinPrice;
  final double? initialMaxPrice;

  const FilterSheet({
    super.key,
    required this.categories,
    this.initialCategoryId,
    this.initialMinPrice,
    this.initialMaxPrice,
  });

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  String? _selectedCategoryId;
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.initialCategoryId;
    if (widget.initialMinPrice != null) {
      _minPriceController.text = widget.initialMinPrice!.toStringAsFixed(0);
    }
    if (widget.initialMaxPrice != null) {
      _maxPriceController.text = widget.initialMaxPrice!.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Автоматический отступ, если открыта экранная клавиатура на мобилке
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Фильтры',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () {
                    // Сбросить всё
                    setState(() {
                      _selectedCategoryId = null;
                      _minPriceController.clear();
                      _maxPriceController.clear();
                    });
                  },
                  child: const Text('Сбросить'),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 15),

            // 1. Фильтр Цены
            Text(
              'Цена (${currentUser!.userProfile.priceType.currency})',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minPriceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'От',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: TextField(
                    controller: _maxPriceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'До',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),

            // 2. Выбор категории (Выпадающий список Dropdown — идеален, когда позиций > 100)
            const Text(
              'Категория товара',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _selectedCategoryId,
              hint: const Text('Выберите категорию'),
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: widget.categories.map((category) {
                return DropdownMenuItem<String>(
                  value: category.id,
                  child: Text(category.name, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedCategoryId = value);
              },
            ),
            const SizedBox(height: 30),

            // Кнопка Применить
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  final double? minPrice = double.tryParse(
                    _minPriceController.text,
                  );
                  final double? maxPrice = double.tryParse(
                    _maxPriceController.text,
                  );

                  // Возвращаем объект Map с результатами обратно в CatalogScreen
                  Navigator.pop(context, {
                    'category': _selectedCategoryId,
                    'minPrice': minPrice,
                    'maxPrice': maxPrice,
                  });
                },
                child: const Text(
                  'Применить фильтры',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
