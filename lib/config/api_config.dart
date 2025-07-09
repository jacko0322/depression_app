class ApiConfig {
  static const String _openAiApiKey = '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';

  // 使用限制設定
  static const int maxDailyMessages = 50;
  static const int maxTokensPerMessage = 500;

  // 獲取 API 密鑰
  static String getOpenAiApiKey() {
    return _openAiApiKey;
  }

  // ✅ 修正後的密鑰檢查邏輯
  static bool get isApiKeyConfigured {
    return _openAiApiKey.isNotEmpty &&
        _openAiApiKey != 'sk-你的新密鑰' &&  // 檢查是否不是預設值
        _openAiApiKey != 'YOUR_OPENAI_API_KEY' &&
        (_openAiApiKey.startsWith('sk-') || _openAiApiKey.startsWith('sk-svcacct-'));
  }

  // API 設定
  static const String openAiBaseUrl = 'https://api.openai.com/v1/chat/completions';
  static const String openAiModel = 'gpt-3.5-turbo';
  static const int maxTokens = 100;
  static const double temperature = 0.7;

  // 驗證密鑰格式
  static bool get isValidApiKeyFormat {
    return _openAiApiKey.startsWith('sk-') && _openAiApiKey.length > 20;
  }

  // 獲取配置狀態（用於調試）
  static Map<String, dynamic> getConfigStatus() {
    return {
      'keyConfigured': isApiKeyConfigured,
      'keyFormatValid': isValidApiKeyFormat,
      'keyPrefix': _openAiApiKey.length > 10 ? _openAiApiKey.substring(0, 10) + '...' : 'invalid',
      'maxDailyMessages': maxDailyMessages,
    };
  }
}