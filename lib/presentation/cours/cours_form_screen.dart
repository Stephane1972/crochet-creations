import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/date_fr.dart';
import '../../core/utils/money.dart';
import '../../core/utils/validateurs.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/cours_repository.dart';
import '../../data/stockage/selecteur_photo.dart';
import '../../domain/enums.dart';
import '../produits/photos_formulaire.dart';
import 'cours_widgets.dart';

enum _ChoixPhoto { appareil, galerie, retirer }

/// Création et modification d'un cours. Sans [coursId] : nouveau cours.
///
/// Titre, description, date et heure, durée, lieu, prix, nombre de places, niveau, matériel inclus ou non et photo.
class CoursFormScreen extends ConsumerStatefulWidget {
  const CoursFormScreen({super.key, this.coursId});

  final int? coursId;

  @override
  ConsumerState<CoursFormScreen> createState() => _CoursFormScreenState();
}

class _CoursFormScreenState extends ConsumerState<CoursFormScreen> {
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();

  final TextEditingController _titre = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _heures = TextEditingController(text: '2');
  final TextEditingController _minutes = TextEditingController(text: '0');
  final TextEditingController _lieu = TextEditingController();
  final TextEditingController _prix = TextEditingController();
  final TextEditingController _places = TextEditingController(text: '6');

  late DateTime _debut;
  NiveauCours _niveau = NiveauCours.tousNiveaux;
  bool _materielInclus = false;

  // La photo est copiée tout de suite dans l'application, mais liée au cours à l'enregistrement seulement.
  late final PhotosFormulaire _photos = PhotosFormulaire(stockage: ref.read(stockagePhotosProvider));

  bool _chargement = true;
  bool _introuvable = false;
  bool _erreurChargement = false;
  bool _modifie = false;
  bool _enregistre = false;
  bool _enCours = false;

  bool get _creation => widget.coursId == null;

  @override
  void initState() {
    super.initState();
    // Un nouveau cours est proposé demain à 14 h.
    final DateTime demain = DateTime.now().add(const Duration(days: 1));
    _debut = DateTime(demain.year, demain.month, demain.day, 14);
    if (_creation) {
      _chargement = false;
    } else {
      _charger();
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _titre,
      _description,
      _heures,
      _minutes,
      _lieu,
      _prix,
      _places,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final CoursFiche? cours = await ref.read(coursRepositoryProvider).obtenir(widget.coursId!);
      if (!mounted) return;
      if (cours == null) {
        setState(() {
          _introuvable = true;
          _chargement = false;
        });
        return;
      }
      setState(() {
        _titre.text = cours.titre;
        _description.text = cours.description ?? '';
        _debut = cours.debutLe;
        _heures.text = '${cours.dureeMinutes ~/ 60}';
        _minutes.text = '${cours.dureeMinutes % 60}';
        _lieu.text = cours.lieu ?? '';
        _prix.text = formatMontantSaisie(cours.prixCentimes);
        _places.text = '${cours.places}';
        _niveau = cours.niveau;
        _materielInclus = cours.materielInclus;
        _photos.principale = cours.photoChemin;
        _chargement = false;
      });
    } catch (erreur, pile) {
      debugPrint('Chargement du cours impossible : $erreur\n$pile');
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

  // --- Date et heure ----------------------------------------------------------

  Future<void> _choisirDate() async {
    final DateTime aujourdhui = DateTime.now();
    final DateTime premier = DateTime(aujourdhui.year - 1);
    final DateTime? choisie = await showDatePicker(
      context: context,
      initialDate: _debut.isBefore(premier) ? premier : _debut,
      firstDate: premier,
      lastDate: DateTime(aujourdhui.year + 5, 12, 31),
      helpText: 'Date du cours',
    );
    if (choisie == null || !mounted) return;
    setState(() {
      _debut = DateTime(choisie.year, choisie.month, choisie.day, _debut.hour, _debut.minute);
      _modifie = true;
    });
  }

  Future<void> _choisirHeure() async {
    final TimeOfDay? choisie = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_debut),
      helpText: 'Heure de début',
      builder: (BuildContext contexte, Widget? enfant) => MediaQuery(
        data: MediaQuery.of(contexte).copyWith(alwaysUse24HourFormat: true),
        child: enfant!,
      ),
    );
    if (choisie == null || !mounted) return;
    setState(() {
      _debut = DateTime(_debut.year, _debut.month, _debut.day, choisie.hour, choisie.minute);
      _modifie = true;
    });
  }

  // --- Photo ------------------------------------------------------------------

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

