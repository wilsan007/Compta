-- ============================================================
-- 460_chain_arborescence_tests.sql — I-01, la « Vue Chaîne » : tout
--   document ouvert sur son amont et son aval.
--
-- L'innovation I-01 du référentiel (D.4) : « depuis n'importe quel
-- document … une frise cliquable : ce qui l'a produit, ce qu'il a
-- produit, et les pièces comptables associées ».
--
-- Ce qu'il faut, techniquement : « une VUE RÉCURSIVE d'ascendance /
-- descendance » et « un composant d'interface unique réutilisé par tous
-- les écrans ». Cette suite ne teste que la moitié base : la fonction
-- qui rend l'ascendance et la descendance. Le composant d'écran est
-- vérifié par Vitest.
--
-- `document_links` et `link_documents` EXISTENT déjà (L0/L1 ; la partie 5
-- les a rendues loyables) : il s'agit de les INSTRUMENTER, pas de les
-- réécrire — c'est écrit dans le référentiel.
--
--   T01  STRUCTURE : SECURITY DEFINER, exécutable par `authenticated`,
--        refusée à `anon` ;
--   T02  la RACINE est rendue (profondeur 0) ;
--   T03  DESCENDANCE : commande → BL (1) → facture (2) ;
--   T04  ASCENDANCE : facture → BL (1) → commande (2) ;
--   T05  un lien FERMÉ sort de l'aval, et revient si on le demande ;
--   T06  CLOISONNEMENT : la chaîne de A ne renvoie RIEN de B ;
--   T07  un CYCLE ne boucle pas : la profondeur borne la descente ;
--   T08  un document INCONNU rend la racine seule, sans exception.
--
-- Vu ROUGE sur le code d'avant : la fonction n'existe pas, donc T01→T08
-- sont tous rouges.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '460', false);
DELETE FROM _audit_results WHERE file = '460';

-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier
-- ─────────────────────────────────────────────────────────────

-- Une chaîne à TROIS niveaux : commande → bon de livraison → facture.
-- Deux maillons posés par la vraie link_documents — donc l'ascendance et
-- la descendance se répondent, ce que T03 et T04 vérifient.
DROP FUNCTION IF EXISTS _i1_chaine(uuid, text);
CREATE OR REPLACE FUNCTION _i1_chaine(p_t uuid, p_nom text)
RETURNS TABLE(commande uuid, bl uuid, facture uuid)
LANGUAGE plpgsql AS $$
-- ⚠️ Les variables locales sont préfixées `v_` : en PL/pgSQL, les paramètres de
-- sortie de RETURNS TABLE portent les mêmes noms que les colonnes, et une
-- variable locale du même nom est AMBIGUË. On l'a mesuré : l'insertion levait
-- « column reference "bl" is ambiguous » et la fonction n'était jamais créée.
DECLARE c uuid; v_so uuid; v_bl uuid; v_fa uuid;
BEGIN
  INSERT INTO customers (name, tenant_id) VALUES ('Client ' || p_nom, p_t) RETURNING id INTO c;
  INSERT INTO sales_orders (tenant_id, number, customer_id, order_date, status)
    VALUES (p_t, 'CV-' || p_nom, c, CURRENT_DATE, 'confirmed') RETURNING id INTO v_so;
  INSERT INTO delivery_notes (tenant_id, number) VALUES (p_t, 'BL-' || p_nom) RETURNING id INTO v_bl;
  INSERT INTO invoices (tenant_id, number, due_date) VALUES (p_t, 'FA-' || p_nom, CURRENT_DATE) RETURNING id INTO v_fa;

  -- p_effet = ce que le maillon produit ; p_link_type = une valeur de
  -- document_links_link_type_check (created_from, delivered_by, invoiced_by…).
  PERFORM link_documents(p_t, 'sales_orders',   v_so, 'delivery_notes', v_bl, 'delivery.create', 'delivered_by');
  PERFORM link_documents(p_t, 'delivery_notes', v_bl, 'invoices',       v_fa, 'invoice.create',  'invoiced_by');

  RETURN QUERY SELECT v_so, v_bl, v_fa;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T01 — structure
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v_secdef boolean; v_auth boolean; v_anon boolean;
  v_sig constant text := 'chain_document_arborescence(uuid,text,uuid,text,integer,boolean)';
