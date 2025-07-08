import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class OpenAIService {
  // 🔍 添加這個靜態構造函數來強制初始化調試
  static void _debugInit() {
    print('🔍 OpenAIService 類被載入！');
    print('🔍 API 密鑰前綴: ${ApiConfig.getOpenAiApiKey().substring(0, 10)}...');
  }

  static Future<String> sendMessage(String message, List<Map<String, String>> conversationHistory) async {
    // 🔍 強制調試輸出 - 放在方法最開始
    print('🚀🚀🚀 OpenAI sendMessage 被調用了！ 🚀🚀🚀');

    final apiKey = ApiConfig.getOpenAiApiKey();
    print('=== OpenAI 服務調試 ===');
    print('實際使用的密鑰前綴: ${apiKey.substring(0, 10)}...');
    print('密鑰長度: ${apiKey.length}');
    print('完整密鑰: $apiKey'); // 🔍 臨時顯示完整密鑰用於調試
    print('======================');

    if (!ApiConfig.isApiKeyConfigured) {
      return '🔑 API 密鑰未配置\n\n需要立即協助：📞 1995 生命線';
    }

    try {
      List<Map<String, String>> messages = [
        {
          'role': 'system',
          'content': '你是一位專業、溫暖且富有同理心的心理陪伴助手，使用繁體中文回應，提供情感支持但不提供醫療建議。'
        },
      ];

      if (conversationHistory.length > 8) {
        messages.addAll(conversationHistory.sublist(conversationHistory.length - 8));
      } else {
        messages.addAll(conversationHistory);
      }

      messages.add({
        'role': 'user',
        'content': message,
      });

      print('準備發送 API 請求...');

      final response = await http.post(
        Uri.parse(ApiConfig.openAiBaseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${ApiConfig.getOpenAiApiKey()}',
        },
        body: jsonEncode({
          'model': ApiConfig.openAiModel,
          'messages': messages,
          'max_tokens': ApiConfig.maxTokens,
          'temperature': ApiConfig.temperature,
        }),
      );

      print('API 回應狀態碼: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['choices'][0]['message']['content'].toString().trim();
      } else if (response.statusCode == 401) {
        print('❌ API 密鑰錯誤: ${response.body}');
        return '🔐 API 密鑰無效\n\n緊急協助：📞 1995 生命線';
      } else if (response.statusCode == 429) {
        return '⏱️ 服務使用量超限\n\n請稍後再試\n其他支持：📞 1995 生命線';
      } else {
        print('OpenAI API 錯誤: ${response.statusCode} - ${response.body}');
        return '❌ 服務暫時無法使用\n\n錯誤代碼: ${response.statusCode}\n請稍後再試或聯繫：📞 1995 生命線';
      }
    } catch (e) {
      print('OpenAI API 異常: $e');
      return '🌐 連接問題\n\n請檢查網路連接後再試\n\n緊急情況請聯繫：📞 1995 生命線';
    }
  }
}
final _autoInit = (() {
  OpenAIService._debugInit();
  return true;
})();