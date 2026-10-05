# Partie F — fonctions manquantes, plateforme

> Fichier de suivi **exclusif** de la partie F (règle **R4** du
> [plan en 6 parties](../PLAN-6-PARTIES-PARALLELES-2026-10-05.md)).
> `SUIVI-CHANTIERS.md` et `AGENTS.md` ne s'écrivent **que** par la session
> d'intégration.

| | |
|---|---|
| **Branche** | `plan6/f-plateforme` |
| **Worktree** | `.claude/worktrees/plan6-f-plateforme` |
| **Plage de migrations** | `700` → `749` |
| **Territoire de fichiers** | `supabase/functions/`, écrans CRM, projets, paramètres, notifications ; leurs tables coquilles |
| **Charge** | **recomptée le 05/10 (F.1)** : ≈ 17 j pour les chantiers décidés « faire » (hors F.2, livré) ; ≈ 45-55 j au total avec F.3 → F.8 |
| **Départ possible** | **tout de suite, par F.1 et F.2** — toutes deux **faites** |

## Les tâches

| # | Tâche | Repris de | Charge | État |
|---|---|---|---|---|
| F.1 | **Recompter** les ❓ de son périmètre et **estimer** les ⬜ | BNQ-04, TRE-01, CRM-03, PRJ-01/06/07/09, BI-03, SEC-03, PRF-03/04, UX-05, ADM-01/03/05, IMP-03, NOT-03, ONB-02, PAY-01/11/12 | à chiffrer | ✅ **recompté le 05/10** — verdicts ci-dessous |
| F.2 | Authentification forte : suite SQL (émission, usage, révocation, rejeu d'une clé ; TOTP), test Edge « clé révoquée → 401 » | ORPH-01, SEC-02 | 1 j | ✅ **livré le 05/10** — migration `700`, suite `700` (T01→T13), test Edge « révoquée → 401 » |
| F.3 | `generate-pdf`, voie A : convertisseur isolé, `GOTENBERG_URL`, un appelant | 1.13, D-4 | 1 j (code) + décision D-4 | ⬜ |
| F.4 | Groupe : structure, opérations intra-groupe, consolidation | GRP-01 → 03 | ≈ 5 j | ⬜ |
| F.5 | CRM (séquences, scoring) ; projets (capacité par ressource, champs personnalisés, automatisations) | CRM-01/02, PRJ-02/04/08 | ≈ 5 j | ⬜ |
| F.6 | Notifications et alertes ; rattachement universel de documents ; générateur d'états ; modèles de documents ; connecteurs métier | NOT-01/02, GED-01, BI-01, ADM-04, API-03 | ≈ 8 j | ⬜ |
| F.7 | RH hors paie : conventions collectives, recrutement ; mobile hors ligne | PAY-08, RH-03, PTL-03 | ≈ 4 j | ⬜ |
| F.8 | Tables coquilles de son périmètre (les 25 autres), **brancher ou supprimer** | ORPH-02 | ≈ 5 j | ⬜ |

## F.1 — le recomptage (fait le 05/10/2026)

Les 20 chantiers ❓ du périmètre, chacun avec un verdict — **faire**,
**reporter**, **écarter** ou **transférer** (R3 : ce qui n'est pas à nous est
consigné ici, l'intégration le transmet). Constats de départ :
[SUIVI-CHANTIERS.md](../SUIVI-CHANTIERS.md) et le plan 9,5.

| Chantier | Verdict | Charge | Pourquoi |
|---|---|---|---|
| **PAY-01** deux corrections immédiates (bloquant, « 2 h ») | **transférer à B** | (B) | moteur de bulletin — territoire de B (R3 : consigné) |
| **PAY-11** solde de tout compte | **transférer à B** | 1,5 j (B) | idem — « la moitié existe déjà » dit le plan 9,5 |
| **PAY-12** architecture cible du moteur | **transférer à B** | décision | décision d'architecture paie, pas une charge F |
| **BNQ-04** SEPA complet | **reporter** | ≈ 3 j | après B.2 (règles d'état trésorerie) : le moteur décide d'abord |
| **TRE-01** prévisionnel enrichi | **reporter** | ≈ 2 j | `cash_flow_forecast` vient d'être réécrit (470) ; laisser B.2 poser ses règles |
| **CRM-03** suivi d'e-mails / IMAP | **écarter (v1)** | — | périmètre marketing ; Resend 👤 en attente ; à revoir après NOT-01/02 |
| **PRJ-01** dépendances, chemin critique | **faire** | 3 j | la base existe (7 fichiers SQL), aucun chemin critique, un seul lecteur |
| **PRJ-06** modèles de projet et jalons | **faire** | 2 j | `project_milestones` est une coquille ; chaque projet se construit à vide |
| **PRJ-07** référence de planning | **reporter** | 1,5 j | dépend de PRJ-01 (la baseline ne se compare qu'à un planning tenu) |
| **PRJ-09** portefeuille, permissions | **faire** | 2 j | `project_members` existe, jamais opposable |
| **BI-03** performance des tableaux de bord | **faire, mesuré d'abord** | 2 j | 137 `.reduce()` dans les pages : mesure avant correctif |
| **SEC-03** journal d'audit applicatif | **faire, en LISANT L23** | 2 j | `415` a posé le journal d'événements unifié : l'étendre, ne pas le réécrire |
| **PRF-03** rendu React (85 `key={index}`) | **transférer à D** | (D) | écrans — territoire de D (R3 : consigné) |
| **PRF-04** équilibre en `FOR EACH STATEMENT` | **reporter — à arbitrer** | 1 j | déclencheur au cœur du socle comptable : ni B ni F ne doivent le réécrire seuls (R7) ; décision d'intégration |
| **UX-05** saisie comptable au clavier | **transférer à D** | (D) | écrans (R3 : consigné) |
| **ADM-01** assistant de paramétrage | **reporter** | 1,5 j | après ONB-02 (le guide suit l'invitation) |
| **ADM-03** paramétrage comptable et fiscal | **transférer à C** | (C) | c'est le lot K : `resolve_account`, grilles fiscales (R3 : consigné) |
| **ADM-05** journal d'audit exposé | **faire (avec SEC-03)** | +0,5 j | même chantier : `/system/audit-log` lit ce que SEC-03 trace |
| **IMP-03** reprise tiers, articles, stocks, salariés | **faire** | 3 j | l'import générique existe (IMP-02), la reprise structurée non |
| **NOT-03** canaux de diffusion | **reporter** | 1,5 j | Resend 👤 en attente ; « trois canaux bien faits » dit le plan |
| **ONB-02** invitations et gestion d'équipe | **faire** | 2 j | `/select-tenant` existe ; le lien d'invitation à durée limitée non |

**Bilan du recomptage** : 8 chantiers « faire » (PRJ-01, PRJ-06, PRJ-09, BI-03,
SEC-03 + ADM-05, IMP-03, ONB-02) ≈ **16,5 j** ; 5 reportés ; 1 écarté ;
6 transférés (PAY-01/11/12 → B, PRF-03 + UX-05 → D, ADM-03 → C — à transmettre
par l'intégration, R3) ; 1 à arbitrer (PRF-04, décision d'intégration).
Avec F.2 livré (1 j) et F.3 → F.8 estimés à ≈ 28 j, **la partie F ≈ 45-55 j**.
Sans F.1, il n'y avait pas de dates — seulement une liste.

## F.2 — livré le 05/10 (ORPH-01 / SEC-02)

« Une clé qu'on ne peut pas révoquer n'est pas une authentification forte. »
La preuve demandée était un test Edge **« clé révoquée → 401 »** — pas
« la clé existe », pas « la clé expire ». Livré :

- **`sql/700_auth_forte_api_keys_totp.sql`** (numéro pris par l'outil, R2) :
  - `authenticate_api_key(p_raw_key)` — **la** vérité du cycle de vie d'une
    clé : refus **nommés** (`not_found`, `revoked`, `expired`), hash SHA-256
    côté base (SEC-01), `last_used_at` posé à l'usage. Réservée à
    `service_role`. **L'ancien chemin de public-api ne lisait QUE
    `active = true` : une clé expirée ouvrait l'API indéfiniment** ;
  - TOTP **réel** (RFC 6238, HMAC-SHA1) : `_totp_b32`, `_totp_code`,
    `verify_totp` réécrit — l'ancienne acceptait **tout** code à 6 chiffres
    dès qu'un enrôlement existait, et **rendait le secret** à l'appelant ;
  - `revoke_api_key` honnête : un identifiant d'une autre société est un
    refus nommé (`API_KEY_INTROUVABLE`), une clé déjà révoquée le dit —
    plus jamais un `success: true` muet.
- **`sql/700_auth_forte_api_keys_totp_tests.sql`** (T01 → T13) : émission,
  usage, mauvaise clé, révocation, **rejeu**, **expiration**, isolation,
  révocation croisée, **trois vecteurs du RFC 6238** (ce n'est pas la
  fonction qui se prouve : c'est le standard), code juste accepté (sans le
  secret), code faux refusé, cycle enable → verify → disable. Les scénarios
  rouges-avant sont nommés dans l'en-tête de la suite.
- **`public-api`** ne garde plus aucune copie de la logique : il appelle la
  RPC et **obéit** au verdict.
- **Test Edge `api_key_auth_test.ts`** : **révoquée → 401** (le refus nomme
  sa raison), expirée → 401, inconnue → 401, contre-épreuve : une clé valide
  ouvre la garde (200 sur `/health`). Le harnais a gagné un crochet
  `__stubRpc` (rétrocompatible : sans lui, tous les tests W6 sont inchangés).
- **Câblage** : la suite est dans `ci.yml` sous le marqueur `plan6:f` (R5).

Pas de changement de schéma (aucune colonne, aucune table) :
`npm run db:types` n'a rien à régénérer (R6 : rien à signaler à
l'intégration sur ce point).

## Attend de vous

- La clé **`sb_secret_…` à tourner**.
- Le **DPA** du prestataire IA.
- Les **comptes des 9 intégrations** : Chorus Pro, Yousign, GoCardless, Resend,
  EFI, SIRENE/VIES, Stripe, Gotenberg, Sentry.

## F.8 — brancher ou supprimer

Comme E.5 : pour chacune des 25 tables coquilles, deux issues seulement. Une
coquille non branchée est un leurre — elle compte dans les mesures sans
apporter d'écran.

## L'arbitrage R7 qui concerne F

En cas de doute sur une fonction d'écriture comptable : **C passe après** les
autres. F n'est pas concernée, mais elle peut l'être indirectement par F.4
(operations intra-groupe) et F.5 (projets).

## Journal

| Date | Chantier | Verdict (faire / reporter / écarter) | Charge estimée | Commit |
|---|---|---|---|---|
| 05/10/2026 | F.1 recomptage des 20 ❓ du périmètre | 8 « faire » ≈ 16,5 j ; 5 reportés ; 1 écarté ; 6 transférés (B/D/C, R3) ; 1 à arbitrer (PRF-04) | — | `plan6/f-plateforme` |
| 05/10/2026 | F.2 authentification forte (ORPH-01/SEC-02) | **fait** : migration `700` + suite T01→T13 + test Edge « clé révoquée → 401 » + câblage CI sous le marqueur `plan6:f` | 1 j | `plan6/f-plateforme` |