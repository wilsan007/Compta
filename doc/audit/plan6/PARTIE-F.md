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
| **Charge** | **à estimer** — c'est la tâche F.1 |
| **Départ possible** | **tout de suite, par F.1 et F.2** |

## Les tâches

| # | Tâche | Repris de | Charge | État |
|---|---|---|---|---|
| F.1 | **Recompter** les ❓ de son périmètre et **estimer** les ⬜ | BNQ-04, TRE-01, CRM-03, PRJ-01/06/07/09, BI-03, SEC-03, PRF-03/04, UX-05, ADM-01/03/05, IMP-03, NOT-03, ONB-02, PAY-01/11/12 | à chiffrer | ⬜ **premiere tâche** |
| F.2 | Authentification forte : suite SQL (émission, usage, révocation, rejeu d'une clé ; TOTP), test Edge « clé révoquée → 401 » | ORPH-01, SEC-02 | 1 j | ⬜ |
| F.3 | `generate-pdf`, voie A : convertisseur isolé, `GOTENBERG_URL`, un appelant | 1.13, D-4 | — | ⬜ |
| F.4 | Groupe : structure, opérations intra-groupe, consolidation | GRP-01 → 03 | — | ⬜ |
| F.5 | CRM (séquences, scoring) ; projets (capacité par ressource, champs personnalisés, automatisations) | CRM-01/02, PRJ-02/04/08 | — | ⬜ |
| F.6 | Notifications et alertes ; rattachement universel de documents ; générateur d'états ; modèles de documents ; connecteurs métier | NOT-01/02, GED-01, BI-01, ADM-04, API-03 | — | ⬜ |
| F.7 | RH hors paie : conventions collectives, recrutement ; mobile hors ligne | PAY-08, RH-03, PTL-03 | — | ⬜ |
| F.8 | Tables coquilles de son périmètre (les 25 autres), **brancher ou supprimer** | ORPH-02 | — | ⬜ |

## F.1 d'abord — et pourquoi c'est urgent

Comme pour E.1 : les charges des parties E **et** F ne sont pas estimées.
**32 chantiers du plan 9,5 n'ont jamais été recomptés.** Sans F.1, il n'y a pas
de dates — seulement une liste.

Pour chaque chantier ❓ ou ⬜, une **décision** : faire, reporter, écarter.
Écrire le verdict dans **ce fichier** (R3).

## F.2 — la tâche la plus courte et la plus utile

1 j, et elle ferme un risque réel : une clé d'authentification forte qu'on ne
peut pas **révoquer** n'est pas une authentification forte. La preuve attendue
est un test Edge : **« clé révoquée → 401 »**. Pas « la clé existe », pas « la
clé expire » — **révoquée → 401**.

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

## Demandes reçues (R3) — transmises par l'intégration du 05/10/2026

| # | Demande | De | Ce qu'elle débloque / corrige |
|---|---|---|---|
| 1 | **Choisir le calcul de marge projet unique** (`PROJ-02`), puis le **figer** | A1 — invariant **INV-12** | rend **INV-12** mesurable. Projets = territoire **F** (F.5) ; à traiter **avec E**, qui porte les achats, le stock et la production dont l'égalité dépend |

## Journal

| Date | Chantier | Verdict (faire / reporter / écarter) | Charge estimée | Commit |
|---|---|---|---|---|