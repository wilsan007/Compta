# Décision `D-4` — `generate-pdf` : la rebrancher derrière un Gotenberg durci, ou la supprimer

> **30/09/2026.** Note d'**aide à la décision**. La décision appartient au
> **produit** : elle n'est **pas** prise ici. Tout ce qui suit est **constaté**
> dans le dépôt (HEAD `b1c05ca`), avec la commande ou le fichier qui le porte.
> **Ce qu'elle ne change pas, d'abord :** le défaut (`AUD-H03`, SSRF prouvée) est
> **déjà contenu**. Ce n'est pas un correctif de sécurité à choisir, c'est une
> **capacité produit** à ouvrir ou à fermer.

---

## 1. Le défaut, tel qu'il a été constaté

`generate-pdf` acceptait du **HTML fourni par le client** et le passait à Chromium
(Gotenberg). Chromium va chercher **tout** ce que contient la page : une
`<iframe src="http://169.254.…">` faisait du serveur un **proxy vers le réseau
interne** (SSRF prouvée, `AUD-H03`), et les valeurs interpolées dans le gabarit
n'étaient **pas échappées**.

## 2. Ce qui est vrai aujourd'hui (W6, 26/09)

| Fait | Où le constater |
|---|---|
| Le HTML client est **refusé** : `400` + `code: "CLIENT_HTML_REFUSED"` | `app/supabase/functions/generate-pdf/index.ts:45-56` |
| Le HTML est **toujours construit par le serveur**, depuis la pièce enregistrée, sur une **liste fermée** de tables (facture, devis, bulletin, avoir, facture d'achat) — la clé de service ne lit jamais une table choisie par le client | `index.ts:58-65`, `:87-88` |
| Jeton obligatoire (`401`), appartenance à la société vérifiée (`403`) | `index.ts:14-34`, `:85` |
| Le PDF est rangé **par société** (`pdfs/<tenant>/…`) et rendu par **URL signée d'une heure** — jamais d'URL publique | `index.ts:118-134` |
| La fonction est **retirée du déploiement** | `app/supabase/deploy-all-functions.sh:64-73` (`FUNCTIONS_NON_DEPLOYEES`) |
| Elle est **couverte par les tests** : `401` sans jeton (contrat d'entrée des 20 fonctions) **et** refus nommé du HTML client | `app/supabase/functions/__tests__/entry_contract_test.ts:28` et `generate_pdf_ssrf_test.ts` (2 tests) |
| **Aucun appelant** dans `src/` — c'est un choix écrit : un export mort ferait monter le plafond de code mort, et brancher un écran sur une fonction **non déployée** serait « un placebo de plus » | `app/src/lib/queries/verifications.ts:137-149` |

## 3. Ce que la lecture du code a montré **en plus** (et qui pèse sur le choix)

Trois choses mesurées dans le corps de la fonction : si l'option A est choisie,
elle ne se résume pas à « rebrancher ».

1. **Le bucket de destination n'existe pas dans le dépôt.** La fonction écrit dans
   `storage.from("documents")` (`index.ts:122-128`) ; les buckets déclarés sont
   `project-docs`, `accounting-docs`, `hr-docs`, `commercial-docs`,
   `general-docs` (`app/sql/68_module_documents_storage_rls.sql:177-217`), plus
   `employee-documents` et `tax-grid-sources` (front et cloud). L'`upload` échoue,
   `uploadErr` est posé, `publicUrl` reste `null`… et la fonction rend quand même
   **`success: true` avec `url: null`** (`index.ts:130-143`).
   **Rebrancher en l'état produirait un « PDF réussi » sans URL.**
2. **Le repli Gotenberg ressemble à un succès.** Si Gotenberg ne répond pas, la
   fonction renvoie **HTTP 200**, `success: false`, `fallback: true` **et le HTML
   entier dans le corps** (`index.ts:104-114`). Un appelant qui lit `res.ok`
   tiendrait un HTML pour un PDF.
3. **Le défaut par défaut ne peut pas marcher.** `GOTENBERG_URL` retombe sur
   `http://localhost:3000` (`index.ts:91`) — le localhost du runtime Edge, où
   aucun Gotenberg n'écoute : **sans le secret, l'option A est inerte**.

## 4. Option A — rebrancher derrière un Gotenberg durci

Ce qu'elle **exige**, dans l'ordre :

| # | Exigence | Pourquoi |
|---|---|---|
| A1 | Un **Gotenberg déployé**, joignable **seulement** depuis le runtime Edge, et **sans** accès aux plages privées ni aux points de métadonnées | la SSRF n'est pas dans le code de la fonction, elle est dans **ce que Chromium peut atteindre** : sans cette politique réseau, le correctif de W6 (refus du HTML client) protège moins qu'il n'y paraît |
| A2 | Le secret `GOTENBERG_URL` posé sur le runtime Edge | sans lui, `localhost:3000` (fait 3) |
| A3 | Une **décision de rangement** : créer le bucket `documents`, ou écrire dans un bucket existant (`accounting-docs`, `hr-docs`…) **en vérifiant ses politiques** | un bulletin de paie et une facture n'ont pas le même public : ce n'est pas un détail d'implémentation (fait 1) |
| A4 | Un **verdict honnête** : jamais `success: true` sans URL ; et le repli (`fallback: true`) tranché — échec nommé, ou repli **côté client** assumé | fait 2 |
| A5 | **Un appelant**, dans le même commit, et le **plafond de code mort** traité dans ce commit | la règle du dépôt : le travail non commité n'existe pas |

**Charge, PROPOSÉE** : ≈ 0,5 j de code (A3, A4, A5) + **1 j** de déploiement et de
politique réseau (A1, A2), à valider — c'est un ordre de grandeur, pas une mesure.

**Ce que l'option rend** : un PDF **serveur** (donc archivé, adressable, opposable)
pour cinq types de pièces, rangé par société et rendu par URL signée.

## 5. Option B — supprimer

| # | Ce que la suppression touche |
|---|---|
| B1 | `app/supabase/functions/generate-pdf/` (196 lignes) |
| B2 | Ses deux tests (`generate_pdf_ssrf_test.ts` et son entrée au contrat) |
| B3 | `FUNCTIONS_NON_DEPLOYEES` dans `deploy-all-functions.sh` — la liste redevient vide |
| B4 | Le bloc de commentaire « PDF côté serveur (Gotenberg) — décision D-4 » dans `verifications.ts` |

**Charge, PROPOSÉE** : ≈ 0,1 j, mécanique et vérifiable (`node
scripts/check-test-suites.mjs` et le plafond de code mort ne peuvent que
**baisser**).

**Ce que l'option coûte** : la **capacité** « PDF serveur ». Aujourd'hui
**personne ne l'appelle** — le produit ne perd donc rien qui soit **absent** ; il
perd la possibilité de l'ouvrir sans réécrire la fonction (l'option A
redeviendrait un développement, plus un rebranchement).

## 6. Ce que la décision ne change pas

* **La sûreté actuelle** : le défaut appliqué (HTML client refusé, valeurs
  échappées, non déployée) tient **dans les deux cas** — c'est écrit ainsi dans
  `RESTE-A-FAIRE` §3.1 depuis le 26/09.
* **Les autres décisions** (`D-5`, `D-7`, `D-10`, `D-11`, `D-13`) et **P0-08** :
  ni l'une ni l'autre ne les débloque. `D-4` est la **seule** dont le défaut est
  **déjà appliqué** : la trancher ne corrige rien de plus, elle **range**.
* **Les intégrations** (tableau B de `RESTE-OUVERT`) : l'option A ajoute
  **Gotenberg** à la recette des services ; l'option B l'en retire.

## 7. Les deux chemins, en une ligne chacun

* **A — ouvrir la capacité** : « nous voulons des PDF **serveur**, archivés et
  adressables, pour les factures et les bulletins » → 4 exigences, ≈ 1,5 j, et
  Gotenberg entre dans la recette des intégrations.
* **B — fermer proprement** : « le front n'en a pas besoin » → ≈ 0,1 j, et la
  surface SSRF **disparaît** au lieu d'être contenue.

**Lecture de cette note, assumée et discutable : B aujourd'hui ; A si et quand le
besoin devient daté** — parce qu'il n'y a **aucun appelant** (mesuré), que le
rangement écrit par la fonction produirait aujourd'hui `success: true` **avec
`url: null`** (fait 1), et que A dépend d'une **politique réseau qui n'existe pas
encore** (A1), là où la suppression est immédiate et vérifiable. **Si le produit
choisit A, ce n'est pas en `--no-verify-jwt`**, et la politique réseau de A1 doit
être **écrite avant** le déploiement, pas après.

## 8. Après la décision

1. Cocher la ligne dans `RESTE-A-FAIRE` §3.1 (et §3.2 si A) **avec sa date** ;
2. appliquer l'option **dans un commit unique**, avec sa vérification
   (`node scripts/check-test-suites.mjs`, `npm run knip:ceiling`,
   `npm run edge:test`) ;
3. mettre à jour la ligne `D-4` de `RESTE-OUVERT` §2.A et le tableau B de ce
   même document si l'entrée « Gotenberg » change.

**Pour re-mesurer ce que cette note affirme** :

```bash
grep -rn 'generate-pdf' app/src app/supabase/deploy-all-functions.sh   # aucun appelant, 1 non déployée
grep -n 'CLIENT_HTML_REFUSED\|from("documents")\|GOTENBERG_URL' app/supabase/functions/generate-pdf/index.ts
grep -rln 'INSERT INTO storage.buckets' app/sql/                       # 68_module_documents_storage_rls.sql
npx -y deno test app/supabase/functions/__tests__/                     # 32 tests, dont generate-pdf
```
