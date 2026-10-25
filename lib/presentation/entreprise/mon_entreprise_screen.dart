import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/texte.dart';
import '../../core/utils/validateurs.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/parametres_repository.dart';
import '../../domain/regles_client.dart';
import '../../domain/regles_entreprise.dart';

/// Profil « Mon entreprise » (écran 22) : ce qui s'imprime en haut et en bas des factures.
class MonEntrepriseScreen extends ConsumerStatefulWidget {
  const MonEntrepriseScreen({super.key});

  @override
  ConsumerState<MonEntrepriseScreen> createState() => _MonEntrepriseScreenState();
}

class _MonEntrepriseScreenState extends ConsumerState<MonEntrepriseScreen> {
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();

  final TextEditingController _nomCommercial = TextEditingController();
  final TextEditingController _nomResponsable = TextEditingController();
  final TextEditingController _adresse = TextEditingController();
  final TextEditingController _codePostal = TextEditingController();
  final TextEditingController _ville = TextEditingController();
  final TextEditingController _telephone = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _siren = TextEditingController();
  final TextEditingController _conditions = TextEditingController();
  final TextEditingController _iban = TextEditingController();
  final TextEditingController _remerciement = TextEditingController();

  bool _chargement = true;
  bool _erreurChargement = false;
  bool _modifie = false;
  bool _enregistre = false;
  bool _enCours = false;

  List<TextEditingController> get _champs => <TextEditingController>[
    _nomCommercial,
    _nomResponsable,
    _adresse,
    _codePostal,
    _ville,
    _telephone,
    _email,
    _siren,
    _conditions,
    _iban,
    _remerciement,
  ];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    for (final TextEditingController c in _champs) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final Entreprise e = await ref.read(parametresRepositoryProvider).lire();
      if (!mounted) return;
      setState(() {
        _nomCommercial.text = e.nomCommercial;
        _nomResponsable.text = e.nomResponsable ?? '';
        _adresse.text = e.adresse ?? '';
        _codePostal.text = e.codePostal ?? '';
        _ville.text = e.ville ?? '';
        _telephone.text = e.telephone ?? '';
        _email.text = e.email ?? '';
        _siren.text = e.siren ?? '';
        _conditions.text = e.conditionsPaiement;
        _iban.text = e.iban ?? '';
        _remerciement.text = e.messageRemerciement;
        _chargement = false;
      });
    } catch (erreur, pile) {
      debugPrint('Chargement du profil impossible : $erreur\n$pile');
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

  Future<void> _enregistrer() async {
    if (_enCours) return;
    if (!_formulaire.currentState!.validate()) {
      afficherMessage(context, 'Corrigez les champs signalés en rouge.');
      return;
    }
    setState(() => _enCours = true);
    try {
      await ref
          .read(parametresRepositoryProvider)
          .enregistrerProfil(
            DonneesEntreprise(
              nomCommercial: nullSiVide(_nomCommercial.text),
              nomResponsable: nullSiVide(_nomResponsable.text),
              adresse: nullSiVide(_adresse.text),
              codePostal: nullSiVide(_codePostal.text),
              ville: nullSiVide(_ville.text),
              telephone: nullSiVide(_telephone.text),
              email: nullSiVide(_email.text),
              siren: nullSiVide(_siren.text),
              conditionsPaiement: nullSiVide(_conditions.text),
              iban: nullSiVide(_iban.text),
              messageRemerciement: nullSiVide(_remerciement.text),
            ),
          );
      if (!mounted) return;
      _enregistre = true;
      afficherMessage(context, 'Profil enregistré.');
      Navigator.of(context).pop();
    } catch (erreur, pile) {
      debugPrint('Enregistrement du profil impossible : $erreur\n$pile');
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
    setState(() => _enregistre = true); // plus rien à protéger : on peut quitter
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _enregistre || !_modifie,
      onPopInvokedWithResult: (bool didPop, Object? resultat) {
        if (!didPop) _demanderAbandon();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mon entreprise'),
          actions: <Widget>[
            if (!_chargement && !_erreurChargement)
              TextButton(onPressed: _enCours ? null : _enregistrer, child: const Text('Enregistrer')),
          ],
        ),
        body: _corps(context),
      ),
    );
  }

  Widget _corps(BuildContext context) {
    if (_chargement) return const Center(child: CircularProgressIndicator());
    if (_erreurChargement) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Impossible de charger le profil.', textAlign: TextAlign.center),
        ),
      );
    }

    final ThemeData theme = Theme.of(context);

    return Form(
      key: _formulaire,
      onChanged: _marquerModifie,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.info_outline, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Ces informations s’impriment sur vos factures. Le nom, l’adresse et le SIREN sont '
                      'nécessaires pour pouvoir créer une facture.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _TitreSection('Votre entreprise', theme),
          TextFormField(
            controller: _nomCommercial,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Nom de l’entreprise',
              helperText: 'Le nom commercial, par exemple « Crochet & Créations ».',
            ),
            validator: (String? v) => validerLongueurMax(v, 100, 'Le nom de l’entreprise'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nomResponsable,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Votre nom (facultatif)'),
            validator: (String? v) => validerLongueurMax(v, 100, 'Votre nom'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _siren,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'SIREN',
              helperText: '9 chiffres, sur votre avis de situation.',
            ),
            validator: verifierSiren,
          ),
          const SizedBox(height: 24),
          _TitreSection('Adresse et contact', theme),
          TextFormField(
            controller: _adresse,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Adresse'),
            validator: (String? v) => validerLongueurMax(v, 200, 'L’adresse'),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _codePostal,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Code postal'),
                  validator: verifierCodePostal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _ville,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Ville'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _telephone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Téléphone (facultatif)'),
            validator: verifierTelephone,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'E-mail (facultatif)'),
            validator: verifierEmail,
          ),
          const SizedBox(height: 24),
          _TitreSection('Sur les factures', theme),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.verified_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Mention automatique : ${AppConstants.mentionTvaFranchise}.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _conditions,
            textCapitalization: TextCapitalization.sentences,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Conditions de paiement',
              hintText: conditionsPaiementParDefaut,
            ),
            validator: (String? v) => validerLongueurMax(v, 300, 'Les conditions de paiement'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _iban,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'IBAN (facultatif)',
              helperText: 'Imprimé sur les factures pour recevoir les virements.',
            ),
            validator: verifierIban,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _remerciement,
            textCapitalization: TextCapitalization.sentences,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Message de remerciement',
              helperText: 'Laissez vide pour ne pas en mettre.',
            ),
            validator: (String? v) => validerLongueurMax(v, 200, 'Le message de remerciement'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _enCours ? null : _enregistrer,
            icon: _enCours
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Enregistrer'),
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
