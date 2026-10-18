import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/money.dart';
import '../../core/utils/texte.dart';
import '../../core/utils/validateurs.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/produit_repository.dart';
import '../../data/stockage/selecteur_photo.dart';
import '../../domain/enums.dart';
import 'photos_formulaire.dart';
import 'produit_widgets.dart';

enum _ChoixPhoto { appareil, galerie, retirer }

/// Ajout et modification d'un produit (écran 5). Sans [produitId] : nouveau produit.
class ProduitFormScreen extends ConsumerStatefulWidget {
  const ProduitFormScreen({super.key, this.produitId});

  final int? produitId;

  @override
  ConsumerState<ProduitFormScreen> createState() => _ProduitFormScreenState();
}

class _ProduitFormScreenState extends ConsumerState<ProduitFormScreen> {
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();

  final TextEditingController _nom = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _matieres = TextEditingController();
  final TextEditingController _couleur = TextEditingController();
  final TextEditingController _dimensions = TextEditingController();
  final TextEditingController _heures = TextEditingController();
  final TextEditingController _minutes = TextEditingController();
  final TextEditingController _cout = TextEditingController();
  final TextEditingController _prix = TextEditingController();
  final TextEditingController _stock = TextEditingController(text: '0');
  final TextEditingController _seuil = TextEditingController(text: '0');

  CategorieProduit? _categorie;
  StatutProduit _statut = StatutProduit.disponible;
  bool _personnalisable = false;

  // Photos : choisies tout de suite, liées au produit seulement à l'enregistrement.
  late final PhotosFormulaire _photos = PhotosFormulaire(stockage: ref.read(stockagePhotosProvider));

  // État de l'écran
  Produit? _existant;
  bool _chargement = true;
  bool _introuvable = false;
  bool _erreurChargement = false;
  bool _aDesVariantes = false;
  bool _modifie = false;
  bool _enregistre = false;
  bool _enCours = false;

  bool get _creation => widget.produitId == null;

