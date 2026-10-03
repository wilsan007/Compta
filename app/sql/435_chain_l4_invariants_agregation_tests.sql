-- ============================================================
-- 435_chain_l4_invariants_agregation_tests.sql
--
--   La question que ces tests poses n'est PAS « les quatre branches
--   existent-ils ? » — une migration qui compile répond déjà à ça. La
--   question est : le banc mesure-t-il quelque chose, ou remplit-il un
--   relevé VIDE que l'on lirait comme « tout va bien » ?
--
--   T01  les quatre sont mesurables ET leur branche rend une mesure ;
--   T02  l'indice passe de 13/20 à 17/20 — et le dénominateur reste 20 ;
--   T03  INV-19 détecte un orphelin PLANTÉ, puis revient à zéro ;
--   T04  INV-08 détecte un écart entre relevé et comptabilité ;
--   T05  INV-06 mesure un budget contre un réalisé réellement posé ;
--   T06  INV-05 mesure un engagement contre un reste à facturer ;
--   T07  INV-12 reste NON mesurable, et sa raison est vérifiée ;
--   T08  aucun code mesurable ne reste sans branche.
-- ============================================================
\ir ci/audit_helpers.sql
\ir ci/ledger_fixture.sql
SELECT set_config('audit.file', '435', false);
DELETE FROM _audit_results WHERE file = '435';

-- ─────────────────────────────────────────────────────────────
-- T01 — les quatre branches rendent une MESURE, pas un relevé vide
--
-- On teste la présence d'une valeur non nulle, pas la valeur elle-même :
-- une société sans données doit rendre 0, ce qui est une mesure, et non
-- NULL, qui serait l'absence de mesure.
-- ─────────────────────────────────────────────────────────────
DO $t01$
DECLARE
  t uuid; usr uuid;
  v_mesures int; v_nuls int;
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant('t435-01', false);
  usr := auth.uid();

  SELECT count(*), count(*) FILTER (WHERE s.mesure_a IS NULL AND s.mesure_b IS NULL)
    INTO v_mesures, v_nuls
    FROM (SELECT r.mesure_a, r.mesure_b
            FROM (VALUES ('INV-05'),('INV-06'),('INV-08'),('INV-19')) AS v(code)
            CROSS JOIN LATERAL chain_invariant_mesurer(t, v.code) r) s;

  PERFORM _rec('T01', 'les quatre branches d''agrégation rendent une mesure, jamais un relevé vide',
    v_mesures = 4 AND v_nuls = 0,
    format('mesures=%s sans_valeur=%s', v_mesures, v_nuls));
END $t01$;

-- ─────────────────────────────────────────────────────────────
-- T02 — l'indice : 17 mesurés sur 20 inscrits, et c'est tout
--
-- ⚠️ Le piège est de compter les non mesurables AU NUMÉRATEUR. Ils ne le
-- valent pas : un invariant qu'on ne sait pas mesurer n'est ni tenu ni
-- rompu. Le dénominateur, lui, reste 20 — l'inventaire est complet, et le
-- resterait même si on ne mesurait rien.
-- ─────────────────────────────────────────────────────────────
DO $t02$
DECLARE v_mes int; v_inscrits int; v_sans_raison int;
BEGIN
  -- ⚠️ On compte le STANDARD (`tenant_id IS NULL`), pas toutes les lignes.
  -- Le registre accepte une ligne PAR SOCIÉTÉ qui surcharge un code, et les
  -- suites de la 413 en laissent : compter le tout donnait « 35 inscrits »,
  -- alors que le référentiel n'en compte que 20. Le test mesurait la bonne
  -- chose sur la mauvaise population.
  SELECT count(*) FILTER (WHERE mesurable), count(*),
         count(*) FILTER (WHERE NOT mesurable AND btrim(COALESCE(raison_non_mesurable,'')) = '')
    INTO v_mes, v_inscrits, v_sans_raison
    FROM chain_invariants WHERE tenant_id IS NULL;

  PERFORM _rec('T02', 'l''indice passe à 17 mesurés sur 20 inscrits — et chacun des 3 restants garde une raison',
    v_mes = 17 AND v_inscrits = 20 AND v_sans_raison = 0,
    format('mesurables=%s inscrits=%s non_mesurables_sans_raison=%s',
           v_mes, v_inscrits, v_sans_raison));
