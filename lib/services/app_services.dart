import 'settings_service.dart';
import 'storage_service.dart';

/// Services partagés de l'application (instances uniques).
final storage = StorageService();
final settingsService = SettingsService();
