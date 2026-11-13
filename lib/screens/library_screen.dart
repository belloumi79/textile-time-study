import 'package:material_ui/material_ui.dart';

import '../models/motion.dart';
import '../services/app_services.dart';
import '../widgets/motion_colors.dart';

const _palette = [
  0xFFFFD54F, 0xFFFFB300, 0xFF4FC3F7, 0xFF0288D1, 0xFF81D4FA, 0xFF4DD0E1, 0xFF26A69A, 0xFF66BB6A,
  0xFF2E7D32, 0xFF81C784, 0xFFFF8A65, 0xFFE53935, 0xFFBA68C8, 0xFF9575CD, 0xFFBDBDBD, 0xFF90A4AE,
];

/// Bibliothèque de mouvements maison (éditable).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Motion>? _lib;

  @override
  void initState() {
    super.initState();
    storage.loadLibrary().then((l) => mounted ? setState(() => _lib = l) : null);
  }

  Future<void> _persist() async {
    await storage.saveLibrary(_lib!);
    if (mounted) setState(() {});
  }

  Future<void> _edit([Motion? m]) async {
    final res = await showDialog<Motion>(
      context: context,
      builder: (_) => MotionDialog(motion: m, existingCodes: _lib!.map((e) => e.code).toSet()..remove(m?.code)),
    );
    if (res == null) return;
    if (m == null) {
      _lib!.add(res);
    } else {
      final i = _lib!.indexOf(m);
      _lib![i] = res;
    }
    await _persist();
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Rétablir la bibliothèque par défaut ?'),
        content: const Text('Vos mouvements personnalisés seront remplacés. Les études existantes ne sont pas modifiées.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Rétablir')),
        ],
      ),
    );
    if (ok == true) {
      _lib = defaultMotionLibrary();
      await _persist();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = _lib;
    return Scaffold(
      appBar: AppBar(title: const Text('Bibliothèque de mouvements'), actions: [
        IconButton(tooltip: 'Rétablir par défaut', icon: const Icon(Icons.restore), onPressed: lib == null ? null : _reset),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: lib == null ? null : () => _edit(), child: const Icon(Icons.add)),
      body: lib == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: lib.length,
              itemBuilder: (_, i) {
                final m = lib[i];
                final c = Color(m.color);
                return ListTile(
                  leading: Container(
                    width: 48,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
                    child: Text(m.code, style: TextStyle(color: onColor(c), fontWeight: FontWeight.bold)),
                  ),
                  title: Text(m.label),
                  subtitle: Text('${m.motionClass.label} · ${m.valueAdded ? 'valeur ajoutée' : 'sans valeur ajoutée'}'
                      '${m.description.isEmpty ? '' : ' · ${m.description}'}'),
                  onTap: () => _edit(m),
                  trailing: m.code == kOtherCode
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Supprimer',
                          onPressed: () async {
                            lib.removeAt(i);
                            await _persist();
                          },
                        ),
                );
              },
            ),
    );
  }
}

class MotionDialog extends StatefulWidget {
  const MotionDialog({super.key, this.motion, required this.existingCodes});
  final Motion? motion;
  final Set<String> existingCodes;
  @override
  State<MotionDialog> createState() => _MotionDialogState();
}

class _MotionDialogState extends State<MotionDialog> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.motion?.code ?? '');
  late final _label = TextEditingController(text: widget.motion?.label ?? '');
  late final _desc = TextEditingController(text: widget.motion?.description ?? '');
  late MotionClass _cls = widget.motion?.motionClass ?? MotionClass.positionnement;
  late bool _va = widget.motion?.valueAdded ?? false;
  late int _color = widget.motion?.color ?? (widget.motion?.motionClass ?? MotionClass.positionnement).defaultColor;

  @override
  Widget build(BuildContext context) {
    final isOther = widget.motion?.code == kOtherCode;
    return AlertDialog(
      title: Text(widget.motion == null ? 'Nouveau mouvement' : 'Modifier le mouvement'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _code,
                enabled: !isOther,
                decoration: const InputDecoration(labelText: 'Code court (maison)', hintText: 'ex. CD2'),
                textCapitalization: TextCapitalization.characters,
                validator: (v) {
                  final s = (v ?? '').trim().toUpperCase();
                  if (s.isEmpty || s.length > 6) return '1 à 6 caractères';
                  if (widget.existingCodes.contains(s)) return 'Code déjà utilisé';
                  return null;
                },
              ),
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Libellé'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
              ),
              TextFormField(controller: _desc, decoration: const InputDecoration(labelText: 'Description (aide pour l\'IA)')),
              const SizedBox(height: 8),
              DropdownButtonFormField<MotionClass>(
                initialValue: _cls,
                decoration: const InputDecoration(labelText: 'Classe'),
                items: [for (final c in MotionClass.values) DropdownMenuItem(value: c, child: Text(c.label))],
                onChanged: (c) => setState(() => _cls = c ?? _cls),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Valeur ajoutée'),
                value: _va,
                onChanged: (v) => setState(() => _va = v),
              ),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in _palette)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(color: c == _color ? Colors.black : Colors.black12, width: c == _color ? 3 : 1),
                      ),
                    ),
                  ),
              ]),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              Motion(
                code: _code.text.trim().toUpperCase(),
                label: _label.text.trim(),
                motionClass: _cls,
                valueAdded: _va,
                color: _color,
                description: _desc.text.trim(),
              ),
            );
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}
