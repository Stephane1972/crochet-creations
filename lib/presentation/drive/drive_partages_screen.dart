import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/drive/compte_google.dart';
import '../../data/drive/service_partages_drive.dart';
import '../../data/providers.dart';
import '../../data/sauvegarde/export_catalogue.dart';
import '../../domain/drive_envoi.dart';
import '../../domain/drive_partage.dart';
import 'drive_partage_fichier_screen.dart';
import 'drive_providers.dart';
import 'drive_widgets.dart';

/// Réglages › Google Drive › Partages : les factures, les devis et les exports qui sont sur Drive, à partager avec une personne
/// précise ou par un lien (écran d'un fichier), et le catalogue des produits à envoyer sur Drive.
///
/// Rien n'est partagé sans un geste de la personne. Les sauvegardes ne figurent jamais ici : elles contiennent toutes les données.
class DrivePartagesScreen extends ConsumerStatefulWidget {
  const DrivePartagesScreen({super.key});

  @override
  ConsumerState<DrivePartagesScreen> createState() => _DrivePartagesScreenState();
}

class _DrivePartagesScreenState extends ConsumerState<DrivePartagesScreen> {
  bool _catalogueEnCours = false;
  String? _catalogueResultat;
  String? _catalogueErreur;

  String _pluriel(int n, String singulier) => '$n ${n > 1 ? '${singulier}s' : singulier}';

  Future<void> _envoyerCatalogue() async {
    if (_catalogueEnCours) return;
    final ProfilGoogleNotifier profil = ref.read(profilGoogleProvider.notifier);
    final ExportCatalogue exportation = ref.read(exportCatalogueProvider);
    final Directory dossierExports = ref.read(serviceSauvegardeProvider).dossierExports;
    final ServicePartagesDrive service = ref.read(servicePartagesDriveProvider);
    setState(() {
      _catalogueEnCours = true;
      _catalogueResultat = null;
      _catalogueErreur = null;
    });
    String? resultat;
    String? erreur;
    try {
      final ResultatCatalogue catalogue = await exportation.ecrireArchive(dossierExports);
      final bool remplace = await service.envoyerExport(catalogue.fichier);
      final String manquantes = catalogue.photosManquantes.isEmpty
          ? ''
          : ' ${_pluriel(catalogue.photosManquantes.length, 'photo')} introuvable${catalogue.photosManquantes.length > 1 ? 's' : ''} '
                'sur cet appareil (voir LISEZMOI.txt dans l’archive).';
      resultat =
          '${remplace ? 'Catalogue mis à jour' : 'Catalogue envoyé'} sur Drive, dans le dossier « $nomDossierExportsDrive » : '
          '${catalogue.fichier.uri.pathSegments.last} (${_pluriel(catalogue.produits, 'produit')}, '
          '${_pluriel(catalogue.photos, 'photo')}).$manquantes';
      if (mounted) ref.invalidate(fichiersPartageablesProvider);
    } on ErreurDrive catch (e) {
      erreur = e.autorisationAExpire
          ? '${e.message} Cela se fait dans Réglages › Google Drive.'
          : e.message;
      if (e.autorisationAExpire) profil.connexionPerdue();
    } catch (e) {
      erreur = messageErreur(e);
    }
    if (!mounted) return;
    setState(() {
      _catalogueEnCours = false;
      _catalogueResultat = resultat;
      _catalogueErreur = erreur;
    });
  }

