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

/// Сколько места занимают кнопки Telegram в fullscreen, если клиент не сообщил
/// safe-area вообще (ни объектами, ни CSS-переменными). Именно этот случай ломал
/// шапку на Android: AppBar рисовался под кнопкой «Закрыть», и ни бургер, ни
/// корзина не нажимались — тап забирал себе Telegram.
/// Значение с запасом покрывает статус-бар (~28) и полосу кнопок (~44).
const double _fullscreenFallbackTopInset = 72;

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

/// Пересчитывает отступы по текущему состоянию Telegram.
///
/// Значения читаем из JS напрямую (см. readTelegramInsets): типизированные
/// геттеры пакета объявлены как `int`, а клиенты присылают дробные пиксели,
/// и на них getter падал — отступ молча оставался нулевым.
void refreshTelegramInsets() {
  final insets = readTelegramInsets();

  var top = insets.top;
  final bottom = insets.bottom;

  // Клиент развернул Mini App на весь экран, но про safe-area ничего не сказал —
  // уводим шапку вниз на фиксированную величину, иначе она нерабочая.
  if (top <= 0 && isTelegramFullscreen()) {
    top = _fullscreenFallbackTopInset;
  }

  telegramTopInset.value = top;
  telegramBottomInset.value = bottom;
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

    refreshTelegramInsets();
    tg.onEvent(SafeAreaChangedEvent(refreshTelegramInsets));
    tg.onEvent(ContentSafeAreaChangedEvent(refreshTelegramInsets));
    tg.onEvent(
      FullscreenChangedEvent(() {
        refreshTelegramInsets();
        _relayout();
        // Android присылает fullscreenChanged в начале анимации, когда safe-area
        // ещё нулевая, а отдельного события про неё потом может и не быть.
        _rereadWhileAnimating();
      }),
    );
    // Приходит и при разворачивании/сворачивании окна, и по ходу анимации
    // (isStateStable == false), и по её завершении.
    tg.onEvent(
      ViewportChangedEvent((payload) {
        refreshTelegramInsets();
        _relayout();
      }),
    );
  } catch (_) {
    // Старые клиенты Telegram (Bot API < 8.0) — события недоступны, не критично.
  }
}

/// Перечитывает отступы по ходу анимации разворачивания — на тех же задержках,
/// на которых пересчитываем размер вьюпорта.
void _rereadWhileAnimating() {
  for (final delay in _relayoutDelays) {
    Timer(delay, refreshTelegramInsets);
  }
}
