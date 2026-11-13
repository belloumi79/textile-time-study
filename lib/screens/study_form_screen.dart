import 'package:material_ui/material_ui.dart';

import '../models/study.dart';
import '../services/format.dart';

/// En-tête de l'étude : article, opération, machine, opératrice, allure, majoration.
class StudyFormScreen extends StatefulWidget {
  const StudyFormScreen({super.key, required this.study});
  final Study study;
  @override
  State<StudyFormScreen> createState() => _StudyFormScreenState();
}

class _StudyFormScreenState extends State<StudyFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _article = TextEditingController(text: widget.study.article);
  late final _operation = TextEditingController(text: widget.study.operation);
  late final _machine = TextEditingController(text: widget.study.machine);
  late final _operator = TextEditingController(text: widget.study.operatorName);
  late final _rating = TextEditingController(text: '${widget.study.rating}');
  late final _allowance = TextEditingController(text: fr(widget.study.allowance, 1));
  late final _eff = TextEditingController(text: fr(widget.study.efficiency, 0));
  late DateTime _date = widget.study.date;

  double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.').replaceAll('%', ''));

  String? _range(String? v, double min, double max) {
    final d = _parse(v ?? '');
    if (d == null) return 'Nombre attendu';
    if (d < min || d > max) return 'Entre ${fr(min, 0)} et ${fr(max, 0)}';
    return null;
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final s = widget.study
      ..article = _article.text.trim()
      ..operation = _operation.text.trim()
      ..machine = _machine.text.trim()
      ..operatorName = _operator.text.trim()
      ..date = _date
      ..rating = _parse(_rating.text)!.round()
      ..allowance = _parse(_allowance.text)!
      ..efficiency = _parse(_eff.text)!;
    Navigator.pop(context, s);
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label, {String? hint, String? Function(String?)? validator, bool number = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            controller: c,
            decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
            keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
            validator: validator,
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text("Étude — en-tête"), actions: [
        TextButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const Text('Valider')),
      ]),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            field(_operation, 'Opération *', hint: 'ex. Montage col', validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null),
            field(_article, 'Article / modèle', hint: 'ex. Polo H 1234'),
            field(_machine, 'Machine / type de point', hint: 'ex. Piqueuse plate 301, Surjeteuse 504'),
            field(_operator, 'Opératrice'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('Date : ${frDate(_date)}'),
              onTap: () async {
                final d = await showDatePicker(
                    context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (d != null) setState(() => _date = d);
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: field(_rating, 'Allure (%)', number: true, validator: (v) => _range(v, 30, 200))),
              const SizedBox(width: 12),
              Expanded(child: field(_allowance, 'Majoration (%)', number: true, validator: (v) => _range(v, 0, 100))),
              const SizedBox(width: 12),
              Expanded(child: field(_eff, 'Rendement (%)', number: true, validator: (v) => _range(v, 1, 200))),
            ]),
            const Text(
              "Allure : jugement global de la vitesse de l'opératrice (100 = normale), modifiable par élément.\n"
              'Majoration : repos, besoins personnels, aléas (≈ 15 % par défaut).\n'
              'Rendement : pour la production horaire réaliste.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
