import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/dialogues.dart';
import '../../data/drive/compte_google.dart';
import '../../data/drive/service_partages_drive.dart';
import '../../data/providers.dart';
import '../../domain/drive_partage.dart';
import 'drive_providers.dart';
import 'drive_widgets.dart';

/// Ce que reçoit l'écran de partage d'un fichier Drive : le fichier, et la rubrique où il se trouve.
class ArgumentsPartageFichier {
  const ArgumentsPartageFichier({required this.id, required this.nom, required this.rubrique});

  /// Identifiant du fichier dans Drive.
  final String id;
  final String nom;

  /// La rubrique (factures, devis, exports).
  final RubriquePartage rubrique;
}

/// Réglages › Google Drive › Partages › un fichier : qui y a accès, le partager avec une personne précise (en lecture), activer
/// ou arrêter le lien public.
///
/// **Rien ne se fait sans un geste** : le lien public demande une confirmation qui explique ce qu'il permet, et retirer un
/// accès aussi. Un partage ne donne que le droit de lire. Arrêter un partage ne supprime jamais le fichier.
class DrivePartageFichierScreen extends ConsumerStatefulWidget {
  const DrivePartageFichierScreen({super.key, required this.fichier});

  final ArgumentsPartageFichier fichier;

  @override
  ConsumerState<DrivePartageFichierScreen> createState() => _DrivePartageFichierScreenState();
}

class _DrivePartageFichierScreenState extends ConsumerState<DrivePartageFichierScreen> {
  final TextEditingController _courriel = TextEditingController();

  AccesFichier? _acces;
  String? _lien;
  bool _chargement = true;
  String? _erreurChargement;

  bool _occupe = false;
  String? _erreurAction;
  String? _erreurCourriel;
  String? _info;

  @override
  void initState() {
    super.initState();
    unawaited(_charger());
  }

  @override
  void dispose() {
    _courriel.dispose();
    super.dispose();
  }

  String get _id => widget.fichier.id;

  String _messageDe(Object erreur) => erreur is ErreurDrive ? erreur.message : messageErreur(erreur);

