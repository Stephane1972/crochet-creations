import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_fr.dart';
import '../../core/utils/duree.dart';
import '../../core/widgets/etiquette.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/cours_vues.dart';
import '../../domain/enums.dart';

/// Photo d'un cours, ou une icône d'école s'il n'en a pas (ou si le fichier a disparu).
class ImageCours extends ConsumerWidget {
  const ImageCours({
    super.key,
    required this.chemin,
    this.largeur,
    this.hauteur,
    this.rayon = 12,
    this.tailleIcone,
  });

  final String? chemin;
  final double? largeur;
  final double? hauteur;
  final double rayon;

  /// Taille de l'icône de substitution. Par défaut : 45 % du côté connu.
  final double? tailleIcone;

  double get _tailleIconeParDefaut {
    final double? cote = <double?>[largeur, hauteur].firstWhere(
      (double? c) => c != null && c.isFinite,
      orElse: () => null,
    );
    return (cote ?? 64) * 0.45;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final Widget substitut = Container(
      width: largeur,
      height: hauteur,
      color: scheme.secondaryContainer,
      alignment: Alignment.center,
      child: Icon(Icons.school_outlined, size: tailleIcone ?? _tailleIconeParDefaut, color: scheme.onSecondaryContainer),
    );

    final String? cheminPhoto = chemin;
    final Widget contenu = cheminPhoto == null
        ? substitut
        : Image.file(
            ref.watch(stockagePhotosProvider).fichier(cheminPhoto),
            width: largeur,
            height: hauteur,
            fit: BoxFit.cover,
            cacheWidth: 800,
            errorBuilder: (BuildContext context, Object erreur, StackTrace? pile) => substitut,
          );

    return ClipRRect(borderRadius: BorderRadius.circular(rayon), child: contenu);
  }
}

/// « samedi 17 octobre 2026 · 14 h 00 ».
String quandCours(DateTime debut) => '${formatDateLongue(debut)} ${debut.year} · ${formatHeure(debut)}';

/// « samedi 17 octobre · 14 h 00 à 16 h 00 » : le jour, l'heure de début et celle de fin.
String creneauCours(DateTime debut, int dureeMinutes) {
  final DateTime fin = debut.add(Duration(minutes: dureeMinutes));
  return '${formatDateLongue(debut)} ${debut.year} · ${formatHeure(debut)} à ${formatHeure(fin)} (${formatDuree(dureeMinutes)})';
}

/// « 3 / 6 places », « Complet ».
String textePlaces({required int confirmes, required int places}) {
  if (confirmes >= places) return 'Complet · $places / $places places';
  return '$confirmes / $places places';
}

/// Pastille « Annulé » d'un cours.
class EtiquetteCoursAnnule extends StatelessWidget {
  const EtiquetteCoursAnnule({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return Etiquette('Annulé', fond: c.errorContainer, couleurTexte: c.onErrorContainer, icone: Icons.event_busy_outlined);
  }
}

/// Pastille « Archivé » d'un cours.
class EtiquetteCoursArchive extends StatelessWidget {
  const EtiquetteCoursArchive({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return Etiquette(
      'Archivé',
      fond: c.surfaceContainerHighest,
      couleurTexte: c.onSurfaceVariant,
      icone: Icons.archive_outlined,
    );
  }
}

/// Pastille de paiement d'une personne inscrite : Payé, Acompte versé, À payer, Remboursé, Vente annulée.
class EtiquettePaiementInscription extends StatelessWidget {
  const EtiquettePaiementInscription(this.personne, {super.key});

  final InscriptionDetail personne;

  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    final Vente? vente = personne.vente;
    if (vente == null) return const SizedBox.shrink();

    if (vente.statut == StatutVente.annulee) {
      return personne.vente!.statutPaiement == StatutPaiement.remboursee
          ? Etiquette(
              'Remboursé',
              fond: c.surfaceContainerHighest,
              couleurTexte: c.onSurfaceVariant,
              icone: Icons.undo,
            )
          : Etiquette(
              'Vente annulée',
              fond: c.surfaceContainerHighest,
              couleurTexte: c.onSurfaceVariant,
              icone: Icons.cancel_outlined,
            );
    }
    return switch (vente.statutPaiement) {
      StatutPaiement.payee => Etiquette(
        vente.totalCentimes == 0 ? 'Gratuit' : 'Payé',
        fond: c.primaryContainer,
        couleurTexte: c.onPrimaryContainer,
        icone: Icons.check,
      ),
      StatutPaiement.partiellementPayee => Etiquette(
        'Acompte versé',
        fond: c.tertiaryContainer,
        couleurTexte: c.onTertiaryContainer,
        icone: Icons.hourglass_bottom,
      ),
      StatutPaiement.impayee => Etiquette(
        'À payer',
        fond: c.errorContainer,
        couleurTexte: c.onErrorContainer,
        icone: Icons.schedule,
      ),
      StatutPaiement.remboursee => Etiquette(
        'Remboursé',
        fond: c.surfaceContainerHighest,
        couleurTexte: c.onSurfaceVariant,
        icone: Icons.undo,
      ),
    };
  }
}

/// Pastille de statut d'une inscription : Confirmée, En attente (rang), Annulée.
class EtiquetteStatutInscription extends StatelessWidget {
  const EtiquetteStatutInscription(this.personne, {super.key});

  final InscriptionDetail personne;

  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return switch (personne.statut) {
      StatutInscription.confirmee => Etiquette(
        'Confirmée',
        fond: c.primaryContainer,
        couleurTexte: c.onPrimaryContainer,
        icone: Icons.check,
      ),
      StatutInscription.listeAttente => Etiquette(
        personne.rangAttente == null ? 'En attente' : 'En attente · n° ${personne.rangAttente}',
        fond: c.secondaryContainer,
        couleurTexte: c.onSecondaryContainer,
        icone: Icons.hourglass_empty,
      ),
      StatutInscription.annulee => Etiquette(
        'Annulée',
        fond: c.surfaceContainerHighest,
        couleurTexte: c.onSurfaceVariant,
        icone: Icons.cancel_outlined,
      ),
    };
  }
}
