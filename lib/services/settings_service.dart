import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Modèles proposés (gratuits sur l'offre Free de l'API Gemini, nov. 2026).
const kSuggestedModels = ['gemini-3.6-flash', 'gemini-3.8-flash', 'gemini-3.5-flash-lite', 'gemini-3.1-flash-lite'];
const kDefaultModel = 'gemini-3.6-flash';

class AppSettings {
  AppSettings({this.apiKey = '', this.model = kDefaultModel, this.fps = 2});
  String apiKey;
  String model;
  double fps;
}

/// Réglages stockés dans le coffre sécurisé de l'appareil
/// (Keystore Android / DPAPI Windows).
class SettingsService {
  SettingsService([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  Future<AppSettings> load() async {
    try {
      final key = await _s.read(key: 'gemini_api_key') ?? '';
      final model = await _s.read(key: 'gemini_model');
      final fps = double.tryParse(await _s.read(key: 'gemini_fps') ?? '');
      return AppSettings(
        apiKey: key,
        model: (model == null || model.trim().isEmpty) ? kDefaultModel : model,
        fps: fps ?? 2,
      );
    } catch (_) {
      return AppSettings();
    }
  }

  Future<void> save(AppSettings s) async {
    await _s.write(key: 'gemini_api_key', value: s.apiKey.trim());
    await _s.write(key: 'gemini_model', value: s.model.trim());
    await _s.write(key: 'gemini_fps', value: s.fps.toString());
  }
}
