import 'package:material_ui/material_ui.dart';

import '../services/app_services.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _key = TextEditingController();
  final _model = TextEditingController();
  double _fps = 2;
  bool _loading = true;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    settingsService.load().then((s) {
      if (!mounted) return;
      setState(() {
        _key.text = s.apiKey;
        _model.text = s.model;
        _fps = s.fps.clamp(0.5, 5).toDouble();
        _loading = false;
      });
    });
  }

  Future<void> _save() async {
    await settingsService.save(AppSettings(apiKey: _key.text, model: _model.text, fps: _fps));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Réglages enregistrés')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages'), actions: [
        TextButton.icon(onPressed: _loading ? null : _save, icon: const Icon(Icons.save), label: const Text('Enregistrer')),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text('IA — découpage automatique (Google Gemini)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text(
                'Créez une clé gratuite sur aistudio.google.com (menu « Get API key »), puis collez-la ici. '
                "Elle est stockée chiffrée sur cet appareil uniquement.\n"
                "Attention : sur l'offre gratuite, Google peut utiliser les contenus envoyés pour améliorer ses produits. "
                "Prévenez l'opératrice / l'entreprise avant d'envoyer une vidéo.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _key,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Clé API Gemini',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _model,
                decoration: const InputDecoration(labelText: 'Modèle', border: OutlineInputBorder()),
              ),
              Wrap(spacing: 6, children: [
                for (final m in kSuggestedModels)
                  ActionChip(label: Text(m), onPressed: () => setState(() => _model.text = m)),
              ]),
              const SizedBox(height: 16),
              Text('Images analysées par seconde : ${_fps.toStringAsFixed(1).replaceAll('.', ',')}'),
              Slider(
                value: _fps,
                min: 0.5,
                max: 5,
                divisions: 9,
                label: _fps.toStringAsFixed(1),
                onChanged: (v) => setState(() => _fps = v),
              ),
              const Text(
                'Plus d’images = découpage plus fin mais plus de jetons consommés (quota gratuit). '
                '2 images/s convient pour des vidéos de 1 à 3 minutes.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ]),
    );
  }
}
