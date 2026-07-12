import 'dart:js_interop' as js;
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qarshi/core/data/api/api_django.dart';
import 'package:qarshi/core/data/constants.dart';
import 'package:qarshi/core/data/models.dart';
import 'package:qarshi/core/utils/formatters.dart';
import 'package:qarshi/presentations/screens/catalog_screen.dart';
import 'package:qarshi/presentations/screens/catalog_screen_responsive.dart';
import 'package:qarshi/presentations/screens/reconciliation_report_screen.dart';

@js.JS('window')
external js.JSObject get _window;

extension WindowExtension on js.JSObject {
  @js.JS('open')
  external js.JSObject? open(js.JSString url, js.JSString target);
}

// Открыть внешнюю ссылку (Instagram и т.п.) новой вкладкой.
void openExternalUrl(String url) {
  if (url.isEmpty || !kIsWeb) return;
  _window.open(url.toJS, '_blank'.toJS);
}

// Позвонить по номеру телефона.
void callPhoneNumber(String phone) {
  final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
  if (clean.isEmpty || !kIsWeb) return;
  _window.open('tel:$clean'.toJS, '_self'.toJS);
}

// Нормализуем instagram: полный URL / @username / username -> валидный URL.
String instagramUrl(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return '';
  if (v.startsWith('http://') || v.startsWith('https://')) return v;
  final handle = v.replaceAll('@', '').trim();
  return 'https://instagram.com/$handle';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DjangoApi _api = DjangoApi();
  Map<String, num> cartQuantities = {};

  double _cartTotalSum = 0;
  List<ProductCategory> _categories = const [];
  bool _isLoading = true;
  int _selectedSection = 0;

  @override
  void initState() {
    super.initState();
    _loadHomeData();
  }

  Future<void> _loadHomeData() async {
    try {
      final results = await Future.wait([_api.getCart(), _api.getCategories()]);

      final cartItems = results[0] as List<CartItem>;
      final categories = results[1] as List<ProductCategory>;

      if (!mounted) return;
      setState(() {
        _cartTotalSum = cartItems.fold<double>(
          0,
          (sum, item) => sum + item.product.price * item.quantity,
        );
        _categories = categories;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Ошибка загрузки главной страницы: $error');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _openSupport() {
    final tgUsername = currentUser?.support.tgUsername;
    final phone = currentUser?.support.phone;

    if (tgUsername != null && tgUsername.trim().isNotEmpty) {
      final username = tgUsername.replaceAll('@', '').trim();
      if (kIsWeb) {
        _window.open('https://t.me/$username'.toJS, '_blank'.toJS);
      }
      return;
    }

    if (phone != null && phone.trim().isNotEmpty) {
      final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
      if (kIsWeb) {
        _window.open('tel:$cleanPhone'.toJS, '_self'.toJS);
      }
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Контакты службы поддержки не указаны')),
    );
  }

  void _openSection(int index) {
    if (index == 2) {
      _openSupport();
      return;
    }

    setState(() => _selectedSection = index);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width < 720) {
          return _MobileHome(
            isLoading: _isLoading,
            categories: _categories,
            cartTotalSum: _cartTotalSum,
            onSupportTap: _openSupport,
            cartQuantities: cartQuantities,
          );
        }

        return _WideHome(
          compact: width < 1050,
          selectedSection: _selectedSection,
          cartTotalSum: _cartTotalSum,
          onSectionChanged: _openSection,
        );
      },
    );
  }
}

class _MobileHome extends StatelessWidget {
  final bool isLoading;
  final List<ProductCategory> categories;
  final double cartTotalSum;
  final VoidCallback onSupportTap;
  Map<String, num> cartQuantities = {};

