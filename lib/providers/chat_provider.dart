import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/openrouter_client.dart';
import '../models/message.dart';
import '../services/analytics_service.dart';
import '../services/database_service.dart';

class ChatProvider with ChangeNotifier {
  final OpenRouterClient _api = OpenRouterClient();
  final DatabaseService _db = DatabaseService();
  final AnalyticsService _analytics = AnalyticsService();

  final List<ChatMessage> _messages = [];
  final List<String> _debugLogs = [];

  List<Map<String, dynamic>> _availableModels = [];
  String? _currentModel;
  String _balance = '\$0.00';
  bool _isLoading = false;
  String _provider = 'OpenRouter';
  String _apiKey = '';
  String _baseUrl = 'https://openrouter.ai/api/v1';

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<Map<String, dynamic>> get availableModels => _availableModels;
  String? get currentModel => _currentModel;
  String get balance => _balance;
  bool get isLoading => _isLoading;
  String get provider => _provider;
  String get apiKey => _apiKey;
  String get baseUrl => _baseUrl;
  bool get isVseGpt => _provider == 'VSEGPT' || _baseUrl.contains('vsegpt.ru');

  ChatProvider() {
    _initializeProvider();
  }

  void _log(String message) {
    _debugLogs.add('${DateTime.now()}: $message');
    debugPrint(message);
  }

