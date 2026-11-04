import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/categories_produit.dart';
import '../../domain/erreurs.dart';

/// Boîte « nom de catégorie » : un champ, l'erreur éventuelle (nom vide, déjà pris...) affichée sous le champ, et un
/// bouton qui lance [enregistrer]. Retourne ce que [enregistrer] a retourné, ou `null` si on annule.
///
/// L'enregistrement se fait **dans** la boîte : un nom refusé la laisse ouverte, avec l'explication.
Future<T?> demanderNomCategorie<T>(
  BuildContext context, {
  required String titre,
  required String libelleValider,
  required Future<T> Function(String nom) enregistrer,
  String nomInitial = '',
  String? aide,
}) {
  return showDialog<T>(
    context: context,
    builder: (BuildContext contexteDialogue) => _DialogueNomCategorie<T>(
      titre: titre,
      libelleValider: libelleValider,
      enregistrer: enregistrer,
      nomInitial: nomInitial,
      aide: aide,
    ),
  );
}

class _DialogueNomCategorie<T> extends StatefulWidget {
  const _DialogueNomCategorie({
    required this.titre,
    required this.libelleValider,
    required this.enregistrer,
    required this.nomInitial,
    required this.aide,
  });

  final String titre;
  final String libelleValider;
  final Future<T> Function(String nom) enregistrer;
  final String nomInitial;
  final String? aide;

  @override
  State<_DialogueNomCategorie<T>> createState() => _DialogueNomCategorieState<T>();
}

class _DialogueNomCategorieState<T> extends State<_DialogueNomCategorie<T>> {
  late final TextEditingController _nom = TextEditingController(text: widget.nomInitial);
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _nom.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_enCours) return;
    final String? probleme = erreurNomCategorie(_nom.text);
    if (probleme != null) {
      setState(() => _erreur = probleme);
      return;
    }
    setState(() {
      _erreur = null;
      _enCours = true;
    });
    try {
      final T resultat = await widget.enregistrer(nettoyerNomCategorie(_nom.text));
      if (mounted) Navigator.of(context).pop(resultat);
    } on ErreurMetier catch (erreur) {
      if (mounted) {
        setState(() {
          _erreur = erreur.message;
          _enCours = false;
        });
      }
    } catch (erreur, pile) {
      debugPrint('Enregistrement de la catégorie impossible : $erreur\n$pile');
      if (mounted) {
        setState(() {
          _erreur = 'La catégorie n’a pas pu être enregistrée. Réessayez.';
          _enCours = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titre),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (widget.aide != null) ...<Widget>[
            Text(widget.aide!),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _nom,
            autofocus: true,
            enabled: !_enCours,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(longueurMaxNomCategorie)],
            decoration: InputDecoration(labelText: 'Nom de la catégorie', errorText: _erreur, errorMaxLines: 3),
            onChanged: (String _) {
              if (_erreur != null) setState(() => _erreur = null);
            },
            onSubmitted: (String _) => _valider(),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _enCours ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _enCours ? null : _valider, child: Text(widget.libelleValider)),
      ],
    );
  }
}
