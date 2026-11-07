import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../domain/notes.dart';
import 'categorie_note_dialogues.dart';
import 'notes_providers.dart';

/// Résultat de la feuille de choix : une catégorie, ou `null` pour « Sans catégorie ».
/// (Fermer la feuille sans choisir ne retourne rien du tout : la différence compte.)
class ChoixCategorieNote {
  const ChoixCategorieNote(this.categorieId);

  final int? categorieId;
}

/// Ouvre la feuille « Catégorie » : « Sans catégorie », les catégories, et « Nouvelle catégorie ».
/// [categorieIdActuelle] est cochée. Retourne `null` si on referme la feuille sans rien choisir.
Future<ChoixCategorieNote?> choisirCategorieNote(BuildContext context, {required int? categorieIdActuelle}) {
  return showModalBottomSheet<ChoixCategorieNote>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext contexteFeuille) => FeuilleChoixCategorieNote(categorieIdActuelle: categorieIdActuelle),
  );
}

/// Carte « catégorie » du formulaire d'une note : la catégorie choisie (ou « Sans catégorie »), un appui ouvre la
/// feuille de choix.
class LigneChoixCategorieNote extends StatelessWidget {
  const LigneChoixCategorieNote({super.key, required this.categorie, required this.onChoisie, this.chargee = true});

  /// `null` = « Sans catégorie ».
  final CategorieNote? categorie;

  /// Appelé avec l'identifiant de la catégorie choisie, ou `null` pour « Sans catégorie ».
  final void Function(int? categorieId) onChoisie;

  /// Faux tant que la liste des catégories se charge : on n'affiche pas « Sans catégorie » pour une catégorie qu'on ne
  /// connaît pas encore.
  final bool chargee;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CategorieNote? choisie = categorie;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          foregroundColor: theme.colorScheme.onSecondaryContainer,
          child: Icon(choisie == null ? Icons.label_off_outlined : Icons.label_outline),
        ),
        title: Text(choisie?.nom ?? (chargee ? libelleSansCategorieNote : '…')),
        subtitle: const Text('Catégorie de la note'),
        trailing: const Icon(Icons.unfold_more),
        onTap: () async {
          final ChoixCategorieNote? choix = await choisirCategorieNote(context, categorieIdActuelle: choisie?.id);
          if (choix != null && context.mounted) onChoisie(choix.categorieId);
        },
      ),
    );
  }
}

/// Feuille du bas : « Sans catégorie », puis les catégories, puis « Nouvelle catégorie » (la catégorie créée est
/// choisie aussitôt).
class FeuilleChoixCategorieNote extends ConsumerWidget {
  const FeuilleChoixCategorieNote({super.key, this.categorieIdActuelle});

  final int? categorieIdActuelle;

  Future<void> _creer(BuildContext context, WidgetRef ref) async {
    final CategorieNote? creee = await demanderNomCategorieNote<CategorieNote>(
      context,
      titre: 'Nouvelle catégorie de notes',
      libelleValider: 'Créer',
      enregistrer: (String nom) => ref.read(categorieNoteRepositoryProvider).creer(nom),
    );
    if (creee != null && context.mounted) Navigator.of(context).pop(ChoixCategorieNote(creee.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CategorieNote>> categories = ref.watch(categoriesNoteProvider);
    final double hauteurMax = MediaQuery.sizeOf(context).height * 0.75;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: hauteurMax),
        child: categories.when(
          loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          error: (Object erreur, StackTrace pile) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Impossible de charger les catégories de notes. ${messageErreur(erreur)}'),
          ),
          data: (List<CategorieNote> liste) => ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.label_off_outlined)),
                title: const Text(libelleSansCategorieNote),
                subtitle: const Text('Aucune catégorie choisie'),
                selected: categorieIdActuelle == null,
                trailing: categorieIdActuelle == null ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(const ChoixCategorieNote(null)),
              ),
              const Divider(height: 1),
              for (final CategorieNote c in liste)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.label_outline)),
                  title: Text(c.nom),
                  selected: categorieIdActuelle == c.id,
                  trailing: categorieIdActuelle == c.id ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.of(context).pop(ChoixCategorieNote(c.id)),
                ),
              const Divider(height: 1),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.add)),
                title: const Text('Nouvelle catégorie'),
                onTap: () => _creer(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
