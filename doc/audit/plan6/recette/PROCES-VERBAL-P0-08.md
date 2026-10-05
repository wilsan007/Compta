# Procès-verbal de recette — P0-08 (les 14 parcours à l’écran)

> Généré le **2026-10-05** par `node app/scripts/qa/recette.mjs`.
> Référentiel : **ce92316fee4f** — un référentiel figé, pas une liste tenue à la main.
> **Preuve par parcours :** une capture + le CHIFFRE lu. Un écart devient un scénario rouge.

**Environnement.** Application locale (`QA_BASE_URL` local — jamais une URL distante) ; base à jour ; 2 sociétés — **remplie** et **vide** ; 4 gabarits — 375 / 768 / 1280 / 1920 px.

| # | Écran | Parcours | Ce qu’on doit voir | Lit | Verdict | Capture |
|---|---|---|---|---|---|---|
| rec-01 | Inscription | Créer une société France, puis Djibouti | plan semé ; pour DJ : plan provisoire signalé ; autre pays refusé (PAYS_NON_DISPONIBLE) | pays accepté / refusé | ⬜ | |
| rec-02 | Factures | Nouvelle facture 2 lignes (TVA 20 % et 5,5 %) → Valider → Envoyer | brouillon BROUILLON-FAC-…, puis FAC-2026-000001 ; badge « Comptabilisé » ; écriture VT équilibrée | numéro + écriture équilibrée | ⬜ | |
| rec-03 | Factures | « Envoyer » un brouillon | la facture est validée d’abord (numéro définitif), puis envoyée | ordre valider → envoyer | ⬜ | |
| rec-04 | Factures | « Marquer payée » | règlement REG-…, facture payée, 411 lettré ; le bouton n’apparaît pas sur un brouillon | règlement + lettrage 411 | ⬜ | |
| rec-05 | Devis | Nouveau devis → Convertir en facture | lignes et TVA reprises ; devis « transformé » | lignes + TVA reprises | ⬜ | |
| rec-06 | Avoirs | Avoir sur facture → Valider | AV-2026-000001, facture soldée ou réduite, lettrage | numéro AV + solde | ⬜ | |
| rec-07 | Factures d’achat | Nouvelle facture (référence fournisseur + lignes) → Approuver → Marquer payée | ACH-2026-000001, écriture AC, décaissement DEC-…, 401 lettré ; libellés traduits (fr/en/ar) | numéro ACH + lettrage 401 | ⬜ | |
| rec-08 | Avoirs fournisseur | Nouveau → Valider | AVF-…, écriture AC inverse | numéro AVF + écriture inverse | ⬜ | |
| rec-09 | Paie | Lot approuvé → « Générer l’écriture de paie » → passer à « payé » | une seule écriture PAIE, équilibrée ; message clair si un bulletin est incohérent | une écriture PAIE équilibrée | ⬜ | |
| rec-10 | Import de relevé | Fichier MT940 / CAMT.053 / CFONB réel | « n opérations importées, m doublons écartés » ; lignes pointées automatiquement | n importées / m doublons | ⬜ | |
| rec-11 | Stock | Inventaire en baisse puis en hausse | stock dépôt = stock article ; écriture ST | stock dépôt = stock article | ⬜ | |
| rec-12 | Caisse | Session avec 2 tickets → clôture | stock du magasin seul décrémenté, une fois | stock décrémenté une fois | ⬜ | |
| rec-13 | Clôture (V2) | Exercice complet → clôture → bilan / compte de résultat | équilibrés, à-nouveaux corrects, bandeau rouge absent | bilan = compte de résultat | ⬜ | |
| rec-14 | Tout | Changer de langue (fr → en → ar) | aucune clé brute affichée ; arabe en RTL | 0 clé brute ; RTL | ⬜ | |

**Matrice.** Chaque parcours est joué sur **2 états** de société et **4 gabarits** — 14 × 2 × 4 = **112 passages**. Un passage non applicable est *barré*, jamais laissé en ⬜ en silence.

## Critères de sortie (tous requis)
- [ ] les 14 parcours portent un verdict (aucun ⬜) ;
- [ ] 0 écart **bloquant** ouvert — les autres sont inscrits pour l’horizon suivant ;
- [ ] modules re-notés (voir le certificat) ;
- [ ] **procès-verbal signé** (ci-dessous).

## Signature

| | Nom | Date | Signature |
|---|---|---|---|
| Recette faite par |  |  |  |
| Accepté par (client) |  |  |  |
