import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/date_fr.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/providers.dart';
import '../../domain/agenda.dart';
import 'agenda_providers.dart';

const List<String> _initialesDesJours = <String>['L', 'M', 'M', 'J', 'V', 'S', 'D'];

/// Le calendrier : la grille du mois, ce qui est prévu chaque jour (cours, fin de validité d'un devis, déclaration des
/// recettes, événements ajoutés à la main), des filtres pour n'afficher que ce qu'on veut, et les liens vers Google Agenda.
class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  /// Le premier jour du mois affiché.
  late DateTime _mois;

  /// Le jour dont on voit le détail.
  late DateTime _jourChoisi;

  @override
  void initState() {
    super.initState();
    final DateTime maintenant = ref.read(horlogeProvider)();
    _mois = DateTime(maintenant.year, maintenant.month);
    _jourChoisi = jourDe(maintenant);
  }

  void _allerAuMois(int decalage) {
    setState(() {
      _mois = DateTime(_mois.year, _mois.month + decalage);
      // Le jour choisi suit : le même quantième si le mois l'a, sinon le dernier jour du mois.
      final int dernier = dernierJourDuMois(_mois.year, _mois.month).day;
      _jourChoisi = DateTime(_mois.year, _mois.month, _jourChoisi.day > dernier ? dernier : _jourChoisi.day);
    });
  }

  void _allerAujourdhui() {
    final DateTime aujourdhui = jourDe(ref.read(horlogeProvider)());
    setState(() {
      _mois = DateTime(aujourdhui.year, aujourdhui.month);
      _jourChoisi = aujourdhui;
    });
  }

  void _choisirJour(DateTime jour) {
    setState(() {
      _jourChoisi = jour;
      // Un jour des semaines voisines : on passe au mois qui le contient.
      if (jour.year != _mois.year || jour.month != _mois.month) _mois = DateTime(jour.year, jour.month);
    });
  }

  Future<void> _ouvrirAdresse(Uri adresse) async {
    final bool ouverte = await ref.read(ouvreurAdresseProvider).ouvrir(adresse);
    if (!ouverte && mounted) {
      afficherMessage(
        context,
        'Impossible d’ouvrir Google Agenda. Vérifiez qu’un navigateur est installé et que l’appareil est connecté à Internet.',
      );
    }
  }

  void _ouvrirEntree(EntreeAgenda entree) {
    final NavigatorState navigateur = Navigator.of(context);
    if (entree.type == TypeEntreeAgenda.declaration) {
      navigateur.pushNamed(AppRoutes.declaration);
      return;
    }
    final int? id = entree.identifiant;
    if (id == null) return;
    switch (entree.type) {
      case TypeEntreeAgenda.cours:
        navigateur.pushNamed(AppRoutes.coursFiche, arguments: id);
      case TypeEntreeAgenda.devis:
        navigateur.pushNamed(AppRoutes.devisDetail, arguments: id);
      case TypeEntreeAgenda.evenement:
        navigateur.pushNamed(AppRoutes.agendaEvenement, arguments: ArgumentsEvenement(evenementId: id));
      case TypeEntreeAgenda.declaration:
        // Déjà traité plus haut (la déclaration n'a pas d'identifiant).
        break;
    }
  }

  Future<void> _changerFiltre(FiltresAgenda actuels, TypeEntreeAgenda type, bool affiche) async {
    try {
      await ref.read(parametresRepositoryProvider).enregistrerFiltresAgenda(actuels.avec(type, affiche: affiche));
    } catch (erreur) {
      if (mounted) afficherMessage(context, messageErreur(erreur));
    }
  }

  @override
  Widget build(BuildContext context) {
    final MoisAgenda cle = (annee: _mois.year, mois: _mois.month);
    final AsyncValue<List<EntreeAgenda>> entrees = ref.watch(entreesAgendaProvider(cle));
    final FiltresAgenda filtres = ref.watch(filtresAgendaProvider).valueOrNull ?? const FiltresAgenda();
    final DateTime aujourdhui = jourDe(ref.watch(horlogeProvider)());

    final Map<DateTime, List<EntreeAgenda>> parJour = regrouperParJour(
      (entrees.valueOrNull ?? const <EntreeAgenda>[]).where((EntreeAgenda e) => filtres.accepte(e.type)),
    );

    final Widget grille = _GrilleDuMois(
      mois: _mois,
      aujourdhui: aujourdhui,
      jourChoisi: _jourChoisi,
      parJour: parJour,
      filtres: filtres,
      chargement: entrees.isLoading && !entrees.hasValue,
      erreur: entrees.hasError && !entrees.hasValue,
      onMoisPrecedent: () => _allerAuMois(-1),
      onMoisSuivant: () => _allerAuMois(1),
      onJour: _choisirJour,
      onFiltre: (TypeEntreeAgenda type, bool affiche) => _changerFiltre(filtres, type, affiche),
      onReessayer: () => ref.invalidate(entreesAgendaProvider(cle)),
    );
    final Widget detail = _DetailDuJour(
      jour: _jourChoisi,
      entrees: parJour[_jourChoisi] ?? const <EntreeAgenda>[],
      onOuvrirEntree: _ouvrirEntree,
      onAjouterAGoogle: (EntreeAgenda e) => _ouvrirAdresse(lienAjouterAGoogleAgenda(e)),
      onOuvrirGoogleAgenda: () => _ouvrirAdresse(lienOuvrirGoogleAgenda(jour: _jourChoisi)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendrier'),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('agenda-synchro-google'),
            tooltip: 'Synchroniser avec Google Agenda',
            icon: const Icon(Icons.sync),
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.agendaGoogle),
          ),
          IconButton(
            tooltip: 'Aujourd’hui',
            icon: const Icon(Icons.today_outlined),
            onPressed: _allerAujourdhui,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'bouton-nouvel-evenement',
        onPressed: () => Navigator.of(context).pushNamed(
          AppRoutes.agendaEvenement,
          arguments: ArgumentsEvenement(jour: _jourChoisi),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Nouvel événement'),
      ),
      // La même page sur téléphone et dans la fenêtre Windows (qui garde la largeur d'un téléphone) : la grille du mois,
      // puis le détail du jour choisi. De la place sous la liste pour que « Nouvel événement » ne la masque pas.
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: <Widget>[grille, const SizedBox(height: 16), const Divider(), const SizedBox(height: 8), detail],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Grille du mois
// -----------------------------------------------------------------------------

Color _couleur(ColorScheme couleurs, TypeEntreeAgenda type) => switch (type) {
  TypeEntreeAgenda.cours => couleurs.primary,
  TypeEntreeAgenda.devis => couleurs.tertiary,
  TypeEntreeAgenda.declaration => couleurs.error,
  TypeEntreeAgenda.evenement => couleurs.secondary,
};

IconData _icone(TypeEntreeAgenda type) => switch (type) {
  TypeEntreeAgenda.cours => Icons.school_outlined,
  TypeEntreeAgenda.devis => Icons.request_quote_outlined,
  TypeEntreeAgenda.declaration => Icons.account_balance_outlined,
  TypeEntreeAgenda.evenement => Icons.event_outlined,
};

String _majuscule(String texte) => texte.isEmpty ? texte : '${texte[0].toUpperCase()}${texte.substring(1)}';

String _cleDuJour(DateTime jour) {
  String deux(int n) => n.toString().padLeft(2, '0');
  return '${jour.year}-${deux(jour.month)}-${deux(jour.day)}';
}

class _GrilleDuMois extends StatelessWidget {
  const _GrilleDuMois({
    required this.mois,
    required this.aujourdhui,
    required this.jourChoisi,
    required this.parJour,
    required this.filtres,
    required this.chargement,
    required this.erreur,
    required this.onMoisPrecedent,
    required this.onMoisSuivant,
    required this.onJour,
    required this.onFiltre,
    required this.onReessayer,
  });

  final DateTime mois;
  final DateTime aujourdhui;
  final DateTime jourChoisi;
  final Map<DateTime, List<EntreeAgenda>> parJour;
  final FiltresAgenda filtres;
  final bool chargement;
  final bool erreur;
  final VoidCallback onMoisPrecedent;
  final VoidCallback onMoisSuivant;
  final ValueChanged<DateTime> onJour;
  final void Function(TypeEntreeAgenda type, bool affiche) onFiltre;
  final VoidCallback onReessayer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<DateTime> jours = joursAffiches(mois.year, mois.month);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(tooltip: 'Mois précédent', icon: const Icon(Icons.chevron_left), onPressed: onMoisPrecedent),
            Expanded(
              child: Text(
                _majuscule(formatMois(mois.year, mois.month)),
                key: const Key('agenda-titre-du-mois'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
            ),
            IconButton(tooltip: 'Mois suivant', icon: const Icon(Icons.chevron_right), onPressed: onMoisSuivant),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          key: const Key('agenda-filtres'),
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            for (final TypeEntreeAgenda type in TypeEntreeAgenda.values)
              FilterChip(
                label: Text(type.libelle),
                avatar: CircleAvatar(radius: 6, backgroundColor: _couleur(theme.colorScheme, type)),
                showCheckmark: false,
                selected: filtres.accepte(type),
                onSelected: (bool choisi) => onFiltre(type, choisi),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            for (final String initiale in _initialesDesJours)
              Expanded(
                child: Center(
                  child: Text(
                    initiale,
                    style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (erreur)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: <Widget>[
                const Text('Impossible de charger le calendrier.'),
                const SizedBox(height: 12),
                FilledButton(onPressed: onReessayer, child: const Text('Réessayer')),
              ],
            ),
          )
        else
          for (int semaine = 0; semaine < jours.length ~/ 7; semaine++)
            Row(
              children: <Widget>[
                for (final DateTime jour in jours.sublist(semaine * 7, semaine * 7 + 7))
                  Expanded(
                    child: _CelluleJour(
                      jour: jour,
                      dansLeMois: jour.month == mois.month,
                      estAujourdhui: jour == aujourdhui,
                      estChoisi: jour == jourChoisi,
                      types: <TypeEntreeAgenda>{
                        for (final EntreeAgenda e in parJour[jour] ?? const <EntreeAgenda>[]) e.type,
                      },
                      nombre: (parJour[jour] ?? const <EntreeAgenda>[]).length,
                      onTap: () => onJour(jour),
                    ),
                  ),
              ],
            ),
        if (chargement)
          const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
      ],
    );
  }
}

class _CelluleJour extends StatelessWidget {
  const _CelluleJour({
    required this.jour,
    required this.dansLeMois,
    required this.estAujourdhui,
    required this.estChoisi,
    required this.types,
    required this.nombre,
    required this.onTap,
  });

  final DateTime jour;
  final bool dansLeMois;
  final bool estAujourdhui;
  final bool estChoisi;
  final Set<TypeEntreeAgenda> types;
  final int nombre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme couleurs = theme.colorScheme;
    final Color texte = !dansLeMois
        ? couleurs.onSurfaceVariant.withValues(alpha: 0.5)
        : estChoisi
        ? couleurs.onPrimaryContainer
        : couleurs.onSurface;
    // Les points suivent l'ordre des types, toujours le même d'un jour à l'autre.
    final List<TypeEntreeAgenda> pointsAMontrer = TypeEntreeAgenda.values.where(types.contains).toList();

    final String resume = nombre == 0
        ? 'rien de prévu'
        : nombre == 1
        ? '1 élément'
        : '$nombre éléments';

    return Semantics(
      button: true,
      selected: estChoisi,
      label: '${formatDateLongue(jour)}${estAujourdhui ? ', aujourd’hui' : ''}, $resume',
      excludeSemantics: true,
      child: InkWell(
        key: Key('jour-${_cleDuJour(jour)}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 58,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: estChoisi ? couleurs.primaryContainer : null,
            border: estAujourdhui ? Border.all(color: couleurs.primary, width: 2) : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                '${jour.day}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: texte,
                  fontWeight: estAujourdhui || estChoisi ? FontWeight.w700 : null,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    for (final TypeEntreeAgenda type in pointsAMontrer)
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: _couleur(couleurs, type).withValues(alpha: dansLeMois ? 1 : 0.5),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Détail d'un jour
// -----------------------------------------------------------------------------

class _DetailDuJour extends StatelessWidget {
  const _DetailDuJour({
    required this.jour,
    required this.entrees,
    required this.onOuvrirEntree,
    required this.onAjouterAGoogle,
    required this.onOuvrirGoogleAgenda,
  });

  final DateTime jour;
  final List<EntreeAgenda> entrees;
  final ValueChanged<EntreeAgenda> onOuvrirEntree;
  final ValueChanged<EntreeAgenda> onAjouterAGoogle;
  final VoidCallback onOuvrirGoogleAgenda;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '${_majuscule(formatDateLongue(jour))} ${jour.year}',
          key: const Key('agenda-titre-du-jour'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (entrees.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Rien de prévu ce jour-là.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          )
        else
          for (final EntreeAgenda entree in entrees)
            _LigneEntree(
              entree: entree,
              onTap: entree.identifiant == null && entree.type != TypeEntreeAgenda.declaration ? null : () => onOuvrirEntree(entree),
              onAjouterAGoogle: () => onAjouterAGoogle(entree),
            ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onOuvrirGoogleAgenda,
          icon: const Icon(Icons.open_in_new),
          label: const Text('Ouvrir Google Agenda'),
        ),
      ],
    );
  }
}

class _LigneEntree extends StatelessWidget {
  const _LigneEntree({required this.entree, required this.onTap, required this.onAjouterAGoogle});

  final EntreeAgenda entree;
  final VoidCallback? onTap;
  final VoidCallback onAjouterAGoogle;

  /// « 14 h 00 – 16 h 00 · Atelier de Léa · 6 places » : l'heure (sauf pour une entrée « toute la journée »), le lieu, puis le détail.
  String get _precisions {
    final List<String> morceaux = <String>[];
    if (!entree.journeeEntiere) {
      final DateTime? fin = entree.fin;
      morceaux.add(fin == null ? formatHeure(entree.debut) : '${formatHeure(entree.debut)} – ${formatHeure(fin)}');
    }
    final String lieu = (entree.lieu ?? '').trim();
    if (lieu.isNotEmpty) morceaux.add(lieu);
    final String detail = (entree.detail ?? '').trim();
    if (detail.isNotEmpty) morceaux.add(detail);
    return morceaux.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme couleurs = Theme.of(context).colorScheme;
    final Color couleur = _couleur(couleurs, entree.type);
    final String precisions = _precisions;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: couleur.withValues(alpha: 0.15),
          child: Icon(_icone(entree.type), color: couleur),
        ),
        title: Text(entree.titre),
        subtitle: precisions.isEmpty ? null : Text(precisions),
        trailing: IconButton(
          tooltip: 'Ajouter à Google Agenda',
          icon: const Icon(Icons.event_available_outlined),
          onPressed: onAjouterAGoogle,
        ),
      ),
    );
  }
}