  @override
  void initState() {
    super.initState();
    if (_creation) {
      _chargement = false;
    } else {
      _charger();
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _nom,
      _description,
      _matieres,
      _couleur,
      _dimensions,
      _heures,
      _minutes,
      _cout,
      _prix,
      _stock,
      _seuil,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final ProduitRepository repo = ref.read(produitRepositoryProvider);
      final Produit? produit = await repo.obtenir(widget.produitId!);
      if (!mounted) return;
      if (produit == null) {
        setState(() {
          _introuvable = true;
          _chargement = false;
        });
        return;
      }
      final List<PhotoProduit> photos = await repo.photosSecondaires(produit.id);
      final List<VarianteProduit> variantes = await repo.variantes(produit.id);
      if (!mounted) return;
      setState(() {
        _existant = produit;
        _nom.text = produit.nom;
        _categorie = produit.categorie;
        _description.text = produit.description ?? '';
        _matieres.text = produit.matieres ?? '';
        _couleur.text = produit.couleur ?? '';
        _dimensions.text = produit.dimensions ?? '';
        final int? temps = produit.tempsFabricationMinutes;
        _heures.text = temps == null ? '' : '${temps ~/ 60}';
        _minutes.text = temps == null ? '' : '${temps % 60}';
        _cout.text = produit.coutMatiereCentimes == 0
            ? ''
            : formatMontantSaisie(produit.coutMatiereCentimes);
        _prix.text = formatMontantSaisie(produit.prixVenteCentimes);
        _stock.text = '${produit.quantiteStock}';
        _seuil.text = '${produit.seuilAlerteStock}';
        _statut = produit.statut;
        _personnalisable = produit.personnalisable;
        _photos.principale = produit.photoPrincipaleChemin;
        _photos.secondaires.addAll(
          photos.map((PhotoProduit p) => PhotoForm(id: p.id, chemin: p.chemin)),
        );
        _aDesVariantes = variantes.isNotEmpty;
        _chargement = false;
      });
    } catch (erreur, pile) {
      debugPrint('Chargement du produit impossible : $erreur\n$pile');
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

  // --- Photos ---------------------------------------------------------------

  Future<_ChoixPhoto?> _demanderChoixPhoto({required bool retirable}) {
    return showModalBottomSheet<_ChoixPhoto>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext contexteFeuille) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.of(contexteFeuille).pop(_ChoixPhoto.appareil),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.of(contexteFeuille).pop(_ChoixPhoto.galerie),
            ),
            if (retirable)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Retirer la photo'),
                onTap: () => Navigator.of(contexteFeuille).pop(_ChoixPhoto.retirer),
              ),
          ],
        ),
      ),
    );
  }

  /// Prend ou choisit une photo ; retourne le chemin du fichier choisi, `null` si elle annule
  /// ou si la photo n'est pas utilisable (un message l'explique).
  Future<String?> _choisirFichier(_ChoixPhoto choix) async {
    try {
      return await ref
          .read(selecteurPhotoProvider)
          .choisir(choix == _ChoixPhoto.appareil ? SourcePhoto.appareil : SourcePhoto.galerie);
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

  /// Exécute une opération sur les photos (copie de fichier...) en affichant l'erreur éventuelle.
  Future<void> _modifierPhotos(Future<void> Function() operation) async {
    try {
      await operation();
      if (mounted) {
        setState(() => _modifie = true);
      }
    } catch (erreur, pile) {
      debugPrint('Photo impossible : $erreur\n$pile');
      if (mounted) {
        afficherMessage(context, 'Impossible d’enregistrer cette photo. Réessayez avec une autre photo.');
      }
    }
  }

  Future<void> _changerPrincipale() async {
    final _ChoixPhoto? choix = await _demanderChoixPhoto(retirable: _photos.principale != null);
    if (choix == null || !mounted) return;
    if (choix == _ChoixPhoto.retirer) {
      await _modifierPhotos(() => _photos.remplacerPrincipale(null));
      return;
    }
    final String? source = await _choisirFichier(choix);
    if (source == null || !mounted) return;
    await _modifierPhotos(() => _photos.remplacerPrincipale(source));
  }

  Future<void> _ajouterSecondaire() async {
    final _ChoixPhoto? choix = await _demanderChoixPhoto(retirable: false);
    if (choix == null || !mounted) return;
    final String? source = await _choisirFichier(choix);
    if (source == null || !mounted) return;
    await _modifierPhotos(() => _photos.ajouterSecondaire(source));
  }

  Future<void> _retirerSecondaire(PhotoForm photo) =>
      _modifierPhotos(() => _photos.retirerSecondaire(photo));

  // --- Enregistrement -------------------------------------------------------

  DonneesProduit _construireDonnees() {
    final bool tempsSaisi = _heures.text.trim().isNotEmpty || _minutes.text.trim().isNotEmpty;
    final int? temps = tempsSaisi
        ? (lireEntier(_heures.text) ?? 0) * 60 + (lireEntier(_minutes.text) ?? 0)
        : null;

    return DonneesProduit(
      nom: _nom.text.trim(),
      categorie: _categorie!,
      prixVenteCentimes: parseMontantEuros(_prix.text)!,
      description: nullSiVide(_description.text),
      matieres: nullSiVide(_matieres.text),
      couleur: nullSiVide(_couleur.text),
      dimensions: nullSiVide(_dimensions.text),
      tempsFabricationMinutes: temps,
      coutMatiereCentimes: parseMontantEuros(_cout.text) ?? 0,
      // Avec des variantes, le stock du produit n'est pas utilisé : on le laisse tel quel.
      quantiteStock: _aDesVariantes ? (_existant?.quantiteStock ?? 0) : (lireEntier(_stock.text) ?? 0),
      seuilAlerteStock: lireEntier(_seuil.text) ?? 0,
      statut: _statut,
      personnalisable: _personnalisable,
      photoPrincipaleChemin: _photos.principale,
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
      final ProduitRepository repo = ref.read(produitRepositoryProvider);
      final DonneesProduit donnees = _construireDonnees();
      final Produit produit;
      if (_creation) {
        produit = await repo.creer(
          donnees,
          photosSecondaires: _photos.secondaires.map((PhotoForm p) => p.chemin).toList(),
        );
      } else {
        produit = await repo.modifier(
          widget.produitId!,
          donnees,
          photosAAjouter: _photos.nouvellesSecondaires,
          photosASupprimer: _photos.idsASupprimer,
        );
      }

      // Enregistré : les fichiers retirés peuvent partir, les nouveaux appartiennent au produit.
      await _photos.apresEnregistrement();

      if (!mounted) return;
      _enregistre = true;
      afficherMessage(context, _creation ? 'Produit ajouté.' : 'Modifications enregistrées.');
      if (_creation) {
        // On ouvre la fiche : c'est là qu'on ajoute des variantes, qu'on règle le stock...
        await Navigator.of(context).pushReplacementNamed(AppRoutes.produitFiche, arguments: produit.id);
      } else {
        Navigator.of(context).pop();
      }
    } catch (erreur, pile) {
      debugPrint('Enregistrement du produit impossible : $erreur\n$pile');
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

  // --- Interface ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _enregistre || !_modifie,
      onPopInvokedWithResult: (bool didPop, Object? resultat) {
        if (!didPop) _demanderAbandon();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_creation ? 'Nouveau produit' : 'Modifier le produit'),
          actions: <Widget>[
            if (!_chargement && !_introuvable && !_erreurChargement)
              TextButton(
                onPressed: _enCours ? null : _enregistrer,
                child: const Text('Enregistrer'),
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
            _introuvable ? 'Ce produit n’existe plus.' : 'Impossible de charger ce produit.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final ThemeData theme = Theme.of(context);
    final Color discret = theme.colorScheme.onSurfaceVariant;
    final List<TextInputFormatter> chiffres = <TextInputFormatter>[
      FilteringTextInputFormatter.digitsOnly,
    ];

    return Form(
      key: _formulaire,
      onChanged: _marquerModifie,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Text(
            _creation
                ? 'La référence (PRD-0001, PRD-0002...) est attribuée automatiquement.'
                : 'Référence : ${_existant!.reference}',
            style: theme.textTheme.bodyMedium?.copyWith(color: discret),
          ),
          const SizedBox(height: 16),
          _TitreSection('Photos', theme),
          _SectionPhotos(
            categorie: _categorie ?? CategorieProduit.crochet,
            principale: _photos.principale,
            secondaires: _photos.secondaires,
            onChangerPrincipale: _changerPrincipale,
            onAjouterSecondaire: _ajouterSecondaire,
            onRetirerSecondaire: _retirerSecondaire,
          ),
          const SizedBox(height: 24),
          _TitreSection('Informations', theme),
          TextFormField(
            controller: _nom,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Nom du produit *'),
            validator: (String? v) =>
                validerObligatoire(v, 'Le nom du produit est obligatoire.') ??
                validerLongueurMax(v, 200, 'Le nom'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<CategorieProduit>(
            initialValue: _categorie,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Catégorie *'),
            items: <DropdownMenuItem<CategorieProduit>>[
              for (final CategorieProduit c in CategorieProduit.values)
                DropdownMenuItem<CategorieProduit>(value: c, child: Text(c.libelle)),
            ],
            onChanged: (CategorieProduit? valeur) => setState(() => _categorie = valeur),
            validator: (CategorieProduit? v) => v == null ? 'Choisissez une catégorie.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            textCapitalization: TextCapitalization.sentences,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _matieres,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Matières',
              hintText: 'Ex. coton bio, rembourrage polyester',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _couleur,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Couleur'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _dimensions,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Taille ou dimensions',
              hintText: 'Ex. 25 cm, taille M',
            ),
          ),
          const SizedBox(height: 24),
          _TitreSection('Fabrication et prix', theme),
          Text('Temps de fabrication', style: theme.textTheme.bodyMedium?.copyWith(color: discret)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: _heures,
                  keyboardType: TextInputType.number,
                  inputFormatters: chiffres,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Heures', suffixText: 'h'),
                  validator: (String? v) => validerEntier(v, max: 999),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  inputFormatters: chiffres,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Minutes', suffixText: 'min'),
                  validator: (String? v) => validerEntier(v, max: 59),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cout,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Coût des matières (€)'),
            validator: validerMontantFacultatif,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _prix,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Prix de vente (€) *'),
            validator: (String? v) => validerMontantObligatoire(v, 'Le prix de vente est obligatoire.'),
          ),
          const SizedBox(height: 24),
          _TitreSection('Stock et statut', theme),
          if (_aDesVariantes)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Ce produit a des variantes : son stock se règle variante par variante, '
                'depuis sa fiche.',
                style: theme.textTheme.bodyMedium?.copyWith(color: discret),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                controller: _stock,
                keyboardType: TextInputType.number,
                inputFormatters: chiffres,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Quantité en stock'),
                validator: (String? v) => validerEntier(v, obligatoire: true),
              ),
            ),
          TextFormField(
            controller: _seuil,
            keyboardType: TextInputType.number,
            inputFormatters: chiffres,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Seuil d’alerte',
              helperText: 'Alerte « stock faible » quand il en reste ce nombre ou moins.',
            ),
            validator: (String? v) => validerEntier(v, obligatoire: true),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<StatutProduit>(
            initialValue: _statut,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Statut',
              helperText: _statut == StatutProduit.surCommande
                  ? 'Le stock d’un produit sur commande n’est pas suivi.'
                  : null,
            ),
            items: <DropdownMenuItem<StatutProduit>>[
              for (final StatutProduit s in StatutProduit.values)
                DropdownMenuItem<StatutProduit>(value: s, child: Text(s.libelle)),
            ],
            onChanged: (StatutProduit? valeur) {
              if (valeur != null) setState(() => _statut = valeur);
            },
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Personnalisable'),
            subtitle: const Text('Le client peut demander une couleur, un prénom, etc.'),
            value: _personnalisable,
            onChanged: (bool valeur) {
              setState(() => _personnalisable = valeur);
              _marquerModifie();
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _enCours ? null : _enregistrer,
            icon: _enCours
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_creation ? 'Ajouter le produit' : 'Enregistrer les modifications'),
          ),
        ],
      ),
    );
  }
}