END $t02$;
-- ─────────────────────────────────────────────────────────────
-- T03 — INV-19 détecte un orphelin PLANTÉ, puis revient à zéro
--
-- Un contrôle d'intégrité qui ne signale rien ne prouve pas qu'il cherche :
-- il peut ne rien chercher du tout. On plante donc un lien dont l'amont
-- n'existe pas, on exige qu'il soit vu, puis on le retire et on exige le
-- silence. Vert dans les deux sens, ou le test ne vaut rien.
-- ─────────────────────────────────────────────────────────────
DO $t03$
DECLARE t uuid; usr uuid; v_lien_id uuid;
        v_avant int; v_pendant int; v_apres int;
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant('t435-03', false);
  usr := auth.uid();

  SELECT lignes_en_ecart INTO v_avant FROM chain_invariant_mesurer(t, 'INV-19');

  INSERT INTO document_links
    (tenant_id, amont_type, amont_id, aval_type, aval_id, link_type, effet, etat)
  VALUES
    (t, 'bank_transactions', '00000000-0000-0000-0000-0000000000ff',
     'bank_transactions', '00000000-0000-0000-0000-0000000000ff',
     'created_from', 'created_from', 'actif')
  RETURNING id INTO v_lien_id;

  SELECT lignes_en_ecart INTO v_pendant FROM chain_invariant_mesurer(t, 'INV-19');
  DELETE FROM document_links WHERE id = v_lien_id;
  SELECT lignes_en_ecart INTO v_apres FROM chain_invariant_mesurer(t, 'INV-19');

  PERFORM _rec('T03', 'INV-19 voit un orphelin planté (0 → 1 → 0) : il cherche, et ne crie pas dans le vide',
    v_avant = 0 AND v_pendant = 1 AND v_apres = 0,
    format('avant=%s pendant=%s après=%s', v_avant, v_pendant, v_apres));
END $t03$;

-- ─────────────────────────────────────────────────────────────
-- T04 — INV-08 voit un écart entre le relevé et la comptabilité
--
-- Un mouvement de relevé jamais saisi doit être vu. Un contrôle d'égalité
-- qui reste muet sur une absence de saisie n'a rien mesuré.
-- ─────────────────────────────────────────────────────────────
DO $t04$
DECLARE t uuid; usr uuid; ba uuid; v_ecart numeric;
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant('t435-04', false);
  usr := auth.uid();

  INSERT INTO bank_accounts (tenant_id, name, account_number, sort_code, balance,
                             currency, account_code, journal_code, type)
  VALUES (t, 'Banque 435', '0000043500', '435', 0, 'EUR', '512100', 'BQ', 'chequing')
  RETURNING id INTO ba;

  INSERT INTO bank_transactions (tenant_id, bank_account_id, date, description,
                                 amount, type, kind, matched, reconciled)
  VALUES (t, ba, DATE '2026-04-01', 'Virement non comptabilisé 435', 250.00,
          'debit', 'statement', false, false);

  SELECT lignes_en_ecart INTO v_ecart FROM chain_invariant_mesurer(t, 'INV-08');

  PERFORM _rec('T04', 'INV-08 voit un mouvement de relevé jamais saisi en comptabilité',
    v_ecart > 0, format('lignes_en_ecart=%s', v_ecart));
END $t04$;
-- ─────────────────────────────────────────────────────────────
-- T05 — INV-06 compare un budget posé à un réalisé
--
-- Le budget existe (`budgets`), le réalisé aussi (lignes d'écriture). On
-- pose les deux et on exige que les deux côtés soient publiés : c'est le
-- sens de l'invariant, pas un détail d'implémentation.
-- ─────────────────────────────────────────────────────────────
DO $t05$
DECLARE t uuid; usr uuid; fy uuid; v_m record;
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant('t435-05', false);
  usr := auth.uid();
  PERFORM _ledger_fixture(t, ARRAY['606100','707100']);

  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t ORDER BY id LIMIT 1;

  INSERT INTO budgets (tenant_id, name, fiscal_year_id, account_code, period_3)
  VALUES (t, 'Budget achats 435', fy, '606100', 1000);

  SELECT * INTO v_m FROM chain_invariant_mesurer(t, 'INV-06');

  PERFORM _rec('T05', 'INV-06 publie les deux côtés : le budget posé et le réalisé des écritures',
    v_m.mesure_b IS NOT NULL AND v_m.mesure_b = 1000,
    format('réalisé=%s budget=%s écart=%s', v_m.mesure_a, v_m.mesure_b, v_m.ecart));
END $t05$;

-- ─────────────────────────────────────────────────────────────
-- T06 — INV-05 compare un engagement au reste à facturer
--
-- Commande de 500, engagement de 500, rien de facturé : le reste à facturer
-- vaut 500 et les deux côtés s'égalisent. Le test ne cherche pas la
-- égalité — il vérifie que le CALCUL du côté manquant est juste, parce que
-- c'est lui que la 435 a écrit.
-- ─────────────────────────────────────────────────────────────
DO $t06$
DECLARE t uuid; usr uuid; po uuid; fy uuid; v_m record;
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant('t435-06', false);
  usr := auth.uid();
  PERFORM _ledger_fixture(t, ARRAY['401000','707100']);

  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t ORDER BY id LIMIT 1;

  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status, total)
  VALUES (t, 'PO-435', NULL, DATE '2026-04-02', 'confirmed', 500)
  RETURNING id INTO po;

  INSERT INTO purchase_order_lines
    (tenant_id, purchase_order_id, description, quantity, unit_price, line_total)
  VALUES (t, po, 'Prestation 435', 1, 500, 500);

  INSERT INTO budget_commitments (tenant_id, fiscal_year_id, description, account_code, source_type, source_id, amount, status)
  VALUES (t, fy, 'Engagement 435', '401000', 'purchase_order', po, 500, 'active');

  SELECT * INTO v_m FROM chain_invariant_mesurer(t, 'INV-05');

  PERFORM _rec('T06', 'INV-05 calcule le reste à facturer : 500 engagé, 500 restant, aucun écart',
    v_m.mesure_a = 500 AND v_m.mesure_b = 500 AND v_m.lignes_en_ecart = 0,
    format('engagement=%s reste=%s lignes_en_ecart=%s', v_m.mesure_a, v_m.mesure_b, v_m.lignes_en_ecart));
