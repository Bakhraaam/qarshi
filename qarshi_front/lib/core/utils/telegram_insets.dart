import 'package:flutter/foundation.dart';
import 'package:telegram_web_app/telegram_web_app.dart';

/// Верхний отступ, который в fullscreen-режиме занимают системные элементы
/// (нотч/статус-бар) и нативные кнопки Telegram (закрыть, «···»).
/// Прокидывается в MediaQuery.padding.top (см. main.dart), чтобы AppBar и
/// SafeArea не уходили под эти кнопки.
final ValueNotifier<double> telegramTopInset = ValueNotifier<double>(0);

/// Нижний отступ (домашний индикатор / жесты) в fullscreen Telegram.
final ValueNotifier<double> telegramBottomInset = ValueNotifier<double>(0);

bool _initialized = false;

/// Подписывается на изменения safe-area/fullscreen Telegram и держит
/// [telegramTopInset] актуальным. Безопасно вне Telegram (no-op).
void initTelegramInsets() {
  if (_initialized) return;
  _initialized = true;
  try {
    final tg = TelegramWebApp.instance;
    if (!tg.isSupported) return;

    void refresh() {
      try {
        // contentSafeAreaInset отсчитывается внутри safeAreaInset, поэтому
        // суммируем: клиренс и от нотча, и от UI-элементов Telegram.
        final top = tg.safeAreaInset.top + tg.contentSafeAreaInset.top;
        final bottom = tg.safeAreaInset.bottom + tg.contentSafeAreaInset.bottom;
        telegramTopInset.value = top.toDouble();
        telegramBottomInset.value = bottom.toDouble();
      } catch (_) {}
    }

    refresh();
    tg.onEvent(SafeAreaChangedEvent(refresh));
    tg.onEvent(ContentSafeAreaChangedEvent(refresh));
    tg.onEvent(FullscreenChangedEvent(refresh));
  } catch (_) {
    // Старые клиенты Telegram (Bot API < 8.0) — insets недоступны, не критично.
  }
}
