---
name: qa
description: Essaim QA parallèle — visite toutes les routes de l'application dans toutes les fenêtres et listes déroulantes, aux quatre gabarits d'écran, sur une société créée du début par l'inscription et l'assistant d'onboarding. Un dispatcheur répartit les routes entre N ouvriers navigateur, un validateur juge les mesures et écrit le rapport. À utiliser pour « tester tous les modules », « vérifier que tout est là », « recette d'écran », « responsive », « QA de bout en bout ».
---

# /qa — l'essaim QA parallèle

## Ce que ça fait

| Étape | Superagent | Ce qu'il produit |
|---|---|---|
| 1 | `inventory.mjs` | la liste **réelle** des routes, lue dans `src/App.tsx` (aucune liste tenue à la main) |
| 2 | `seed.mjs` | une **société créée du début** : inscription réelle (`/signup`) puis assistant réel (`/onboarding`), un compte par ouvrier |
| 3 | `dispatch.mjs` | le découpage en shards et **N ouvriers Playwright en parallèle**, avec journal par ouvrier |
| 4 | `worker.mjs` | par route et par gabarit : rendu, onglets, listes déroulantes, fenêtres, boutons, accessibilité, débordements, proportions, console, appels refusés |
| 5 | `validate.mjs` | fusion, dédoublonnage, gravité, confrontation au registre, `RAPPORT-QA-<date>.md` + `findings.json` |

## Commandes

```bash
cd app
npm run dev -- --port 5174          # terminal 1 : l'application (localhost)

npm run qa:inventory                # le plan de tournée
npm run qa:seed -- --workers=4      # société remplie : inscription + assistant + 4 comptes
npm run qa:amorce                   # …puis les données métier (par l'API du produit)
npm run qa:run -- --workers=4 --viewports=desktop,mobile
npm run qa:validate                 # rejoue le jugement seul
npm run qa:summary                  # les comptes : par règle, par module, par gabarit
```

Les deux **états** de société (écrans remplis et écrans vides), les quatre
gabarits, et le guide — une seule commande :

```bash
npm run qa:seed -- --session=session-vide.json   # seconde société, JAMAIS remplie
npm run qa:run -- --states=remplie,vide --viewports=all --workers=5
```

Utile :

```bash
npm run qa:run -- --viewports=all                    # 375 / 768 / 1280 / 1920
npm run qa:run -- --states=remplie --workers=6       # un seul état
npm run qa:run -- --modules=accounting,hr            # un périmètre
npm run qa:run -- --light                            # rendu seul (rapide)
npm run qa:validate -- --baseline                    # inscrire les défauts connus
node scripts/qa/worker.mjs --shard=0 --of=1 --viewports=desktop \
     --routes=/sales/invoices,/stock/boms            # rejouer une ligne du registre
node scripts/qa/guide.mjs --viewports=all            # le guide de bienvenue, seul
```

Le **guide de bienvenue** a son scénario (`guide.mjs`) parce que la tournée le
pose comme déjà vu (`compta-onboarded`) : sans lui, il recouvrirait les 334
écrans. `dispatch.mjs` le lance après les vagues, sous le même jeton de tournée.

## Doctrine (à respecter)

1. **Local seulement.** `QA_BASE_URL` et `QA_API_URL` doivent être locaux ; le script refuse
   autre chose sans `QA_ALLOW_REMOTE=1`. Le banc écrit : jamais la production.
2. **Un agent ne détruit rien.** Les boutons dont le libellé contient supprimer / valider /
   payer / annuler sont **inventoriés, jamais cliqués**. Les parcours irréversibles restent
   couverts par `sql/*_tests.sql` et `src/__screen__`.
3. **Un défaut hors registre fait échouer.** `.qa-baseline.json` a le même contrat que
   `sql/ci/expected_failures.sql` : entrer un défaut se fait **explicitement** (`--baseline`),
   et une entrée devenue verte doit **partir** dans le commit du correctif.
4. **Ce qui n'est pas mesuré n'est pas dit.** Chaque verdict vient d'une mesure dans la page
   (géométrie, texte, statut HTTP), pas d'une impression.

## Où sont les preuves

- `.qa-out/RAPPORT-QA-<date>.md` — le rapport, avec l'écran source à ouvrir par défaut
- `.qa-out/findings.json` — les défauts, exploitables par un script
- `.qa-out/shots/<module>/` — les captures des écrans en défaut
- `.qa-out/logs/ouvrier-<n>.log` — la trace brute de chaque ouvrier

## Limites connues

- La tournée se fait sur une société **neuve** : les listes sont vides (c'est vérifié), la
  recette avec données métier reste à faire.
- Le module `employee`, `portal` et les routes à identifiant (`:id`) ne sont pas visitables à
  l'aveugle : l'inventaire les écarte explicitement.
- Un défaut de **calcul** (montant faux, écriture comptable) ne se voit pas dans cette tournée :
  il appartient aux suites SQL et à `src/__screen__`.
