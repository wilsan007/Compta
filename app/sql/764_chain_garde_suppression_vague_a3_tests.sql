-- ═══════════════════════════════════════════════════════════════════════════
-- 764_chain_garde_suppression_vague_a3_tests.sql — la garde sur les types A3
-- ═══════════════════════════════════════════════════════════════════════════
-- Ce que cette suite ÉPROUVE, et pourquoi ces scénarios-là :
--   T01  NOMINAL : un DEVIS TRANSFORMÉ — type `quotes`, inscrit par `493`, l'un
--        des treize qui n'avaient AUCUNE garde avant ce fichier — ne se
--        supprime plus : la garde refuse (CHAIN_DELETE_REFUSED), le refus porte
--        le contrat complet de `453` (DETAIL JSON + HINT en français), et rien
--        n'a bougé ;
--   T02  LE SEUL REFUS QUI COMPTE : une fois le lien FERMÉ, la même suppression
--        PASSE — la garde ne regarde que les liens ACTIFS ;
--   T03  LA COUVERTURE (l'invariant qui remplace le compte GELÉ de `450`) :
--        100 % des types du registre ET de leurs tables de lignes portent leur
--        garde, et le compte tombe juste ;
--   T04  LA GARDE PAR LIGNE : une LIGNE de devis tenue par un lien actif ne se
--        supprime pas non plus (mode « ligne » de `453`), et se supprime le lien
--        fermé ;
--   T05  NON-RÉGRESSION : un brouillon SANS lien se supprime — la garde ne
--        paralyse pas le travail normal ;
--   T06  NON-RÉGRESSION : la suppression d'une SOCIÉTÉ entière passe (cascade) :
--        une garde qui bloque la cascade rendrait la suppression de société
--        impossible, et c'est le seul chemin par lequel un client part.
--
-- ⚠️ La fermeture de lien de T02/T04 est faite à la main (`UPDATE … 'rompu'`) :
-- aucun chemin d'annulation n'existe pour un devis. Ce que ces scénarios
-- mesurent est que la garde ne regarde que l'ÉTAT du lien — pas d'où vient la
-- fermeture.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '764', false);
DELETE FROM _audit_results WHERE file = '764';

-- ─────────────────────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier
-- ─────────────────────────────────────────────────────────────────────────────

