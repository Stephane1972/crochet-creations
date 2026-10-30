import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_fr.dart';
import '../../core/utils/money.dart';
import '../../core/utils/validateurs.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/depense_repository.dart';
import '../../data/stockage/selecteur_photo.dart';
import '../../domain/enums.dart';
import '../common/choix_photo.dart';
import '../produits/photos_formulaire.dart';
import 'depenses_widgets.dart';
import 'selecteur_produit.dart';

enum _ActionDepense { archiver, restaurer }

/// Création et modification d'une dépense. Sans [depenseId] : nouvelle dépense.
///
/// Date, catégorie, montant, fournisseur, description, photo du ticket et produit concerné (facultatif).
/// Une dépense ne se supprime pas : on l'archive (elle quitte la liste et les totaux) et on peut la restaurer.
class DepenseFormScreen extends ConsumerStatefulWidget {
  const DepenseFormScreen({super.key, this.depenseId});

  final int? depenseId;

  @override
  ConsumerState<DepenseFormScreen> createState() => _DepenseFormScreenState();
}

class _DepenseFormScreenState extends ConsumerState<DepenseFormScreen> {
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();

  final TextEditingController _montant = TextEditingController();
  final TextEditingController _fournisseur = TextEditingController();
  final TextEditingController _description = TextEditingController();

  late DateTime _date;
  CategorieDepense _categorie = CategorieDepense.laineFil;
  Produit? _produit;
  bool _archivee = false;

  // La photo est copiée tout de suite dans l'application, mais liée à la dépense à l'enregistrement seulement.
  late final PhotosFormulaire _photos = PhotosFormulaire(stockage: ref.read(stockagePhotosProvider));

  bool _chargement = true;
  bool _introuvable = false;
  bool _erreurChargement = false;
  bool _modifie = false;
  bool _enregistre = false;
  bool _enCours = false;

  bool get _creation => widget.depenseId == null;

  @override
  void initState() {
    super.initState();
    _date = jourDuJour();
    if (_creation) {
      _chargement = false;
    } else {
      _charger();
    }
  }

  /// Aujourd'hui, à minuit.
  static DateTime jourDuJour() {
    final DateTime maintenant = DateTime.now();
    return DateTime(maintenant.year, maintenant.month, maintenant.day);
  }