class _TitreSection extends StatelessWidget {
  const _TitreSection(this.texte, this.theme);

  final String texte;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(texte, style: theme.textTheme.titleMedium),
    );
  }
}

class _SectionPhotos extends StatelessWidget {
  const _SectionPhotos({
    required this.categorie,
    required this.principale,
    required this.secondaires,
    required this.onChangerPrincipale,
    required this.onAjouterSecondaire,
    required this.onRetirerSecondaire,
  });

  final CategorieProduit categorie;
  final String? principale;
  final List<PhotoForm> secondaires;
  final VoidCallback onChangerPrincipale;
  final VoidCallback onAjouterSecondaire;
  final ValueChanged<PhotoForm> onRetirerSecondaire;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          button: true,
          label: principale == null ? 'Ajouter la photo principale' : 'Changer la photo principale',
          child: InkWell(
            onTap: onChangerPrincipale,
            borderRadius: BorderRadius.circular(16),
            child: principale == null
                ? Container(
                    height: 140,
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outline),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.add_a_photo_outlined, size: 32, color: scheme.primary),
                        const SizedBox(height: 8),
                        const Text('Ajouter la photo principale'),
                      ],
                    ),
                  )
                : ImageProduit(
                    chemin: principale,
                    categorie: categorie,
                    largeur: double.infinity,
                    hauteur: 200,
                    rayon: 16,
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Autres photos',
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              for (final PhotoForm photo in secondaires)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 88,
                    height: 88,
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: ImageProduit(
                            chemin: photo.chemin,
                            categorie: categorie,
                            largeur: 88,
                            hauteur: 88,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Material(
                            color: scheme.surface.withValues(alpha: 0.85),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => onRetirerSecondaire(photo),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close, size: 16, semanticLabel: 'Retirer cette photo'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              InkWell(
                onTap: onAjouterSecondaire,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outline),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(Icons.add_photo_alternate_outlined, color: scheme.primary),
                      const SizedBox(height: 4),
                      Text('Ajouter', style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
