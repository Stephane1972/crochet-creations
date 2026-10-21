import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/money.dart';
import '../../core/utils/texte.dart';
import '../../core/utils/validateurs.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/produit_repository.dart';

/// Formulaire d'ajout ou de modification d'une variante (couleur, taille...).
/// Retourne les données saisies, ou `null` si elle annule.
Future<DonneesVariante?> afficherFormulaireVariante(
  BuildContext context, {
  VarianteProduit? variante,
}) {
  return showModalBottomSheet<DonneesVariante>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext contexteFeuille) => _FormulaireVariante(variante: variante),
  );
}

class _FormulaireVariante extends StatefulWidget {
  const _FormulaireVariante({this.variante});

  final VarianteProduit? variante;

  @override
  State<_FormulaireVariante> createState() => _FormulaireVarianteState();
}

class _FormulaireVarianteState extends State<_FormulaireVariante> {
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();
  late final TextEditingController _libelle = TextEditingController(text: widget.variante?.libelle);
  late final TextEditingController _couleur = TextEditingController(text: widget.variante?.couleur);
  late final TextEditingController _taille = TextEditingController(text: widget.variante?.taille);
  late final TextEditingController _prix = TextEditingController(
    text: widget.variante?.prixCentimes == null
        ? ''
        : formatMontantSaisie(widget.variante!.prixCentimes!),
  );
  late final TextEditingController _stock = TextEditingController(
    text: (widget.variante?.quantiteStock ?? 0).toString(),
  );
  late final TextEditingController _seuil = TextEditingController(
    text: widget.variante?.seuilAlerteStock?.toString() ?? '',
  );

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _libelle,
      _couleur,
      _taille,
      _prix,
      _stock,
      _seuil,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _valider() {
    if (!_formulaire.currentState!.validate()) return;
    Navigator.of(context).pop(
      DonneesVariante(
        libelle: _libelle.text.trim(),
        couleur: nullSiVide(_couleur.text),
        taille: nullSiVide(_taille.text),
        prixCentimes: parseMontantEuros(_prix.text),
        quantiteStock: lireEntier(_stock.text) ?? 0,
        seuilAlerteStock: lireEntier(_seuil.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool creation = widget.variante == null;
    final List<TextInputFormatter> chiffres = <TextInputFormatter>[
      FilteringTextInputFormatter.digitsOnly,
    ];

    return Padding(
      // Le clavier ne doit pas cacher les champs.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: _formulaire,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                creation ? 'Nouvelle variante' : 'Modifier la variante',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _libelle,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nom de la variante *',
                  hintText: 'Ex. Rose – taille M',
                ),
                validator: (String? v) =>
                    validerObligatoire(v, 'Le nom de la variante est obligatoire.') ??
                    validerLongueurMax(v, 120, 'Le nom'),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      controller: _couleur,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Couleur'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _taille,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Taille'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _prix,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Prix (€)',
                  helperText: 'Laissez vide pour garder le prix du produit.',
                ),
                validator: validerMontantFacultatif,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      controller: _stock,
                      keyboardType: TextInputType.number,
                      inputFormatters: chiffres,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Stock'),
                      validator: (String? v) => validerEntier(v, obligatoire: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _seuil,
                      keyboardType: TextInputType.number,
                      inputFormatters: chiffres,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Seuil d’alerte',
                        helperText: 'Vide = celui du produit',
                      ),
                      validator: validerEntier,
                      onFieldSubmitted: (String _) => _valider(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _valider,
                    child: Text(creation ? 'Ajouter' : 'Enregistrer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
