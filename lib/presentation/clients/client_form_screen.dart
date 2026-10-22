import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/texte.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/client_repository.dart';
import '../../domain/enums.dart';
import '../../domain/regles_client.dart';

/// Ajout et modification d'un client. Sans [clientId] : nouveau client.
class ClientFormScreen extends ConsumerStatefulWidget {
  const ClientFormScreen({super.key, this.clientId});

  final int? clientId;

  @override
  ConsumerState<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends ConsumerState<ClientFormScreen> {
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();

  final TextEditingController _raisonSociale = TextEditingController();
  final TextEditingController _siret = TextEditingController();
  final TextEditingController _prenom = TextEditingController();
  final TextEditingController _nom = TextEditingController();
  final TextEditingController _telephone = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _adresse = TextEditingController();
  final TextEditingController _codePostal = TextEditingController();
  final TextEditingController _ville = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  TypeClient _type = TypeClient.particulier;
  Civilite? _civilite;

  // État de l'écran
  bool _chargement = true;
  bool _introuvable = false;
  bool _erreurChargement = false;
  bool _modifie = false;
  bool _enregistre = false;
  bool _enCours = false;

  bool get _creation => widget.clientId == null;
  bool get _professionnel => _type == TypeClient.professionnel;

  @override
  void initState() {
    super.initState();
    if (_creation) {
      _chargement = false;
    } else {
      _charger();
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _raisonSociale,
      _siret,
      _prenom,
      _nom,
      _telephone,
      _email,
      _adresse,
      _codePostal,
      _ville,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final Client? client = await ref.read(clientRepositoryProvider).obtenir(widget.clientId!);
      if (!mounted) return;
      if (client == null) {
        setState(() {
          _introuvable = true;
          _chargement = false;
        });
        return;
      }
      setState(() {
        _type = client.typeClient;
        _civilite = client.civilite;
        _raisonSociale.text = client.raisonSociale ?? '';
        _siret.text = client.siret ?? '';
        _prenom.text = client.prenom ?? '';
        _nom.text = client.nom ?? '';
        _telephone.text = client.telephone ?? '';
        _email.text = client.email ?? '';
        _adresse.text = client.adresse ?? '';
        _codePostal.text = client.codePostal ?? '';
        _ville.text = client.ville ?? '';
        _notes.text = client.notes ?? '';
        _chargement = false;
      });
    } catch (erreur, pile) {
      debugPrint('Chargement du client impossible : $erreur\n$pile');
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

  // --- Enregistrement -------------------------------------------------------

  /// Il faut au moins un nom : prénom, nom ou (pour un professionnel) raison sociale.
  String? _validerNomPresent(String? valeur) {
    final bool aUnNom =
        nullSiVide(_prenom.text) != null ||
        nullSiVide(_nom.text) != null ||
        (_professionnel && nullSiVide(_raisonSociale.text) != null);
    if (aUnNom) return null;
    return _professionnel
        ? 'Indiquez au moins une raison sociale, un prénom ou un nom.'
        : 'Indiquez au moins un prénom ou un nom.';
  }

  DonneesClient _construireDonnees() {
    return DonneesClient(
      typeClient: _type,
      civilite: _civilite,
      prenom: nullSiVide(_prenom.text),
      nom: nullSiVide(_nom.text),
      // La raison sociale et le SIREN/SIRET n'existent que pour un professionnel.
      raisonSociale: _professionnel ? nullSiVide(_raisonSociale.text) : null,
      siret: _professionnel ? nullSiVide(_siret.text) : null,
      telephone: nullSiVide(_telephone.text),
      email: nullSiVide(_email.text),
      adresse: nullSiVide(_adresse.text),
      codePostal: nullSiVide(_codePostal.text),
      ville: nullSiVide(_ville.text),
      notes: nullSiVide(_notes.text),
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
      final ClientRepository repo = ref.read(clientRepositoryProvider);
      final DonneesClient donnees = _construireDonnees();
      final Client client = _creation
          ? await repo.creer(donnees)
          : await repo.modifier(widget.clientId!, donnees);

      if (!mounted) return;
      _enregistre = true;
      afficherMessage(context, _creation ? 'Client ajouté.' : 'Modifications enregistrées.');
      if (_creation) {
        // On ouvre la fiche du nouveau client.
        await Navigator.of(context).pushReplacementNamed(AppRoutes.clientFiche, arguments: client.id);
      } else {
        Navigator.of(context).pop();
      }
    } catch (erreur, pile) {
      debugPrint('Enregistrement du client impossible : $erreur\n$pile');
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

  // --- Interface ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _enregistre || !_modifie,
      onPopInvokedWithResult: (bool didPop, Object? resultat) {
        if (!didPop) _demanderAbandon();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_creation ? 'Nouveau client' : 'Modifier le client'),
          actions: <Widget>[
            if (!_chargement && !_introuvable && !_erreurChargement)
              TextButton(
                onPressed: _enCours ? null : _enregistrer,
                child: const Text('Enregistrer'),
              ),
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
            _introuvable ? 'Ce client n’existe plus.' : 'Impossible de charger ce client.',
            textAlign: TextAlign.center,
          ),
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
          _TitreSection('Type de client', theme),
          SegmentedButton<TypeClient>(
            segments: <ButtonSegment<TypeClient>>[
              for (final TypeClient t in TypeClient.values)
                ButtonSegment<TypeClient>(value: t, label: Text(t.libelle)),
            ],
            selected: <TypeClient>{_type},
            showSelectedIcon: false,
            onSelectionChanged: (Set<TypeClient> choix) {
              setState(() => _type = choix.first);
              _marquerModifie();
            },
          ),
          const SizedBox(height: 24),
          if (_professionnel) ...<Widget>[
            _TitreSection('Entreprise', theme),
            TextFormField(
              controller: _raisonSociale,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Raison sociale'),
              validator: _validerNomPresent,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _siret,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'SIREN ou SIRET',
                helperText: '9 chiffres (SIREN) ou 14 chiffres (SIRET).',
              ),
              validator: verifierSiret,
            ),
            const SizedBox(height: 24),
          ],
          _TitreSection(_professionnel ? 'Personne à contacter' : 'Identité', theme),
          DropdownButtonFormField<Civilite?>(
            initialValue: _civilite,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Civilité'),
            items: <DropdownMenuItem<Civilite?>>[
              const DropdownMenuItem<Civilite?>(value: null, child: Text('Non précisée')),
              for (final Civilite c in Civilite.values)
                DropdownMenuItem<Civilite?>(value: c, child: Text(c.libelle)),
            ],
            onChanged: (Civilite? valeur) => setState(() => _civilite = valeur),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _prenom,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Prénom'),
            validator: _professionnel ? null : _validerNomPresent,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nom,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Nom'),
          ),
          const SizedBox(height: 24),
          _TitreSection('Contact', theme),
          TextFormField(
            controller: _telephone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Téléphone'),
            validator: verifierTelephone,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'E-mail'),
            validator: verifierEmail,
          ),
          const SizedBox(height: 24),
          _TitreSection('Adresse', theme),
          TextFormField(
            controller: _adresse,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Adresse'),
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
          const SizedBox(height: 24),
          _TitreSection('Notes', theme),
          TextFormField(
            controller: _notes,
            textCapitalization: TextCapitalization.sentences,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'Goûts, préférences, informations utiles...',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _enCours ? null : _enregistrer,
            icon: _enCours
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_creation ? 'Ajouter le client' : 'Enregistrer les modifications'),
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
