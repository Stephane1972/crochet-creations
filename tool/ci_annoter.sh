#!/usr/bin/env bash
# Publie un extrait d'un journal comme « annotation » GitHub Actions (visible en haut
# de la page de l'exécution), sans avoir à ouvrir le journal complet.
#
# Usage : bash tool/ci_annoter.sh "Titre" fichier.log [motif_regex]
#   - motif_regex (facultatif) : ne garde que les lignes qui correspondent
#     (par exemple les erreurs) ; sinon, les 70 dernières lignes du journal.
set -u
titre="${1:?titre manquant}"
fichier="${2:?fichier manquant}"
motif="${3:-}"

extrait=""
if [ -n "$motif" ]; then
  extrait=$(grep -E "$motif" "$fichier" | head -n 60 | head -c 7000 || true)
fi
if [ -z "$extrait" ]; then
  extrait=$(tail -n 70 "$fichier" | head -c 7000)
fi

# Encodage attendu par GitHub pour les annotations multi-lignes.
extrait="${extrait//'%'/'%25'}"
extrait="${extrait//$'\r'/'%0D'}"
extrait="${extrait//$'\n'/'%0A'}"
echo "::error title=${titre}::${extrait}"
