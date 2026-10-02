-- ═══════════════════════════════════════════════════════════════════════════
-- 432 — Lot L3, tranche 4 : LE RELEVÉ BANCAIRE MANUEL, ses trois maillons
--   tracés par leur chemin d'appel (tâche 3.3 du plan de la partie 3)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **Objet.** Dernier trio de maillons RPC named par le recomptage de la tâche
-- 3.1 (`post_bank_statement_line`, `reconcile_bank_statement_line`,
-- `unreconcile_bank_statement_line`). Les trois écrivent dans la trésorerie ET
-- la compta, et aucun n'était tracé : une ligne de relevé comptabilisée à la
-- main ne laissait aucun lien, donc rien ne disait quelle écriture elle avait
-- produite — et le dé-lettrage ne disait rien non plus.
--
-- **LE TROISIÈME N'EST PAS COMME LES DEUX AUTRES — ET C'EST LE POINT.**
-- `unreconcile_bank_statement_line` ne PRODUIT rien : il RETIRE un pointage. Il
-- ne pose donc ni entrée de chaîne ni contrat d'effet : il **ferme le lien**
-- que l'un des deux autres a ouvert (doctrine 320 — « le chemin qui
-- contrepasse ferme l'effet retiré »). La fermeture n'écrit AUCUNE trace
-- (doctrine 312) : son journal est le lien lui-même, désormais rompu, motivé.
-- Une trace `applique` pour un dé-lettrage dirait « on a appliqué un effet »,
-- ce qui est le contraire de ce qui s'est passé.
--
-- **DEUX EFFETS DISTINCTS, ET POURQUOI PAS UN SEUL.** Les deux premiers
--   maillons décrivent deux faits DIFFÉRENTS :
--   * `post_bank_statement_line` fait NAÎTRE une écriture à partir de la ligne
--     de relevé (c'est une comptabilisation) ;
--   * `reconcile_bank_statement_line` ne fait que CONSTATER qu'une écriture
--     existante est la contrepartie de la ligne (c'est un pointage).
-- Ce sont deux faits distincts, avec deux avatars distincts : l'une part vers
-- une écriture neuve, l'autre vers une ligne d'écriture déjà validée. Les
-- confondre en un seul effet obligerait à choisir un avatar par défaut, et le
-- maillon choisirait FAUX une fois sur deux. Le nommage le dit : `posted`
-- (l'écriture est née) et `manually_reconciled` (l'écriture existait).
--
-- ⚠️ ON NE RÉEMPLOIE PAS L'EFFET DE L'AUTOMATIQUE. La 316 trace déjà
-- `treasury.bank_transaction.reconciled` (bank_transactions / reconciled) par le
-- compagnon `zz_l1_bank_reconciliation`, pour le RAPPROCHEMENT AUTOMATIQUE
-- (`auto_reconcile_by_score`). Le pointage manuel ne réemploie pas ce nom : ce
-- serait dire que deux gestes différents ont produit le même effet, et le
-- maillon automatique ne serait plus distinguable du geste de l'utilisateur.
-- Les deux coexistent, avec deux effets distincts — et l'invariant de
-- bouclage (M-03) peut les lire séparément.
--
-- **MÊME DOCTRINE QUE 412 ET 415.** Les trois corps sont RENOMMÉS `_inner`
-- (rien n'est recopié) et trois wrappers portent le nom public, le `SECURITY
-- DEFINER` et les gardes de permission d'origine. Le lecteur du front n'a pas
-- changé d'appel : `check-rpc-contract` est confronté aux mêmes noms.
-- ═══════════════════════════════════════════════════════════════════════════
-- ─────────────────────────────────────────────────────────────
-- 1. LES DEUX CONTRATS D'EFFET — déclarés ici (porte G2, même fichier).
--    Le troisième maillon n'en a pas : le dé-lettrage ne produit rien, il
--    retire. Un contrat pour lui dirait le contraire de la vérité.
-- ─────────────────────────────────────────────────────────────
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES
  (NULL, 'bank_transactions', 'posted', 'treasury.statement_line.posted',
   true, NULL, false, false, true, false, true,
   'L3/432 : post_bank_statement_line fait NAÎTRE une écriture à partir d''une ligne de relevé (la banque d''un côté, la contrepartie de l''autre, la ligne bancaire née pointée). Lien `generated_entry` vers l''écriture créée. Réversible : unreconcile_bank_statement_line défait le pointage et ROMPT ce lien (doctrine 320).'),
  (NULL, 'bank_transactions', 'reconciled', 'treasury.statement_line.manually_reconciled',
   false, NULL, false, false, true, false, true,
   'L3/432 : reconcile_bank_statement_line CONSTATE qu''une ligne d''écriture DÉJÀ validée est la contrepartie de la ligne de relevé (montant et sens vérifiés). Lien `reconciled_with` vers l''ÉCRITURE, le détail de la ligne au payload. Distinct de treasury.bank_transaction.reconciled (316, rapprochement AUTOMATIQUE) : deux gestes différents, deux effets différents.')
ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
             document_type, evenement, effet)
DO UPDATE SET
  ecrit_comptable = EXCLUDED.ecrit_comptable,
  journal_code    = EXCLUDED.journal_code,
  touche_stock    = EXCLUDED.touche_stock,
  touche_paie     = EXCLUDED.touche_paie,
  reversible      = EXCLUDED.reversible,
  obligatoire     = EXCLUDED.obligatoire,
  actif           = EXCLUDED.actif,
  note            = EXCLUDED.note;
-- ─────────────────────────────────────────────────────────────
-- 1 bis. LE VOCABULAIRE DES LIENS A BESOIN D'UN MOT POUR UN RAPPROCHEMENT
--    `document_links_link_type_check` n'admettait que huit valeurs (mesuré) :
--    created_from, delivered_by, invoiced_by, paid_by, reversed_by,
--    adjusted_by, generated_entry, consumed_by_absence.
--    Aucune ne dit « cette ligne de relevé a été pointée sur CETTE écriture ».
--    `adjusted_by` serait faux (rien n'est corrigé), `paid_by` serait faux
--    (aucun règlement), `generated_entry` serait FAUX une fois sur deux
--    (l'écriture existait déjà — c'est tout le sens du pointage manuel).
--    On ADDONCE donc `reconciled_with` au CHECK, comme la 315 a ajouté
--    `sans_effet` à `chain_traces.resultat` : un vocabulaire qui ne sait pas
--    dire ce qui s'est passé oblige à mentir. Le CHECK est étendu DANS CE
--    MÊME FICHIER, pour que la migration et son vocabulaire partent ensemble.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE document_links DROP CONSTRAINT IF EXISTS document_links_link_type_check;
ALTER TABLE document_links ADD CONSTRAINT document_links_link_type_check
  CHECK (link_type = ANY (ARRAY['created_from','delivered_by','invoiced_by','paid_by',
                                 'reversed_by','adjusted_by','generated_entry',
                                 'consumed_by_absence','reconciled_with']));

-- ─────────────────────────────────────────────────────────────
-- 2. post_bank_statement_line — LA COMPTABILISATION D'UNE LIGNE DE RELEVÉ
--    Le corps (garde de permission, contrôle de nature et de doublon,
--    résolution du compte bancaire, écriture brouillon à deux lignes puis
--    validation, ligne bancaire née pointée, ligne de relevé marquée) devient
--    `post_bank_statement_line_inner`. Rien n'est recopié.
-- ─────────────────────────────────────────────────────────────
DO $bloc$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'post_bank_statement_line'
                AND pg_get_function_identity_arguments(p.oid) = 'p_transaction_id uuid, p_account_code text, p_label text')
      AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'post_bank_statement_line_inner') THEN
    ALTER FUNCTION public.post_bank_statement_line(uuid, text, text) RENAME TO post_bank_statement_line_inner;
  END IF;
END $bloc$;

REVOKE ALL ON FUNCTION public.post_bank_statement_line_inner(uuid, text, text)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.post_bank_statement_line(
  p_transaction_id uuid,
  p_account_code   text DEFAULT NULL,
  p_label          text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_tid    uuid := current_tenant_id();
  v_debut  timestamptz := clock_timestamp();
  v_r      jsonb;
  v_je     uuid;
  v_num    text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active' USING ERRCODE = '42501';
  END IF;

  -- L'effet métier d'abord : le corps intact, dans la transaction de l'appel.
  -- Il porte ses propres gardes (permission, nature, doublon, montant, compte).
  v_r := public.post_bank_statement_line_inner(p_transaction_id, p_account_code, p_label);

  v_je  := (v_r->>'journal_entry_id')::uuid;
  v_num := v_r->>'entry_number';

  IF chain_avant(v_tid, 'bank_transactions', 'posted', 'treasury.statement_line.posted',
                 'bank_transactions', p_transaction_id, NULL,
                 format('Ligne de relevé %s : la comptabilisation n''a pas été tracée (règle treasury.statement_line.posted, module trésorerie).',
                        COALESCE(v_num, p_transaction_id::text))) THEN
    IF v_je IS NOT NULL THEN
      PERFORM link_documents(v_tid, 'bank_transactions', p_transaction_id,
                             'journal_entries', v_je,
                             'treasury.statement_line.posted', 'generated_entry',
                             jsonb_build_object('entry_number', v_num,
                                                'journal_code', v_r->>'journal_code',
                                                'account_code', v_r->>'account_code',
                                                'amount', v_r->>'amount',
                                                'direction', v_r->>'direction',
                                                'lien_par_ligne', false));
      PERFORM chain_apres(v_tid, 'treasury.statement_line.posted', 'bank_transactions',
                          p_transaction_id, v_debut, 1, 'applique', NULL, NULL, NULL);
      PERFORM emit_domain_event(v_tid, 'bank_transactions.posted', 'bank_transactions',
                                p_transaction_id,
                                jsonb_build_object('entry_id', v_je, 'entry_number', v_num,
                                                   'amount', v_r->>'amount'), NULL);
    ELSE
      -- Le corps a réussi sans rendre d'écriture : c'est une anomalie, elle se dit.
      PERFORM chain_apres(v_tid, 'treasury.statement_line.posted', 'bank_transactions',
                          p_transaction_id, v_debut, 0, 'sans_effet',
                          format('Ligne de relevé %s : comptabilisée sans écriture rendue (règle treasury.statement_line.posted).',
                                 COALESCE(v_num, p_transaction_id::text)),
                          NULL, NULL);
    END IF;
  END IF;

  RETURN v_r;
END $maillon$;

-- ─────────────────────────────────────────────────────────────
-- 3. reconcile_bank_statement_line — LE POINTAGE MANUEL
--    Le corps (nature de la ligne, absence de doublon, écriture validée au
--    bon compte, montant et sens vérifiés, pointage des deux côtés) devient
--    `reconcile_bank_statement_line_inner`.
--    L'aval est l'ÉCRITURE (`journal_entries`), pas la ligne, parce que c'est
--    l'écriture que le dé-lettrage rouvrira — et que le lien doit désigner la
--    même chose que ce qui sera défait. La LIGNE est au payload.
-- ─────────────────────────────────────────────────────────────
DO $bloc$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'reconcile_bank_statement_line'
                AND pg_get_function_identity_arguments(p.oid) = 'p_transaction_id uuid, p_journal_line_id uuid')
      AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'reconcile_bank_statement_line_inner') THEN
    ALTER FUNCTION public.reconcile_bank_statement_line(uuid, uuid) RENAME TO reconcile_bank_statement_line_inner;
  END IF;
END $bloc$;

REVOKE ALL ON FUNCTION public.reconcile_bank_statement_line_inner(uuid, uuid)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.reconcile_bank_statement_line(
  p_transaction_id  uuid,
  p_journal_line_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_tid    uuid := current_tenant_id();
  v_debut  timestamptz := clock_timestamp();
  v_r      jsonb;
  v_je     uuid;
  v_num    text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active' USING ERRCODE = '42501';
  END IF;

  v_r := public.reconcile_bank_statement_line_inner(p_transaction_id, p_journal_line_id);

  v_je  := (v_r->>'journal_entry_id')::uuid;
  v_num := v_r->>'entry_number';

  IF chain_avant(v_tid, 'bank_transactions', 'reconciled', 'treasury.statement_line.manually_reconciled',
                 'bank_transactions', p_transaction_id, NULL,
                 format('Ligne de relevé %s : le pointage manuel n''a pas été tracé (règle treasury.statement_line.manually_reconciled, module trésorerie).',
                        p_transaction_id::text)) THEN
    IF v_je IS NOT NULL THEN
      PERFORM link_documents(v_tid, 'bank_transactions', p_transaction_id,
                             'journal_entries', v_je,
                             'treasury.statement_line.manually_reconciled', 'reconciled_with',
                             jsonb_build_object('entry_number', v_num,
                                                'journal_line_id', p_journal_line_id,
                                                'account_code', v_r->>'account_code',
                                                'amount', v_r->>'amount',
                                                'entry_date', v_r->>'entry_date',
                                                'lien_par_ligne', false));
      PERFORM chain_apres(v_tid, 'treasury.statement_line.manually_reconciled', 'bank_transactions',
                          p_transaction_id, v_debut, 1, 'applique', NULL, NULL, NULL);
      PERFORM emit_domain_event(v_tid, 'bank_transactions.reconciled', 'bank_transactions',
                                p_transaction_id,
                                jsonb_build_object('entry_id', v_je, 'entry_number', v_num,
                                                   'journal_line_id', p_journal_line_id,
                                                   'mode', 'manuel'), NULL);
    ELSE
      PERFORM chain_apres(v_tid, 'treasury.statement_line.manually_reconciled', 'bank_transactions',
                          p_transaction_id, v_debut, 0, 'sans_effet',
                          format('Ligne de relevé %s : pointée sans écriture rendue (règle treasury.statement_line.manually_reconciled).',
                                 p_transaction_id::text),
                          NULL, NULL);
    END IF;
  END IF;

  RETURN v_r;
END $maillon$;

COMMENT ON FUNCTION public.reconcile_bank_statement_line(uuid, uuid) IS
  'L3/432 : le pointage manuel d''une ligne de relevé, tracé par son chemin d''appel. Corps renommé reconcile_bank_statement_line_inner, intact. Lien `reconciled_with` vers l''ÉCRITURE (la ligne est au payload) — c''est l''écriture que le dé-lettrage rouvrira.';
-- ─────────────────────────────────────────────────────────────
-- 4. unreconcile_bank_statement_line — LE DÉ-LETTRAGE, QUI FERME LE LIEN
--    Le corps (garde de permission, contrôle de nature et de pointage, ligne
--    d'écriture rouverte, ligne de relevé remise à zéro) devient
--    `unreconcile_bank_statement_line_inner`.
--
--    ⚠️ CE WRAPPER N'OUVRE AUCUNE ENTRÉE DE CHAÎNE, ET C'EST DÉLIBÉRÉ.
--    Il ne produit pas d'effet : il RETIRE un pointage. Il n'appelle donc NI
--    `chain_avant` NI `link_documents` NI `chain_apres` : il utilise
--    `chain_lien_rompre`, la porte de la 312 — c'est la DOCTRINE DE LA 320,
--    déjà appliquée à la caisse (412) : « le chemin qui contrepasse ferme
--    l'effet retiré ». La fermeture n'écrit AUCUNE trace (doctrine 312) : son
--    journal est le lien, désormais rompu, motivé.
--
--    ET IL FERME LES DEUX LIENS POSSIBLES : celui de la comptabilisation
--    (`treasury.statement_line.posted`, posé par le §2) comme celui du
--    pointage manuel (`treasury.statement_line.manually_reconciled`, §3). Un
--    dé-lettrage ne sait pas quel chemin a produit le pointage — et il n'a pas
--    à le savoir : il défait le pointage, donc tout lien qui le décrivait
--    devient faux.
--
--    ⚠️ `chain_lien_rompre` **LÈVE** s'il n'y a pas de lien actif — mesuré :
--    « Fermeture de lien refusée : aucun lien ACTIF … il n'y a rien à
--    On ne peut donc pas appeler les deux à l'aveugle : un dé-lettrage d'une
--    ligne comptabilisée ferait lever le second appel et REJETER toute
--    l'opération, alors que le retrait métier a réussi. Il faut donc tester
--    avec `chain_lien_actif`, comme le fait la 412 sur l'avoir de caisse.
-- ─────────────────────────────────────────────────────────────
DO $bloc$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'unreconcile_bank_statement_line'
                AND pg_get_function_identity_arguments(p.oid) = 'p_transaction_id uuid')
      AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'unreconcile_bank_statement_line_inner') THEN
    ALTER FUNCTION public.unreconcile_bank_statement_line(uuid) RENAME TO unreconcile_bank_statement_line_inner;
  END IF;
END $bloc$;

REVOKE ALL ON FUNCTION public.unreconcile_bank_statement_line_inner(uuid)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.unreconcile_bank_statement_line(p_transaction_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_tid   uuid := current_tenant_id();
  v_r     jsonb;
  v_je    uuid;
  v_num   text;
  v_motif text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active' USING ERRCODE = '42501';
  END IF;

  -- La fermeture se prépare AVANT le retrait : après, le corps a remis
  -- `reconciled_entry_id` à NULL, et l'on ne saurait plus QUELLE écriture
  -- était liée — donc quel lien fermer, ni comment le motiver.
  SELECT bt.reconciled_entry_id INTO v_je
    FROM bank_transactions bt
   WHERE bt.id = p_transaction_id AND bt.tenant_id = v_tid;

  SELECT je.number INTO v_num FROM journal_entries je WHERE je.id = v_je;

  v_motif := format('Dé-lettrage de la ligne de relevé %s : le pointage de l''écriture %s est défait (doctrine 320).',
                    p_transaction_id::text, COALESCE(v_num, v_je::text, '(sans écriture)'));

  -- L'effet métier : le retrait, dans la transaction de l'appel.
  v_r := public.unreconcile_bank_statement_line_inner(p_transaction_id);

  -- LA DOCTRINE DE LA 320 : le chemin qui contrepasse ferme les liens.
  -- Chaque fermeture est PRÉCONDITIONNÉE par l'existence d'un lien actif :
  -- `chain_lien_rompre` lève sinon, et ferait échouer tout le dé-lettrage
  -- alors que le retrait métier a réussi (mesuré — voir l'en-tête du §4).
  IF chain_lien_actif(v_tid, 'bank_transactions', p_transaction_id,
                      'treasury.statement_line.posted') IS NOT NULL THEN
    PERFORM chain_lien_rompre(v_tid, 'bank_transactions', p_transaction_id,
                              'treasury.statement_line.posted', v_motif);
  END IF;

  IF chain_lien_actif(v_tid, 'bank_transactions', p_transaction_id,
                      'treasury.statement_line.manually_reconciled') IS NOT NULL THEN
    PERFORM chain_lien_rompre(v_tid, 'bank_transactions', p_transaction_id,
                              'treasury.statement_line.manually_reconciled', v_motif);
  END IF;

  PERFORM emit_domain_event(v_tid, 'bank_transactions.unreconciled', 'bank_transactions',
                            p_transaction_id,
                            jsonb_build_object('entry_id', v_je,
                                               'ledger_lines_reopened', v_r->'ledger_lines_reopened'),
                            NULL);

  RETURN v_r;
END $maillon$;

COMMENT ON FUNCTION public.unreconcile_bank_statement_line(uuid) IS
  'L3/432 : le dé-lettrage d''une ligne de relevé, tracé par la FERMETURE de ses liens (doctrine 320) — pas par une trace `applique`, qui dirait le contraire de ce qui s''est passé. Corps renommé unreconcile_bank_statement_line_inner, intact. Ferme les deux liens possibles : la comptabilisation et le pointage manuel.';
COMMENT ON FUNCTION public.post_bank_statement_line(uuid, text, text) IS
  'L3/432 : la comptabilisation d''une ligne de relevé, tracée par son chemin d''appel. Le corps est renommé post_bank_statement_line_inner, intact, non exposé. Lien `generated_entry` vers l''écriture créée ; le dé-lettrage rompt ce lien (doctrine 320).';
-- ─────────────────────────────────────────────────────────────
-- 5. DROITS — inchangés, comme la 412 et la 430
--    Les trois wrappers gardent le régime des corps qu'ils enveloppaient : ils
--    portent les mêmes gardes de permission, dans le corps intact. Les corps
--    `_inner` ne sont plus exposés (leçon R-17). On rétablit donc exactement
--    les droits mesurés avant la migration.
-- ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.post_bank_statement_line(uuid, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.post_bank_statement_line(uuid, text, text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.reconcile_bank_statement_line(uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.reconcile_bank_statement_line(uuid, uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.unreconcile_bank_statement_line(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.unreconcile_bank_statement_line(uuid) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────
-- 6. Ce que cette migration ne fait pas — nommé
-- ─────────────────────────────────────────────────────────────
-- * **Elle ne trace pas le rapprochement AUTOMATIQUE** : `auto_reconcile_by_score`
--   est déjà tracé depuis la 316 (compagnon `zz_l1_bank_reconciliation`). Les
--   deux gestes coexistent, avec deux effets distincts.
-- * **Elle ne pose pas de contrat pour le dé-lettrage** : il ne produit aucun
--   effet, il en retire un. Un contrat serait un mensonge de vocabulaire.
-- * **Elle ne reprise pas les pointages antérieurs** : une ligne pointée avant
--   le déploiement de la 432 n'a pas de lien. Son dé-lettrage produira un
--   `chain_lien_rompre` sans effet (aucun lien actif) — c'est sans danger, et
--   cela vaut mieux qu'un lien inventé après coup.
-- * **Elle ne mesure pas la performance** : le banc D1→D8 (tâches 3.4 → 3.7)
--   s'appliquera à ces trois maillons comme aux autres.