-- Tente une suppression SOUS LE RÔLE PROPRIÉTAIRE : c'est la seule façon de
-- mesurer LA GARDE elle-même et non une politique RLS (même technique que la
-- suite de la Partie 5). Rend 'supprimé', 'refusé (chaîne)' ou 'refusé : …'.
DROP FUNCTION IF EXISTS _g764_supprimer(text, uuid);
CREATE OR REPLACE FUNCTION _g764_supprimer(p_table text, p_id uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE n integer;
BEGIN
  EXECUTE format('DELETE FROM %I WHERE id = $1', p_table) USING p_id;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN CASE WHEN n = 1 THEN 'supprimé' ELSE 'aucune ligne' END;
EXCEPTION
  WHEN foreign_key_violation THEN
    RETURN CASE WHEN SQLERRM = 'CHAIN_DELETE_REFUSED' THEN 'refusé (chaîne)' ELSE 'refusé : ' || SQLERRM END;
  WHEN OTHERS THEN
    RETURN 'refusé : ' || SQLERRM;
END $$;

-- Un devis accepté TRANSFORMÉ en commande par le maillon de `493` — le vrai
-- chemin, pas une écriture directe : le lien `quotes → sales_orders` est celui
-- qu'un utilisateur pose, et c'est donc lui qui doit tenir la garde.
DROP FUNCTION IF EXISTS _g764_devis_lie(uuid, text);
CREATE OR REPLACE FUNCTION _g764_devis_lie(p_t uuid, p_nom text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE c uuid; q uuid;
BEGIN
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (p_t, 'Client ' || p_nom, 'C' || p_nom) RETURNING id INTO c;
  INSERT INTO quotes (tenant_id, number, customer_id, customer_name, date, expiry_date,
                      status, subtotal, vat_total, total)
    VALUES (p_t, 'D-' || p_nom, c, 'Client ' || p_nom, '2026-03-01', '2026-03-31',
            'accepted', 1000, 200, 1200)
    RETURNING id INTO q;
  INSERT INTO quote_lines (tenant_id, quote_id, description, quantity, unit_price,
                           vat_rate, total, vat_total, line_order)
    VALUES (p_t, q, 'Prestation', 1, 1000, 20, 1000, 200, 0);
  PERFORM convert_quote_to_order(q);
  RETURN q;
END $$;
-- ── T01 — LE NOMINAL : un devis TRANSFORMÉ ne se supprime plus ─────────────
DO $$
DECLARE t uuid; q uuid; n int; v_detail text; v_hint text; v_code text := '(aucun refus)';
BEGIN
  t := _mk_tenant('G764A');
  PERFORM _as_user();
  q := _g764_devis_lie(t, 'G764A');
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'quotes' AND amont_id = q
     AND effet = 'sale.quote.to_order' AND etat = 'actif';
  PERFORM _rec('T01a', 'le devis transformé porte son lien actif (effet sale.quote.to_order)',
    n = 1, 'liens actifs = ' || n);

  BEGIN
    EXECUTE format('DELETE FROM quotes WHERE id = %L', q);
    v_code := '(supprimé !)';
  EXCEPTION
    WHEN foreign_key_violation THEN
      v_code := SQLERRM;
      GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL, v_hint = PG_EXCEPTION_HINT;
    WHEN OTHERS THEN
      v_code := 'autre : ' || SQLSTATE || ' ' || SQLERRM;
  END;

  PERFORM _rec('T01b', 'la suppression est REFUSÉE par la garde (message CHAIN_DELETE_REFUSED)',
    v_code = 'CHAIN_DELETE_REFUSED', 'code = ' || v_code);
  PERFORM _rec('T01c', 'le refus NOMME le lien : DETAIL JSON avec l''effet et l''aval',
    COALESCE(v_detail, '') LIKE '%sale.quote.to_order%' AND COALESCE(v_detail, '') LIKE '%sales_orders%',
    'DETAIL = ' || COALESCE(v_detail, '(vide)'));
  PERFORM _rec('T01d', 'le refus dit QUOI FAIRE (HINT en français : le chemin d''annulation)',
    COALESCE(v_hint, '') LIKE 'Suppression refusée%', 'HINT = ' || COALESCE(v_hint, '(vide)'));

  SELECT count(*) INTO n FROM quotes WHERE id = q AND tenant_id = t;
  PERFORM _rec('T01e', 'rien n''a bougé : le devis existe toujours', n = 1, 'devis trouvés = ' || n);
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'quotes' AND amont_id = q AND etat = 'actif';
  PERFORM _rec('T01f', 'rien n''a bougé : le lien est toujours ACTIF (le refus ne ferme rien)',
    n = 1, 'liens actifs = ' || n);
END $$;

-- ── T02 — LE SEUL REFUS QUI COMPTE : la garde ne tient que l'ACTIF ────────
DO $$
DECLARE t uuid; q uuid; v1 text; v2 text; n int;
BEGIN
  t := _mk_tenant('G764B');
  PERFORM _as_user();
  q := _g764_devis_lie(t, 'G764B');
  PERFORM set_config('role', 'none', true);

  v1 := _g764_supprimer('quotes', q);
  UPDATE document_links SET etat = 'rompu', ferme_le = now(), motif = 'G764 : lien fermé à la main'
   WHERE tenant_id = t AND amont_type = 'quotes' AND amont_id = q AND etat = 'actif';
  v2 := _g764_supprimer('quotes', q);
  SELECT count(*) INTO n FROM quotes WHERE id = q;
  PERFORM _rec('T02a', 'tant que le lien est ACTIF, la suppression est refusée', v1 = 'refusé (chaîne)', 'verdict = ' || v1);
  PERFORM _rec('T02b', 'une fois le lien FERMÉ, la même suppression PASSE, et le devis a bien disparu',
    v2 = 'supprimé' AND n = 0, 'verdict = ' || v2 || ', devis restants = ' || n);
END $$;


-- ── T03 — LA COUVERTURE : l'invariant qui remplace le compte GELÉ de 450 ───
-- C'est le scénario né du défaut : `450` T11 assertait « = 32 » et T01 « = 27 ».
-- Un compte figé se périmètre tout seul ; ici on mesure la COUVERTURE (aucune
-- table du registre sans garde) et on PUBLIE les nombres au lieu de les geler.
DO $$
DECLARE v_sans text; v_attendu int; v_pose int;
BEGIN
  SELECT string_agg(x.tbl, ', ' ORDER BY x.tbl) INTO v_sans
  FROM chain_document_types c
  CROSS JOIN LATERAL (VALUES (c.table_name, 'zz_garde_p5_suppression'),
                             (c.ligne_table, 'zz_garde_p5_suppression_ligne')) x(tbl, trig)
  WHERE x.tbl IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM pg_trigger g
                     WHERE g.tgrelid = to_regclass('public.' || x.tbl)
                       AND g.tgname = x.trig AND g.tgenabled <> 'D');

  SELECT count(*) + (SELECT count(*) FROM chain_document_types WHERE ligne_table IS NOT NULL)
    INTO v_attendu FROM chain_document_types;
  SELECT count(*) INTO v_pose FROM pg_trigger WHERE tgname LIKE 'zz_garde_p5_suppression%';

  PERFORM _rec('T03', 'LA COUVERTURE : tout type du registre et toute table de lignes porte sa garde (aucun compte gelé)',
    v_sans IS NULL AND v_pose = v_attendu,
    format('sans garde = %s ; gardes posées = %s pour %s table(s) attendue(s)',
           COALESCE(v_sans, 'aucune'), v_pose, v_attendu));
END $$;

-- ── T04 — LA GARDE PAR LIGNE : une LIGNE de devis tenue ne part pas ───────
DO $$
DECLARE t uuid; c uuid; q uuid; l uuid; so uuid; v1 text; v2 text; n int;
BEGIN
  t := _mk_tenant('G764D');
  PERFORM _as_user();
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client G764D', 'CG764D') RETURNING id INTO c;
  INSERT INTO quotes (tenant_id, number, customer_id, customer_name, date, expiry_date, status)
    VALUES (t, 'D-G764D', c, 'Client G764D', '2026-03-01', '2026-03-31', 'draft') RETURNING id INTO q;
  INSERT INTO quote_lines (tenant_id, quote_id, description, quantity, unit_price, vat_rate, total, vat_total, line_order)
    VALUES (t, q, 'Ligne tenue', 1, 500, 20, 500, 100, 0) RETURNING id INTO l;
  INSERT INTO sales_orders (tenant_id, number, status) VALUES (t, 'BC-G764D', 'draft') RETURNING id INTO so;

  -- Le lien PAR LIGNE (mode « ligne » de la garde) : c'est la LIGNE qui est
  -- l'amont du lien, pas le devis.
  PERFORM set_config('role', 'none', true);
  PERFORM link_documents(t, 'quotes', q, 'sales_orders', so, 'p5.g764.ligne', 'created_from',
                         '{}'::jsonb, l, NULL);

  v1 := _g764_supprimer('quote_lines', l);
  UPDATE document_links SET etat = 'rompu', ferme_le = now(), motif = 'G764 : lien de ligne fermé'
   WHERE tenant_id = t AND amont_type = 'quotes' AND amont_ligne_id = l AND etat = 'actif';
  v2 := _g764_supprimer('quote_lines', l);
  SELECT count(*) INTO n FROM quote_lines WHERE id = l;
  PERFORM _rec('T04a', 'une LIGNE tenue par un lien ACTIF ne se supprime pas (mode « ligne » de 453)',
    v1 = 'refusé (chaîne)', 'verdict = ' || v1);
  PERFORM _rec('T04b', 'le lien de ligne fermé, la même ligne se supprime',
    v2 = 'supprimé' AND n = 0, 'verdict = ' || v2 || ', lignes restantes = ' || n);
END $$;

-- ── T05 — NON-RÉGRESSION : un brouillon SANS lien se supprime ─────────────
DO $$
DECLARE t uuid; c uuid; q uuid; v text; n int;
BEGIN
  t := _mk_tenant('G764E');
  PERFORM _as_user();
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client G764E', 'CG764E') RETURNING id INTO c;
  INSERT INTO quotes (tenant_id, number, customer_id, customer_name, date, expiry_date, status)
    VALUES (t, 'D-G764E', c, 'Client G764E', '2026-04-01', '2026-04-30', 'draft') RETURNING id INTO q;
  PERFORM set_config('role', 'none', true);

  v := _g764_supprimer('quotes', q);
  SELECT count(*) INTO n FROM quotes WHERE id = q;
  PERFORM _rec('T05', 'un brouillon SANS lien se supprime : la garde ne paralyse pas le travail normal',
    v = 'supprimé' AND n = 0, format('verdict = %s, devis restants = %s', v, n));
END $$;

-- ── T06 — NON-RÉGRESSION : une SOCIÉTÉ entière part, liens compris ────────
DO $$
DECLARE t uuid; q uuid; v text := 'supprimée'; n_liens int; n_devis int;
BEGIN
  t := _mk_tenant('G764F');
  PERFORM _as_user();
  q := _g764_devis_lie(t, 'G764F');
  PERFORM set_config('role', 'none', true);
  BEGIN
    DELETE FROM tenants WHERE id = t;
  EXCEPTION WHEN OTHERS THEN v := 'refusée : ' || SQLERRM; END;
  SELECT count(*) INTO n_liens FROM document_links WHERE tenant_id = t;
  SELECT count(*) INTO n_devis FROM quotes WHERE tenant_id = t;
  PERFORM _rec('T06', 'supprimer une SOCIÉTÉ entière passe : la garde laisse la cascade (liens et documents ensemble)',
    v = 'supprimée' AND n_liens = 0 AND n_devis = 0,
    format('société = %s, liens restants = %s, devis restants = %s', v, n_liens, n_devis));
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('764');


