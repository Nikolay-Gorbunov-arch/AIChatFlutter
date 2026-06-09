import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  String _provider = 'OpenRouter';
  bool _obscureKey = true;
  bool _initialized = false;

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    if (!_initialized) {
      _provider = chat.provider;
      _apiKeyController.text = chat.apiKey;
      _baseUrlController.text = chat.baseUrl;
      _initialized = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки провайдера')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Провайдер API', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'OpenRouter', label: Text('OpenRouter'), icon: Icon(Icons.hub)),
                    ButtonSegment(value: 'VSEGPT', label: Text('VSEGPT'), icon: Icon(Icons.api)),
                  ],
                  selected: {_provider},
                  onSelectionChanged: (value) {
                    setState(() {
                      _provider = value.first;
                      _baseUrlController.text = _provider == 'VSEGPT'
                          ? 'https://api.vsegpt.ru/v1'
                          : 'https://openrouter.ai/api/v1';
                    });
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _apiKeyController,
                  obscureText: _obscureKey,
                  decoration: InputDecoration(
                    labelText: 'API ключ',
                    hintText: 'Вставьте ключ выбранного провайдера',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _baseUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    border: OutlineInputBorder(),
                    helperText: 'Можно оставить значение по умолчанию или указать совместимый endpoint.',
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return 'URL не должен быть пустым';
                    final uri = Uri.tryParse(text);
                    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return 'Некорректный URL';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('Сохранить и обновить модели'),
                    onPressed: () async {
                      if (!_formKey.currentState!.validate()) return;
                      await context.read<ChatProvider>().saveSettings(
                            provider: _provider,
                            apiKey: _apiKeyController.text,
                            customBaseUrl: _baseUrlController.text,
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Настройки сохранены')),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 24),
                _InfoCard(chat: chat),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final ChatProvider chat;
  const _InfoCard({required this.chat});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF2F2F2F),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Текущее подключение', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Провайдер: ${chat.provider}'),
            Text('URL: ${chat.baseUrl}'),
            Text('Баланс: ${chat.balance}'),
            Text('Моделей загружено: ${chat.availableModels.length}'),
          ],
        ),
      ),
    );
  }
}
