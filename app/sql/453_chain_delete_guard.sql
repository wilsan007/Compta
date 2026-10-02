-- ═══════════════════════════════════════════════════════════════════════════
-- 453 — Partie 5 : on ne supprime pas un document qu'un lien ACTIF relie
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Défaut mesuré le 02/10/2026 (administrateur connecté, chemin de l'écran) :
--   D1 compte bancaire supprimé → 2 liens actifs vers rien ;
--   D2 règlement client supprimé → la facture reste « payée », l'écriture reste,
--      plus aucun document de règlement ;
--   D3 commande confirmée supprimée → sa réservation (3 u.) reste ACTIVE ;
--   D4 réservation supprimée → lien actif vers rien ;
--   D5 journal et compte comptable créés pour la banque supprimés.
-- 15 des 27 tables reliées n'avaient aucune garde de suppression.
--
-- La garde :
--   * un seul corps, `chain_refuser_suppression_liee()`, posé en BEFORE DELETE
--     sur les 27 tables du registre (mode 'document') et sur leurs 5 tables de
--     lignes (mode 'ligne') ;
--   * ne regarde que les liens ACTIFS — un document annulé par son chemin
--     d'annulation (qui ferme ses liens, 410/412) se supprime normalement ;
--   * laisse passer la suppression EN CASCADE d'une société (la ligne `tenants`
--     n'est déjà plus visible quand la cascade atteint le document) ;
--   * lève 23503 (foreign_key_violation) : `apply_chart_pack` sait déjà
--     transformer ce code en « compte marqué obsolète », et PostgREST rend 409 ;
--   * message = 'CHAIN_DELETE_REFUSED' (clé lue par l'écran, src/lib/utils.ts),
--     DETAIL = JSON (type, id, liens), HINT = phrase en français ;
--   * NOM des déclencheurs : `zz_garde_p5_…`. Il se trie AVANT les compagnons
--     `zz_l1_…` / `zz_l3_…` : les suites 316 (T10) et 321 (T05) exigent qu'aucun
--     déclencheur ne se trie après un compagnon. (Un nom `zz_p5_…` les fait
--     rougir — mesuré le 02/10.)
--
-- EXCEPTION MÉTIER, la seule : le COMPTE BANCAIRE SANS OPÉRATION. La 244 (T04)
-- garantit qu'il se supprime toujours. Or sa création pose deux liens (journal
-- et compte comptable, maillon chain_l1_bank_account_ledger). Le compagnon
-- `zz_garde_p5_0_banque_vide` (qui se trie AVANT la garde, et APRÈS la garde de
-- la 244 qui refuse un compte AVEC opérations) FERME ces deux liens (rompu,
-- motif) : la garde ne voit plus de lien actif, la suppression passe, et il ne
-- reste aucun orphelin actif — c'était le vrai défaut D1.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.chain_refuser_suppression_liee()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_type  text := TG_ARGV[0];
  v_mode  text := TG_ARGV[1];   -- 'document' ou 'ligne'
  v_n     integer;
  v_liens jsonb;
BEGIN
  -- Suppression en cascade de la société : rien à protéger.
  IF NOT EXISTS (SELECT 1 FROM tenants WHERE id = OLD.tenant_id) THEN
    RETURN OLD;
  END IF;

  IF v_mode = 'ligne' THEN
    SELECT count(*),
           jsonb_agg(jsonb_build_object('effet', l.effet, 'vers', l.aval_type, 'vers_id', l.aval_id))
      INTO v_n, v_liens
    FROM document_links l
    WHERE l.tenant_id = OLD.tenant_id
      AND l.etat = 'actif'
      AND l.amont_type = v_type
      AND l.amont_ligne_id = OLD.id;
  ELSE
    SELECT count(*),
           jsonb_agg(jsonb_build_object(
             'effet', l.effet,
             'vers',    CASE WHEN l.amont_id = OLD.id AND l.amont_type = v_type THEN l.aval_type ELSE l.amont_type END,
             'vers_id', CASE WHEN l.amont_id = OLD.id AND l.amont_type = v_type THEN l.aval_id   ELSE l.amont_id   END,
             'sens',    CASE WHEN l.amont_id = OLD.id AND l.amont_type = v_type THEN 'amont'     ELSE 'aval'       END))
      INTO v_n, v_liens
    FROM document_links l
    WHERE l.tenant_id = OLD.tenant_id
      AND l.etat = 'actif'
      AND ((l.amont_type = v_type AND l.amont_id = OLD.id)
        OR (l.aval_type  = v_type AND l.aval_id  = OLD.id));
  END IF;

  IF v_n > 0 THEN
    RAISE EXCEPTION 'CHAIN_DELETE_REFUSED'
      USING ERRCODE = '23503',
            DETAIL  = jsonb_build_object('type', v_type, 'mode', v_mode, 'id', OLD.id,
                                         'liens', v_liens)::text,
            HINT    = format('Suppression refusée : ce document (%s) est relié à %s document(s) par la chaîne. Annulez-le par son chemin d''annulation, qui ferme les liens, avant de le supprimer.',
                             v_type, v_n);
  END IF;

  RETURN OLD;
END $fn$;

COMMENT ON FUNCTION public.chain_refuser_suppression_liee() IS
  '453 : garde BEFORE DELETE. Refuse (23503, message CHAIN_DELETE_REFUSED) la suppression d''un document — ou d''une ligne amont — tenu par un lien ACTIF. Laisse passer la cascade d''une société. Arguments : type du registre, mode (document|ligne).';

REVOKE ALL ON FUNCTION public.chain_refuser_suppression_liee() FROM PUBLIC, anon, authenticated;

-- Pose sur toutes les tables du registre, et sur leurs tables de lignes.
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT code, table_name, ligne_table FROM public.chain_document_types ORDER BY code LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS zz_garde_p5_suppression ON public.%I', r.table_name);
    EXECUTE format('CREATE TRIGGER zz_garde_p5_suppression BEFORE DELETE ON public.%I '
                   'FOR EACH ROW EXECUTE FUNCTION public.chain_refuser_suppression_liee(%L, %L)',
                   r.table_name, r.code, 'document');
    IF r.ligne_table IS NOT NULL THEN
      EXECUTE format('DROP TRIGGER IF EXISTS zz_garde_p5_suppression_ligne ON public.%I', r.ligne_table);
      EXECUTE format('CREATE TRIGGER zz_garde_p5_suppression_ligne BEFORE DELETE ON public.%I '
                     'FOR EACH ROW EXECUTE FUNCTION public.chain_refuser_suppression_liee(%L, %L)',
                     r.ligne_table, r.code, 'ligne');
    END IF;
  END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────
-- L'exception métier : un compte bancaire SANS opération se supprime (244 T04).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_fermer_liens_banque_vide()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM tenants WHERE id = OLD.tenant_id) THEN
    RETURN OLD;   -- cascade d'une société : rien à fermer, tout part
  END IF;
  IF NOT EXISTS (SELECT 1 FROM bank_transactions
                  WHERE account_id = OLD.id AND tenant_id = OLD.tenant_id) THEN
    PERFORM chain_liens_fermer(OLD.tenant_id, 'bank_accounts', OLD.id, 'rompu',
      format('Compte bancaire « %s » supprimé sans aucune opération (règle 244) : ses liens vers son journal et son compte comptable sont fermés.', OLD.name));
  END IF;
  RETURN OLD;
END $fn$;

COMMENT ON FUNCTION public.chain_fermer_liens_banque_vide() IS
  '453 : compagnon BEFORE DELETE de bank_accounts. Un compte sans opération se supprime (244) : ses liens de chaînage sont FERMÉS (rompu) avant que la garde zz_garde_p5_suppression ne les voie.';

REVOKE ALL ON FUNCTION public.chain_fermer_liens_banque_vide() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS zz_garde_p5_0_banque_vide ON public.bank_accounts;
CREATE TRIGGER zz_garde_p5_0_banque_vide BEFORE DELETE ON public.bank_accounts
  FOR EACH ROW EXECUTE FUNCTION public.chain_fermer_liens_banque_vide();

