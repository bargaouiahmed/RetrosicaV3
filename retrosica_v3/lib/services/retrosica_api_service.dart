class RetrosicaApiService {
  static const baseUrl = String.fromEnvironment(
    'RETROSICA_API_URL',
    defaultValue: 'https://ahmed.tail867339.ts.net',
  );

  static Uri get backgroundDownloadUri =>
      Uri.parse('$baseUrl/api/downloads/file');

  static Uri get ttsStreamUri => Uri.parse('$baseUrl/api/tts/stream');

  static Uri get ttsVoicesUri => Uri.parse('$baseUrl/api/tts/voices');

  static Uri get ttsJobsUri => Uri.parse('$baseUrl/api/tts/jobs');

  static Uri ttsJobUri(String id) => Uri.parse('$baseUrl/api/tts/jobs/$id');

  static Uri ttsJobRetryUri(String id) =>
      Uri.parse('$baseUrl/api/tts/jobs/$id/retry');

  static Uri ttsJobFileUri(String id) =>
      Uri.parse('$baseUrl/api/tts/jobs/$id/file');
}
