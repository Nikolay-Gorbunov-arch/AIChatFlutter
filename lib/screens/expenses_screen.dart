import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final expenses = chat.getDailyExpenses();
    final entries = expenses.entries.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Расходы по дням')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: const Color(0xFF2F2F2F),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  height: 260,
                  child: entries.isEmpty
                      ? const Center(child: Text('Нет расходов для построения графика', style: TextStyle(color: Colors.white70)))
                      : CustomPaint(
                          painter: _ExpensesChartPainter(entries: entries, formatMoney: chat.formatMoney),
                          child: const SizedBox.expand(),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Детализация', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              const Text('История расходов пуста. Странно, но приятно для кошелька.', style: TextStyle(color: Colors.white70)),
            ...entries.reversed.map((entry) => Card(
                  color: const Color(0xFF2F2F2F),
                  child: ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: Text(DateFormat('dd.MM.yyyy').format(entry.key)),
                    trailing: Text(chat.formatMoney(entry.value)),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _ExpensesChartPainter extends CustomPainter {
  final List<MapEntry<DateTime, double>> entries;
  final String Function(double) formatMoney;

  _ExpensesChartPainter({required this.entries, required this.formatMoney});

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    final barPaint = Paint()..color = Colors.blueAccent;
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);

    const leftPadding = 52.0;
    const bottomPadding = 42.0;
    const topPadding = 24.0;
    const rightPadding = 12.0;

    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - topPadding - bottomPadding;
    final origin = Offset(leftPadding, topPadding + chartHeight);

    canvas.drawLine(Offset(leftPadding, topPadding), origin, axisPaint);
    canvas.drawLine(origin, Offset(size.width - rightPadding, origin.dy), axisPaint);

    final maxValue = entries.map((e) => e.value).fold<double>(0, math.max);
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;
    final barGap = 8.0;
    final barWidth = math.max(10.0, (chartWidth - barGap * (entries.length + 1)) / entries.length);

    for (var i = 0; i < entries.length; i++) {
      final value = entries[i].value;
      final height = chartHeight * (value / safeMax);
      final left = leftPadding + barGap + i * (barWidth + barGap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, origin.dy - height, barWidth, height),
        const Radius.circular(6),
      );
      canvas.drawRRect(rect, barPaint);

      if (entries.length <= 7 || i == 0 || i == entries.length - 1) {
        _drawText(
          canvas,
          textPainter,
          DateFormat('dd.MM').format(entries[i].key),
          Offset(left - 4, origin.dy + 8),
          fontSize: 10,
        );
      }
    }

    _drawText(canvas, textPainter, formatMoney(safeMax), const Offset(0, topPadding - 6), fontSize: 10);
    _drawText(canvas, textPainter, '0', Offset(8, origin.dy - 10), fontSize: 10);
  }

  void _drawText(Canvas canvas, TextPainter painter, String text, Offset offset, {double fontSize = 12}) {
    painter.text = TextSpan(text: text, style: TextStyle(color: Colors.white70, fontSize: fontSize));
    painter.layout(maxWidth: 70);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _ExpensesChartPainter oldDelegate) => oldDelegate.entries != entries;
}