BEGIN
  SELECT p.prosecdef INTO v_secdef FROM pg_proc p WHERE p.oid = v_sig::regprocedure;
  SELECT has_function_privilege('authenticated', v_sig, 'EXECUTE') INTO v_auth;
  SELECT has_function_privilege('anon',         v_sig, 'EXECUTE') INTO v_anon;
  PERFORM _rec('T01', 'STRUCTURE : SECURITY DEFINER, exécutable par authenticated, refusée à anon',
    COALESCE(v_secdef, false) AND COALESCE(v_auth, false) AND NOT COALESCE(v_anon, true),
    format('SECURITY DEFINER=%s, authenticated=%s, anon=%s',
           COALESCE(v_secdef::text, 'fonction absente'), v_auth, v_anon));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'T01 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — la racine
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('vuechaine'); v_so uuid; v_bl uuid; v_fa uuid; v_nb int; v_prof int;
BEGIN
  SELECT commande, bl, facture INTO v_so, v_bl, v_fa FROM _i1_chaine(t, 'T02');
  SELECT count(*), min(profondeur) INTO v_nb, v_prof
    FROM chain_document_arborescence(t, 'sales_orders', v_so);
  PERFORM _rec('T02', 'la RACINE est rendue (profondeur 0)',
    v_nb >= 1 AND v_prof = 0,
    format('%s document(s) rendu(s), profondeur minimale %s', v_nb, v_prof));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'T02 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;
-- ── T03 — descendance
-- ── T03 — descendance
DO $$
DECLARE t uuid := _mk_tenant('descendance'); v_so uuid; v_bl uuid; v_fa uuid; c_bl int; c_fa int;
BEGIN
  SELECT commande, bl, facture INTO v_so, v_bl, v_fa FROM _i1_chaine(t, 'T03');
  SELECT count(*) INTO c_bl FROM chain_document_arborescence(t, 'sales_orders', v_so)
    WHERE type = 'delivery_notes' AND profondeur = 1;
  SELECT count(*) INTO c_fa FROM chain_document_arborescence(t, 'sales_orders', v_so)
    WHERE type = 'invoices' AND profondeur = 2;
  PERFORM _rec('T03', 'DESCENDANCE : la commande trouve le BL (profondeur 1) puis la facture (profondeur 2)',
    c_bl = 1 AND c_fa = 1, format('BL a profondeur 1 : %s, facture a profondeur 2 : %s', c_bl, c_fa));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'T03 — le scenario n''a pas pu s''executer', false, SQLERRM);
END $$;

-- ── T04 — ascendance
DO $$
DECLARE t uuid := _mk_tenant('ascendance'); v_so uuid; v_bl uuid; v_fa uuid; c_bl int; c_so int;
BEGIN
  SELECT commande, bl, facture INTO v_so, v_bl, v_fa FROM _i1_chaine(t, 'T04');
  SELECT count(*) INTO c_bl FROM chain_document_arborescence(t, 'invoices', v_fa, 'amont')
    WHERE type = 'delivery_notes' AND profondeur = 1;
  SELECT count(*) INTO c_so FROM chain_document_arborescence(t, 'invoices', v_fa, 'amont')
    WHERE type = 'sales_orders' AND profondeur = 2;
  PERFORM _rec('T04', 'ASCENDANCE : la facture remonte au BL (profondeur 1) puis a la commande (profondeur 2)',
    c_bl = 1 AND c_so = 1, format('BL : %s, commande : %s', c_bl, c_so));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'T04 — le scenario n''a pas pu s''executer', false, SQLERRM);
END $$;

-- ── T05 — un lien fermé sort de l'aval, mais reste consultable
DO $$
DECLARE t uuid := _mk_tenant('lienferme'); v_so uuid; v_bl uuid; v_fa uuid; v_actif int; v_ferme int;
BEGIN
  SELECT commande, bl, facture INTO v_so, v_bl, v_fa FROM _i1_chaine(t, 'T05');
  -- Le maillon de livraison est annulé : son lien passe « rompu ». Le
  -- principe tient : on contre-passe, on n'efface pas.
  PERFORM chain_lien_fermer(t, 'sales_orders', v_so, 'delivery.create', NULL, 'rompu', 'annulation test');

  SELECT count(*) INTO v_actif FROM chain_document_arborescence(t, 'sales_orders', v_so)
    WHERE type = 'delivery_notes';
  SELECT count(*) INTO v_ferme FROM chain_document_arborescence(t, 'sales_orders', v_so, 'aval', 20, true)
    WHERE type = 'delivery_notes' AND etat = 'rompu';
  PERFORM _rec('T05', 'un lien FERMÉ sort de l''aval, et revient quand on demande l''historique',
    v_actif = 0 AND v_ferme = 1,
    format('aval courant : %s BL ; avec l''historique : %s BL rompu', v_actif, v_ferme));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'T05 — le scenario n''a pas pu s''executer', false, SQLERRM);