  Future<void> _charger() async {
    try {
      final ServicePartagesDrive service = ref.read(servicePartagesDriveProvider);
      final AccesFichier acces = await service.acces(_id);
      final String? lien = await service.lien(_id);
      if (!mounted) return;
      setState(() {
        _acces = acces;
        _lien = lien;
        _chargement = false;
        _erreurChargement = null;
      });
    } catch (erreur) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreurChargement = _messageDe(erreur);
      });
    }
  }

  void _recharger() {
    setState(() {
      _chargement = true;
      _erreurChargement = null;
    });
    unawaited(_charger());
  }

  /// Exécute une action sur Drive : un seul geste à la fois, et toute erreur est dite en clair.
  Future<void> _executer(Future<void> Function(ServicePartagesDrive service) action) async {
    if (_occupe) return;
    final ServicePartagesDrive service = ref.read(servicePartagesDriveProvider);
    final ProfilGoogleNotifier profil = ref.read(profilGoogleProvider.notifier);
    setState(() {
      _occupe = true;
      _erreurAction = null;
      _info = null;
    });
    String? erreurAction;
    try {
      await action(service);
    } on ErreurDrive catch (erreur) {
      erreurAction = erreur.autorisationAExpire
          ? '${erreur.message} Cela se fait dans Réglages › Google Drive.'
          : erreur.message;
      if (erreur.autorisationAExpire) profil.connexionPerdue();
    } catch (erreur) {
      erreurAction = messageErreur(erreur);
    }
    if (!mounted) return;
    setState(() {
      _occupe = false;
      if (erreurAction != null) _erreurAction = erreurAction;
    });
  }

  Future<void> _partager() async {
    final String saisie = _courriel.text;
    final String? monAdresse = ref.read(profilGoogleProvider).valueOrNull?.email;
    final String? probleme = erreurCourrielPartage(
      saisie,
      emailProprietaire: monAdresse,
      dejaPartagees: <String>[
        for (final AccesDrive a in _acces?.personnes ?? const <AccesDrive>[])
          if (a.email != null) a.email!,
      ],
    );
    if (probleme != null) {
      setState(() {
        _erreurCourriel = probleme;
        _info = null;
        _erreurAction = null;
      });
      return;
    }
    setState(() => _erreurCourriel = null);
    await _executer((ServicePartagesDrive service) async {
      final AccesFichier maj = await service.partagerAvec(_id, saisie, emailProprietaire: monAdresse);
      if (!mounted) return;
      _courriel.clear();
      setState(() {
        _acces = maj;
        _info =
            'Partagé avec ${normaliserCourriel(saisie)}. Google prévient la personne par e-mail ; '
            'elle peut lire le fichier, sans le modifier.';
      });
    });
  }

  Future<void> _retirer(AccesDrive acces) async {
    final bool ok = await confirmer(
      context,
      titre: 'Retirer l’accès ?',
      message: '${acces.libelle} ne pourra plus ouvrir « ${widget.fichier.nom} ». Le fichier reste sur votre Drive.',
      libelleConfirmer: 'Retirer l’accès',
    );
    if (!ok || !mounted) return;
    await _executer((ServicePartagesDrive service) async {
      final AccesFichier maj = await service.retirer(_id, acces);
      if (!mounted) return;
      setState(() {
        _acces = maj;
        _info = 'L’accès de ${acces.libelle} est retiré. Le fichier reste sur votre Drive.';
      });
    });
  }

  Future<void> _activerLien() async {
    final bool contientUnClient =
        widget.fichier.rubrique == RubriquePartage.factures || widget.fichier.rubrique == RubriquePartage.devis;
    final bool ok = await confirmer(
      context,
      titre: 'Activer le lien public ?',
      message:
          'Toute personne qui a le lien pourra lire « ${widget.fichier.nom} », même sans compte Google. Elle ne pourra pas '
          'le modifier, et le fichier n’apparaît dans aucune recherche : seul le lien y mène, mais il peut être transmis à '
          'n’importe qui.\n\n'
          '${contientUnClient ? 'Une facture ou un devis contient le nom et l’adresse du client : préférez un partage avec une personne précise.\n\n' : ''}'
          'Vous pourrez arrêter le lien public à tout moment.',
      libelleConfirmer: 'Activer le lien',
    );
    if (!ok || !mounted) return;
    await _executer((ServicePartagesDrive service) async {
      final String? lien = await service.activerLien(_id);
      final AccesFichier maj = await service.acces(_id);
      if (!mounted) return;
      setState(() {
        _acces = maj;
        _lien = lien ?? _lien;
        _info = 'Le lien public est activé : toute personne qui l’a peut lire le fichier.';
      });
    });
  }

  Future<void> _arreterLien() async {
    final AccesDrive? lienPublic = _acces?.lienPublic;
    if (lienPublic == null) return;
    final bool ok = await confirmer(
      context,
      titre: 'Arrêter le lien public ?',
      message:
          'Les personnes qui n’ont que le lien ne pourront plus ouvrir « ${widget.fichier.nom} ». Celles avec qui le fichier '
          'est partagé gardent leur accès. Le fichier reste sur votre Drive.',
      libelleConfirmer: 'Arrêter le lien',
    );
    if (!ok || !mounted) return;
    await _executer((ServicePartagesDrive service) async {
      final AccesFichier maj = await service.retirer(_id, lienPublic);
      if (!mounted) return;
      setState(() {
        _acces = maj;
        _info = 'Le lien public est arrêté. Le fichier reste sur votre Drive.';
      });
    });
  }

  Future<void> _copierLien() async {
    final String? lien = _lien;
    if (lien == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: lien));
      if (!mounted) return;
      setState(() {
        _info = 'Lien copié.';
        _erreurAction = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erreurAction = 'Impossible de copier le lien.';
        _info = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AccesFichier? acces = _acces;

    final List<Widget> contenu = <Widget>[
      Text(widget.fichier.nom, key: const Key('partage-nom'), style: theme.textTheme.titleMedium),
      texteDiscretDrive(context, 'Rubrique : ${widget.fichier.rubrique.titre}'),
      const SizedBox(height: 8),
    ];

    if (_info != null) {
      contenu.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(_info!, key: const Key('partage-info'), style: theme.textTheme.bodyMedium),
        ),
      );
    }
    if (_erreurAction != null) {
      contenu.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: texteErreurDrive(context, _erreurAction!, key: const Key('partage-erreur')),
        ),
      );
    }

    if (_chargement) {
      contenu.add(const Center(child: CircularProgressIndicator(key: Key('partage-chargement'))));
    } else if (acces == null) {
      contenu.add(
        CarteDrive(
          titre: 'Lecture impossible',
          enfants: <Widget>[
            texteErreurDrive(
              context,
              _erreurChargement ?? 'Les accès à ce fichier n’ont pas pu être lus.',
              key: const Key('partage-erreur-chargement'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const Key('partage-reessayer'),
              onPressed: _recharger,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      );
    } else {
      contenu
        ..add(_carteAcces(context, acces))
        ..add(const SizedBox(height: 12))
        ..add(_cartePersonne(context))
        ..add(const SizedBox(height: 12))
        ..add(_carteLien(context, acces));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Partager un fichier')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: contenu),
    );
  }

  Widget _carteAcces(BuildContext context, AccesFichier acces) {
    final AccesDrive? proprietaire = acces.proprietaire;
    final List<AccesDrive> personnes = acces.personnes;
    final List<AccesDrive> autres = acces.autres;
    return CarteDrive(
      titre: 'Qui a accès',
      enfants: <Widget>[
        Text(acces.resume, key: const Key('partage-resume')),
        const SizedBox(height: 4),
        if (proprietaire != null)
          ListTile(
            key: const Key('partage-proprietaire'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: const Text('Vous (propriétaire)'),
            subtitle: Text(proprietaire.libelle),
          ),
        for (int i = 0; i < personnes.length; i++)
          ListTile(
            key: Key('partage-personne-$i'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_add_alt_outlined),
            title: Text(personnes[i].libelle),
            subtitle: Text(
              personnes[i].peutModifier ? 'Peut aussi modifier (accordé en dehors de l’application)' : 'Peut lire',
            ),
            trailing: IconButton(
              key: Key('partage-retirer-$i'),
              tooltip: 'Retirer l’accès',
              icon: const Icon(Icons.person_remove_outlined),
              onPressed: _occupe ? null : () => _retirer(personnes[i]),
            ),
          ),
        for (int i = 0; i < autres.length; i++)
          ListTile(
            key: Key('partage-autre-$i'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.groups_outlined),
            title: Text(autres[i].libelle),
            subtitle: const Text('Accès créé en dehors de l’application : à gérer dans Drive.'),
          ),
      ],
    );
  }

  Widget _cartePersonne(BuildContext context) {
    return CarteDrive(
      titre: 'Partager avec une personne',
      enfants: <Widget>[
        const Text(
          'La personne reçoit un e-mail de Google et peut lire le fichier, sans pouvoir le modifier. Vous pourrez retirer '
          'son accès ici, à tout moment.',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('partage-courriel'),
          controller: _courriel,
          enabled: !_occupe,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Adresse e-mail de la personne',
            border: const OutlineInputBorder(),
            errorText: _erreurCourriel,
            errorMaxLines: 3,
          ),
          onChanged: (_) {
            if (_erreurCourriel != null) setState(() => _erreurCourriel = null);
          },
          onSubmitted: (_) => _partager(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('partage-partager'),
          onPressed: _occupe ? null : _partager,
          icon: const Icon(Icons.send_outlined),
          label: const Text('Partager (lecture seule)'),
        ),
      ],
    );
  }

  Widget _carteLien(BuildContext context, AccesFichier acces) {
    final bool public = acces.lienPublic != null;
    final String? lien = _lien;
    return CarteDrive(
      titre: 'Lien',
      enfants: <Widget>[
        if (!public)
          texteDiscretDrive(
            context,
            'Le lien du fichier n’est pas public : seules les personnes ayant accès au fichier peuvent l’ouvrir.',
            key: const Key('partage-lien-prive'),
          )
        else
          const Text(
            'Lien public activé : toute personne qui a ce lien peut lire le fichier, sans compte Google.',
            key: Key('partage-lien-public'),
          ),
        if (lien != null) ...<Widget>[
          const SizedBox(height: 8),
          SelectableText(lien, key: const Key('partage-lien'), style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            OutlinedButton.icon(
              key: const Key('partage-copier-lien'),
              onPressed: lien == null ? null : _copierLien,
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copier le lien'),
            ),
            if (!public)
              OutlinedButton.icon(
                key: const Key('partage-activer-lien'),
                onPressed: _occupe ? null : _activerLien,
                icon: const Icon(Icons.link),
                label: const Text('Activer le lien public…'),
              )
            else
              OutlinedButton.icon(
                key: const Key('partage-arreter-lien'),
                onPressed: _occupe ? null : _arreterLien,
                icon: const Icon(Icons.link_off),
                label: const Text('Arrêter le lien public…'),
              ),
          ],
        ),
      ],
    );
  }
}