  Future<void> _initializeProvider() async {
    try {
      await _loadSettings();
      await refreshProviderData();
      await _loadHistory();
    } catch (e, stackTrace) {
      _log('Provider init error: $e');
      _log('Stack trace: $stackTrace');
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _provider = prefs.getString('provider') ?? dotenv.env['PROVIDER'] ?? 'OpenRouter';
    _baseUrl = prefs.getString('base_url') ??
        dotenv.env['BASE_URL'] ??
        (_provider == 'VSEGPT' ? 'https://api.vsegpt.ru/v1' : 'https://openrouter.ai/api/v1');
    _apiKey = prefs.getString('api_key') ?? dotenv.env['OPENROUTER_API_KEY'] ?? '';

    _api.configure(ApiProviderConfig(
      provider: _provider,
      apiKey: _apiKey,
      baseUrl: _baseUrl,
    ));
  }

  Future<void> saveSettings({
    required String provider,
    required String apiKey,
    String? customBaseUrl,
  }) async {
    _provider = provider;
    _apiKey = apiKey.trim();
    _baseUrl = (customBaseUrl?.trim().isNotEmpty ?? false)
        ? customBaseUrl!.trim()
        : provider == 'VSEGPT'
            ? 'https://api.vsegpt.ru/v1'
            : 'https://openrouter.ai/api/v1';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('provider', _provider);
    await prefs.setString('api_key', _apiKey);
    await prefs.setString('base_url', _baseUrl);

    _api.configure(ApiProviderConfig(
      provider: _provider,
      apiKey: _apiKey,
      baseUrl: _baseUrl,
    ));

    _currentModel = null;
    await refreshProviderData();
    notifyListeners();
  }

  Future<void> refreshProviderData() async {
    await _loadModels();
    await _loadBalance();
  }

  Future<void> _loadModels() async {
    _availableModels = await _api.getModels();
    _availableModels.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    if (_availableModels.isNotEmpty && _currentModel == null) {
      _currentModel = _availableModels.first['id'] as String?;
    }
    notifyListeners();
  }

  Future<void> _loadBalance() async {
    _balance = await _api.getBalance();
    notifyListeners();
  }

  Future<void> _loadHistory() async {
    final loadedMessages = await _db.getMessages();
    _messages
      ..clear()
      ..addAll(loadedMessages);
    notifyListeners();
  }

  Future<void> _saveMessage(ChatMessage message) async {
    await _db.saveMessage(message);
  }

  Future<void> sendMessage(String content, {bool trackAnalytics = true}) async {
    if (content.trim().isEmpty || _currentModel == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      content = utf8.decode(utf8.encode(content));
      final userMessage = ChatMessage(content: content, isUser: true, modelId: _currentModel);
      _messages.add(userMessage);
      notifyListeners();
      await _saveMessage(userMessage);

      final startTime = DateTime.now();
      final response = await _api.sendMessage(content, _currentModel!);
      final responseTime = DateTime.now().difference(startTime).inMilliseconds / 1000;

      if (response.containsKey('error')) {
        final errorMessage = ChatMessage(
          content: 'Ошибка: ${response['error']}',
          isUser: false,
          modelId: _currentModel,
        );
        _messages.add(errorMessage);
        await _saveMessage(errorMessage);
      } else {
        final choices = response['choices'];
        String? aiContent;
        if (choices is List && choices.isNotEmpty) {
          final firstChoice = choices.first;
          if (firstChoice is Map && firstChoice['message'] is Map) {
            aiContent = firstChoice['message']['content']?.toString();
          }
        }
        if (aiContent == null) throw Exception('Некорректный формат ответа API');

        final usage = response['usage'] is Map ? response['usage'] as Map : <String, dynamic>{};
        final tokens = int.tryParse((usage['total_tokens'] ?? 0).toString()) ?? 0;
        final promptTokens = int.tryParse((usage['prompt_tokens'] ?? 0).toString()) ?? 0;
        final completionTokens = int.tryParse((usage['completion_tokens'] ?? 0).toString()) ?? 0;
        final totalCost = double.tryParse((usage['total_cost'] ?? '').toString());

        final model = _availableModels.firstWhere(
          (model) => model['id'] == _currentModel,
          orElse: () => {'pricing': {'prompt': '0', 'completion': '0'}},
        );
        final promptPrice = double.tryParse(model['pricing']?['prompt']?.toString() ?? '0') ?? 0;
        final completionPrice = double.tryParse(model['pricing']?['completion']?.toString() ?? '0') ?? 0;
        final calculatedCost = totalCost ?? (promptTokens * promptPrice + completionTokens * completionPrice);

        if (trackAnalytics) {
          _analytics.trackMessage(
            model: _currentModel!,
            messageLength: content.length,
            responseTime: responseTime,
            tokensUsed: tokens,
          );
        }

        final aiMessage = ChatMessage(
          content: utf8.decode(utf8.encode(aiContent)),
          isUser: false,
          modelId: _currentModel,
          tokens: tokens,
          cost: calculatedCost,
        );
        _messages.add(aiMessage);
        await _saveMessage(aiMessage);
        await _loadBalance();
      }
    } catch (e) {
      _log('Error sending message: $e');
      final errorMessage = ChatMessage(content: 'Ошибка: $e', isUser: false, modelId: _currentModel);
      _messages.add(errorMessage);
      await _saveMessage(errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setCurrentModel(String modelId) {
    _currentModel = modelId;
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _messages.clear();
    await _db.clearHistory();
    _analytics.clearData();
    notifyListeners();
  }

  Map<String, dynamic> getUsageSummary() {
    final stats = <String, Map<String, dynamic>>{};
    int totalTokens = 0;
    double totalCost = 0;

    for (final message in _messages.where((m) => !m.isUser)) {
      final model = message.modelId ?? 'unknown';
      stats.putIfAbsent(model, () => {'messages': 0, 'tokens': 0, 'cost': 0.0});
      stats[model]!['messages'] = (stats[model]!['messages'] as int) + 1;
      stats[model]!['tokens'] = (stats[model]!['tokens'] as int) + (message.tokens ?? 0);
      stats[model]!['cost'] = (stats[model]!['cost'] as double) + (message.cost ?? 0.0);
      totalTokens += message.tokens ?? 0;
      totalCost += message.cost ?? 0.0;
    }

    return {
      'totalMessages': _messages.length,
      'assistantMessages': _messages.where((m) => !m.isUser).length,
      'totalTokens': totalTokens,
      'totalCost': totalCost,
      'models': stats,
    };
  }

  Map<DateTime, double> getDailyExpenses() {
    final expenses = <DateTime, double>{};
    for (final message in _messages.where((m) => !m.isUser && (m.cost ?? 0) > 0)) {
      final day = DateTime(message.timestamp.year, message.timestamp.month, message.timestamp.day);
      expenses[day] = (expenses[day] ?? 0) + (message.cost ?? 0);
    }
    return Map.fromEntries(expenses.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  String formatPricing(double pricing) => _api.formatPricing(pricing);

  String formatMoney(double value) {
    if (isVseGpt) return '${value.toStringAsFixed(value < 1 ? 4 : 2)}₽';
    return '\$${value.toStringAsFixed(value < 1 ? 6 : 2)}';
  }

  Future<String> exportLogs() async {
    final directory = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final file = File('${directory.path}/chat_logs_${now.millisecondsSinceEpoch}.txt');
    final buffer = StringBuffer('=== Debug Logs ===\n');
    for (final log in _debugLogs) {
      buffer.writeln(log);
    }
    buffer.writeln('\n=== Chat ===\n');
    for (final message in _messages) {
      buffer.writeln('${message.isUser ? "User" : "AI"} (${message.modelId}): ${message.content}');
      buffer.writeln('Tokens: ${message.tokens ?? 0}; Cost: ${message.cost ?? 0}; Time: ${message.timestamp}');
      buffer.writeln('---');
    }
    await file.writeAsString(buffer.toString());
    return file.path;
  }

  Future<String> exportMessagesAsJson() async {
    final directory = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final file = File('${directory.path}/chat_history_${now.millisecondsSinceEpoch}.json');
    await file.writeAsString(jsonEncode(_messages.map((message) => message.toJson()).toList()));
    return file.path;
  }

  Future<Map<String, dynamic>> exportHistory() async {
    return {
      'database_stats': await _db.getStatistics(),
      'analytics_stats': _analytics.getStatistics(),
      'session_data': _analytics.exportSessionData(),
      'model_efficiency': _analytics.getModelEfficiency(),
      'response_time_stats': _analytics.getResponseTimeStats(),
      'message_length_stats': _analytics.getMessageLengthStats(),
    };
  }
}
