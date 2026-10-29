import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/money.dart';
import '../../data/repositories/cours_vues.dart';
import 'cours_providers.dart';
import 'cours_widgets.dart';

/// Liste des cours (écran 16) : à venir, passés ou archivés, avec les places prises et la liste d'attente.
/// Un appui ouvre la fiche du cours.
class CoursScreen extends ConsumerStatefulWidget {
  const CoursScreen({super.key});

  @override
  ConsumerState<CoursScreen> createState() => _CoursScreenState();
}

class _CoursScreenState extends ConsumerState<CoursScreen> {
  FiltreCours _filtre = FiltreCours.aVenir;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<CoursResume>> cours = ref.watch(coursListeProvider(_filtre));

    return Scaffold(
      appBar: AppBar(title: const Text('Cours')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pushNamed(AppRoutes.coursNouveau),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau cours'),
      ),
      body: Column(
        children: <Widget>[
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: <Widget>[
                for (final FiltreCours f in FiltreCours.values) ...<Widget>[
                  ChoiceChip(
                    label: Text(f.libelle),
                    selected: _filtre == f,
                    onSelected: (bool _) => setState(() => _filtre = f),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: cours.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object erreur, StackTrace pile) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text('Impossible de charger les cours.'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => ref.invalidate(coursListeProvider(_filtre)),
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (List<CoursResume> liste) {
                if (liste.isEmpty) return _AucunCours(filtre: _filtre);
                return ListView.separated(
                  // De la place sous la dernière ligne pour que le bouton « Nouveau cours » ne la masque pas.
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: liste.length,
                  separatorBuilder: (BuildContext context, int index) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) => _LigneCours(resume: liste[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LigneCours extends StatelessWidget {
  const _LigneCours({required this.resume});

  final CoursResume resume;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool complet = resume.complet;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      leading: ImageCours(chemin: resume.cours.photoChemin, largeur: 56, hauteur: 56),
      title: Text(resume.cours.titre, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(quandCours(resume.cours.debutLe)),
          Text(
            textePlaces(confirmes: resume.confirmes, places: resume.cours.places) +
                (resume.enAttente > 0 ? ' · ${resume.enAttente} en attente' : ''),
            style: theme.textTheme.bodySmall?.copyWith(
              color: complet ? scheme.error : scheme.onSurfaceVariant,
              fontWeight: complet ? FontWeight.w600 : null,
            ),
          ),
          if (resume.annule || resume.archive)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  if (resume.annule) const EtiquetteCoursAnnule(),
                  if (resume.archive) const EtiquetteCoursArchive(),
                ],
              ),
            ),
        ],
      ),
      isThreeLine: true,
      trailing: Text(
        resume.cours.prixCentimes == 0 ? 'Gratuit' : formatEuros(resume.cours.prixCentimes),
        style: theme.textTheme.titleSmall,
      ),
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.coursFiche, arguments: resume.cours.id),
    );
  }
}

class _AucunCours extends StatelessWidget {
  const _AucunCours({required this.filtre});

  final FiltreCours filtre;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (String titre, String? conseil) = switch (filtre) {
      FiltreCours.aVenir => ('Aucun cours à venir.', 'Appuyez sur « Nouveau cours » pour en programmer un.'),
      FiltreCours.passes => ('Aucun cours passé.', null),
      FiltreCours.archives => ('Aucun cours archivé.', 'Un cours terminé ou annulé peut être archivé depuis sa fiche.'),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.school_outlined, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(titre, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (conseil != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                conseil,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