  Future<void> _ouvrir(RubriquePartage rubrique, FichierDistant fichier) async {
    await Navigator.of(context).pushNamed(
      AppRoutes.drivePartageFichier,
      arguments: ArgumentsPartageFichier(id: fichier.id, nom: fichier.nom, rubrique: rubrique),
    );
    // Au retour, la liste est relue : l'indication « partagé » a pu changer.
    if (mounted) ref.invalidate(fichiersPartageablesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ProfilGoogle?> profil = ref.watch(profilGoogleProvider);
    final bool connecte = profil.valueOrNull != null;

    final List<Widget> contenu = <Widget>[
      CarteDrive(
        titre: 'Comment ça marche',
        enfants: <Widget>[
          const Text(
            'Partagez un fichier de votre Drive avec une personne précise (elle le lit, sans pouvoir le modifier), ou par un '
            'lien. Rien n’est partagé sans votre accord, vous pouvez arrêter un partage à tout moment, et le fichier lui-même '
            'n’est jamais supprimé. Vos sauvegardes ne sont jamais proposées ici.',
          ),
        ],
      ),
      const SizedBox(height: 12),
    ];

    if (!connecte) {
      contenu.add(
        CarteDrive(
          titre: 'Connexion à Google',
          enfants: <Widget>[
            if (profil.isLoading)
              const LinearProgressIndicator(key: Key('partages-chargement-compte'))
            else
              const Text(
                'Connectez-vous à Google (écran Google Drive) pour partager des fichiers.',
                key: Key('partages-non-connecte'),
              ),
          ],
        ),
      );
    } else {
      contenu
        ..add(_carteCatalogue(context))
        ..add(const SizedBox(height: 12));
      final AsyncValue<FichiersPartageables> fichiers = ref.watch(fichiersPartageablesProvider);
      for (final RubriquePartage rubrique in RubriquePartage.values) {
        contenu
          ..add(_carteRubrique(context, rubrique, fichiers))
          ..add(const SizedBox(height: 12));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Partager des fichiers')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: contenu),
    );
  }

  Widget _carteCatalogue(BuildContext context) {
    return CarteDrive(
      titre: 'Catalogue des produits',
      enfants: <Widget>[
        const Text(
          'Prépare un fichier .zip avec le tableau des produits (prix de vente) et leurs photos, sans les coûts, les stocks ni les '
          'clients, et l’envoie dans le dossier « $nomDossierExportsDrive » de votre Drive. Vous pouvez ensuite le partager ci-dessous.',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('partages-envoyer-catalogue'),
          onPressed: _catalogueEnCours ? null : _envoyerCatalogue,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('Envoyer le catalogue sur Drive'),
        ),
        if (_catalogueEnCours) ...<Widget>[
          const SizedBox(height: 12),
          const LinearProgressIndicator(key: Key('partages-catalogue-en-cours')),
        ],
        if (_catalogueResultat != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(_catalogueResultat!, key: const Key('partages-catalogue-resultat')),
        ],
        if (_catalogueErreur != null) ...<Widget>[
          const SizedBox(height: 12),
          texteErreurDrive(context, _catalogueErreur!, key: const Key('partages-catalogue-erreur')),
        ],
      ],
    );
  }

  Widget _carteRubrique(BuildContext context, RubriquePartage rubrique, AsyncValue<FichiersPartageables> fichiers) {
    final List<FichierDistant>? liste = fichiers.valueOrNull?[rubrique];
    final List<Widget> enfants = <Widget>[texteDiscretDrive(context, rubrique.explication)];

    if (liste == null) {
      if (fichiers.hasError) {
        final Object erreur = fichiers.error!;
        enfants
          ..add(const SizedBox(height: 8))
          ..add(
            texteErreurDrive(
              context,
              erreur is ErreurDrive ? erreur.message : messageErreur(erreur),
              key: Key('partages-erreur-${rubrique.name}'),
            ),
          )
          ..add(const SizedBox(height: 8))
          ..add(
            FilledButton.tonalIcon(
              key: Key('partages-reessayer-${rubrique.name}'),
              onPressed: () => ref.invalidate(fichiersPartageablesProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          );
      } else {
        enfants
          ..add(const SizedBox(height: 8))
          ..add(LinearProgressIndicator(key: Key('partages-chargement-${rubrique.name}')));
      }
    } else if (liste.isEmpty) {
      enfants
        ..add(const SizedBox(height: 8))
        ..add(
          Text(
            rubrique == RubriquePartage.exports
                ? 'Aucun export sur Drive pour l’instant : utilisez « Envoyer le catalogue sur Drive » ci-dessus.'
                : 'Aucun fichier sur Drive pour l’instant : envoyez-les depuis l’écran Google Drive (« Envoyer sur Drive »).',
            key: Key('partages-vide-${rubrique.name}'),
          ),
        );
    } else {
      for (final FichierDistant f in liste) {
        enfants.add(
          ListTile(
            key: Key('partages-fichier-${f.nom}'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(f.nom.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_outlined : Icons.insert_drive_file_outlined),
            title: Text(f.nom),
            subtitle: Text(f.partage ? 'Partagé' : 'Privé', key: Key('partages-etat-${f.nom}')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ouvrir(rubrique, f),
          ),
        );
      }
    }
    return CarteDrive(titre: rubrique.titre, enfants: enfants);
  }
}
