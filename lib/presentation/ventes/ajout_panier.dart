import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/money.dart';
import '../../core/utils/validateurs.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/produit_vues.dart';
import '../../domain/calculs/stock.dart';
import '../../domain/enums.dart';
import '../../domain/erreurs.dart';
import 'panier_provider.dart';

/// Ajoute un produit au panier de la vente en cours, en demandant la variante si le produit
/// en a. Retourne `true` si l'article a été ajouté. Un refus (stock insuffisant, produit non
/// vendable...) est affiché en français et retourne `false`.
Future<bool> ajouterAuPanier(
  BuildContext context,
  WidgetRef ref,
  ProduitResume resume, {
  double margeBas = 0,
}) async {
  VarianteProduit? variante;
  if (resume.aDesVariantes) {
    variante = await choisirVariante(context, resume);
    if (variante == null || !context.mounted) return false;
  }
  try {
    ref.read(venteEnCoursProvider.notifier).ajouterProduit(resume, variante: variante);
    return true;
  } on ErreurMetier catch (erreur) {
    if (context.mounted) afficherMessage(context, erreur.message, margeBas: margeBas);
    return false;
  }
}

/// Feuille du bas : choix d'une variante (couleur, taille...) d'un produit. `null` si on ferme.
Future<VarianteProduit?> choisirVariante(BuildContext context, ProduitResume resume) {
  final bool suivi = suitLeStock(resume.produit.statut);
  return showModalBottomSheet<VarianteProduit>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext contexteFeuille) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Quelle variante de « ${resume.produit.nom} » ?',
              style: Theme.of(contexteFeuille).textTheme.titleMedium,
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                for (final VarianteProduit v in resume.variantes)
                  ListTile(
                    title: Text(v.libelle),
                    subtitle: Text(
                      !suivi
                          ? 'Fabriquée à la demande'
                          : (v.quantiteStock <= 0
                                ? 'Épuisée'
                                : (v.quantiteStock == 1 ? '1 en stock' : '${v.quantiteStock} en stock')),
                    ),
                    trailing: Text(formatEuros(v.prixCentimes ?? resume.produit.prixVenteCentimes)),
                    enabled: !suivi || v.quantiteStock > 0,
                    onTap: () => Navigator.of(contexteFeuille).pop(v),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Ce que saisit la vendeuse pour une ligne libre (vente ou devis).
class LigneLibreSaisie {
  const LigneLibreSaisie({
    required this.designation,
    required this.description,
    required this.nature,
    required this.prixCentimes,
    required this.quantite,
  });

  final String designation;
  final String? description;
  final NatureLigne nature;
  final int prixCentimes;
  final int quantite;
}

/// Demande une ligne libre (création sur mesure, cours, prestation...). `null` si on ferme la fenêtre.
/// Avec [initiale], la fenêtre sert à **modifier** une ligne existante.
Future<LigneLibreSaisie?> demanderLigneLibre(BuildContext context, {LigneLibreSaisie? initiale}) {
  return showDialog<LigneLibreSaisie>(
    context: context,
    builder: (BuildContext contexteDialogue) => DialogueLigneLibre(initiale: initiale),
  );
}

/// Demande une ligne libre (création sur mesure, cours, prestation...) et l'ajoute au panier.
Future<bool> ajouterLigneLibre(BuildContext context, WidgetRef ref, {double margeBas = 0}) async {
  final LigneLibreSaisie? saisie = await demanderLigneLibre(context);
  if (saisie == null || !context.mounted) return false;
  try {
    ref
        .read(venteEnCoursProvider.notifier)
        .ajouterLigneLibre(
          designation: saisie.designation,
          description: saisie.description,
          nature: saisie.nature,
          prixUnitaireCentimes: saisie.prixCentimes,
          quantite: saisie.quantite,
        );
    return true;
  } on ErreurMetier catch (erreur) {
    afficherMessage(context, erreur.message, margeBas: margeBas);
    return false;
  }
}

/// Fenêtre de saisie d'une ligne libre. Avec [initiale], les champs sont préremplis (modification).
class DialogueLigneLibre extends StatefulWidget {
  const DialogueLigneLibre({super.key, this.initiale});

  final LigneLibreSaisie? initiale;

  @override
  State<DialogueLigneLibre> createState() => _DialogueLigneLibreState();
}

class _DialogueLigneLibreState extends State<DialogueLigneLibre> {
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();
  late final TextEditingController _designation = TextEditingController(text: widget.initiale?.designation ?? '');
  late final TextEditingController _description = TextEditingController(text: widget.initiale?.description ?? '');
  late final TextEditingController _prix = TextEditingController(
    text: widget.initiale == null ? '' : formatMontantSaisie(widget.initiale!.prixCentimes),
  );
  late final TextEditingController _quantite = TextEditingController(text: '${widget.initiale?.quantite ?? 1}');
  late NatureLigne _nature = widget.initiale?.nature ?? NatureLigne.service;

  bool get _modification => widget.initiale != null;

  @override
  void dispose() {
    _designation.dispose();
    _description.dispose();
    _prix.dispose();
    _quantite.dispose();
    super.dispose();
  }

  void _ajouter() {
    if (!_formulaire.currentState!.validate()) return;
    final String description = _description.text.trim();
    Navigator.of(context).pop(
      LigneLibreSaisie(
        designation: _designation.text.trim(),
        description: description.isEmpty ? null : description,
        nature: _nature,
        prixCentimes: parseMontantEuros(_prix.text)!,
        quantite: lireEntier(_quantite.text)!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_modification ? 'Modifier la ligne' : 'Article ou prestation libre'),
      content: SingleChildScrollView(
        child: Form(
          key: _formulaire,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SegmentedButton<NatureLigne>(
                segments: <ButtonSegment<NatureLigne>>[
                  for (final NatureLigne n in NatureLigne.values)
                    ButtonSegment<NatureLigne>(value: n, label: Text(n.libelle)),
                ],
                selected: <NatureLigne>{_nature},
                showSelectedIcon: false,
                onSelectionChanged: (Set<NatureLigne> choix) => setState(() => _nature = choix.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _designation,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Désignation'),
                validator: (String? v) => validerObligatoire(v, 'Indiquez le nom de l’article.'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Description (facultatif)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _prix,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Prix unitaire (€)'),
                validator: (String? v) => validerMontantObligatoire(v, 'Indiquez le prix.'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantite,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantité'),
                validator: (String? v) {
                  final String? probleme = validerEntier(v, obligatoire: true, max: 9999);
                  if (probleme != null) return probleme;
                  return (lireEntier(v) ?? 0) < 1 ? 'La quantité doit être d’au moins 1.' : null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _ajouter, child: Text(_modification ? 'Enregistrer' : 'Ajouter')),
      ],
    );
  }
}