  _MobileHome({
    required this.isLoading,
    required this.categories,
    required this.cartTotalSum,
    required this.onSupportTap,
    required this.cartQuantities,
  });
  Widget _drawer(context) {
    return Drawer(
      // Меняем дефолтный серый цвет Drawer на чистый белый или глубокий темный,
      // в зависимости от вашей темы. Для светлой темы лучше чистый белый:
      backgroundColor: Colors.white,
      surfaceTintColor: Colors
          .transparent, // Отключаем дефолтный фиолетовый оттенок Flutter 3
      child: SafeArea(
        child: Column(
          children: [
            // --- ШАПКА ДРОЕРА ---
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: _AccountHeader(),
            ),

            const Divider(
              height: 1,
              thickness: 1,
              color: Color(0xFFF1F5F9), // Более мягкий цвет разделителя
            ),
            const SizedBox(height: 16),

            // --- ОСНОВНЫЕ КНОПКИ МЕНЮ ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    // Мягкий сине-голубой фон (светлый пастельный)
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  // Контрастная иконка глубокого синего цвета
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: Color(0xFF0369A1),
                  ),
                ),
                title: const Text(
                  'Акт-сверка',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(
                      0xFF1E293B,
                    ), // Уверенно темный, но не чисто черный
                  ),
                ),
                onTap: () {
                  // Захватываем роутер ДО pop: после закрытия Drawer контекст
                  // ListTile деактивируется и context.push по нему не срабатывает.
                  final router = GoRouter.of(context);
                  Navigator.pop(context);
                  router.push('/reports');
                },
              ),
            ),

            const SizedBox(height: 4), // Небольшой отступ между элементами

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    // Мягкий фиолетово-лавандовый фон
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  // Контрастная иконка глубокого фиолетового цвета
                  child: const Icon(
                    Icons.shopping_bag_rounded,
                    color: Color(0xFF0369A1),
                  ),
                ),
                title: const Text(
                  'Заказы',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                onTap: () {
                  // Захватываем роутер ДО pop (см. коммент выше про Акт-сверку).
                  final router = GoRouter.of(context);
                  Navigator.pop(context);
                  router.push('/orders');
                },
              ),
            ),

            // Этот виджет занимает всё оставшееся пространство
            const Spacer(),

            const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),

            // --- ПОДДЕРЖКА: НОМЕР ТЕЛЕФОНА ---
            Builder(
              builder: (context) {
                final phone = currentUser?.support.phone.trim() ?? '';
                if (phone.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.headset_mic_outlined,
                        color: Color(0xFF0369A1),
                      ),
                    ),
                    title: Text(
                      phone,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                    onTap: () => callPhoneNumber(phone),
                  ),
                );
              },
            ),

            // --- INSTAGRAM (в самом низу) ---
            Builder(
              builder: (context) {
                final ig = currentUser?.support.instagram.trim() ?? '';
                if (ig.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFCE7F3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.camera_alt_outlined,
                        color: Color(0xFFDB2777),
                      ),
                    ),
                    title: const Text(
                      'Instagram',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                    onTap: () => openExternalUrl(instagramUrl(ig)),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _drawer(context),
      appBar: AppBar(
        title: Text('Каталог товаров'),
        actions: [
          ValueListenableBuilder<Map<String, num>>(
            valueListenable: cartNotifier,
            builder: (context, quantities, _) {
              return IconButton(
                icon: Badge(
                  label: Text('${quantities.length}'),
                  isLabelVisible: quantities.isNotEmpty,
                  backgroundColor: const Color(0xFF2563EB),
                  child: const Icon(
                    Icons.shopping_cart,
                    color: Color(0xFF0F172A),
                  ),
                ),
                onPressed: () => context.push('/cart'),
              );
            },
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF6F8FC),
      body: SafeArea(
        child: Stack(
          children: [
            CatalogScreen(embedded: true),
            // CustomScrollView(
            //   slivers: [
            //     if (cartTotalSum > 0)
            //       Positioned(
            //         left: 16,
            //         right: 16,
            //         bottom: 14,
            //         child: _CartBar(totalSum: cartTotalSum),
            //       ),
            //     // SliverPadding(
            //     //   padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            //     //   sliver: SliverToBoxAdapter(
            //     //     child: _AccountHeader(
            //     //       onCartTap: () => context.push('/cart'),
            //     //     ),
            //     //   ),
            //     // ),
            //     const SliverToBoxAdapter(child: SizedBox(height: 20)),
            //     // SliverPadding(
            //     //   padding: const EdgeInsets.symmetric(horizontal: 16),
            //     //   sliver: SliverToBoxAdapter(
            //     //     child: _PrimaryCatalogCard(
            //     //       onTap: () => context.push('/catalog'),
            //     //     ),
            //     //   ),
            //     // ),
            //     // const SliverToBoxAdapter(child: SizedBox(height: 22)),
            //     // const SliverPadding(
            //     //   padding: EdgeInsets.symmetric(horizontal: 16),
            //     //   sliver: SliverToBoxAdapter(
            //     //     child: _SectionTitle(title: 'Разделы'),
            //     //   ),
            //     // ),
            //     // const SliverToBoxAdapter(child: SizedBox(height: 10)),
            //     // SliverPadding(
            //     //   padding: const EdgeInsets.symmetric(horizontal: 16),
            //     //   sliver: SliverToBoxAdapter(
            //     //     child: _MobileSections(onSupportTap: onSupportTap),
            //     //   ),
            //     // ),
            //     // const SliverToBoxAdapter(child: SizedBox(height: 24)),
            //     // SliverPadding(
            //     //   padding: const EdgeInsets.symmetric(horizontal: 16),
            //     //   sliver: SliverToBoxAdapter(
            //     //     child: Row(
            //     //       children: [
            //     //         const Expanded(
            //     //           child: _SectionTitle(title: 'Категории товаров'),
            //     //         ),
            //     //         TextButton(
            //     //           onPressed: () => context.push('/catalog'),
            //     //           child: const Text('Все'),
            //     //         ),
            //     //       ],
            //     //     ),
            //     //   ),
            //     // ),
            //     SliverPadding(
            //       padding: EdgeInsets.fromLTRB(
            //         16,
            //         4,
            //         16,
            //         cartTotalSum > 0 ? 110 : 24,
            //       ),
            //       sliver: isLoading
            //           ? const SliverToBoxAdapter(
            //               child: Padding(
            //                 padding: EdgeInsets.all(40),
            //                 child: Center(child: CircularProgressIndicator()),
            //               ),
            //             )
            //           : categories.isEmpty
            //           ? const SliverToBoxAdapter(child: _EmptyCategories())
            //           : SliverGrid.builder(
            //               itemCount: categories.length,
            //               gridDelegate:
            //                   const SliverGridDelegateWithFixedCrossAxisCount(
            //                     crossAxisCount: 2,
            //                     crossAxisSpacing: 10,
            //                     mainAxisSpacing: 10,
            //                     mainAxisExtent: 74,
            //                   ),
            //               itemBuilder: (context, index) {
            //                 final category = categories[index];
            //                 return _CategoryTile(
            //                   category: category,
            //                   onTap: () =>
            //                       context.push('/catalog', extra: category.id),
            //                 );
            //               },
            //             ),
            //     ),
            //   ],
            // ),
            // if (cartTotalSum > 0)
            //   Positioned(
            //     left: 16,
            //     right: 16,
            //     bottom: 14,
            //     child: _CartBar(totalSum: cartTotalSum),
            //   ),
          ],
        ),
      ),
    );
  }
}

class _WideHome extends StatelessWidget {
  final bool compact;
  final int selectedSection;
  final double cartTotalSum;
  final ValueChanged<int> onSectionChanged;

  const _WideHome({
    required this.compact,
    required this.selectedSection,
    required this.cartTotalSum,
    required this.onSectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      body: SafeArea(
        child: Row(
          children: [
            _DesktopSidebar(
              compact: compact,
              selectedIndex: selectedSection,
              cartTotalSum: cartTotalSum,
              onChanged: onSectionChanged,
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: IndexedStack(
                index: selectedSection,
                children: const [
                  CatalogScreen(embedded: false),
                  ReconciliationReportScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  final bool compact;
  final int selectedIndex;
  final double cartTotalSum;
  final ValueChanged<int> onChanged;

  const _DesktopSidebar({
    required this.compact,
    required this.selectedIndex,
    required this.cartTotalSum,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final width = compact ? 88.0 : 250.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: width,
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 18,
        vertical: 18,
      ),
      child: Column(
        children: [
          _SidebarAccount(compact: compact),
          const SizedBox(height: 26),
          _SidebarItem(
            compact: compact,
            icon: Icons.storefront_rounded,
            title: 'Каталог товаров',
            selected: selectedIndex == 0,
            onTap: () => onChanged(0),
          ),
          const SizedBox(height: 8),
          _SidebarItem(
            compact: compact,
            icon: Icons.receipt_long_rounded,
            title: 'Акт сверки',
            selected: selectedIndex == 1,
            onTap: () => onChanged(1),
          ),
          const SizedBox(height: 8),
          // Поддержка: номер телефона (клик — звонок)
          Builder(
            builder: (context) {
              final phone = currentUser?.support.phone.trim() ?? '';
              if (phone.isEmpty) return const SizedBox.shrink();
              return _SidebarItem(
                compact: compact,
                icon: Icons.headset_mic_rounded,
                title: phone,
                selected: false,
                onTap: () => callPhoneNumber(phone),
              );
            },
          ),
          const Spacer(),
          // Instagram (в самом низу)
          Builder(
            builder: (context) {
              final ig = currentUser?.support.instagram.trim() ?? '';
              if (ig.isEmpty) return const SizedBox.shrink();
              return _SidebarItem(
                compact: compact,
                icon: Icons.camera_alt_rounded,
                title: 'Instagram',
                selected: false,
                onTap: () => openExternalUrl(instagramUrl(ig)),
              );
            },
          ),
          // if (cartTotalSum > 0)
          //   _SidebarCart(compact: compact, totalSum: cartTotalSum),
        ],
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader();

  @override
  Widget build(BuildContext context) {
    final tg = currentUser?.telegramAccount;
    String? tgLine;
    if (tg != null) {
      final uname = tg.username.trim();
      tgLine = uname.isNotEmpty ? '@$uname (${tg.id})' : '${tg.id}';
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UserAvatar(size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ваш аккаунт',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 2),
              // Имя переносится на 2 строки, а не обрезается.
              Text(
                currentUser?.getName() ?? 'Пользователь',
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                  height: 1.2,
                ),
              ),
              if (tgLine != null) ...[
                const SizedBox(height: 3),
                Text(
                  tgLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PrimaryCatalogCard extends StatelessWidget {
  final VoidCallback onTap;

  const _PrimaryCatalogCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF173B7A),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Каталог товаров',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Поиск, цены, остатки и оформление заказа',
                      style: TextStyle(
                        color: Color(0xFFD8E4FF),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              CircleAvatar(
                radius: 24,
                backgroundColor: Color(0xFF315796),
                child: Icon(Icons.arrow_forward_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// class _MobileSections extends StatelessWidget {
//   final VoidCallback onSupportTap;

//   const _MobileSections({required this.onSupportTap});

//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       children: [
//         Expanded(
//           child: _SectionButton(
//             icon: Icons.receipt_long_outlined,
//             title: 'Акт сверки',
//             onTap: () {
//               context.push('/reports');
//             },
//           ),
//         ),
//         const SizedBox(width: 10),
//         Expanded(
//           child: _SectionButton(
//             icon: Icons.support_agent_outlined,
//             title: 'Поддержка',
//             onTap: onSupportTap,
//           ),
//         ),
//       ],
//     );
//   }
// }

class _SectionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _SectionButton({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 70,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF173B7A)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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

class _CategoryTile extends StatelessWidget {
  final ProductCategory category;
  final VoidCallback onTap;

  const _CategoryTile({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF4FF),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.category_outlined,
                  color: Color(0xFF173B7A),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
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

class _SidebarAccount extends StatelessWidget {
  final bool compact;

  const _SidebarAccount({required this.compact});

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const Tooltip(message: 'Аккаунт', child: _UserAvatar(size: 44));
    }

    return Row(
      children: [
        const _UserAvatar(size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Аккаунт',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              Text(
                currentUser?.getName() ?? 'Пользователь',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final bool compact;
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.compact,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        height: 50,
        padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF4FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          mainAxisAlignment: compact
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: selected
                  ? const Color(0xFF173B7A)
                  : const Color(0xFF64748B),
            ),
            if (!compact) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? const Color(0xFF173B7A)
                        : const Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return compact ? Tooltip(message: title, child: content) : content;
  }
}

class _SidebarCart extends StatelessWidget {
  final bool compact;
  final double totalSum;

  const _SidebarCart({required this.compact, required this.totalSum});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0F172A),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => context.push('/cart'),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: compact
              ? const Icon(Icons.shopping_bag_rounded, color: Colors.white)
              : Row(
                  children: [
                    const Icon(Icons.shopping_bag_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Корзина',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            formatPrice(totalSum),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  final double totalSum;

  const _CartBar({required this.totalSum});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      color: const Color(0xFF0F172A),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => context.push('/cart'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              const Icon(Icons.shopping_bag_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Корзина',
                      style: TextStyle(color: Colors.white60, fontSize: 10),
                    ),
                    Text(
                      formatPrice(totalSum),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                'Открыть',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  final double size;

  const _UserAvatar({required this.size});

  @override
  Widget build(BuildContext context) {
    final photoUrl = currentUser?.telegramAccount?.photoUrl;
    final userName = currentUser?.getName() ?? 'U';
    final initial = userName.trim().isEmpty
        ? 'U'
        : userName.trim()[0].toUpperCase();

    if (photoUrl != null && photoUrl.trim().isNotEmpty) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              _InitialAvatar(size: size, initial: initial),
        ),
      );
    }

    return _InitialAvatar(size: size, initial: initial);
  }
}

class _InitialAvatar extends StatelessWidget {
  final double size;
  final String initial;

  const _InitialAvatar({required this.size, required this.initial});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFFE6EEFF),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * .4,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF173B7A),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Color(0xFF0F172A),
      ),
    );
  }
}

class _EmptyCategories extends StatelessWidget {
  const _EmptyCategories();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Center(
        child: Text(
          'Категории пока не загружены',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
      ),
    );
  }
}

// class _ReportsPlaceholder extends StatelessWidget {
//   const _ReportsPlaceholder();

//   @override
//   Widget build(BuildContext context) {
//     return const Center(
//       child: Text(
//         'Экран акта сверки',
//         style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
//       ),
//     );
//   }
// }
