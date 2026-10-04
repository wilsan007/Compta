# Règlement français — audit des règles de paie (frais de transport, titres-restaurant, énergie)

> **Objet de ce document.** Vérification, sur sources officielles françaises, de cinq règles de
> gestion de paie destinées à être tranchées par l'expert-comptable. Chaque point soumis à la
> décision humaine est repris ici avec la **règle de droit applicable**, la **source primaire**,
> et le **verdict** : `CONFIRMÉ`, `RÉFUTÉ` ou `À CORRIGER`.
>
> **Ce document ne tranche pas.** Il documente l'état du droit et isole les points qui appellent
> une décision de l'expert-comptable. Les points marqués « à trancher » ne doivent pas être
> implémentés en dur avant arbitrage.

**Date de rédaction :** 04/10/2026
**Relu et corrigé :** 04/10/2026 — voir § 0 bis (trois corrections, et l'état du code)
**Périmètre :** paie — avantages en nature et frais professionnels
**Statut :** à faire trancher par l'expert-comptable

---

## 0. Note méthodologique — ce qui a pu être lu, et ce qui ne l'a pas pu

Cette vérification est une **recherche documentaire**, pas un audit de code.

| | |
|---|---|
| **Périmètre réellement couvert** | Les **règles de droit** applicables aux 5 points soumis |
| **Périmètre NON couvert** | Le **code du moteur de paie** lui-même — aucun dépôt de moteur n'était accessible depuis l'environnement de travail |

Il est donc **possible que le code soit déjà conforme** sur certains points. Les verdicts ci-dessous
portent sur la **règle**, pas sur l'implémentation.

### Sources interrogées

| Source | Statut | Remarque |
|---|:---:|---|
| **BOFiP** (documentation officielle DGFiP) | ✅ lu | Source fiscale primaire |
| **Code du travail numérique** (ministère du Travail) | ✅ lu | Source sociale primaire |
| **service-public / Entreprendre Service Public** | ✅ lu | Fiche prime carburant, vérifiée 12/06/2026 |
| **BOSS** (Bulletin officiel de la sécurité sociale) | ⚠️ partiel | Communiqués cités via sources professionnelles |
| **URSSAF** | ✅ lu à la relecture | Deux pages de barèmes lues dans un navigateur le 04/10 : « Avantages en nature » (mise à jour 01/06/2026) et « Frais professionnels » (mise à jour 01/01/2026). L'actualité « transports publics 2026 » était en erreur |
| **Légifrance** | ❌ inaccessible | HTTP 403 sur l'ensemble des URL |

> ⚠️ **Réserve importante.** Les points marqués « source primaire non lue » ci-dessous n'ont pas été
> confirmés sur le texte officiel lui-même. Ils reposent sur des sources professionnelles
> (LégiSocial, LégiFiscal, Voltaire Avocats, Swile, Paie & Social), elles-mêmes concordantes entre
> elles mais **de second rang**. Un contrôle sur Légifrance ou l'URSSAF reste souhaitable avant
> tout engagement contractuel.

---

## 0 bis. Relecture du 04/10/2026 — ce qui a été corrigé, et l'état du code

La première version de ce document n'avait pas pu lire l'URSSAF. Deux pages de barèmes ont été
lues depuis ; elles **contredisent trois affirmations** de la première version, corrigées ci-dessous.

| # | Affirmation d'origine | Ce que dit la source lue | Corrigé au |
|---|---|---|---|
| A | Plafond d'exonération des titres-restaurant : **6,50 €** « depuis le 1er janvier 2023 » (titre entre 10,83 € et 13,00 €) | **7,32 € en 2026** ; valeur du titre ouvrant droit à l'exonération maximale **entre 12,20 € et 14,64 €** — URSSAF, « Avantages en nature », taux et barèmes, mis à jour le 01/06/2026 | § 3 |
| B | Forfait mobilités durables : plafonds sociaux **300 / 600 / 900 € selon les jours de présence** ; le « plafond global de 900 € » serait **inexact** | Employeurs **privés** : **600 €** par an ; **900 €** en cumul avec la prise en charge des transports publics ; **600 € dont 300 €** pour le carburant en cumul avec la prime carburant — URSSAF, « Frais professionnels », taux et barèmes, mis à jour le 01/01/2026 (tableau intitulé « 2025 ») | § 5.1 |
| C | Part patronale **> 60 %** : « totalité réintégrée » | **Aucune source** n'appuie cette règle dans le document : la citation du BOSS (§ 3) ne porte que sur le seuil de **50 %**. Reclassé **« à trancher »** | § 3 et § 4 |

**Non vérifié à la relecture** (ni confirmé, ni infirmé) : la prime carburant à 600 € puis
1 000 € en 2026 (§ 5.2) — la page URSSAF lue affiche encore « 600 € dont 300 € pour les frais de
carburant » ; les plafonds **fiscaux** de 500 € / 600 € du forfait mobilités durables (§ 5.1).

### État du code au 04/10/2026 (migration `341`, non déployée)

La première version précisait qu'aucun code n'avait été audité. Voici ce que le moteur de
bulletin (`payroll_compute_slip`) fait aujourd'hui — suite `321`, 10 scénarios verts :

| Point | Ce que le moteur fait | Statut |
|---|---|---|
| 1 — transport 75 % | La prise en charge est versée hors brut ; ce qui dépasse 75 % du coût de l'abonnement entre dans le brut. Le taux est un **paramètre daté** (`TRANSPORT_PUBLIC_EXO_PCT`) | conforme au § 2 |
| 2 — part patronale < 50 % | La **totalité** de la participation entre dans l'assiette (brut) et ressort du net : rien n'est versé en plus au salarié | conforme au § 3 |
| 3 — part patronale > 60 % ou > plafond | **Seul l'excédent** au-delà de min(60 % de la valeur, 7,32 €) entre dans l'assiette | **à trancher** (§ 4) |
| 4 — prime carburant, forfait mobilités durables | **Non codés** : plafonds annuels, qui demandent un cumul par salarié | à faire après arbitrage |
| 5 — régime fiscal | Inchangé par la `341` | à arbitrer |

La part **salariale** des titres est retenue sur le net (elle y était ajoutée avant la `341`).
Le plafond des titres est lui aussi un paramètre daté (`TITRE_RESTAURANT_EXO_MAX` = 7,32, à
compter du 01/01/2026). **La `341` ne doit pas être déployée avant la signature de l'expert.**

---

## 1. Les 5 points soumis à décision

| # | Point soumis | Verdict | Gravité |
|---|---|:---:|:---:|
| **1** | Le taux de **75 %** pour le transport | ✅ **CONFIRMÉ**, à nuancer | 🟡 Mineur |
| **2** | Part patronale **< 50 %** du titre : règle de réintégration | ❌ **RÉFUTÉ** — la règle existe | 🔴 **Bloquant** |
| **3** | « **Seul l'excédent entre dans le brut** » | ⚠️ **À TRANCHER** pour la part > 60 % (aucune source) ; faux pour la part < 50 % | 🟠 Grave |
| **4** | Plafonds annuels prime carburant et FMD | ⚠️ **À CORRIGER** — plafond social et plafond fiscal distincts | 🔴 **Bloquant** |
| **5** | Régime fiscal de ces postes « inchangé » | ⚠️ **À NUANCER** | 🟠 Grave |

### Cotation

| Niveau | Sens |
|---|---|
| 🔴 **Bloquant** | Résultat faux sur un cas de figure réel — risque de redressement URSSAF et de reprise de paie |
| 🟠 **Grave** | Résultat faux sur un cas d'espèce — à documenter et arbitrer |
| 🟡 **Mineur** | Correct mais incomplet ou fragile face aux évolutions du droit |

---

## 2. Point 1 — Le taux de 75 % pour le transport ✅ CONFIRMÉ

Le taux de 75 % **existe** et la règle exacte est la suivante :

| Tranche de l'abonnement | Régime |
|---|---|
| 0 → 50 % | **Obligation légale** de l'employeur (art. L3261-2 CT) — exonérée |
| 50 → 75 % | **Facultatif** — exonéré de cotisations **et** d'impôt |
| **> 75 %** | **Soumis à cotisations**, et imposable selon le droit commun des rémunérations |

**Base légale :** art. 19° ter de l'article 81 du CGI.
**Prorogation 2026 confirmée :** l'art. 68 de la loi n° 2026-103 du 19 février 2026 (LF 2026)
proroge d'un an, soit **jusqu'au 31 décembre 2026** (actu BOFiP du 07/04/2026,
BOI-RSA-CHAMP-20-30-10-20).

### Précisions à retenir

- **75 % est un plafond d'exonération, pas un taux obligatoire.** Le passage de 50 % à 75 % doit
  être décidé **unilatéralement par l'employeur ou par accord collectif**. C'est un **paramètre de
  paramétrage**, pas une constante du moteur.
- **Obligation de déclaration :** l'exonération doit figurer dans la **rubrique « frais
  professionnels » de la DSN** et **ne doit pas** être comprise dans les cases 1AJ à 1DJ de la
  déclaration 2042 (BOFiP § 440).
- **Point de vigilance juridique :** la LF 2026 a été adoptée sous la procédure de l'article 49.3
  de la Constitution et **attend une décision du Conseil constitutionnel** susceptible de modifier
  ou censurer des dispositions. À documenter au dossier.

---

## 3. Point 2 — Part patronale < 50 % : la règle de réintégration existe ❌ RÉFUTÉ

> **Point le plus important du lot.** La prémisse « je n'ai pas trouvé la règle de réintégration
> à la source » est **infirmée** : la règle existe, elle est explicite, et elle a été publiée
> précisément parce que la situation avait été ambiguë.

Le **BOSS a traité ce cas le 16 mars 2023** :

> « *en cas de non-respect du seuil de 50 % de la valeur du titre-restaurant, la **totalité** de
> la participation patronale est réintégrée dans l'assiette des contributions et cotisations* »
> — BOSS, mises à jour de mars 2023, § Avantages en nature / titres-restaurant

Confirmé par trois sources professionnelles concordantes (LégiFiscal, Voltaire Avocats, Swile
relatant la position URSSAF).

### 🔴 Nuance technique capitale pour le codage

Il s'agit d'une **réintégration dans l'assiette** de calcul des cotisations et contributions —
**pas** d'un versement supplémentaire au salarié.

L'employeur **n'a pas** à majorer le salaire effectivement versé ; il doit **ajouter** le montant à
l'assiette de liquidation. Confondre les deux est une erreur classique de moteur, et une source
fréquente de surdéclaration.

### Tableau complet des cas — titres-restaurant

| Situation | Traitement **social** | Traitement **fiscal** | Source |
|---|---|---|---|
| Part patronale entre 50 % et 60 %, **≤ 7,32 €** | Exonérée | Non imposable | URSSAF, barème 2026 |
| Entre 50 % et 60 %, **> 7,32 €** | Seule la fraction **excédant 7,32 €** est réintégrée | Fraction excédante imposable | URSSAF (limite maximale) |
| **Part < 50 %** | **TOTALITÉ** réintégrée dans l'assiette | **TOTALITÉ** = avantage en argent imposable | BOSS, 16/03/2023 (second rang) |
| **Part > 60 %** | **À TRANCHER** — excédent seul, ou totalité | **À TRANCHER** | **aucune source lue** |

**Plafond d'exonération : 7,32 € par titre en 2026.** La valeur du titre ouvrant droit à
l'exonération maximale est comprise entre :

- **12,20 €** → part patronale de 60 %
- **14,64 €** → part patronale de 50 %

Source : URSSAF, « Avantages en nature », taux et barèmes, mis à jour le 01/06/2026 —
https://www.urssaf.fr/accueil/outils-documentation/taux-baremes/avantages-en-nature.html

> *Correction de relecture (A) : la première version donnait 6,50 € et la fourchette
> 10,83 € – 13,00 €, valeurs de 2023. Correction (C) : elle donnait « totalité » pour la part
> supérieure à 60 %, sans source.*

---

## 4. Point 3 — « Seul l'excédent entre dans le brut » ⚠️ À TRANCHER pour la part > 60 %

La règle est **correcte** pour le **forfait mobilités durables**, la **prime carburant**, la prise
en charge du **transport** au-delà de 75 %, et pour un titre-restaurant dont la part patronale
dépasse le **plafond par titre** (7,32 €) : seule la fraction excédentaire est soumise.

Elle est **fausse** pour les titres-restaurant quand la part patronale est **inférieure à 50 %** :
c'est alors la **totalité** de la participation qui est réintégrée (BOSS, 16/03/2023 — § 3).

Pour une part patronale **supérieure à 60 %**, la première version de ce document affirmait aussi
« la totalité ». **Aucune source ne l'appuie ici** : la citation du BOSS ne vise que le seuil de
50 %. Le point est donc **ouvert** :

| Hypothèse | Effet sur un titre de 14 € pris en charge à 9 € (64 %) |
|---|---|
| **Excédent seul** (ce que fait la `341`) | 9,00 − min(7,32 ; 8,40) = **1,68 €** réintégré par titre |
| **Totalité** | **9,00 €** réintégrés par titre |

> **Conséquence pour le code :** la fonction de calcul des titres-restaurant doit rester distincte
> de celle des frais de transport — c'est le cas dans la `341`.

---

## 5. Point 4 — Plafonds annuels prime carburant et FMD ⚠️ À CORRIGER

### 5.1 Forfait mobilités durables — plafond social et plafond fiscal

**Plafonds d'exonération de cotisations et contributions sociales — employeurs privés**
(URSSAF, « Frais professionnels », taux et barèmes, mis à jour le 01/01/2026 ; le tableau est
intitulé « Montant exonéré maximum par an en 2025 ») :

| Situation | Montant exonéré maximum par an |
|---|:---:|
| Forfait mobilités durables seul | **600 €** |
| Cumul avec la prise en charge des frais de transports publics | **900 €** |
| Cumul avec la prise en charge des frais de carburant (ou d'alimentation de véhicules électriques, hybrides rechargeables ou à hydrogène) | **600 €, dont 300 €** pour le carburant |

Source : https://www.urssaf.fr/accueil/outils-documentation/taux-baremes/frais-professionnels.html

> *Correction de relecture (B) : la première version donnait « 300 / 600 / 900 € selon 1, 2 ou
> 3+ jours de présence par semaine » et qualifiait d'inexact le plafond de 900 € en cumul. La page
> URSSAF dit le contraire pour les employeurs privés : aucune échelle par jours de présence, et
> les 900 € SONT le plafond de cumul avec les transports publics. La page porte un second onglet
> « Employeurs publics », qui n'a pas été lu.*

**Plafond d'exonération d'impôt sur le revenu** — *non relu, repris de la première version* :

> « *Le b du 19° ter de l'article 81 du CGI exonère d'impôt sur le revenu ce forfait mobilités
> durables dans la limite de **500 €** par an* »

> « *L'article 128 de la loi n° 2021-1104 du 22 août 2021 (loi Climat et résilience) a porté ce
> seuil de 500 à **600 €** en cas de cumul du forfait mobilités durables avec la prise en charge
> d'un abonnement aux transports en commun. Ce nouveau plafond s'applique à compter de
> l'imposition des revenus de l'année 2021.* »
> — BOI-RSA-CHAMP-20-30-10-20, § 391 et suivants

⚠️ Ces deux montants fiscaux diffèrent des plafonds sociaux ci-dessus (600 € / 900 €). **L'écart
est à faire confirmer par l'expert** : s'il est réel, le moteur doit porter deux plafonds pour le
forfait — un social, un fiscal.

### 5.2 Prime carburant — situation instable en 2026

| Période | Plafond social exonéré |
|---|:---:|
| Jusqu'à 2025 | 300 €/an/salarié |
| Juin 2026 (décret publié) | **600 €** |
| Primes versées **jusqu'au 31/12/2026** | **1 000 €** (mesure annoncée) |

Sources concordantes : Code du travail numérique (23/09/2026), BOSS (communiqué du 6 août 2026),
URSSAF (19 août 2026), communiqué du Gouvernement du 22 septembre 2026.

> *Relecture : ces montants n'ont pas pu être confirmés. La page URSSAF « Frais professionnels »
> lue le 04/10/2026 affiche encore « 600 € dont 300 € pour les frais de carburant ».*

#### 🔴 Réserves à sécuriser avec l'expert-comptable

1. **Les textes réglementaires définitifs ne sont pas encore publiés.** Le Code du travail numérique
   indique que les employeurs **peuvent anticiper** ces modifications dans leurs déclarations 2026,
   sur la base des positions du BOSS et de l'URSSAF, sans attendre la publication.
2. **Périmètre restreint :** le relèvement à 1 000 € vise **expressément les frais de carburant**.
   Son extension aux véhicules **électriques, hybrides rechargeables et hydrogène n'est pas
   confirmée**.
3. **Conditions d'attribution temporairement assouplies** : plus de contrainte de lieu de
   résidence, ni d'existence d'un transport collectif.
4. **Cumul avec l'abonnement transports en commun autorisé jusqu'au 31/12/2026** — alors que le
   droit commun l'interdit (art. L3261-3 CT : « *Le bénéfice de cette prise en charge ne peut être
   cumulé avec celle prévue à l'article L. 3261-2* »).
5. **Retour au régime normal au 1er janvier 2027.** Un paramétrage **par année civile** est
   indispensable ; un montant figé en dur dans le code sera faux à partir de janvier 2027.

---

## 6. Point 5 — « Régime fiscal inchangé » ⚠️ À NUANCER

La **structure juridique** est bien inchangée :

- art. 19° ter CGI ;
- option pour les bénéfices en kind / forfait 30 % (véhicule) ou 10 % (deux-roues) ;
- articulation avec le régime des frais réels.

**Mais deux éléments ont bougé en 2026**, donc « inchangé » n'est pas exact :

1. Le **plafond de la prime carburant** : 300 € → 600 € → 1 000 €, temporairement jusqu'au
   31/12/2026.
2. Il faut **distinguer**, sur le FMD, le plafond **social** du plafond **fiscal** (cf. § 5.1).

> **Pour mémoire :** la prise en charge obligatoire des 50 % et le forfait mobilités durables sont
> **deux dispositifs distincts et non substituables**. Le FMD ne remplace pas l'obligation de prise
> en charge.

---

## 7. Récapitulatif pour arbitrage

| # | Point | Verdict | Action requise |
|---|---|:---:|---|
| 1 | Transport 75 % | ✅ Confirmé | Paramétrer le taux (50 → 75 %) ; tracer la rubrique DSN « frais professionnels » |
| 2 | Titre < 50 % | ❌ Règle existe | **Fait** dans la `341` : la **totalité** entre dans l'**assiette** (pas au salaire versé) |
| 3 | « Seul l'excédent » | ⚠️ À trancher | Part > 60 % : **excédent seul ou totalité ?** — aucune source lue ; la `341` réintègre l'excédent |
| 4 | Plafonds annuels | ⚠️ À corriger | Forfait : plafond social **600 € / 900 €** (URSSAF), plafond fiscal à confirmer ; prime carburant **paramétrée par année** — non codés |
| 5 | Régime fiscal | ⚠️ À nuancer | Documenter les 2 évolutions 2026 |

### Séquence de correction recommandée

L'ordre compte : le **point 3 conditionne le point 2**. Corriger l'un sans l'autre produit un
résultat contradictoire.

1. Isoler la fonction de calcul **titres-restaurant** de celle des **frais de transport** (point 3)
2. Appliquer la règle de **réintégration totale** pour une part patronale **inférieure à 50 %** (point 2) — fait ; trancher le cas **supérieur à 60 %** (point 3)
3. Scinder les **plafonds social et fiscal** du FMD (point 4)
4. Paramétrer les **plafonds prime carburant par année civile** jusqu'au 31/12/2026 (point 4)
5. Documenter les **arbitrages** restants au dossier de l'expert-comptable

---

## 8. Sources consultées

**Sources primaires lues :**

- **BOFiP** — BOI-RSA-CHAMP-20-30-10-20, « Avantage résultant de la prise en charge des frais de
  trajet », version en vigueur au 07/04/2026
- **Code du travail numérique** (ministère du Travail) — art. L3261-3 ; actualité prime carburant du
  23/09/2026
- **service-public / Entreprendre Service Public** — fiche « Prise en charge des frais de carburant
  et d'alimentation des véhicules (prime carburant) », vérifiée le 12/06/2026

**Textes cités :**

- **LF 2026 art. 68** — loi n° 2026-103 du 19 février 2026 (prorogation du mécanisme 75 %)
- **Art. 19° ter de l'article 81 du CGI** — exonérations de frais de trajet
- **Loi Climat et résilience art. 128** — loi n° 2021-1104 du 22 août 2021 (plafond fiscal FMD
  500 → 600 €)
- **Art. L3261-2, L3261-3, L3261-4 du Code du travail** — prise en charge des transports
- **BOSS** — mise à jour du 16/03/2023 (titres-restaurant) ; communiqués des 6/08/2026 et 19/08/2026
  (prime carburant)

- **URSSAF** *(relecture du 04/10/2026)* — « Avantages en nature », taux et barèmes, mis à jour le
  01/06/2026 ; « Frais professionnels », taux et barèmes, mis à jour le 01/01/2026

**Sources professionnelles de second rang** (BOSS inaccessible directement) :
LégiSocial, LégiFiscal, Voltaire Avocats, Swile, Paie & Social, Meyer & Associés, ExpertComptable.fr.

---

## 9. Limites du présent document

- ⚠️ **Le code a été confronté à ce document à la relecture** (§ 0 bis) ; les verdicts des § 2 à
  § 6 portent sur les règles.
- ❌ **Légifrance et le BOSS non accessibles** ; l'URSSAF n'a été lue que sur deux pages de barèmes.
  La règle des 50 % (BOSS, 16/03/2023) repose sur des sources de second rang, concordantes.
- 🔴 **Le régime de la prime carburant est instable en 2026** : textes réglementaires non publiés,
  mesures annoncées par le Gouvernement mais non encore codifiées. Susceptible d'évoluer d'ici le
  31/12/2026.
- 🔴 **La LF 2026 est sous la procédure du 49.3** et attend une décision du Conseil constitutionnel.
- ⚠️ **Les plafonds sont exprimés par année civile** : tout paramétrage figé en dur sera faux au
  1er janvier 2027.

> **Recommandation :** faire trancher les points 2, 3 et 4 par l'expert-comptable **avant toute
> implémentation**, puis compléter ce document d'une colonne « décision retenue » et d'une
> colonne « Arbitrage n° / pièce justificative ».

---