  Future<void> _changerPhoto() async {
    final _ChoixPhoto? choix = await _demanderChoixPhoto(retirable: _photos.principale != null);
    if (choix == null || !mounted) return;
    final String? source = choix == _ChoixPhoto.retirer ? null : await _choisirFichier(choix);
    if (choix != _ChoixPhoto.retirer && (source == null || !mounted)) return;
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

  DonneesCours _construireDonnees() {
    final int duree = (lireEntier(_heures.text) ?? 0) * 60 + (lireEntier(_minutes.text) ?? 0);
    return DonneesCours(
      titre: _titre.text,
      description: _description.text,
      debutLe: _debut,
      dureeMinutes: duree,
      lieu: _lieu.text,
      prixCentimes: parseMontantEuros(_prix.text)!,
      places: lireEntier(_places.text)!,
      niveau: _niveau,
      materielInclus: _materielInclus,
      photoChemin: _photos.principale,
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
      final CoursRepository repo = ref.read(coursRepositoryProvider);
      final DonneesCours donnees = _construireDonnees();
      final CoursFiche cours = _creation ? await repo.creer(donnees) : await repo.modifier(widget.coursId!, donnees);

      // Enregistré : l'ancienne photo peut partir, la nouvelle appartient au cours.
      await _photos.apresEnregistrement();

      if (!mounted) return;
      _enregistre = true;
      afficherMessage(context, _creation ? 'Cours créé.' : 'Modifications enregistrées.');
      if (_creation) {
        // On ouvre la fiche : c'est là qu'on inscrit les premières personnes.
        await Navigator.of(context).pushReplacementNamed(AppRoutes.coursFiche, arguments: cours.id);
      } else {
        Navigator.of(context).pop();
      }
    } catch (erreur, pile) {
      debugPrint('Enregistrement du cours impossible : $erreur\n$pile');
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
    return PopScope(
      canPop: _enregistre || !_modifie,
      onPopInvokedWithResult: (bool didPop, Object? resultat) {
        if (!didPop) _demanderAbandon();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_creation ? 'Nouveau cours' : 'Modifier le cours'),
          actions: <Widget>[
            if (!_chargement && !_introuvable && !_erreurChargement)
              TextButton(onPressed: _enCours ? null : _enregistrer, child: const Text('Enregistrer')),
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
            _introuvable ? 'Ce cours n’existe plus.' : 'Impossible de charger ce cours.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<TextInputFormatter> chiffres = <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly];

    return Form(
      key: _formulaire,
      onChanged: _marquerModifie,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Text('Photo', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Semantics(
            button: true,
            label: _photos.principale == null ? 'Ajouter une photo' : 'Changer la photo',
            child: InkWell(
              onTap: _changerPhoto,
              borderRadius: BorderRadius.circular(16),
              child: _photos.principale == null
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
                          const Text('Ajouter une photo'),
                        ],
                      ),
                    )
                  : ImageCours(chemin: _photos.principale, largeur: double.infinity, hauteur: 200, rayon: 16),
            ),
          ),
          const SizedBox(height: 24),
          Text('Le cours', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextFormField(
            controller: _titre,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Titre du cours *'),
            validator: (String? v) =>
                validerObligatoire(v, 'Le titre du cours est obligatoire.') ?? validerLongueurMax(v, 200, 'Le titre'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
            validator: (String? v) => validerLongueurMax(v, 2000, 'La description'),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: InkWell(
                  onTap: _choisirDate,
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date *',
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text('${formatDateLongue(_debut)} ${_debut.year}'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: _choisirHeure,
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Heure *', suffixIcon: Icon(Icons.schedule)),
                    child: Text(formatHeure(_debut)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: _heures,
                  keyboardType: TextInputType.number,
                  inputFormatters: chiffres,
                  decoration: const InputDecoration(labelText: 'Durée : heures'),
                  validator: (String? v) => validerEntier(v, max: 24),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  inputFormatters: chiffres,
                  decoration: const InputDecoration(labelText: 'Durée : minutes'),
                  validator: (String? v) => validerEntier(v, max: 59),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _lieu,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Lieu'),
            validator: (String? v) => validerLongueurMax(v, 200, 'Le lieu'),
          ),
          const SizedBox(height: 24),
          Text('Prix et places', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextFormField(
            controller: _prix,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Prix par personne (€) *',
              helperText: _creation
                  ? '0 si le cours est gratuit.'
                  : 'Les personnes déjà inscrites gardent le prix qui leur a été fait.',
              helperMaxLines: 2,
            ),
            validator: (String? v) => validerMontantObligatoire(v, 'Indiquez le prix (0 si c’est gratuit).'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _places,
            keyboardType: TextInputType.number,
            inputFormatters: chiffres,
            decoration: const InputDecoration(labelText: 'Nombre de places *'),
            validator: (String? v) {
              final String? probleme = validerEntier(v, obligatoire: true, max: 999);
              if (probleme != null) return probleme;
              return (lireEntier(v) ?? 0) < 1 ? 'Il faut au moins une place.' : null;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<NiveauCours>(
            initialValue: _niveau,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Niveau'),
            items: <DropdownMenuItem<NiveauCours>>[
              for (final NiveauCours n in NiveauCours.values)
                DropdownMenuItem<NiveauCours>(value: n, child: Text(n.libelle)),
            ],
            onChanged: (NiveauCours? valeur) {
              if (valeur != null) {
                setState(() {
                  _niveau = valeur;
                  _modifie = true;
                });
              }
            },
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Matériel inclus'),
            subtitle: const Text('Laine et crochets fournis pendant le cours.'),
            value: _materielInclus,
            onChanged: (bool valeur) => setState(() {
              _materielInclus = valeur;
              _modifie = true;
            }),
          ),
        ],
      ),
    );
  }
}