END $$;
-- ── T06 — cloisonnement
-- ── T06 — cloisonnement
-- ⚠️ `current_tenant_id()` ne résout une société que si l'appelant y APPARTIENT
-- (tenant_users + auth.uid()). On crée donc B d'abord et A en DERNIER : A est
-- alors la société active, et c'est sous A qu'on interroge les deux.
DO $$
DECLARE tb uuid := _mk_tenant('societe-b'); ta uuid := _mk_tenant('societe-a');
        v_aso uuid; v_abl uuid; v_afa uuid; v_bso uuid; v_bbl uuid; v_bfa uuid;
        v_etranger int; v_siens int; v_refus text;
BEGIN
  SELECT commande, bl, facture INTO v_bso, v_bbl, v_bfa FROM _i1_chaine(tb, 'B');
  SELECT commande, bl, facture INTO v_aso, v_abl, v_afa FROM _i1_chaine(ta, 'A');

  -- 1. Contrôle positif : la chaîne de A contient bien ses 3 documents.
  SELECT count(*) INTO v_siens FROM chain_document_arborescence(ta, 'sales_orders', v_aso);
  -- 2. Et AUCUN de ceux de B.
  SELECT count(*) INTO v_etranger FROM chain_document_arborescence(ta, 'sales_orders', v_aso)
    WHERE id IN (v_bso, v_bbl, v_bfa);
  -- 3. Interroger B depuis A est REFUSÉ.
  BEGIN
    PERFORM chain_document_arborescence(tb, 'sales_orders', v_bso);
    v_refus := 'accepté';
  EXCEPTION WHEN insufficient_privilege THEN
    v_refus := 'refusé (42501)';
  END;

  PERFORM _rec('T06', 'CLOISONNEMENT : la chaîne de A ne contient que A, et B est refusée depuis A',
    v_siens = 3 AND v_etranger = 0 AND v_refus = 'refusé (42501)',
    format('%s document(s) de A, %s de B, B depuis A : %s', v_siens, v_etranger, v_refus));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'T06 — le scenario n''a pas pu s''executer', false, SQLERRM);
END $$;

-- ── T07 — un cycle ne boucle pas
DO $$
DECLARE t uuid := _mk_tenant('cycle'); v_so uuid; v_bl uuid; v_fa uuid; v_nb int;
BEGIN
  SELECT commande, bl, facture INTO v_so, v_bl, v_fa FROM _i1_chaine(t, 'T07');
  -- La facture « produit » la commande : boucle. Sans borne, la
  -- récursion ne s'arrêterait jamais.
  PERFORM link_documents(t, 'invoices', v_fa, 'sales_orders', v_so, 'invoice.create', 'invoiced_by');
  SELECT count(*) INTO v_nb FROM chain_document_arborescence(t, 'sales_orders', v_so, 'aval', 10);
  PERFORM _rec('T07', 'un CYCLE ne boucle pas : la profondeur borne la descente',
    v_nb > 0 AND v_nb <= 11, format('%s document(s) rendu(s) sur une boucle, profondeur demandee 10', v_nb));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T07', 'T07 — le scenario n''a pas pu s''executer', false, SQLERRM);
END $$;

-- ── T08 — un document inconnu
DO $$
DECLARE t uuid := _mk_tenant('inconnu'); v_nb int;
BEGIN
  SELECT count(*) INTO v_nb FROM chain_document_arborescence(t, 'sales_orders', uuid_generate_v4());
  PERFORM _rec('T08', 'un document INCONNU rend la racine seule, sans exception',
    v_nb = 1, format('%s document(s) rendu(s) pour un identifiant invente', v_nb));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T08', 'T08 — le scenario n''a pas pu s''executer', false, SQLERRM);
END $$;

-- Verdict final : sans cette ligne, un rouge ne ferait jamais echouer
-- la CI (le defaut corrige en 1.2 pour la caisse).
SELECT _audit_assert('460');
