import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../models/motion.dart';
import '../models/study.dart';
import '../models/study_element.dart';
import '../services/ai_segmentation.dart';
import '../services/app_services.dart';
import '../services/calculations.dart';
import '../services/element_editor.dart';
import '../services/format.dart';
import '../services/gemini_service.dart';
import '../widgets/element_chart.dart';
import '../widgets/motion_colors.dart';
import 'results_screen.dart';
import 'study_form_screen.dart';

/// Écran principal : vidéo + chrono, tableau des éléments synchronisé,
/// outils de correction, histogramme.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key, required this.study});
  final Study study;
  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  static const double rowH = 40;
  static const double tableWidth = 860;
  static const double frameStep = 1 / 30;

  late Study study = widget.study;
  List<Motion> library = defaultMotionLibrary();
  VideoPlayerController? _ctrl;
  String? _videoError;
  double _pos = 0;
  double _speed = 1;
  String? _selectedId;
  int? _viewCycle; // null = tous les cycles
  double? _pendingStart;
  String _manualCode = kOtherCode;
  bool _dirty = false;
  bool _wasPlaying = false;
  final List<List<StudyElement>> _undo = [];
  final _scroll = ScrollController();

  List<StudyElement> get elements => study.elements;

  @override
  void initState() {
    super.initState();
    study.elements = ElementEditor.sorted(study.elements);
    storage.loadLibrary().then((l) {
      if (mounted) setState(() => library = l);
    });
    _initVideo();
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_onTick);
    _ctrl?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- vidéo

  Future<void> _initVideo() async {
    final path = study.videoPath;
    if (path == null) return;
    if (!File(path).existsSync()) {
      setState(() => _videoError = 'Vidéo introuvable sur cet appareil : $path');
      return;
    }
    final old = _ctrl;
    old?.removeListener(_onTick);
    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
      await c.setPlaybackSpeed(_speed);
      c.addListener(_onTick);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _ctrl = c;
        _videoError = null;
      });
      await old?.dispose();
    } catch (e) {
      await c.dispose();
      if (mounted) setState(() => _videoError = 'Lecture impossible : $e');
    }
  }

  double get _duration => (_ctrl?.value.duration.inMilliseconds ?? 0) / 1000.0;

  void _onTick() {
    final c = _ctrl;
    if (c == null || !mounted) return;
    final p = c.value.position.inMilliseconds / 1000.0;
    final playing = c.value.isPlaying;
    if ((p - _pos).abs() < 0.02 && playing == _wasPlaying) return;
    _wasPlaying = playing;
    _pos = p;
    if (playing) {
      final i = ElementEditor.indexAt(elements, p);
      if (i >= 0 && elements[i].id != _selectedId) {
        _selectedId = elements[i].id;
        if (_viewCycle != null) _viewCycle = elements[i].cycle;
        _scrollToSelected();
      }
    }
    setState(() {});
  }

  Future<void> _seek(double t) async {
    final c = _ctrl;
    if (c == null) return;
    t = t.clamp(0, _duration).toDouble();
    await c.seekTo(Duration(milliseconds: (t * 1000).round()));
    setState(() => _pos = t);
  }

  Future<void> _step(double delta) async {
    await _ctrl?.pause();
    await _seek(_pos + delta);
  }

  Future<void> _togglePlay() async {
    final c = _ctrl;
    if (c == null) return;
    c.value.isPlaying ? await c.pause() : await c.play();
    setState(() {});
  }

  Future<void> _setSpeed(double s) async {
    _speed = s;
    await _ctrl?.setPlaybackSpeed(s);
    setState(() {});
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final x = await ImagePicker().pickVideo(source: source, maxDuration: const Duration(minutes: 10));
      if (x == null) return;
      final dest = await storage.importVideo(x.path, study.id);
      study.videoPath = dest;
      await storage.saveStudy(study);
      await _initVideo();
    } catch (e) {
      _snack('Vidéo non chargée : $e');
    }
  }

  // ------------------------------------------------------------- édition

  int get _selIndex => _selectedId == null ? -1 : elements.indexWhere((e) => e.id == _selectedId);

  List<StudyElement> get _visible =>
      _viewCycle == null ? elements : elements.where((e) => e.cycle == _viewCycle).toList();

  List<int> get _cycles => (elements.map((e) => e.cycle).toSet().toList()..sort());

  void _apply(List<StudyElement>? next, String failMsg) {
    if (next == null) {
      _snack(failMsg);
      return;
    }
    setState(() {
      _undo.add(elements.map((e) => e.copyWith()).toList());
      if (_undo.length > 60) _undo.removeAt(0);
      study.elements = next;
      _dirty = true;
      if (_viewCycle != null && !_cycles.contains(_viewCycle)) _viewCycle = null;
    });
  }

  void _undoLast() {
    if (_undo.isEmpty) return _snack('Rien à annuler');
    setState(() {
      study.elements = _undo.removeLast();
      _dirty = true;
    });
  }

  bool _needSel() {
    if (_selIndex < 0) {
      _snack("Sélectionnez d'abord un élément dans le tableau");
      return false;
    }
    return true;
  }

  void _split() {
    final next = ElementEditor.splitAt(elements, _pos);
    _apply(next, 'Placez la lecture à l\'intérieur d\'un élément (pas trop près de ses bords)');
    if (next != null) {
      final i = ElementEditor.indexAt(next, _pos);
      if (i >= 0) setState(() => _selectedId = next[i].id);
    }
  }

  void _merge() {
    if (!_needSel()) return;
    _apply(ElementEditor.mergeWithNext(elements, _selIndex), 'Impossible de fusionner (dernier élément ou cycle différent)');
  }

  void _setStartHere() {
    if (!_needSel()) return;
    _apply(ElementEditor.setStart(elements, _selIndex, _pos), 'Début impossible à cette position');
  }

  void _setEndHere() {
    if (!_needSel()) return;
    _apply(ElementEditor.setEnd(elements, _selIndex, _pos), 'Fin impossible à cette position');
  }

  void _delete() {
    if (!_needSel()) return;
    _apply(ElementEditor.delete(elements, _selIndex), 'Suppression impossible');
    _selectedId = null;
  }

  void _newCycle() {
    if (!_needSel()) return;
    _apply(ElementEditor.startNewCycleAt(elements, _selIndex),
        'Cet élément commence déjà un cycle (ou c\'est le premier)');
  }

  Motion get _manualMotion => library.firstWhere((m) => m.code == _manualCode, orElse: () => library.last);

  void _markStart() => setState(() => _pendingStart = _pos);

  void _markEnd() {
    final s = _pendingStart;
    if (s == null) return _snack('Touchez d\'abord « Début » au début du geste');
    if (_pos <= s) return _snack('La fin doit être après le début (${clock(s)})');
    final next = ElementEditor.addManual(elements, start: s, end: _pos, motion: _manualMotion);
    _apply(next, 'Élément trop court');
    if (next != null) {
      final i = next.indexWhere((e) => (e.start - s).abs() < 1e-9);
      setState(() {
        if (i >= 0) _selectedId = next[i].id;
        _pendingStart = _pos; // chaînage : la fin devient le début du suivant
      });
    }
  }

  Future<void> _editElement(StudyElement e) async {
    final res = await showDialog<StudyElement>(
      context: context,
      builder: (_) => _ElementDialog(element: e.copyWith(), library: library, studyRating: study.rating),
    );
    if (res == null) return;
    final next = ElementEditor.sorted(elements.map((x) => x.id == e.id ? res : x.copyWith()).toList());
    for (var i = 1; i < next.length; i++) {
      if (next[i].start < next[i - 1].end - 1e-6) {
        return _snack('Début / fin en chevauchement avec un élément voisin : modification refusée');
      }
    }
    _apply(next, '');
  }

  void _snack(String m) {
    if (m.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 3)));
  }

  void _scrollToSelected() {
    final i = _visible.indexWhere((e) => e.id == _selectedId);
    if (i < 0 || !_scroll.hasClients) return;
    final target = (i * rowH - rowH * 2).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  // -------------------------------------------------------------------- IA

  Future<void> _runAi() async {
    final path = study.videoPath;
    if (path == null || _ctrl == null) return _snack("Chargez d'abord une vidéo");
    final settings = await settingsService.load();
    if (!mounted) return;
    if (settings.apiKey.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Clé API manquante'),
          content: const Text("Ajoutez votre clé Gemini gratuite dans Réglages pour utiliser le découpage automatique.\n"
              'En attendant, utilisez le découpage manuel (Début / Fin).'),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
      return;
    }
    if (elements.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Remplacer le découpage ?'),
          content: const Text("Le découpage actuel sera remplacé par la proposition de l'IA (vous pourrez annuler)."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Non')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remplacer')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _ctrl?.pause();
    final progress = ValueNotifier('Préparation…');
    var cancelled = false;
    if (!mounted) return;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: ValueListenableBuilder(valueListenable: progress, builder: (_, v, _) => Text(v))),
        ]),
        actions: [
          TextButton(
              onPressed: () {
                cancelled = true;
                Navigator.pop(c);
              },
              child: const Text('Annuler')),
        ],
      ),
    ));
    try {
      final svc = GeminiService(apiKey: settings.apiKey, model: settings.model, fps: settings.fps);
      final prompt = buildSegmentationPrompt(library: library, operation: study.operation, machine: study.machine);
      final text = await svc.analyzeVideo(File(path), prompt, onProgress: (s) => progress.value = s);
      final norm = normalizeAiSegmentation(extractJson(text), library: library, videoDuration: _duration);
      if (cancelled || !mounted) return;
      Navigator.of(context).pop();
      study.aiModel = settings.model;
      _apply(norm.elements, '');
      setState(() {
        _viewCycle = null;
        _selectedId = norm.elements.first.id;
      });
      final cycles = norm.elements.map((e) => e.cycle).toSet().length;
      _snack("IA : ${norm.elements.length} éléments, $cycles cycle(s). Vérifiez et corrigez."
          "${norm.warnings.isEmpty ? '' : '\n${norm.warnings.join(' ')}'}");
    } catch (e) {
      if (cancelled || !mounted) return;
      Navigator.of(context).pop();
      final msg = e is GeminiException || e is AiFormatException ? e.toString() : 'Erreur inattendue : $e';
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Découpage IA impossible'),
          content: Text('$msg\n\nLe découpage manuel reste disponible (boutons Début / Fin).'),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
    } finally {
      progress.dispose();
    }
  }

  // ------------------------------------------------------------ sauvegarde

  Future<void> _save() async {
    await storage.saveStudy(study);
    setState(() => _dirty = false);
    _snack('Étude enregistrée');
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Modifications non enregistrées'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'cancel'), child: const Text('Rester')),
          TextButton(onPressed: () => Navigator.pop(c, 'discard'), child: const Text('Quitter sans enregistrer')),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (r == 'save') {
      await storage.saveStudy(study);
      return true;
    }
    return r == 'discard';
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(study.title, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'En-tête de l\'étude',
              icon: const Icon(Icons.edit_note),
              onPressed: () async {
                final s = await Navigator.push<Study>(
                    context, MaterialPageRoute(builder: (_) => StudyFormScreen(study: study)));
                if (s != null) setState(() => _dirty = true);
              },
            ),
            IconButton(
              tooltip: 'Découpage automatique (IA)',
              icon: const Icon(Icons.auto_awesome),
              onPressed: _runAi,
            ),
            IconButton(tooltip: 'Enregistrer', icon: Icon(Icons.save, color: _dirty ? Colors.orange : null), onPressed: _save),
            IconButton(
              tooltip: 'Résultats et export',
              icon: const Icon(Icons.bar_chart),
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => ResultsScreen(study: study, library: library))),
            ),
          ],
        ),
        body: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          if (wide) {
            return Row(children: [
              SizedBox(
                width: box.maxWidth * 0.40,
                child: SingleChildScrollView(
                  child: Column(children: [_videoArea(maxH: box.maxHeight * 0.5), _playerControls(), _editToolbar()]),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(children: [
                  _cycleBar(),
                  Expanded(child: _table()),
                  SizedBox(height: 170, child: _chart()),
                ]),
              ),
            ]);
          }
          return Column(children: [
            _videoArea(maxH: box.maxHeight * 0.32),
            _playerControls(),
            _editToolbar(),
            _cycleBar(),
            Expanded(child: _table()),
            SizedBox(height: 110, child: _chart()),
          ]);
        }),
      ),
    );
  }

  Widget _videoArea({required double maxH}) {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) {
      return Container(
        height: maxH.clamp(140.0, 320.0),
        color: Colors.black87,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_videoError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_videoError!, style: const TextStyle(color: Colors.orangeAccent), textAlign: TextAlign.center),
            ),
          const Text("Filmez l'opération ou importez une vidéo", style: TextStyle(color: Colors.white)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            if (Platform.isAndroid || Platform.isIOS)
              FilledButton.icon(
                  onPressed: () => _pickVideo(ImageSource.camera),
                  icon: const Icon(Icons.videocam),
                  label: const Text('Filmer')),
            FilledButton.tonalIcon(
                onPressed: () => _pickVideo(ImageSource.gallery),
                icon: const Icon(Icons.video_library),
                label: const Text('Importer')),
          ]),
        ]),
      );
    }
    final cur = ElementEditor.indexAt(elements, _pos);
    final curEl = cur >= 0 ? elements[cur] : null;
    return Container(
      color: Colors.black,
      constraints: BoxConstraints(maxHeight: maxH.clamp(160.0, 600.0)),
      child: Stack(alignment: Alignment.center, children: [
        AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
        Positioned(
          left: 6,
          top: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.black54,
            child: Text(
              '${clock(_pos)}${curEl == null ? '' : '   #${cur + 1} ${curEl.code}  +${fr(_pos - curEl.start, 1)} s'}',
              style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 16, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ),
        Positioned(
          right: 6,
          top: 6,
          child: Material(
            color: Colors.black45,
            child: IconButton(
              tooltip: 'Changer de vidéo',
              icon: const Icon(Icons.swap_horiz, color: Colors.white70, size: 18),
              onPressed: () => _pickVideo(ImageSource.gallery),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _playerControls() {
    final c = _ctrl;
    final enabled = c != null && c.value.isInitialized;
    final dur = enabled ? _duration : 1.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(children: [
        Slider(
          value: _pos.clamp(0, dur).toDouble(),
          max: dur <= 0 ? 1 : dur,
          onChanged: enabled ? (v) => _seek(v) : null,
        ),
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 2, children: [
          IconButton(tooltip: '-0,5 s', onPressed: enabled ? () => _step(-0.5) : null, icon: const Icon(Icons.replay_5)),
          IconButton(tooltip: 'Image précédente (~1/30 s)', onPressed: enabled ? () => _step(-frameStep) : null, icon: const Icon(Icons.skip_previous)),
          IconButton.filled(
            tooltip: 'Lecture / pause',
            onPressed: enabled ? _togglePlay : null,
            icon: Icon(enabled && c.value.isPlaying ? Icons.pause : Icons.play_arrow),
          ),
          IconButton(tooltip: 'Image suivante (~1/30 s)', onPressed: enabled ? () => _step(frameStep) : null, icon: const Icon(Icons.skip_next)),
          IconButton(tooltip: '+0,5 s', onPressed: enabled ? () => _step(0.5) : null, icon: const Icon(Icons.forward_5)),
          const SizedBox(width: 6),
          SegmentedButton<double>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: 0.25, label: Text('¼×')),
              ButtonSegment(value: 0.5, label: Text('½×')),
              ButtonSegment(value: 1, label: Text('1×')),
            ],
            selected: {_speed},
            onSelectionChanged: enabled ? (s) => _setSpeed(s.first) : null,
          ),
        ]),
      ]),
    );
  }

  Widget _editToolbar() {
    Widget b(IconData i, String label, VoidCallback? f, {Color? color}) => Padding(
          padding: const EdgeInsets.all(2),
          child: OutlinedButton.icon(
            onPressed: f,
            icon: Icon(i, size: 18, color: color),
            label: Text(label, style: const TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
          ),
        );
    final hasVideo = _ctrl != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(children: [
        Wrap(alignment: WrapAlignment.center, children: [
          b(Icons.content_cut, 'Couper ici', hasVideo ? _split : null),
          b(Icons.merge_type, 'Fusionner suiv.', _merge),
          b(Icons.first_page, 'Début ici', hasVideo ? _setStartHere : null),
          b(Icons.last_page, 'Fin ici', hasVideo ? _setEndHere : null),
          b(Icons.repeat, 'Nouveau cycle ici', _newCycle),
          b(Icons.delete_outline, 'Supprimer', _delete),
          b(Icons.undo, 'Annuler', _undo.isEmpty ? null : _undoLast),
        ]),
        // Saisie manuelle pendant la lecture.
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Manuel : ', style: TextStyle(fontSize: 12)),
          DropdownButton<String>(
            value: library.any((m) => m.code == _manualCode) ? _manualCode : library.last.code,
            isDense: true,
            items: [
              for (final m in library)
                DropdownMenuItem(value: m.code, child: Text('${m.code} ${m.label}', style: const TextStyle(fontSize: 12))),
            ],
            onChanged: (v) => setState(() => _manualCode = v ?? _manualCode),
          ),
          b(Icons.flag_outlined, _pendingStart == null ? 'Début' : 'Début (${fr(_pendingStart!, 1)})', hasVideo ? _markStart : null,
              color: Colors.green),
          b(Icons.flag, 'Fin', hasVideo ? _markEnd : null, color: Colors.red),
        ]),
      ]),
    );
  }

  Widget _cycleBar() {
    final cycles = _cycles;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(children: [
        const Text('Cycle : '),
        DropdownButton<int?>(
          value: cycles.contains(_viewCycle) ? _viewCycle : null,
          isDense: true,
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Tous')),
            for (final c in cycles) DropdownMenuItem<int?>(value: c, child: Text('$c')),
          ],
          onChanged: (v) => setState(() => _viewCycle = v),
        ),
        const Spacer(),
        Text('${elements.length} éléments · ${cycles.length} cycle(s)', style: const TextStyle(fontSize: 12)),
      ]),
    );
  }

  Widget _table() {
    final rows = _visible;
    final playIdx = ElementEditor.indexAt(elements, _pos);
    final playId = playIdx >= 0 ? elements[playIdx].id : null;
    const head = TextStyle(fontWeight: FontWeight.bold, fontSize: 12);
    Widget cell(double w, Widget child, {Alignment a = Alignment.centerLeft}) =>
        SizedBox(width: w, child: Align(alignment: a, child: child));
    Widget headerRow() => Container(
          height: 34,
          color: const Color(0xFFDDE6F0),
          child: Row(children: [
            cell(46, const Text('N°', style: head), a: Alignment.center),
            cell(50, const Text('Code', style: head)),
            cell(210, const Text('Nom', style: head)),
            cell(66, const Text('Début', style: head), a: Alignment.centerRight),
            cell(66, const Text('Fin', style: head), a: Alignment.centerRight),
            cell(70, const Text('Mesuré', style: head), a: Alignment.centerRight),
            cell(70, const Text('Édité', style: head), a: Alignment.centerRight),
            cell(60, const Text('Allure', style: head), a: Alignment.center),
            cell(112, const Text('Classe', style: head), a: Alignment.center),
            cell(40, const Text('VA', style: head), a: Alignment.center),
            cell(40, const Text('IA', style: head), a: Alignment.center),
            cell(30, const SizedBox()),
          ]),
        );
    if (elements.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            "Aucun élément.\n✨ Lancez le découpage IA (icône en haut), ou saisissez à la main : choisissez le mouvement, "
            'touchez « Début » puis « Fin » pendant la lecture.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: tableWidth,
        child: Column(children: [
          headerRow(),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemExtent: rowH,
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final e = rows[i];
                final globalIdx = elements.indexOf(e);
                final color = motionColor(e.code, e.motionClass, library);
                final selected = e.id == _selectedId;
                final playing = e.id == playId;
                final firstOfCycle = globalIdx == 0 || elements[globalIdx - 1].cycle != e.cycle;
                final bg = playing
                    ? const Color(0xFFB9F6CA)
                    : selected
                        ? const Color(0xFFE3F2FD)
                        : (i.isEven ? Colors.white : const Color(0xFFF7F9FB));
                final lowConf = e.confidence != null && e.confidence! < 0.5;
                return InkWell(
                  onTap: () {
                    setState(() => _selectedId = e.id);
                    _seek(e.start + 0.001);
                  },
                  onDoubleTap: () => _editElement(e),
                  onLongPress: () => _editElement(e),
                  child: Container(
                    decoration: BoxDecoration(
                      color: bg,
                      border: Border(
                        top: firstOfCycle ? const BorderSide(color: Colors.indigo, width: 2) : BorderSide.none,
                        bottom: const BorderSide(color: Colors.black12),
                        left: BorderSide(color: playing ? Colors.deepOrange : Colors.transparent, width: 4),
                      ),
                    ),
                    child: Row(children: [
                      cell(
                        42,
                        Container(
                          width: 34,
                          height: 26,
                          alignment: Alignment.center,
                          color: color,
                          child: Text('${i + 1}', style: TextStyle(color: onColor(color), fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        a: Alignment.center,
                      ),
                      cell(50, Text(e.code, style: const TextStyle(fontWeight: FontWeight.w600))),
                      cell(
                          210,
                          Text(
                            (_viewCycle == null ? 'C${e.cycle} · ' : '') + e.label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: playing ? Colors.red.shade900 : null),
                          )),
                      cell(66, Text(fr(e.start)), a: Alignment.centerRight),
                      cell(66, Text(fr(e.end)), a: Alignment.centerRight),
                      cell(70, Text(fr(e.measured), style: const TextStyle(fontWeight: FontWeight.w600)), a: Alignment.centerRight),
                      cell(70, Text(e.editedTime == null ? '—' : fr(e.editedTime!)), a: Alignment.centerRight),
                      cell(60, Text('${e.rating ?? study.rating} %', style: TextStyle(color: e.rating == null ? Colors.grey : null)),
                          a: Alignment.center),
                      cell(
                        112,
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          color: Color(e.motionClass.defaultColor).withValues(alpha: 0.5),
                          child: Text(e.motionClass.label, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                        ),
                        a: Alignment.center,
                      ),
                      cell(
                        40,
                        Checkbox(
                          value: e.valueAdded,
                          visualDensity: VisualDensity.compact,
                          onChanged: (v) {
                            final next = elements.map((x) => x.copyWith()).toList();
                            next[globalIdx].valueAdded = v ?? false;
                            _apply(next, '');
                          },
                        ),
                        a: Alignment.center,
                      ),
                      cell(
                        40,
                        e.confidence == null
                            ? const SizedBox()
                            : Text('${(e.confidence! * 100).round()}',
                                style: TextStyle(fontSize: 11, color: lowConf ? Colors.red : Colors.grey.shade700)),
                        a: Alignment.center,
                      ),
                      cell(
                        30,
                        IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          tooltip: 'Modifier',
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editElement(e),
                        ),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _chart() {
    final rows = _visible;
    final playIdx = rows.indexWhere((e) => _pos >= e.start && _pos < e.end);
    return ElementChart(
      bars: [
        for (final e in rows)
          ChartBar(
            label: '${e.code} ${e.label}',
            value: e.observed,
            color: motionColor(e.code, e.motionClass, library),
            tooltip: 'normal ${fr(normalTime(e, study.rating))} s',
          ),
      ],
      highlight: playIdx >= 0 ? playIdx : null,
      onTap: (i) {
        if (i < rows.length) {
          setState(() => _selectedId = rows[i].id);
          _seek(rows[i].start + 0.001);
        }
      },
    );
  }
}

/// Dialogue de modification d'un élément.
class _ElementDialog extends StatefulWidget {
  const _ElementDialog({required this.element, required this.library, required this.studyRating});
  final StudyElement element;
  final List<Motion> library;
  final int studyRating;
  @override
  State<_ElementDialog> createState() => _ElementDialogState();
}

class _ElementDialogState extends State<_ElementDialog> {
  late final e = widget.element;
  late String _code = widget.library.any((m) => m.code == e.code) ? e.code : kOtherCode;
  late final _label = TextEditingController(text: e.label);
  late final _rating = TextEditingController(text: e.rating?.toString() ?? '');
  late final _edited = TextEditingController(text: e.editedTime == null ? '' : fr(e.editedTime!));
  late final _start = TextEditingController(text: fr(e.start, 3));
  late final _end = TextEditingController(text: fr(e.end, 3));
  late bool _va = e.valueAdded;
  String? _error;

  double? _d(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Élément ${e.code}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: _code,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Mouvement (bibliothèque)'),
              items: [
                for (final m in widget.library)
                  DropdownMenuItem(
                    value: m.code,
                    child: Row(children: [
                      Container(width: 14, height: 14, color: Color(m.color)),
                      const SizedBox(width: 6),
                      Expanded(child: Text('${m.code} — ${m.label}', overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                final m = widget.library.firstWhere((x) => x.code == v);
                setState(() {
                  _code = v;
                  _label.text = m.label;
                  _va = m.valueAdded;
                });
              },
            ),
            TextField(controller: _label, decoration: const InputDecoration(labelText: 'Nom affiché')),
            Row(children: [
              Expanded(child: TextField(controller: _start, decoration: const InputDecoration(labelText: 'Début (s)'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _end, decoration: const InputDecoration(labelText: 'Fin (s)'))),
            ]),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _rating,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'Allure (%)', hintText: 'vide = ${widget.studyRating}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _edited,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Temps édité (s)', hintText: 'vide = mesuré'),
                ),
              ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Travail efficace (valeur ajoutée)'),
              value: _va,
              onChanged: (v) => setState(() => _va = v),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final s = _d(_start.text), en = _d(_end.text);
            final r = _rating.text.trim().isEmpty ? null : int.tryParse(_rating.text.trim().replaceAll('%', ''));
            final ed = _d(_edited.text);
            if (s == null || en == null || en - s < ElementEditor.minDuration || s < 0) {
              return setState(() => _error = 'Début / fin invalides');
            }
            if (_rating.text.trim().isNotEmpty && (r == null || r < 30 || r > 200)) {
              return setState(() => _error = 'Allure entre 30 et 200 %');
            }
            if (_edited.text.trim().isNotEmpty && (ed == null || ed <= 0)) {
              return setState(() => _error = 'Temps édité invalide');
            }
            final m = widget.library.firstWhere((x) => x.code == _code);
            e.applyMotion(m, keepLabel: true);
            e
              ..label = _label.text.trim().isEmpty ? m.label : _label.text.trim()
              ..valueAdded = _va
              ..start = s
              ..end = en
              ..rating = r
              ..editedTime = ed;
            Navigator.pop(context, e);
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}
