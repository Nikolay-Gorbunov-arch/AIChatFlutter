import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class ApiProviderConfig {
  final String provider;
  final String apiKey;
  final String baseUrl;

  const ApiProviderConfig({
    required this.provider,
    required this.apiKey,
    required this.baseUrl,
  });

  bool get isVseGpt => provider == 'VSEGPT' || baseUrl.contains('vsegpt.ru');

  String get providerTitle => isVseGpt ? 'VSEGPT' : 'OpenRouter';
}

class OpenRouterClient {
  ApiProviderConfig _config = ApiProviderConfig(
    provider: dotenv.env['PROVIDER'] ?? 'OpenRouter',
    apiKey: dotenv.env['OPENROUTER_API_KEY'] ?? '',
    baseUrl: dotenv.env['BASE_URL'] ?? 'https://openrouter.ai/api/v1',
  );

  ApiProviderConfig get config => _config;
  String? get baseUrl => _config.baseUrl;

  Map<String, String> get headers => {
        'Authorization': 'Bearer ${_config.apiKey}',
        'Content-Type': 'application/json',
        'X-Title': 'AI Chat Flutter',
      };

  void configure(ApiProviderConfig config) {
    _config = config;
    if (kDebugMode) {
      print('API provider configured: ${config.providerTitle}, ${config.baseUrl}');
    }
  }

  Future<List<Map<String, dynamic>>> getModels() async {
    if (_config.apiKey.trim().isEmpty) {
      return _fallbackModels();
    }

    try {
      final response = await http.get(
        Uri.parse('${_config.baseUrl}/models'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final modelsData = json.decode(utf8.decode(response.bodyBytes));
        final data = modelsData['data'];
        if (data is List) {
          return data.map<Map<String, dynamic>>((model) {
            final pricing = model['pricing'] is Map ? model['pricing'] : {};
            final topProvider = model['top_provider'] is Map ? model['top_provider'] : {};
            return {
              'id': model['id']?.toString() ?? 'unknown-model',
              'name': model['name']?.toString() ?? model['id']?.toString() ?? 'Unknown model',
              'pricing': {
                'prompt': pricing['prompt']?.toString() ?? '0',
                'completion': pricing['completion']?.toString() ?? '0',
              },
              'context_length': (model['context_length'] ?? topProvider['context_length'] ?? 0).toString(),
            };
          }).toList();
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error getting models: $e');
    }

    return _fallbackModels();
  }

  Future<Map<String, dynamic>> sendMessage(String message, String model) async {
    if (_config.apiKey.trim().isEmpty) {
      return {'error': 'API ключ не задан. Откройте настройки провайдера.'};
    }

    try {
      final data = {
        'model': model,
        'messages': [
          {'role': 'user', 'content': message},
        ],
        'max_tokens': int.tryParse(dotenv.env['MAX_TOKENS'] ?? '1000') ?? 1000,
        'temperature': double.tryParse(dotenv.env['TEMPERATURE'] ?? '0.7') ?? 0.7,
        'stream': false,
      };

      final response = await http.post(
        Uri.parse('${_config.baseUrl}/chat/completions'),
        headers: headers,
        body: json.encode(data),
      );

      final body = utf8.decode(response.bodyBytes);
      final decoded = body.isNotEmpty ? json.decode(body) : <String, dynamic>{};

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded as Map<String, dynamic>;
      }

      String errorMessage = 'Ошибка API: ${response.statusCode}';

       if (decoded is Map) {
         final error = decoded['error'];

         if (error is Map && error['message'] != null) {
           errorMessage = error['message'].toString();
         } else if (decoded['message'] != null) {
           errorMessage = decoded['message'].toString();
         }
       }

return {
  'error': errorMessage,
};
    } catch (e) {
      if (kDebugMode) print('Error sending message: $e');
      return {'error': e.toString()};
    }
  }

  Future<String> getBalance() async {
    if (_config.apiKey.trim().isEmpty) {
      return _config.isVseGpt ? '0.00₽' : '\$0.00';
    }

    try {
      final response = await http.get(
        Uri.parse(_config.isVseGpt ? '${_config.baseUrl}/balance' : '${_config.baseUrl}/credits'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data is Map && data['data'] != null) {
          if (_config.isVseGpt) {
            final credits = double.tryParse(data['data']['credits'].toString()) ?? 0.0;
            return '${credits.toStringAsFixed(2)}₽';
          }
          final credits = double.tryParse(data['data']['total_credits'].toString()) ?? 0.0;
          final usage = double.tryParse(data['data']['total_usage'].toString()) ?? 0.0;
          return '\$${(credits - usage).toStringAsFixed(2)}';
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error getting balance: $e');
    }

    return _config.isVseGpt ? '0.00₽' : '\$0.00';
  }

  String formatPricing(double pricing) {
    if (_config.isVseGpt) {
      return '${pricing.toStringAsFixed(3)}₽/K';
    }
    return '\$${(pricing * 1000000).toStringAsFixed(3)}/M';
  }

  List<Map<String, dynamic>> _fallbackModels() => [
        {
          'id': 'openai/gpt-4o-mini',
          'name': 'GPT-4o mini',
          'pricing': {'prompt': '0', 'completion': '0'},
          'context_length': '128000',
        },
        {
          'id': 'deepseek/deepseek-chat',
          'name': 'DeepSeek Chat',
          'pricing': {'prompt': '0', 'completion': '0'},
          'context_length': '64000',
        },
        {
          'id': 'anthropic/claude-3.5-sonnet',
          'name': 'Claude 3.5 Sonnet',
          'pricing': {'prompt': '0', 'completion': '0'},
          'context_length': '200000',
        },
      ];
}
