import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qarshi/core/data/api/api_django.dart';
import 'package:qarshi/core/data/models.dart';
import 'package:qarshi/core/utils/formatters.dart';
import 'package:qarshi/core/utils/telegram_launch.dart';

class ReconciliationReportScreen extends StatefulWidget {
  const ReconciliationReportScreen({super.key});

  @override
  State<ReconciliationReportScreen> createState() =>
      _ReconciliationReportScreenState();
}

/// Как часто спрашиваем сервер, не пришёл ли акт из 1С.
const Duration _pollInterval = Duration(seconds: 3);

/// Сколько ждём на экране. Дальше акт всё равно придёт — сообщением в Telegram,
/// поэтому держать человека у экрана дольше незачем.
const Duration _pollTimeout = Duration(minutes: 3);

class _ReconciliationReportScreenState
    extends State<ReconciliationReportScreen> {
  final DjangoApi _api = DjangoApi();

  DateTime? _dateFrom;
  DateTime? _dateTo;

  bool _isLoading = false;

  /// Текущая заявка: pending — ждём 1С, ready — есть файл, failed — отказ.
  ActRequest? _request;
  Timer? _pollTimer;
  DateTime? _pollStartedAt;

  /// Прошлые заявки этого клиента: заказал акт, вышел из приложения — файл
  /// должен найтись здесь, а не только в чате Telegram.
  List<ActRequest> _history = const [];
  bool _isHistoryLoading = true;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();

    _dateFrom = DateTime(now.year, now.month, 1);
    _dateTo = now;

    _loadHistory();
  }

  /// Подтягивает прошлые заявки и, если последняя ещё формируется, продолжает её ждать.
  Future<void> _loadHistory() async {
    final history = await _api.getActRequests();
    if (!mounted) return;

    setState(() {
      _history = history;
      _isHistoryLoading = false;
      // Открыли экран после выхода — показываем последнюю заявку и её период,
      // иначе карточка результата относилась бы к другим датам.
      if (_request == null && history.isNotEmpty) {
        _request = history.first;
        _dateFrom = DateTime.tryParse(history.first.dateFrom) ?? _dateFrom;
        _dateTo = DateTime.tryParse(history.first.dateTo) ?? _dateTo;
      }
    });

    if (_request?.isPending ?? false) _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _selectDate({required bool isStartDate}) async {
    final now = DateTime.now();

    final initialDate = isStartDate
        ? (_dateFrom ?? DateTime(now.year, now.month, 1))
        : (_dateTo ?? now);

    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      helpText: isStartDate ? 'Начало периода' : 'Конец периода',
      cancelText: 'Отмена',
      confirmText: 'Выбрать',
    );

    if (selected == null || !mounted) return;

    setState(() {
      if (isStartDate) {
        _dateFrom = selected;

        if (_dateTo != null && _dateTo!.isBefore(selected)) {
          _dateTo = selected;
        }
      } else {
        _dateTo = selected;

        if (_dateFrom != null && _dateFrom!.isAfter(selected)) {
          _dateFrom = selected;
        }
      }

      _resetRequest();
    });
  }

  /// Период изменили — прежний акт к нему не относится.
  void _resetRequest() {
    _pollTimer?.cancel();
    _request = null;
  }

  void _setCurrentMonth() {
    final now = DateTime.now();

    setState(() {
      _dateFrom = DateTime(now.year, now.month, 1);
      _dateTo = now;
      _resetRequest();
    });
  }

  void _setPreviousMonth() {
    final now = DateTime.now();
    final firstDayCurrentMonth = DateTime(now.year, now.month, 1);
    final lastDayPreviousMonth = firstDayCurrentMonth.subtract(
      const Duration(days: 1),
    );

    setState(() {
      _dateFrom = DateTime(
        lastDayPreviousMonth.year,
        lastDayPreviousMonth.month,
        1,
      );
      _dateTo = lastDayPreviousMonth;
      _resetRequest();
    });
  }

  void _setCurrentYear() {
    final now = DateTime.now();

    setState(() {
      _dateFrom = DateTime(now.year, 1, 1);
      _dateTo = now;
      _resetRequest();
    });
  }

  Future<void> _generateReport() async {
    if (_dateFrom == null || _dateTo == null) {
      _toast('Выберите период формирования');
      return;
    }

    if (_dateFrom!.isAfter(_dateTo!)) {
      _toast('Дата начала не может быть позже даты окончания');
      return;
    }

    setState(() => _isLoading = true);

    final (request, error) = await _api.createActRequest(_dateFrom!, _dateTo!);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _request = request;
    });

    if (request == null) {
      _toast(error ?? 'Не удалось отправить заявку на акт сверки');
      return;
    }

    _refreshHistory(request);
    if (request.isPending) _startPolling();
  }

  /// Держит список в согласии с текущей заявкой, не дёргая сервер лишний раз.
  void _refreshHistory(ActRequest request) {
    final updated = [..._history];
    final index = updated.indexWhere((item) => item.id == request.id);
    if (index >= 0) {
      updated[index] = request;
    } else {
      updated.insert(0, request);
    }
    setState(() => _history = updated);
  }

  /// Пока экран открыт, сами спрашиваем сервер: так клиент увидит готовый акт,
  /// не выходя в Telegram за сообщением.
  void _startPolling() {
    _pollTimer?.cancel();
    _pollStartedAt = DateTime.now();
    _pollTimer = Timer.periodic(_pollInterval, (timer) async {
      final id = _request?.id;
      if (id == null || !mounted) {
        timer.cancel();
        return;
      }

      if (DateTime.now().difference(_pollStartedAt!) > _pollTimeout) {
        timer.cancel();
        return;
      }

      final fresh = await _api.getActRequest(id);
      if (!mounted || fresh == null) return;

      if (!fresh.isPending) {
        timer.cancel();
        setState(() => _request = fresh);
        _refreshHistory(fresh);
      }
    });
  }

  Future<void> _downloadReport() async => _openAct(_request);

  /// Открывает готовый акт. Ссылка подписана, поэтому работает и в браузере Telegram.
  void _openAct(ActRequest? request) {
    final url = request?.fileUrl ?? '';
    if (url.isEmpty) {
      _toast('Файл ещё не готов');
      return;
    }
    openExternalLink(url);
  }

  /// Показать прошлую заявку в основной карточке.
  void _selectFromHistory(ActRequest request) {
    setState(() {
      _request = request;
      _dateFrom = DateTime.tryParse(request.dateFrom) ?? _dateFrom;
      _dateTo = DateTime.tryParse(request.dateTo) ?? _dateTo;
    });
    if (request.isReady) _openAct(request);
    if (request.isPending) _startPolling();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Выберите дату';

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day.$month.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text(
          'Акт сверки',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isWide ? 24 : 14),
                child: isWide ? _buildWideLayout() : _buildMobileLayout(),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPeriodCard(),
        const SizedBox(height: 14),
        _buildResultCard(),
        const SizedBox(height: 14),
        _buildHistoryCard(),
      ],
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 360, child: _buildPeriodCard()),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildResultCard(),
              const SizedBox(height: 20),
              _buildHistoryCard(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.date_range_rounded,
              color: Color(0xFF2563EB),
              size: 24,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Период сверки',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Выберите даты, за которые необходимо сформировать документ.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          const _FieldTitle('Начало периода'),
          const SizedBox(height: 7),
          _DateField(
            value: _formatDate(_dateFrom),
            onTap: () => _selectDate(isStartDate: true),
          ),
          const SizedBox(height: 14),
          const _FieldTitle('Конец периода'),
          const SizedBox(height: 7),
          _DateField(
            value: _formatDate(_dateTo),
            onTap: () => _selectDate(isStartDate: false),
          ),
          const SizedBox(height: 18),
          const _FieldTitle('Быстрый выбор'),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PeriodChip(label: 'Этот месяц', onTap: _setCurrentMonth),
              _PeriodChip(label: 'Прошлый месяц', onTap: _setPreviousMonth),
              _PeriodChip(label: 'Этот год', onTap: _setCurrentYear),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                disabledBackgroundColor: const Color(0xFF93C5FD),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _isLoading ? null : _generateReport,
              icon: _isLoading
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.description_outlined, size: 20),
              label: Text(
                _isLoading ? 'Формирование...' : 'Сформировать',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard() {
    return _HistoryCard(
      requests: _history,
      isLoading: _isHistoryLoading,
      selectedId: _request?.id,
      onTap: _selectFromHistory,
      onDownload: _openAct,
    );
  }

  Widget _buildResultCard() {
    final request = _request;

    if (_isLoading || (request != null && request.isPending)) {
      return const _ReportLoadingCard();
    }

    if (request != null && request.isReady) {
      return _GeneratedReportCard(
        // Период берём из самой заявки: поля выбора мог поменять клиент.
        period: request.periodLabel,
        filename: request.filename,
        onDownload: _downloadReport,
      );
    }

    if (request != null && request.isFailed) {
      return _FailedReportCard(message: request.message);
    }

    return const _EmptyReportCard();
  }
}

