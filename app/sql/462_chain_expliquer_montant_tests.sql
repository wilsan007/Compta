-- ============================================================
-- 462_chain_expliquer_montant_tests.sql — I-08, le « pourquoi ce
--   chiffre ? » : dérouler la chaîne qui produit un montant.
--
-- I-08 est déjà posé par la 461 (le dictionnaire : un indicateur est
-- une requête NOMMÉE et DATÉE). Cette migration répond à l'autre
-- moitié : une fois le chiffre identifié, QUELLE pièce l'a produit ?
--
-- Le référentiel : « sur n'importe quel montant, un bouton qui déroule
-- la chaîne des documents et écritures qui produit ce montant ».
--
-- Elle ne calcule RIEN et n'invente AUCUN lien : elle s'appuie sur ce
-- que les maillons ont déjà tracé (460) et sur les écritures qui
-- portent réellement le montant. Un chiffre dont on ne sait pas dire
-- d'où il vient n'est pas expliqué — il est seulement affiché, et le
-- résultat le dit.
--
--   T01  STRUCTURE : exposée à `authenticated`, refusée à `anon` ;
--   T02  la chaîne rend la PIÈCE COMPTABLE produite par le document ;
--   T03  les LIGNES d'écriture portant le montant sont déroulées ;
--   T04  MONTANT : la somme des lignes rendues est celle de l'écriture ;
--   T05  SANS EXPLICATION : un chiffre dont aucune chaîne ne le porte
--        est renvoyé VIDE — jamais un chiffre fabriqué.
--
-- Vu ROUGE sur le code d'avant : la fonction n'existe pas, T01→T05 rouges.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '462', false);
DELETE FROM _audit_results WHERE file = '462';

DROP FUNCTION IF EXISTS _i8_piece(uuid, text);
CREATE OR REPLACE FUNCTION _i8_piece(p_t uuid, p_nom text)
RETURNS TABLE(facture uuid, ecriture uuid)
LANGUAGE plpgsql AS $$
DECLARE v_c uuid; v_fa uuid; v_je uuid;
BEGIN
  INSERT INTO customers (name, tenant_id) VALUES ('Client ' || p_nom, p_t) RETURNING id INTO v_c;
  INSERT INTO invoices (tenant_id, number, due_date) VALUES (p_t, 'FA-' || p_nom, CURRENT_DATE) RETURNING id INTO v_fa;
  -- Le noyau (187) REFUSE de créer une écriture déjà validée : il faut la
  -- créer en brouillon, écrire les lignes, puis la valider. C'est mesuré —
  -- la première version demandait 'posted' à l'insertion.
  INSERT INTO journal_entries (tenant_id, number, date, description, journal_code, status,
                               total_debit, total_credit)
    VALUES (p_t, 'VE-' || p_nom, CURRENT_DATE, 'Vente ' || p_nom, 'VT', 'draft', 120, 120)
    RETURNING id INTO v_je;
  -- La facture PRODUIT l'écriture : c'est le maillon réel (`invoiced_by`).
  PERFORM link_documents(p_t, 'invoices', v_fa, 'journal_entries', v_je, 'invoice.create', 'invoiced_by');
  -- Les comptes du plan sont sur SIX CHIFFRES (`700000`, `445000`) : la
  -- première version écrivait `706` / `445` et le noyau refusait —
  -- « Compte 706 absent du plan comptable de la société ». Mesuré.
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
    VALUES (p_t, v_je, '700000', 'Ventes', 120, 0, 'Vente HT'),
           (p_t, v_je, '445000', 'Clients',  0, 120, 'Client ' || p_nom);
  UPDATE journal_entries SET status = 'posted' WHERE id = v_je;
  RETURN QUERY SELECT v_fa, v_je;
END $$;

-- ── T01 — structure
DO $$
DECLARE v_auth boolean; v_anon boolean; v_sd boolean;
BEGIN
  SELECT p.prosecdef INTO v_sd FROM pg_proc p
   WHERE p.oid = 'chain_expliquer_montant(uuid,text,uuid)'::regprocedure;
  SELECT has_function_privilege('authenticated', 'chain_expliquer_montant(uuid,text,uuid)', 'EXECUTE') INTO v_auth;
  SELECT has_function_privilege('anon',         'chain_expliquer_montant(uuid,text,uuid)', 'EXECUTE') INTO v_anon;
  PERFORM _rec('T01', 'STRUCTURE : exposée à authenticated, refusée à anon',
    COALESCE(v_sd, false) AND COALESCE(v_auth, false) AND NOT COALESCE(v_anon, true),
    format('SECURITY DEFINER=%s, authenticated=%s, anon=%s',
           COALESCE(v_sd::text, 'fonction absente'), v_auth, v_anon));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'T01 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T02 — la pièce comptable apparaît
DO $$
DECLARE t uuid := _mk_tenant('explication'); v_piece uuid; v_ec uuid; v_nb int;
BEGIN
  SELECT facture, ecriture INTO v_piece, v_ec FROM _i8_piece(t, 'T02');
  SELECT count(*) INTO v_nb FROM chain_expliquer_montant(t, 'invoices', v_piece)
    WHERE genre = 'ecriture' AND id = v_ec;
  PERFORM _rec('T02', 'la chaîne rend la PIÈCE COMPTABLE produite par le document',
    v_nb = 1, format('%s écriture(s) trouvée(s) pour la facture', v_nb));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'T02 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;
-- ── T03 — les lignes sont déroulées
DO $$
DECLARE t uuid := _mk_tenant('explication'); v_fa uuid; v_ec uuid; v_nb int;
BEGIN
  SELECT facture, ecriture INTO v_fa, v_ec FROM _i8_piece(t, 'T03');
  SELECT count(*) INTO v_nb FROM chain_expliquer_montant(t, 'invoices', v_fa)
    WHERE genre = 'ligne';
  PERFORM _rec('T03', 'les LIGNES d''écriture portant le montant sont déroulées',
    v_nb = 2, format('%s ligne(s) rendue(s) (2 attendues)', v_nb));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'T03 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T04 — le montant se recompose
DO $$
DECLARE t uuid := _mk_tenant('explication'); v_fa uuid; v_ec uuid; v_somme numeric;
BEGIN
  SELECT facture, ecriture INTO v_fa, v_ec FROM _i8_piece(t, 'T04');
  SELECT coalesce(sum(montant), 0) INTO v_somme FROM chain_expliquer_montant(t, 'invoices', v_fa)
    WHERE genre = 'ligne' AND debit;
  PERFORM _rec('T04', 'MONTANT : la somme des lignes rendues est celle de l''écriture',
    v_somme = 120, format('somme des débits rendus : %s (120 attendu)', v_somme));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'T04 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T05 — un chiffre sans explication n'est pas expliqué
DO $$
DECLARE t uuid := _mk_tenant('explication'); v_fa uuid; v_nb int;
BEGIN
  INSERT INTO invoices (tenant_id, number, due_date) VALUES (t, 'FA-orpheline', CURRENT_DATE)
    RETURNING id INTO v_fa;
  SELECT count(*) INTO v_nb FROM chain_expliquer_montant(t, 'invoices', v_fa)
    WHERE genre IN ('ecriture', 'ligne');
  PERFORM _rec('T05', 'SANS EXPLICATION : un chiffre dont aucune chaîne ne le porte est renvoyé VIDE',
    v_nb = 0, format('%s pièce(s) comptable(s) rendue(s) (0 attendue)', v_nb));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'T05 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

SELECT _audit_assert('462');