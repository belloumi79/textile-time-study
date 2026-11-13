import 'package:material_ui/material_ui.dart';

import '../models/study.dart';
import '../services/app_services.dart';
import '../services/calculations.dart';
import '../services/format.dart';
import 'analysis_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'study_form_screen.dart';

class StudiesListScreen extends StatefulWidget {
  const StudiesListScreen({super.key});
  @override
  State<StudiesListScreen> createState() => _StudiesListScreenState();
}

class _StudiesListScreenState extends State<StudiesListScreen> {
  List<Study>? _studies;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final l = await storage.listStudies();
    if (mounted) setState(() => _studies = l);
  }

  Future<void> _new() async {
    final s = await Navigator.push<Study>(context, MaterialPageRoute(builder: (_) => StudyFormScreen(study: Study())));
    if (s == null || !mounted) return;
    await storage.saveStudy(s);
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AnalysisScreen(study: s)));
    _reload();
  }

  Future<void> _open(Study s) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AnalysisScreen(study: s)));
    _reload();
  }

  Future<void> _delete(Study s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Supprimer l'étude ?"),
        content: Text('« ${s.title} » et sa vidéo seront supprimées de cet appareil.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) {
      await storage.deleteStudy(s);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final studies = _studies;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analyse du travail — études'),
        actions: [
          IconButton(
            tooltip: 'Bibliothèque de mouvements',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryScreen())),
          ),
          IconButton(
            tooltip: 'Réglages',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle étude'),
      ),
      body: studies == null
          ? const Center(child: CircularProgressIndicator())
          : studies.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      "Aucune étude.\nCréez une étude, filmez ou importez la vidéo de l'opération, "
                      "puis laissez l'IA proposer le découpage en éléments et corrigez-le.",
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: studies.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final s = studies[i];
                      final r = computeStudy(s);
                      return ListTile(
                        leading: CircleAvatar(child: Text('${r.elements.length}')),
                        title: Text(s.title),
                        subtitle: Text([
                          if (s.machine.isNotEmpty) s.machine,
                          if (s.operatorName.isNotEmpty) s.operatorName,
                          frDate(s.date),
                          if (r.elements.isNotEmpty) 'SMV ${fr(r.smv, 4)} min',
                          if (s.videoPath == null) 'sans vidéo',
                        ].join(' · ')),
                        onTap: () => _open(s),
                        trailing: IconButton(
                          tooltip: 'Supprimer',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(s),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
