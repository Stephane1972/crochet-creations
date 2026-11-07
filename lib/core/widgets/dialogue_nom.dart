import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/erreurs.dart';

/// Boîte « nom » (catégorie, lieu de vente...) : un champ, l'erreur éventuelle (nom vide, déjà pris...) affichée sous le
/// champ, et un bouton qui lance [enregistrer]. Retourne ce que [enregistrer] a retourné, ou `null` si on annule.
///
/// L'enregistrement se fait **dans** la boîte : un nom refusé la laisse ouverte, avec l'explication.
///
/// - [erreurNom] : ce qui ne va pas dans le texte saisi (`null` si tout va bien) ;
/// - [nettoyerNom] : le nom prêt à enregistrer (espaces superflus retirés) ;
/// - [longueurMax] : nombre maximal de caractères saisissables ;
/// - [messageEchec] : ce qu'on affiche si l'enregistrement échoue pour une raison imprévue.
Future<T?> demanderNom<T>(
  BuildContext context, {
  required String titre,
  required String libelleValider,
  required String libelleChamp,
  required String messageEchec,
  required Future<T> Function(String nom) enregistrer,
  required String? Function(String? nom) erreurNom,
  required String Function(String? nom) nettoyerNom,
  required int longueurMax,
  String nomInitial = '',
  String? aide,
}) {
  return showDialog<T>(
    context: context,
    builder: (BuildContext contexteDialogue) => _DialogueNom<T>(
      titre: titre,
      libelleValider: libelleValider,
      libelleChamp: libelleChamp,
      messageEchec: messageEchec,
      enregistrer: enregistrer,
      erreurNom: erreurNom,
      nettoyerNom: nettoyerNom,
      longueurMax: longueurMax,
      nomInitial: nomInitial,
      aide: aide,
    ),
  );
}

class _DialogueNom<T> extends StatefulWidget {
  const _DialogueNom({
    required this.titre,
    required this.libelleValider,
    required this.libelleChamp,
    required this.messageEchec,
    required this.enregistrer,
    required this.erreurNom,
    required this.nettoyerNom,
    required this.longueurMax,
    required this.nomInitial,
    required this.aide,
  });

  final String titre;
  final String libelleValider;
  final String libelleChamp;
  final String messageEchec;
  final Future<T> Function(String nom) enregistrer;
  final String? Function(String? nom) erreurNom;
  final String Function(String? nom) nettoyerNom;
  final int longueurMax;
  final String nomInitial;
  final String? aide;

  @override
  State<_DialogueNom<T>> createState() => _DialogueNomState<T>();
}

class _DialogueNomState<T> extends State<_DialogueNom<T>> {
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
    final String? probleme = widget.erreurNom(_nom.text);
    if (probleme != null) {
      setState(() => _erreur = probleme);
      return;
    }
    setState(() {
      _erreur = null;
      _enCours = true;
    });
    try {
      final T resultat = await widget.enregistrer(widget.nettoyerNom(_nom.text));
      if (mounted) Navigator.of(context).pop(resultat);
    } on ErreurMetier catch (erreur) {
      if (mounted) {
        setState(() {
          _erreur = erreur.message;
          _enCours = false;
        });
      }
    } catch (erreur, pile) {
      debugPrint('Enregistrement du nom impossible : $erreur\n$pile');
      if (mounted) {
        setState(() {
          _erreur = widget.messageEchec;
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
            inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(widget.longueurMax)],
            decoration: InputDecoration(labelText: widget.libelleChamp, errorText: _erreur, errorMaxLines: 3),
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
