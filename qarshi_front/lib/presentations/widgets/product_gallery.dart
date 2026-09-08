import 'package:flutter/material.dart';

/// Галерея картинок товара: листается свайпом, точки-индикаторы снизу,
/// на широком экране — стрелки влево/вправо.
///
/// Используется и в карточке каталога (компактно, без стрелок),
/// и на экране товара (крупно, со стрелками).
class ProductGallery extends StatefulWidget {
  final List<String> images;

  /// Показывать стрелки перелистывания (для мыши на десктопе).
  final bool showArrows;

  /// Нажатие по картинке — например, открыть карточку товара.
  final VoidCallback? onTap;

  const ProductGallery({
    super.key,
    required this.images,
    this.showArrows = false,
    this.onTap,
  });

  @override
  State<ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends State<ProductGallery> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int target) {
    if (target < 0 || target >= widget.images.length) return;
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;

    if (images.isEmpty) {
      return GestureDetector(
        onTap: widget.onTap,
        child: const ColoredBox(
          color: Color(0xFFF8FAFC),
          child: Center(
            child: Icon(Icons.image_not_supported_rounded, color: Colors.grey),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: ColoredBox(
        color: const Color(0xFFF8FAFC),
        child: Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                controller: _controller,
                // Одна картинка не листается — лишний скролл только мешает жестам списка.
                physics: images.length > 1
                    ? const PageScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                itemCount: images.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) {
                  return Image.network(
                    images[index],
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.image_not_supported_rounded,
                        color: Colors.grey,
                      ),
                    ),
                  );
                },
              ),
            ),
            if (images.length > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(images.length, (i) {
                    final active = i == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF2563EB)
                            : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
            if (widget.showArrows && images.length > 1) ...[
              Positioned(
                left: 4,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _GalleryArrow(
                    icon: Icons.chevron_left_rounded,
                    onPressed: () => _goTo(_index - 1),
                  ),
                ),
              ),
              Positioned(
                right: 4,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _GalleryArrow(
                    icon: Icons.chevron_right_rounded,
                    onPressed: () => _goTo(_index + 1),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GalleryArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _GalleryArrow({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.85),
      shape: const CircleBorder(),
      elevation: 1,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 24, color: const Color(0xFF334155)),
        ),
      ),
    );
  }
}