  @override
  void dispose() {
    _montant.dispose();
    _fournisseur.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final Depense? depense = await ref.read(depenseRepositoryProvider).obtenir(widget.depenseId!);
      if (!mounted) return;
      if (depense == null) {
        setState(() {
          _introuvable = true;
          _chargement = false;
        });
        return;
      }
      final int? produitId = depense.produitId;
      final Produit? produit = produitId == null ? null : await ref.read(produitRepositoryProvider).obtenir(produitId);
      if (!mounted) return;
      setState(() {
        _date = depense.dateDepense;
        _categorie = depense.categorie;
        _montant.text = formatMontantSaisie(depense.montantCentimes);
        _fournisseur.text = depense.fournisseur ?? '';
        _description.text = depense.description ?? '';
        _produit = produit;
        _photos.principale = depense.photoTicketChemin;
        _archivee = depense.archiveLe != null;
        _chargement = false;
      });
    } catch (erreur, pile) {
      debugPrint('Chargement de la dépense impossible : $erreur\n$pile');
      if (!mounted) return;
      setState(() {
        _erreurChargement = true;
        _chargement = false;
      });
    }
  }

  void _marquerModifie() {
    if (!_modifie) setState(() => _modifie = true);
  }

  // --- Date -------------------------------------------------------------------

  Future<void> _choisirDate() async {
    final DateTime aujourdhui = jourDuJour();
    final DateTime premier = DateTime(aujourdhui.year - 5);
    final DateTime initiale = _date.isBefore(premier) ? premier : (_date.isAfter(aujourdhui) ? aujourdhui : _date);
    final DateTime? choisie = await showDatePicker(
      context: context,
      initialDate: initiale,
      firstDate: premier,
      lastDate: aujourdhui,
      helpText: 'Date de la dépense',
    );
    if (choisie == null || !mounted) return;
    setState(() {
      _date = DateTime(choisie.year, choisie.month, choisie.day);
      _modifie = true;
    });
  }

  // --- Photo du ticket --------------------------------------------------------

  Future<String?> _choisirFichier(ChoixPhoto choix) async {
    try {
      return await ref
          .read(selecteurPhotoProvider)
          .choisir(choix == ChoixPhoto.appareil ? SourcePhoto.appareil : SourcePhoto.galerie);
    } catch (erreur, pile) {
      debugPrint('Photo impossible : $erreur\n$pile');
      if (mounted) {
        afficherMessage(
          context,
          'Impossible d’utiliser cette photo. Vérifiez que l’application a le droit '
          'd’accéder à l’appareil photo et aux photos.',
        );
      }
      return null;
    }
  }

  Future<void> _changerPhoto() async {
    final ChoixPhoto? choix = await demanderChoixPhoto(context, retirable: _photos.principale != null);
    if (choix == null || !mounted) return;
    final String? source = choix == ChoixPhoto.retirer ? null : await _choisirFichier(choix);
    if (choix != ChoixPhoto.retirer && (source == null || !mounted)) return;
    try {
      await _photos.remplacerPrincipale(source);
      if (mounted) setState(() => _modifie = true);
    } catch (erreur, pile) {
      debugPrint('Photo impossible : $erreur\n$pile');
      if (mounted) {
        afficherMessage(context, 'Impossible d’enregistrer cette photo. Réessayez avec une autre photo.');
      }
    }
  }

  // --- Enregistrement ---------------------------------------------------------

  DonneesDepense _construireDonnees() {
    return DonneesDepense(
      date: _date,
      categorie: _categorie,
      montantCentimes: parseMontantEuros(_montant.text)!,
      fournisseur: _fournisseur.text,
      description: _description.text,
      photoTicketChemin: _photos.principale,
      produitId: _produit?.id,
    );
  }

  Future<void> _enregistrer() async {
    if (_enCours) return;
    if (!_formulaire.currentState!.validate()) {
      afficherMessage(context, 'Corrigez les champs signalés en rouge.');
      return;
    }
    setState(() => _enCours = true);
    try {
      final DepenseRepository repo = ref.read(depenseRepositoryProvider);
      final DonneesDepense donnees = _construireDonnees();
      if (_creation) {
        await repo.creer(donnees);
      } else {
        await repo.modifier(widget.depenseId!, donnees);
      }

      // Enregistré : l'ancienne photo peut partir, la nouvelle appartient à la dépense.
      await _photos.apresEnregistrement();

      if (!mounted) return;
      _enregistre = true;
      afficherMessage(context, _creation ? 'Dépense enregistrée.' : 'Modifications enregistrées.');
      Navigator.of(context).pop();
    } catch (erreur, pile) {
      debugPrint('Enregistrement de la dépense impossible : $erreur\n$pile');
      if (mounted) {
        afficherMessage(context, messageErreur(erreur));
        setState(() => _enCours = false);
      }
    }
  }

  Future<void> _archiver() async {
    final bool oui = await confirmer(
      context,
      titre: 'Archiver cette dépense ?',
      message: 'Elle disparaît de la liste et des totaux. Vous pourrez la retrouver dans « Archivées » et la restaurer.',
      libelleConfirmer: 'Archiver',
    );
    if (!oui || !mounted) return;
    await _changerArchivage(
      () => ref.read(depenseRepositoryProvider).archiver(widget.depenseId!),
      'Dépense archivée.',
    );
  }

  Future<void> _restaurer() {
    return _changerArchivage(
      () => ref.read(depenseRepositoryProvider).restaurer(widget.depenseId!),
      'Dépense restaurée.',
    );
  }

  Future<void> _changerArchivage(Future<void> Function() action, String confirmation) async {
    if (_enCours) return;
    setState(() => _enCours = true);
    try {
      await action();
      // Ce qui était saisi mais pas enregistré est abandonné : les photos copiées pour rien partent.
      await _photos.abandonner();
      if (!mounted) return;
      _enregistre = true; // plus rien à protéger : on peut quitter
      afficherMessage(context, confirmation);
      Navigator.of(context).pop();
    } catch (erreur, pile) {
      debugPrint('Archivage de la dépense impossible : $erreur\n$pile');
      if (mounted) {
        afficherMessage(context, messageErreur(erreur));
        setState(() => _enCours = false);
      }
    }
  }

  Future<void> _demanderAbandon() async {
    final bool abandonner = await confirmer(
      context,
      titre: 'Abandonner les modifications ?',
      message: 'Ce que vous avez saisi ne sera pas enregistré.',
      libelleConfirmer: 'Abandonner',
      libelleAnnuler: 'Continuer la saisie',
    );
    if (!abandonner || !mounted) return;
    await _photos.abandonner();
    if (mounted) {
      setState(() => _enregistre = true); // plus rien à protéger : on peut quitter
      Navigator.of(context).pop();
    }
  }

  // --- Interface --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool chargee = !_chargement && !_introuvable && !_erreurChargement;
    return PopScope(
      canPop: _enregistre || !_modifie,
      onPopInvokedWithResult: (bool didPop, Object? resultat) {
        if (!didPop) _demanderAbandon();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_creation ? 'Nouvelle dépense' : 'Modifier la dépense'),
          actions: <Widget>[
            if (chargee)
              TextButton(onPressed: _enCours ? null : _enregistrer, child: const Text('Enregistrer')),
            if (chargee && !_creation)
              PopupMenuButton<_ActionDepense>(
                tooltip: 'Plus d’actions',
                onSelected: (_ActionDepense action) {
                  switch (action) {
                    case _ActionDepense.archiver:
                      _archiver();
                    case _ActionDepense.restaurer:
                      _restaurer();
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<_ActionDepense>>[
                  if (_archivee)
                    const PopupMenuItem<_ActionDepense>(
                      value: _ActionDepense.restaurer,
                      child: ListTile(
                        leading: Icon(Icons.unarchive_outlined),
                        title: Text('Restaurer la dépense'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    )
                  else
                    const PopupMenuItem<_ActionDepense>(
                      value: _ActionDepense.archiver,
                      child: ListTile(
                        leading: Icon(Icons.archive_outlined),
                        title: Text('Archiver la dépense'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                ],
              ),
          ],
        ),
        body: _corps(context),
      ),
    );
  }

  Widget _corps(BuildContext context) {
    if (_chargement) return const Center(child: CircularProgressIndicator());
    if (_introuvable || _erreurChargement) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _introuvable ? 'Cette dépense n’existe plus.' : 'Impossible de charger cette dépense.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? ticket = _photos.principale;

    return Form(
      key: _formulaire,
      onChanged: _marquerModifie,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          if (_archivee) ...<Widget>[
            Card(
              margin: EdgeInsets.zero,
              color: scheme.tertiaryContainer,
              child: ListTile(
                leading: Icon(Icons.archive_outlined, color: scheme.onTertiaryContainer),
                title: Text(
                  'Cette dépense est archivée.',
                  style: theme.textTheme.titleSmall?.copyWith(color: scheme.onTertiaryContainer),
                ),
                subtitle: Text(
                  'Elle n’apparaît plus dans la liste ni dans les totaux. Menu ⋮ → « Restaurer la dépense ».',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onTertiaryContainer),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text('La dépense', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          InkWell(
            onTap: _choisirDate,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Date *', suffixIcon: Icon(Icons.calendar_today_outlined)),
              child: Text('${formatDateLongue(_date)} ${_date.year}'),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<CategorieDepense>(
            initialValue: _categorie,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Catégorie *'),
            items: <DropdownMenuItem<CategorieDepense>>[
              for (final CategorieDepense c in CategorieDepense.values)
                DropdownMenuItem<CategorieDepense>(
                  value: c,
                  child: Row(
                    children: <Widget>[
                      Icon(iconeCategorieDepense(c), size: 20, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Text(c.libelle),
                    ],
                  ),
                ),
            ],
            onChanged: (CategorieDepense? valeur) {
              if (valeur != null) {
                setState(() {
                  _categorie = valeur;
                  _modifie = true;
                });
              }
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _montant,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Montant (€) *'),
            validator: (String? v) {
              final String? probleme = validerMontantObligatoire(v, 'Indiquez le montant.');
              if (probleme != null) return probleme;
              return parseMontantEuros(v!) == 0 ? 'Le montant doit être supérieur à 0.' : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _fournisseur,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Fournisseur'),
            validator: (String? v) => validerLongueurMax(v, 200, 'Le nom du fournisseur'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
            validator: (String? v) => validerLongueurMax(v, 2000, 'La description'),
          ),
          const SizedBox(height: 24),
          LigneChoixProduit(
            produit: _produit,
            onChoisi: (Produit? produit) => setState(() {
              _produit = produit;
              _modifie = true;
            }),
          ),
          const SizedBox(height: 24),
          Text('Photo du ticket', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Semantics(
            button: true,
            label: ticket == null ? 'Ajouter la photo du ticket' : 'Changer la photo du ticket',
            child: InkWell(
              onTap: _changerPhoto,
              borderRadius: BorderRadius.circular(16),
              child: ticket == null
                  ? Container(
                      height: 120,
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.outline),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(Icons.add_a_photo_outlined, size: 32, color: scheme.primary),
                          const SizedBox(height: 8),
                          const Text('Ajouter la photo du ticket'),
                        ],
                      ),
                    )
                  : ImageTicket(chemin: ticket, largeur: double.infinity, hauteur: 280, rayon: 16),
            ),
          ),
          if (ticket != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _changerPhoto,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Changer ou retirer la photo'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