class _FieldTitle extends StatelessWidget {
  final String text;

  const _FieldTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF334155),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String value;
  final VoidCallback onTap;

  const _DateField({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_month_outlined,
                color: Color(0xFF64748B),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PeriodChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: const Color(0xFFF8FAFC),
      side: const BorderSide(color: Color(0xFFE2E8F0)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: const TextStyle(
        color: Color(0xFF475569),
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _EmptyReportCard extends StatelessWidget {
  const _EmptyReportCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 390),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  color: Color(0xFF64748B),
                  size: 42,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Акт ещё не сформирован',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Выберите период и нажмите «Сформировать». Результат появится здесь.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportLoadingCard extends StatelessWidget {
  const _ReportLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 390),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 46,
              height: 46,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFF2563EB),
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Заявка передана в 1С',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 7),
            Text(
              'Акт формируется. Файл появится здесь, а ссылку на него '
              'мы пришлём сообщением в Telegram — можно закрыть экран.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Прошлые заявки: период, состояние и кнопка скачивания у готовых.
class _HistoryCard extends StatelessWidget {
  final List<ActRequest> requests;
  final bool isLoading;
  final String? selectedId;
  final ValueChanged<ActRequest> onTap;
  final ValueChanged<ActRequest> onDownload;

  const _HistoryCard({
    required this.requests,
    required this.isLoading,
    required this.selectedId,
    required this.onTap,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'История запросов',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Готовые акты остаются здесь — их можно скачать повторно.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else if (requests.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Вы ещё не запрашивали акт сверки.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
            )
          else
            for (final request in requests)
              _HistoryRow(
                request: request,
                selected: request.id == selectedId,
                onTap: () => onTap(request),
                onDownload: () => onDownload(request),
              ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final ActRequest request;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  const _HistoryRow({
    required this.request,
    required this.selected,
    required this.onTap,
    required this.onDownload,
  });

  static const _statusColors = {
    'ready': (Color(0xFF16A34A), Color(0xFFDCFCE7)),
    'failed': (Color(0xFFDC2626), Color(0xFFFEE2E2)),
    'pending': (Color(0xFFD97706), Color(0xFFFEF3C7)),
  };

  @override
  Widget build(BuildContext context) {
    final (textColor, background) =
        _statusColors[request.status] ?? _statusColors['pending']!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.periodLabel,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Запрошен ${formatDateTime(request.createdAt)}',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    request.statusLabel,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (request.isReady)
                  IconButton(
                    tooltip: 'Скачать',
                    onPressed: onDownload,
                    icon: const Icon(
                      Icons.download_rounded,
                      size: 20,
                      color: Color(0xFF2563EB),
                    ),
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 1С не смогла построить акт: показываем её причину как есть.
class _FailedReportCard extends StatelessWidget {
  final String message;

  const _FailedReportCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 390),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFDC2626),
                size: 28,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Акт сверки не сформирован',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              message.isEmpty
                  ? 'Попробуйте другой период или обратитесь к менеджеру.'
                  : message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneratedReportCard extends StatelessWidget {
  final String period;
  final String filename;
  final VoidCallback onDownload;

  const _GeneratedReportCard({
    required this.period,
    required this.filename,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 390),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF16A34A),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Акт сформирован',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Документ готов к просмотру или скачиванию.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _ReportInfoRow(label: 'Период', value: period),
                const SizedBox(height: 12),
                // Имя файла приходит из 1С — показываем его, а не выдуманный формат.
                _ReportInfoRow(
                  label: 'Файл',
                  value: filename.isEmpty ? 'Документ' : filename,
                ),
                const SizedBox(height: 12),
                const _ReportInfoRow(
                  label: 'Статус',
                  value: 'Готов',
                  valueColor: Color(0xFF16A34A),
                ),
              ],
            ),
          ),
          const Spacer(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded, size: 20),
              label: const Text(
                'Скачать документ',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ReportInfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: valueColor ?? const Color(0xFF0F172A),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