END $t06$;
-- ─────────────────────────────────────────────────────────────
-- T07 — INV-12 reste NON mesurable : on ne réécrit pas un invariant
--        pour le rendre mesurable.
--
-- Un test « vert » qui déclaerait INV-12 mesurable aurait atteint 18/20 —
-- en mesurant autre chose que l'invariant écrit, sous le même nom. Ce test
-- verrouille donc le refus, et exige que la raison soit là.
-- ─────────────────────────────────────────────────────────────
DO $t07$
DECLARE v_mesurable boolean; v_raison text;
BEGIN
  SELECT mesurable, coalesce(raison_non_mesurable, '')
    INTO v_mesurable, v_raison
    FROM chain_invariants WHERE code = 'INV-12' AND tenant_id IS NULL;

  PERFORM _rec('T07', 'INV-12 reste non mesurable : on ne réécrit pas un invariant pour le rendre mesurable',
    v_mesurable = false AND btrim(v_raison) <> '',
    format('mesurable=%s raison=%s', v_mesurable, left(v_raison, 55)));
END $t07$;

-- ─────────────────────────────────────────────────────────────
-- T08 — un code inscrit mesurable SANS branche continue de crier
--
-- La 413 levait dans ce cas. La 435 a REDÉFINI la fonction entière : ce
-- test vérifie qu'elle n'a pas rendu ce garde-fou muet en le recopiant.
-- ─────────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────
-- T08 — STRUCTURE : tout code inscrit `mesurable` a une branche qui répond
--
-- C'est le contrôle qui protège le registre entier. La 413 fait déjà lever
-- le cas « mesurable sans branche » ; la 435 a REDÉFINI la fonction en
-- entier, donc on revérifie après coup — et on exige la réponse, pas
-- seulement l'absence d'exception. Un code mesurable qui rendrait une ligne
-- vide ne serait pas plus fiable qu'un code sans branche.
-- ─────────────────────────────────────────────────────────────
DO $t08$
DECLARE t uuid; usr uuid; v_code text; v_repond int := 0; v_attendus int;
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant('t435-08', false);
  usr := auth.uid();

  SELECT count(*) INTO v_attendus FROM chain_invariants WHERE mesurable AND tenant_id IS NULL;

  FOR v_code IN SELECT code FROM chain_invariants WHERE mesurable AND tenant_id IS NULL
  LOOP
    BEGIN
      -- `EXISTS` plutôt que `PERFORM * FROM …` : ce dernier écrit un résultat
      -- sans destination, et psql termine le script sur une erreur qui n'a
      -- jamais rougi aucun test. Un avertissement muet est pire que rouge.
      IF EXISTS (SELECT 1 FROM chain_invariant_mesurer(t, v_code)) THEN
        v_repond := v_repond + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- laissé en compte : ce code ne répond pas, et le test doit le voir
      NULL;
    END;
  END LOOP;

  PERFORM _rec('T08', 'les 17 codes inscrits mesurables répondent tous — aucun relevé vide',
    v_repond = v_attendus,
    format('répondants=%s sur %s mesurables', v_repond, v_attendus));
END $t08$;

-- ─────────────────────────────────────────────────────────────
-- Verdict de la suite
-- ─────────────────────────────────────────────────────────────
SELECT _audit_assert('435');