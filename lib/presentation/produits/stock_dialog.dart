import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/validateurs.dart';

/// Demande la nouvelle quantité en stock (inventaire). Retourne `null` si elle annule.
Future<int?> demanderQuantiteStock(
  BuildContext context, {
  required String designation,
  required int quantiteActuelle,
}) {
  return showDialog<int>(
    context: context,
    builder: (BuildContext contexteDialogue) =>
        _DialogueStock(designation: designation, quantiteActuelle: quantiteActuelle),
  );
}

class _DialogueStock extends StatefulWidget {
  const _DialogueStock({required this.designation, required this.quantiteActuelle});

  final String designation;
  final int quantiteActuelle;

  @override
  State<_DialogueStock> createState() => _DialogueStockState();
}

class _DialogueStockState extends State<_DialogueStock> {
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();
  late final TextEditingController _quantite = TextEditingController(
    text: widget.quantiteActuelle.toString(),
  );

  @override
  void dispose() {
    _quantite.dispose();
    super.dispose();
  }

  void _valider() {
    if (!_formulaire.currentState!.validate()) return;
    Navigator.of(context).pop(lireEntier(_quantite.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajuster le stock'),
      content: Form(
        key: _formulaire,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.designation, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('Quantité actuelle : ${widget.quantiteActuelle}'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _quantite,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Nouvelle quantité en stock'),
              validator: (String? v) => validerEntier(v, obligatoire: true),
              onFieldSubmitted: (String _) => _valider(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _valider, child: const Text('Enregistrer')),
      ],
    );
  }
}
