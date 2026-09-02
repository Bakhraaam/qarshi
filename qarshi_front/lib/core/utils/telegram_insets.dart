import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:telegram_web_app/telegram_web_app.dart';
// Условный импорт: на web — package:web (совместим с --wasm), на остальных
// платформах — заглушка, чтобы сборка под мобилки/десктоп не падала.
import 'host/host_stub.dart' if (dart.library.js_interop) 'host/host_web.dart';

/// Верхний отступ, который в fullscreen-режиме занимают системные элементы
/// (нотч/статус-бар) и нативные кнопки Telegram (закрыть, «···»).
/// Прокидывается в MediaQuery.padding.top (см. main.dart), чтобы AppBar и
/// SafeArea не уходили под эти кнопки.
final ValueNotifier<double> telegramTopInset = ValueNotifier<double>(0);

/// Нижний отступ (домашний индикатор / жесты) в fullscreen Telegram.
final ValueNotifier<double> telegramBottomInset = ValueNotifier<double>(0);

bool _initialized = false;

/// Задержки, на которых повторяем пересчёт размера после изменения вьюпорта.
/// Анимация разворачивания в клиентах Telegram длится до ~600 мс, а событие
/// приходит в её начале — одного пересчёта не хватает.
const List<Duration> _relayoutDelays = [
  Duration(milliseconds: 50),
  Duration(milliseconds: 250),
  Duration(milliseconds: 600),
  Duration(milliseconds: 1000),
];

/// Просит Flutter перемерить вьюпорт: сразу и несколько раз по ходу анимации.
/// Без этого на десктопе после перехода в fullscreen остаётся застывший кадр
/// прежнего (маленького) размера.
void _relayout() {
  dispatchWindowResize();
  for (final delay in _relayoutDelays) {
    Timer(delay, dispatchWindowResize);
  }
}

/// Подписывается на изменения safe-area/fullscreen/вьюпорта Telegram: держит
/// [telegramTopInset] актуальным и не даёт Flutter застрять на старом размере.
/// Безопасно вне Telegram (no-op).
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
    tg.onEvent(FullscreenChangedEvent(() {
      refresh();
      _relayout();
    }));
    // Приходит и при разворачивании/сворачивании окна, и по ходу анимации
    // (isStateStable == false), и по её завершении.
    tg.onEvent(ViewportChangedEvent((payload) {
      refresh();
      _relayout();
    }));
  } catch (_) {
    // Старые клиенты Telegram (Bot API < 8.0) — события недоступны, не критично.
  }
}
