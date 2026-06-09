import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final summary = chat.getUsageSummary();
    final models = summary['models'] as Map<String, Map<String, dynamic>>;

    return Scaffold(
      appBar: AppBar(title: const Text('Статистика токенов')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => chat.refreshProviderData(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(title: 'Сообщений', value: '${summary['totalMessages']}', icon: Icons.forum),
                  _MetricCard(title: 'Ответов AI', value: '${summary['assistantMessages']}', icon: Icons.smart_toy),
                  _MetricCard(title: 'Токенов', value: '${summary['totalTokens']}', icon: Icons.generating_tokens),
                  _MetricCard(title: 'Стоимость', value: chat.formatMoney(summary['totalCost'] as double), icon: Icons.payments),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Использование по моделям', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (models.isEmpty)
                const _EmptyState(text: 'Пока нет статистики. Отправьте пару сообщений, и здесь появятся токены, стоимость и модели.'),
              ...models.entries.map((entry) {
                final data = entry.value;
                return Card(
                  color: const Color(0xFF2F2F2F),
                  child: ListTile(
                    title: Text(entry.key, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('Ответов: ${data['messages']} • Токенов: ${data['tokens']}'),
                    trailing: Text(chat.formatMoney(data['cost'] as double)),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _MetricCard({required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width > 600
          ? (MediaQuery.of(context).size.width - 56) / 4
          : (MediaQuery.of(context).size.width - 44) / 2,
      child: Card(
        color: const Color(0xFF2F2F2F),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 12),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF2F2F2F),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(text, style: const TextStyle(color: Colors.white70)),
      ),
    );
  }
}
