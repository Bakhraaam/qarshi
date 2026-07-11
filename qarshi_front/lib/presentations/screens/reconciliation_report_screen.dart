import 'package:flutter/material.dart';

class ReconciliationReportScreen extends StatefulWidget {
  const ReconciliationReportScreen({super.key});

  @override
  State<ReconciliationReportScreen> createState() =>
      _ReconciliationReportScreenState();
}

class _ReconciliationReportScreenState
    extends State<ReconciliationReportScreen> {
  DateTime? _dateFrom;
  DateTime? _dateTo;

  bool _isLoading = false;
  bool _hasGeneratedReport = false;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();

    _dateFrom = DateTime(now.year, now.month, 1);
    _dateTo = now;
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

      _hasGeneratedReport = false;
    });
  }

  void _setCurrentMonth() {
    final now = DateTime.now();

    setState(() {
      _dateFrom = DateTime(now.year, now.month, 1);
      _dateTo = now;
      _hasGeneratedReport = false;
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
      _hasGeneratedReport = false;
    });
  }

  void _setCurrentYear() {
    final now = DateTime.now();

    setState(() {
      _dateFrom = DateTime(now.year, 1, 1);
      _dateTo = now;
      _hasGeneratedReport = false;
    });
  }

  Future<void> _generateReport() async {
    if (_dateFrom == null || _dateTo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите период формирования')),
      );
      return;
    }

    if (_dateFrom!.isAfter(_dateTo!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Дата начала не может быть позже даты окончания'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // TODO: Здесь вызовите API формирования акта сверки.
      //
      // Пример:
      // final result = await DjangoApi().getReconciliationReport(
      //   dateFrom: _dateFrom!,
      //   dateTo: _dateTo!,
      // );
      //
      // После получения результата сохраните его в состоянии.

      await Future<void>.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      setState(() {
        _hasGeneratedReport = true;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сформировать акт сверки')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _downloadReport() async {
    // TODO: Добавьте скачивание PDF, Excel или открытие файла.
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
      ],
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 360, child: _buildPeriodCard()),
        const SizedBox(width: 20),
        Expanded(child: _buildResultCard()),
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

  Widget _buildResultCard() {
    if (_isLoading) {
      return const _ReportLoadingCard();
    }

    if (_hasGeneratedReport) {
      return _GeneratedReportCard(
        dateFrom: _formatDate(_dateFrom),
        dateTo: _formatDate(_dateTo),
        onDownload: _downloadReport,
      );
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
              'Формируем акт сверки',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 7),
            Text(
              'Получаем данные из 1С. Это может занять некоторое время.',
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

class _GeneratedReportCard extends StatelessWidget {
  final String dateFrom;
  final String dateTo;
  final VoidCallback onDownload;

  const _GeneratedReportCard({
    required this.dateFrom,
    required this.dateTo,
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
                _ReportInfoRow(label: 'Период', value: '$dateFrom — $dateTo'),
                const SizedBox(height: 12),
                const _ReportInfoRow(label: 'Формат', value: 'PDF / Excel'),
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
