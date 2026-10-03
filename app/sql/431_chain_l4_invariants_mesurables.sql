-- ============================================================
-- 431_chain_l4_invariants_mesurables.sql — L4, tranche 3 : le
--   dernier invariant non mesurable, et la preuve des six autres
--
-- TÂCHE 3.8 DU PLAN DE LA PARTIE 3 (02/10/2026) : « rendre MESURABLES
-- les 7 invariants "non mesurables" (ou en retirer avec raison
-- écrite) ». Point de départ mesuré le 02/10 : **13 / 20** mesurables,
-- 7 nommés sans contrôle — `INV-05, 06, 07, 08, 10, 12, 19`.
--
-- ─────────────────────────────────────────────────────────────
-- CE QUE LA MESURE A DONNÉ, ET ELLE A DONNÉ UNE RÉPONSE DIFFÉRENTE
-- DE CELLE ATTENDUE
-- ─────────────────────────────────────────────────────────────
-- On a d'abord **regardé la base** au lieu de relire la raison
-- écrite par la 413. Interrogation sur PostgreSQL 16, conteneur
-- `compta-pg16` (port 5433), base neuve :
--
--   | invariant | ce que la base porte réellement            | suite |
--   |-----------|-----------------------------------------------|-------|
--   | INV-05    | `purchase_orders` : 13 colonnes, **aucune**  | non   |
--   |           | de facturé ni de reçu ; `document_links`     | mes.  |
--   |           | ne contient AUCUN lien commande→facture      |       |
--   | INV-06    | `budgets` : 11 colonnes numériques           | non   |
--   |           | `period_1..12`, **aucun réalisé stocké**      | mes.  |
--   | INV-07    | `lettrage_groups` : aucune clé vers          | non   |
--   |           | `journal_lines` ; `bank_transactions` porte  | mes.  |
--   |           | `reconciled_entry_id`, qui ne relie pas au   |       |
--   |           | groupe de lettrage                           |       |
--   | INV-08    | `bank_transactions` : 33 colonnes, **aucun**  | non   |
--   |           | solde de relevé ; aucune table de relevé     | mes.  |
--   | INV-10    | `dsn_declarations` : 11 colonnes, **zéro     | non   |
--   |           | numérique** — le brut n'existe qu'en fichier  | mes.  |
--   | INV-12    | `projects.actual_cost` existe (3 projets),   | non   |
--   |           | les DEUX recalculs concurrents subsistent    | mes.  |
--   | INV-19    | `amont_type` texte + `amont_id` uuid ; les   | ✅    |
--   |           | types en usage sont `pay_runs` et             | MES.  |
--   |           | `journal_entries`, et **les deux tables       |       |
--   |           | existent** — le résolvable est là            |       |
--
-- LA LECTURE HONNÊTE DE CE TABLEAU. Six des sept n'ont pas une
-- *méthode* de mesure manquante : ils ont une **donnée absente**. On
-- pourrait les rendre « mesurables » en écrivant une requête qui
-- compare un montant à un agrégat **inventé** — le résultat serait un
-- chiffre, il serait faux, et l'indice afficherait une santé que
-- personne n'a. C'est exactement le mensonge que la 413 refuse
-- (« Mesurer l'écart d'un agrégat inventé produirait un chiffre
-- faux — l'invariant est nommé, pas mesuré. ») : cette migration
-- **conserve ce refus** et le rend opposable.
--
-- Ce qu'elle apporte à la place : ces six raisons, qui n'étaient que
-- des affirmations, deviennent des **preuves mesurées** (nombre de
-- colonnes, nom de la colonne manquante). C'est ce que le plan
-- demande en repli — « la raison de chaque exclusion » — et une
-- raison vérifiable vaut mieux qu'un invariant vide.
--
-- LE SEPTIÈME, LUI, EST MESURABLE. INV-19 disait : « Devient
-- mesurable dès qu'un registre des types de documents est écrit
-- (**c'est la matière de la vue chaîne, lot L6**) ». La mesure
-- confirme que les types sont énumérables et que les tables
-- correspondantes existent. Cette migration écrit donc **ce
-- registre** — et le compte est réglé : L6 n'aura plus à l'inventer.
-- ─────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────
-- HARMONISATION DU 03/10/2026 — ce que ce fichier NE fait PLUS
-- ─────────────────────────────────────────────────────────────
-- Cette migration (branche `l4-invariants`) et la partie 5 (`450` → `455`)
-- ont résolu INV-19 chacune de son côté, le même jour, avec DEUX tables
-- `chain_document_types` aux colonnes différentes (ici : tenant_id, type,
-- cote ; en 450 : code, ligne_table, libelle_fr). Sur base neuve, la 450
-- échouait : « column "code" of relation "chain_document_types" does not
-- exist ». C'est l'alerte ALR-05 du suivi.
--
-- UN SEUL registre est gardé : celui de la 450. Il est livré, il porte les
-- deux clés étrangères de `document_links` (451), la garde de suppression
-- (453) et la mesure d'INV-19 (455), et l'écran le lit. Sont donc RETIRÉS
-- d'ici : la table, `chain_document_resout`, le semis du registre,
-- l'enveloppe `chain_invariant_mesurer` / `_base` (la 455 réécrit la
-- fonction de la 413 en y ajoutant la branche INV-19) et le passage
-- d'INV-19 à « mesurable » (fait par la 455).
--
-- CE QUI RESTE est ce que seule cette migration apportait : les SIX raisons
-- de non-mesure passent de l'affirmation à la preuve datée.
-- ─────────────────────────────────────────────────────────────

UPDATE chain_invariants
   SET raison_non_mesurable =
       'Mesuré le 02/10/2026 sur base neuve. `purchase_orders` porte 13 '
       'colonnes (id, number, supplier_id, order_date, expected_date, '
       'status, subtotal, vat, total, notes, created_at, updated_at, '
       'tenant_id) : NI montant facturé, NI montant reçu. Et '
       '`document_links` ne porte aucun lien de type `purchase_orders` '
       '(types relevés : `pay_runs`, `journal_entries`). Le reste à '
       'facturer n''a donc ni colonne ni chaîne : le mesurer suppose '
       'd''inventer l''une des deux. Référentiel : « rompu (BUD-03) ». '
       'Mesurable dès que la commande porte son facturé/reçu — décision '
       'de modèle, pas contrôle.'
 WHERE tenant_id IS NULL AND code = 'INV-05';

UPDATE chain_invariants
   SET raison_non_mesurable =
       'Mesuré le 02/10/2026 sur base neuve. `budgets` porte 17 colonnes, '
       'dont les 12 numériques `period_1..12` — qui sont le BUDGET. '
       'Aucun « réalisé » n''y est stocké. Le côté `journal_lines` est '
       'mesurable : c''est le réalisé budgétaire STOCKÉ qui manque, et '
       'l''ajouter (colonne + fonction qui l''écrit + arbitrage de qui '
       'fait foi) est une décision de modèle. Référentiel : « rompu '
       '(BUD-01, BUD-02) ».'
 WHERE tenant_id IS NULL AND code = 'INV-06';

UPDATE chain_invariants
   SET raison_non_mesurable =
       'Mesuré le 02/10/2026 sur base neuve. `lettrage_groups` porte 11 '
       'colonnes et AUCUNE clé vers `journal_lines`. '
       '`bank_transactions.reconciled_entry_id` existe, mais il pointe '
       'vers une écriture, pas vers le groupe de lettrage : il n''y a '
       'donc aucune jointure à contrôler. Référentiel : « inexistant » — '
       'et c''est ce que la mesure confirme.'
 WHERE tenant_id IS NULL AND code = 'INV-07';

UPDATE chain_invariants
   SET raison_non_mesurable =
       'Mesuré le 02/10/2026 sur base neuve. `bank_transactions` porte 33 '
       'colonnes — aucune de solde de relevé — et le schéma ne comporte '
       'AUCUNE table de relevé. Le côté gauche de l''égalité n''existe '
       'pas. Référentiel : « partiellement tenu (223) » : la 223 tient le '
       'rapprochement, pas le solde du relevé.'
 WHERE tenant_id IS NULL AND code = 'INV-08';

UPDATE chain_invariants
   SET raison_non_mesurable =
       'Mesuré le 02/10/2026 sur base neuve. `dsn_declarations` porte 11 '
       'colonnes — id, tenant_id, period, type, status, file_url, '
       'generated_at, transmitted_at, response_code, response_message, '
       'created_at — dont ZÉRO numérique. Le brut déclaré n''existe que '
       'dans le fichier produit : il n''est pas lisible en base. '
       'Référentiel : « non testé ».'
 WHERE tenant_id IS NULL AND code = 'INV-10';

UPDATE chain_invariants
   SET raison_non_mesurable =
       'Mesuré le 02/10/2026 sur base neuve. `projects.actual_cost` '
       || 'existe (3 projets relevés) : le côté gauche est donc lisible. '
       'Mais le référentiel nomme « DEUX calculs concurrents (PROJ-02) » '
       ': tant que le calcul unique de marge n''est pas choisi, '
       'l''égalité n''a pas de terme de droite. Le choisir est une '
       'décision de modèle, pas un contrôle.'
 WHERE tenant_id IS NULL AND code = 'INV-12';
