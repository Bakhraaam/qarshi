// Кастомный бутстрап Flutter web (Flutter подставит плейсхолдеры при сборке).
//
// Зачем он нужен: сборка с --wasm объявляет рендерер skwasm. В Telegram Desktop
// на Windows (движок WebView2) skwasm после изменения размера окна перестаёт
// перерисовывать канвас — приложение «зависает» застывшим кадром прежнего
// размера. На macOS клиент Telegram WasmGC не поддерживает, сам откатывается на
// canvaskit, и там проблемы нет — отсюда и разница между платформами.
//
// Решение: на десктопных клиентах Telegram принудительно грузим canvaskit,
// на мобильных (где skwasm работает и быстрее) оставляем как есть.
{{flutter_js}}
{{flutter_build_config}}

(function () {
  // Платформы, где skwasm проверенно работает
  var SKWASM_PLATFORMS = ['android', 'ios'];

  var platform = '';
  try {
    // telegram-web-app.js подключён в <head> выше, объект уже доступен
    platform = (window.Telegram && window.Telegram.WebApp && window.Telegram.WebApp.platform) || '';
  } catch (e) {}

  var config = {};
  if (platform && SKWASM_PLATFORMS.indexOf(platform) === -1) {
    config.renderer = 'canvaskit';
  }

  _flutter.loader.load({config: config});
})();
