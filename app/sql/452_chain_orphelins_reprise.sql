-- ═══════════════════════════════════════════════════════════════════════════
-- 452 — Partie 5 : les liens ORPHELINS déjà présents sont fermés, pas effacés
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Avant la garde (453), un document relié pouvait être supprimé : son lien
-- restait « actif » vers rien (mesuré le 02/10 : compte bancaire, règlement
-- client, commande confirmée, réservation, journal et compte de la banque).
--
-- On ne SUPPRIME pas ces liens : ils sont l'historique de ce qui s'est produit.
-- On les FERME (`etat = 'rompu'`) avec un motif daté — exactement ce que fait
-- le cycle de vie du lien (402) quand un effet est retiré.
--
-- `chain_fermer_orphelins(société)` est rejouable : un second appel rend 0.
-- Elle sert à la reprise ci-dessous, et à toute base où des orphelins seraient
-- découverts plus tard (copie de production, base de développement).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.chain_fermer_orphelins(p_tenant uuid DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  r     record;
  v_n   integer := 0;
BEGIN
  FOR r IN
    SELECT l.id, l.tenant_id, l.amont_type, l.amont_id, l.amont_ligne_id,
           l.aval_type, l.aval_id
    FROM document_links l
    WHERE l.etat = 'actif'
      AND (p_tenant IS NULL OR l.tenant_id = p_tenant)
  LOOP
    IF NOT chain_document_existe(r.tenant_id, r.amont_type, r.amont_id)
       OR NOT chain_document_existe(r.tenant_id, r.aval_type, r.aval_id)
       OR (r.amont_ligne_id IS NOT NULL
           AND NOT chain_document_existe(r.tenant_id, r.amont_type, r.amont_ligne_id, true))
    THEN
      UPDATE document_links
         SET etat     = 'rompu',
             ferme_le = now(),
             motif    = '452 — reprise : le document amont ou aval (ou la ligne amont) a été supprimé avant la garde de suppression de la Partie 5. Lien orphelin constaté et fermé, pas effacé.'
       WHERE id = r.id;
      v_n := v_n + 1;
    END IF;
  END LOOP;
  RETURN v_n;
END $fn$;

COMMENT ON FUNCTION public.chain_fermer_orphelins(uuid) IS
  '452 : ferme (rompu, motif daté) tout lien ACTIF dont l''amont, l''aval ou la ligne amont n''existe plus. NULL = toutes les sociétés. Rend le nombre de liens fermés. Rejouable.';

REVOKE ALL ON FUNCTION public.chain_fermer_orphelins(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chain_fermer_orphelins(uuid) TO service_role;

-- La reprise elle-même.
DO $$
DECLARE v_n integer;
BEGIN
  v_n := public.chain_fermer_orphelins(NULL);
  RAISE NOTICE '452 : % lien(s) orphelin(s) fermé(s) (rompu).', v_n;
END $$;
