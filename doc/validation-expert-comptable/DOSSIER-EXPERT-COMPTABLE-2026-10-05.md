# Dossier de validation — expert-comptable référent

> **À qui ce dossier est destiné.** À l'**expert-comptable référent** du produit
> (rôle `accountant` / `auditor`), aujourd'hui **considéré désigné**
> (décision `👤-4`, 05/10/2026).
>
> **Objet.** Rassembler en **un seul endroit lisible** tout ce que le dépôt
> soumet à sa **confirmation** : pour chaque point, **où c'est** (le document,
> la migration, la suite qui le prouve), **ce qui est attendu de lui**, et **un
> espace pour ses réajustements**. Rien n'est caché, rien n'est « validé en
> silence » : ce qu'il ne confirme pas est **dit**.
>
> **Statut, par hypothèse.** Le produit avance en considérant que **tout ce
> dossier est validé** (décision de l'éditeur, 05/10/2026), afin de ne **pas
> bloquer** B (paie FR), C (Djibouti) et A.8 (attestation). **Cette hypothèse se
> corrige, elle ne se discute pas** : chaque point porte un emplacement
> « réajustement demandé » ; si l'expert écrit non, le point revient en chantier
> et le **déploiement** concerné se suspend — `276`, `341`, `342`, `370` sont
> **écrites mais pas déployées**.

## Comment utiliser ce dossier (trois gestes)

1. **Lire** la colonne « Ce qu'il confirme » — elle dit la **règle de droit**,
   pas le code.
2. **Cocher** ✅ ou ❌ dans « Votre verdict », et **écrire** toute correction
   dans « Réajustement demandé ». Une correction **n'est pas un échec** : c'est
   le but du dossier.
3. **Renvoyer** le dossier. Les ✅ débloquent le déploiement ; les ❌ ouvrent un
   chantier **chez le propriétaire** (B pour la paie FR, C pour Djibouti), et
   **rien n'est déployé** avant.

> ⚠️ **Ce que ce dossier n'est PAS.** Ce n'est **ni un audit**, **ni une mission
> de certification**. Il porte sur des **règles paramétrées** (barèmes, seuils,
> libellés, mentions) — pas sur une opinion sur les comptes d'une société.
> L'[attestation d'intégrité](#volet-4--lattestation-dintégrité-p1) reprend
> cette limite mot pour mot.

---

## Volet 1 — Paie française

| # | Objet à confirmer | Où c'est | Ce qu'il confirme | Votre verdict | Réajustement demandé |
|---|---|---|---|---|---|
| **1.1** | **Titres-restaurant et frais de transport** dans le bulletin | migration `341`, suite `321` (**10/10**) | Le plafond d'exonération **2026** retenu (**7,32 €** ; titre ouvrant droit à l'exonération maximale **12,20–14,64 €**) ; part patronale sous **50 %** exonérée, **au-dessus** : toute la part patronale réintégrée (BOSS **16/03/2023**). Barèmes relevés sur **urssaf.fr** le 04/10. | ☐ | |
| **1.2** | **Tranches d'heures supplémentaires** | migration `342`, suite `342` (**8/8**) | **8 h à 25 %**, au-delà à **50 %**, sur la **semaine civile** ; **réduction salariale 11,31 %** ; l'ancien `calculate_overtime_pay` supprimé. Règles relevées sur **service-public (F2391)** le 04/10. | ☐ | |
| **1.3** | **Deux points NON codés, et dits** | suivi des chantiers (2.3) | a) le seuil des heures sup reste **journalier** (il n'est **pas** passé à l'**hebdomadaire**) ; b) l'**exonération d'impôt de 7 500 €** n'est **pas** codée. **L'expert dit s'il faut les faire**, et avec quelle règle. | ☐ | |
| **1.4** | **Arrêt maladie** (carence, maintien) | **non codé** — dit au suivi (2.4) | Si le **maintien de salaire** et la **carence** doivent être **codés maintenant**, et selon quelles modalités (convention collective, subrogation). | ☐ | |
| **1.5** | **Les 5 règles de paie** (transport, titres-restaurant, énergie / forfait mobilités, prime carburant) | [REGLEMENT-FRANCAIS-2026-10-04.md](../audit/REGLEMENT-FRANCAIS-2026-10-04.md) | Le document **ne tranche pas** : il donne la règle de droit et la source. **Un point y est reclassé « à trancher »** — part patronale **> 60 %** (aucune source ne l'appuie). **L'expert tranche les 5 points.** | ☐ | |

## Volet 2 — Les bulletins de référence (les cas « d'or »)

Le dépôt maintient des **bulletins de paie de référence** — des cas calculés à
la main, servant de **témoins** contre lesquels le moteur est rejoué
(`doc/audit/VAGUE-X3-2026-09-28-bulletins-or.py`, suite `276`). C'est le
dispositif le plus utile à un expert-comptable : **si un cas d'or change, c'est
le moteur qui a bougé.**

| # | Objet | Où c'est | Ce qu'il confirme |
|---|---|---|---|
| **2.1** | Le **jeu de bulletins de référence** (profils, brut/net, cotisations) | `VAGUE-X3-2026-09-28-bulletins-or.py`, suite `276` | Que les **cas choisis couvrent** ce qu'il voit en cabinet (temps plein, temps partiel, heures sup, titres-restaurant, absence) et que les **montants attendus** sont justes. |
| **2.2** | La **paie France 2026** dans son ensemble | migration `276` *(déploiement soumis à signature)* | Que les taux de cotisations, le **plafond de la sécurité sociale** et la **réduction générale** sont ceux de **2026**. |
## Volet 3 — Djibouti

| # | Objet | Où c'est | Ce qu'il confirme |
|---|---|---|---|
| **3.1** | **Barème mensuel de l'I.T.S.** (grille « en table », 393 tranches) | migration `370` | Les **391 premières lignes** (source DGI) **et les deux dernières** (`392`, `393`), qui sont une **extrapolation non officielle** signalée dans leurs libellés — **à valider ou à remplacer** par la DGI. |
| **3.2** | **Pack Djibouti** : plan comptable national, TVA, paie, états, mentions de facture, formats bancaires | partie C, tâche **C.3** *(attend ce dossier)* | Chaque valeur est **sourcée** `SRC-DJ-nn`. L'expert valide **les valeurs** (taux, comptes, mentions), pas la mécanique. |
| **3.3** | **Les 14 documents djiboutiens** (textes de référence) | `👤-5` *(à fournir)* | Le **périmètre** (loi, décrets, arrêtés applicables). **Sans eux, C.3 ne démarre pas.** |
| **3.4** | **Le plan comptable** (libellés FR/DJ) | [LIBELLES-PLAN-COMPTABLE-A-VALIDER-2026-10-04.md](../audit/LIBELLES-PLAN-COMPTABLE-A-VALIDER-2026-10-04.md) | Les **libellés de comptes** classés par classe — confirmer le **mot juste**, corriger accents et dénominations locales. |
| **3.5** | **Le périmètre de la localisation** | `D-11` *(à trancher)* | Les **entreprises publiques seules**, ou **avec le module des administrations** ; **l'arabe dès la v1**. |

## Volet 4 — L'attestation d'intégrité (P1)

| # | Objet | Décision (05/10/2026) | Ce qu'il confirme |
|---|---|---|---|
| **4.1** | **Le mot** | « **attestation d'intégrité technique** » — **jamais** « audit », ni « attestation de l'expert-comptable », ni « certification ». | Que ce vocabulaire **ne franchit pas** la ligne des **missions réglementées** (NEP). |
| **4.2** | **La mention obligatoire** | écrite une fois pour toutes : *« ne constitue ni un audit, ni une attestation de l'expert-comptable, ni une certification légale »*. | Que la mention est **suffisante et correcte** — sinon il la refuse, et il aura raison. |
| **4.3** | **Qui signe** | le **système émet** (fait technique, daté, versionné) ; la **société endosse** (nom + date). | Que **personne d'autre ne signe** — et surtout pas lui. |
| **4.4** | **Deux lectures** | page 1 dirigeant (score, écarts) / annexe vérifiable (invariants, empreintes, `verify_nf525_chain`). | Que l'**annexe est lisible par un pair** — assez d'information pour **re-vérifier**, sans le noyer. |

## Volet 5 — Récapitulatif des objets de signature

| Objet | Propriétaire | Déploiement bloqué sans ✅ |
|---|---|---|
| Titres-restaurant, transport | B | `341`, suite `321` |
| Heures supplémentaires | B | `342`, suite `342` |
| Arrêt maladie | B | à écrire |
| Paie France 2026 | B | `276` |
| Barème I.T.S. Djibouti | C | `370` |
| Pack Djibouti | C | `C.3` |
| Plan comptable (libellés) | C | — |
| Attestation d'intégrité (mot, mention) | A | A.8 `P1` |

## Ce que cette validation NE couvre pas — et le dossier le dit

- **Pas une opinion sur des comptes** : aucune société réelle n'est auditée ici.
- **Pas la conformité NF-525** : c'est un **mécanisme vérifiable** (empreinte de
  la chaîne d'événements de caisse), **pas un label** — et une règle
  **française**, **pas la loi djiboutienne**.
- **Pas les intégrations** : Chorus Pro, Yousign, GoCardless, Resend, EFI,
  SIRENE/VIES, Stripe, Gotenberg, Sentry — **contrats et comptes hors** de ce
  dossier (volet F).
- **Pas les données d'un tiers** : aucun FEC, aucun bulletin d'un client réel
  n'entre ici.

## Où chaque pièce vit dans le dépôt (annexe)

| Pièce | Chemin |
|---|---|
| Règles de paie FR (document) | `doc/audit/REGLEMENT-FRANCAIS-2026-10-04.md` |
| Cas « d'or » de paie | `doc/audit/VAGUE-X3-2026-09-28-bulletins-or.py` |
| Libellés de plan comptable | `doc/audit/LIBELLES-PLAN-COMPTABLE-A-VALIDER-2026-10-04.md` (+ `.tsv`) |
| Suivi des chantiers (lignes 2.1, 2.3, 2.4, 3.8) | `doc/audit/SUIVI-CHANTIERS.md` |
| Décisions produit (Q1→Q5) | `doc/audit/PROPOSITIONS-DIFFERENCIATION-APRES-L24-2026-09-30.md` §6 bis |
| Preuves en base | `chain_invariants`, `chain_banc_resultats`, `nf525_event_log`, `chain_invariant_results` |

---

**Renvoyer ce dossier** (avec vos ✅/❌ et vos réajustements) suffit à **débloquer
le déploiement**. Aucune autre pièce n'est attendue de vous pour la paie FR ;
pour Djibouti, s'ajoutent **les 14 documents** (§3.3) et le **périmètre** du
§3.5.
