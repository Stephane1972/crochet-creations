import 'package:flutter/material.dart';

import '../../core/utils/money.dart';
import '../../core/utils/validateurs.dart';
import '../../domain/calculs/panier.dart';
import '../../domain/enums.dart';
import '../../domain/erreurs.dart';
import 'recap_widgets.dart';

/// Comment une vente est réglée au moment de la validation.
enum FormulePaiement {
  tout('Payée'),
  acompte('Acompte'),
  plusTard('Plus tard');

  const FormulePaiement(this.libelle);
  final String libelle;
}

/// Rubrique « Paiement » : payé en totalité, acompte ou plus tard, avec le mode de règlement.
/// Sert à la validation d'une vente (panier) et à l'inscription à un cours. L'écran qui l'affiche lit le résultat
/// avec une `GlobalKey<SaisiePaiementState>` : [SaisiePaiementState.paiement].
///
/// À placer dans un `Form` : le montant de l'acompte est vérifié avec les autres champs.
class SaisiePaiement extends StatefulWidget {
  const SaisiePaiement({
    super.key,
    this.phraseTout = 'La vente est réglée en totalité maintenant.',
    this.phrasePlusTard = 'Rien n’est encaissé : la vente reste impayée jusqu’au règlement.',
  });

  /// Explication affichée sous « Payée ».
  final String phraseTout;

  /// Explication affichée sous « Plus tard ».
  final String phrasePlusTard;

  @override
  State<SaisiePaiement> createState() => SaisiePaiementState();
}

class SaisiePaiementState extends State<SaisiePaiement> {
  final TextEditingController _acompte = TextEditingController();
  FormulePaiement _formule = FormulePaiement.tout;
  ModePaiement _mode = ModePaiement.especes;

  @override
  void dispose() {
    _acompte.dispose();
    super.dispose();
  }

  /// Le paiement à enregistrer pour un total de [totalCentimes] ; `null` = rien à encaisser maintenant
  /// (« Plus tard », ou total nul). Lance [DonneeInvalide] si l'acompte est incorrect.
  PaiementSaisi? paiement(int totalCentimes) {
    if (totalCentimes <= 0) return null;
    switch (_formule) {
      case FormulePaiement.tout:
        return PaiementSaisi(mode: _mode, montantCentimes: totalCentimes);
      case FormulePaiement.acompte:
        final int? montant = parseMontantEuros(_acompte.text);
        if (montant == null || montant <= 0) {
          throw const DonneeInvalide('Indiquez le montant de l’acompte.');
        }
        return PaiementSaisi(mode: _mode, montantCentimes: montant);
      case FormulePaiement.plusTard:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return CarteRubrique(
      titre: 'Paiement',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SegmentedButton<FormulePaiement>(
            segments: <ButtonSegment<FormulePaiement>>[
              for (final FormulePaiement f in FormulePaiement.values)
                ButtonSegment<FormulePaiement>(value: f, label: Text(f.libelle)),
            ],
            selected: <FormulePaiement>{_formule},
            showSelectedIcon: false,
            onSelectionChanged: (Set<FormulePaiement> choix) => setState(() => _formule = choix.first),
          ),
          const SizedBox(height: 8),
          Text(
            switch (_formule) {
              FormulePaiement.tout => widget.phraseTout,
              FormulePaiement.acompte => 'Une partie est réglée maintenant, le solde sera encaissé plus tard.',
              FormulePaiement.plusTard => widget.phrasePlusTard,
            },
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (_formule != FormulePaiement.plusTard) ...<Widget>[
            const SizedBox(height: 12),
            DropdownButtonFormField<ModePaiement>(
              initialValue: _mode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Mode de paiement'),
              items: <DropdownMenuItem<ModePaiement>>[
                for (final ModePaiement m in ModePaiement.values)
                  DropdownMenuItem<ModePaiement>(value: m, child: Text(m.libelle)),
              ],
              onChanged: (ModePaiement? valeur) {
                if (valeur != null) setState(() => _mode = valeur);
              },
            ),
          ],
          if (_formule == FormulePaiement.acompte) ...<Widget>[
            const SizedBox(height: 12),
            TextFormField(
              controller: _acompte,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Montant de l’acompte (€)'),
              validator: (String? v) => validerMontantObligatoire(v, 'Indiquez le montant de l’acompte.'),
            ),
          ],
        ],
      ),
    );
  }
}
