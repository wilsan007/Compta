-- ============================================================
-- 434_chain_banc_epreuves_tests.sql — les huit épreuves sont JOUÉES,
--   et le rapport est daté
--
--   T01  le moteur produit 8 verdicts DATÉS par maillon — « un chaînage
--        déclaré = 8 verdicts datés » (preuve attendue de la tâche 3.4) ;
--   T02  D1 rejue : le 2ᵉ appel n'ajoute ni lien ni trace ;
--   T03  D4 annulation : le lien se ferme, plus de lien actif ;
--   T04  D6 retour arrière : après annulation, rien ne subsiste ;
--   T05  D7 volume : le p95 est mesuré et rapporté ;
--   T06  D8 isolation : aucun lien visible depuis une autre société ;
--   T07  D2, D3 et D5 sont NOMMÉES non jouées AVEC leur raison — jamais
--        vertes par défaut. C'est le cœur de la méthode : un banc qui
--        déclare tenu ce qu'il n'a pas éprouvé ne prouve rien ;
--   T08  STRUCTURE : la fonction existe, ses huit branches sont
--        présentes, et le rapport garde l'historique des passages.
-- ============================================================
\ir ci/audit_helpers.sql
\ir ci/ledger_fixture.sql
SELECT set_config('audit.file', '434', false);
DELETE FROM _audit_results WHERE file = '434';

-- ─────────────────────────────────────────────────────────────
-- Outillage : une société, une banque, et VINGT lignes de relevé
-- distinctes.
--
-- Pourquoi vingt et pas une : D7 mesure le chemin NOMINAL. Sur une seule
-- ligne, dès le deuxième tour le maillon refuse, et le banc mesurerait le
-- coût d'un refus en l'appelant une performance. Le décor doit donc fournir
-- ce que l'épreuve prétend mesurer.
-- ─────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS _l434_banque(text);
CREATE OR REPLACE FUNCTION _l434_banque(p_nom text, OUT t uuid, OUT ba uuid, OUT tx uuid, OUT usr uuid)
LANGUAGE plpgsql AS $fn$
DECLARE
  v_txs  uuid[] := '{}';
  v_one  uuid;
  i      int;
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant(p_nom, false);
  usr := auth.uid();
  PERFORM _ledger_fixture(t, ARRAY['512100','627000','768000']);

  INSERT INTO journals (tenant_id, code, name, type, status, next_number)
  VALUES (t, 'BQ', 'Banque', 'bank', 'active', 1) ON CONFLICT DO NOTHING;

  -- ⚠️ Vingt lignes de relevé, donc vingt écritures à numéroter. Le décor
  -- laisse le compteur banque à 1, alors que la comptabilité générale l'a déjà
  -- utilisé : on tombait sur `uniq_journal_entry_number_tenant`, et deux
  -- scénarios entiers disparaissaient du rapport — non parce qu'ils avaient
  -- échoué, mais parce que le décor les avait empêchés de tourner. Un test
  -- qu'on n'a pas pu faire n'est pas un test passé.
  UPDATE journals SET next_number = 5000 WHERE tenant_id = t AND code = 'BQ';

  INSERT INTO bank_accounts (tenant_id, name, account_number, sort_code, balance,
                             currency, account_code, journal_code, type)
  VALUES (t, 'Compte ' || p_nom, '00000012345', '123', 0, 'EUR', '512100', 'BQ', 'chequing')
  RETURNING id INTO ba;

  -- Vingt lignes RÉELLEMENT distinctes : chacune a son montant et sa date,
  -- pour qu'aucune ne puisse être confondue avec une autre.
  FOR i IN 1..20 LOOP
    INSERT INTO bank_transactions (tenant_id, bank_account_id, date, description,
                                   amount, type, kind, matched, reconciled)
    VALUES (t, ba, DATE '2026-03-01' + i, 'Frais ' || p_nom || ' n°' || i,
            10.00 * i, 'debit', 'statement', false, false)
    RETURNING id INTO v_one;
    v_txs := v_txs || v_one;
  END LOOP;
  tx := v_txs[1];

  -- On DÉCRIT le maillon dans le catalogue : gabarit, gestes dédiés, série.
  -- C'est ainsi que le moteur apprend à l'appeler sans rien savoir du métier —
  -- et c'est aussi pourquoi il ne peut rien inventer quand un geste manque.
  UPDATE chain_banc_maillons
     SET appat             = 'SELECT public.post_bank_statement_line(%s, NULL, ''Banc 434'')',
         appat_annul       = 'SELECT public.unreconcile_bank_statement_line(%s)',
         appat_reouverture = 'SELECT public.post_bank_statement_line(%s, NULL, ''Banc 434'')',
         arg_valeurs       = jsonb_build_array(tx::text),
         arg_types         = ARRAY['uuid'],
         arg_series        = to_jsonb(ARRAY(
           -- On EXCLUT la première ligne : c'est le stimulus de D1, D4 et D5.
           -- La réouverture de D5 la laisse pointée, et D7 la rejouerait alors
           -- sur une ligne déjà comptabilisée — le banc mesurerait un doublon
           -- rejeté au lieu du chemin nominal. Les dix-neuf autres suffisent
           -- largement à un p95.
           SELECT jsonb_build_array(x::text) FROM unnest(v_txs) WITH ORDINALITY AS u(x, n)
           WHERE n > 1))
   WHERE code = 'releve.comptabilise';
END $fn$;

-- Remet le contexte d'une société (identité ET société : `current_tenant_id()`
-- exige que `auth.uid()` en soit membre — mesuré en 3.2, T09).
DROP FUNCTION IF EXISTS _l434_revenir(uuid, uuid);
CREATE OR REPLACE FUNCTION _l434_revenir(p_t uuid, p_usr uuid)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_usr::text, false);
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', p_usr, 'role', 'authenticated')::text, false);
  PERFORM set_config('app.active_tenant_id', p_t::text, false);
END $fn$;

-- Un verdict du rapport, pour un (maillon, épreuve).
DROP FUNCTION IF EXISTS _l434_verdict(text, text);
CREATE OR REPLACE FUNCTION _l434_verdict(p_code text, p_ep text)
RETURNS TABLE (verdict text, obtenu text, raison text, joue_le timestamptz)
LANGUAGE sql STABLE AS $fn$
  -- ⚠️ La vue nomme la colonne `dernier_passage`, PAS `joue_le` : elle expose
  -- le dernier passage de l'épreuve, pas l'horodatage brut du relevé. Écrire
  -- `joue_le` ici échouait — et l'échec était silencieux dans le sens où la
  -- suite continuait, sans qu'on sache que l'outillage était faux.
  SELECT r.verdict, r.obtenu, r.raison, r.dernier_passage
  FROM chain_banc_rapport r
  WHERE r.code = p_code AND r.epreuve = p_ep
$fn$;
-- ─────────────────────────────────────────────────────────────
-- T01 — le moteur produit HUIT verdicts DATÉS par maillon
--    C'est la preuve attendue de la tâche 3.4. Une épreuve jamais jouée
--    reste VISIBLE comme telle : l'absence est publiée.
-- ─────────────────────────────────────────────────────────────
DO $t01$
DECLARE t uuid; ba uuid; tx uuid; usr uuid; n int; dates_ok boolean; v_jeu int;
BEGIN
  SELECT * FROM _l434_banque('t01') INTO t, ba, tx, usr;

  SELECT count(*) INTO n FROM chain_banc_lancer(t, 'releve.comptabilise');

  SELECT count(*) INTO v_jeu FROM chain_banc_rapport
   WHERE code = 'releve.comptabilise';
  -- La vue expose `dernier_passage` : c'est la date du dernier passage,
  -- pas un horodatage par ligne. On vérifie qu'il n'y a AUCUN verdict
  -- « non daté », pas qu'une colonne homonyme existe.
  SELECT bool_and(r.dernier_passage IS NOT NULL) INTO dates_ok FROM chain_banc_rapport r
   WHERE r.code = 'releve.comptabilise';

  PERFORM _rec('T01', 'le moteur rend 8 verdicts DATÉS par maillon (un chaînage déclaré = 8 verdicts datés)',
    n = 1 AND v_jeu = 8 AND dates_ok,
    format('maillons=%s lignes_de_rapport=%s toutes_datées=%s', n, v_jeu, COALESCE(dates_ok,false)));
END $t01$;

-- ─────────────────────────────────────────────────────────────
-- T02 — D1 rejeu : le 2ᵉ appel n'ajoute NI lien NI trace
-- ─────────────────────────────────────────────────────────────
DO $t02$
DECLARE t uuid; ba uuid; tx uuid; usr uuid; r record;
BEGIN
  SELECT * FROM _l434_banque('t02') INTO t, ba, tx, usr;
  SELECT * INTO r FROM chain_banc_epreuve(t, 'releve.comptabilise', 'D1');

  PERFORM _rec('T02', 'D1 (rejeu) : le 2ᵉ appel n''ajoute aucun lien ni aucune trace',
    r.verdict = 'tenu',
    format('verdict=%s obtenu=%s', r.verdict, COALESCE(r.obtenu,'(null)')));
END $t02$;

-- ─────────────────────────────────────────────────────────────
-- T03 — D4 annulation : le lien se ferme
-- ─────────────────────────────────────────────────────────────
DO $t03$
DECLARE t uuid; ba uuid; tx uuid; usr uuid; r record;
BEGIN
  SELECT * FROM _l434_banque('t03') INTO t, ba, tx, usr;
  -- d'abord l'effet, pour qu'il y ait un lien à annuler
  PERFORM post_bank_statement_line(tx, NULL, 'Banc 434');
  SELECT * INTO r FROM chain_banc_epreuve(t, 'releve.comptabilise', 'D4');

  PERFORM _rec('T03', 'D4 (annulation) : le lien se ferme — plus aucun lien actif',
    r.verdict = 'tenu',
    format('verdict=%s obtenu=%s', r.verdict, COALESCE(r.obtenu,'(null)')));
END $t03$;

-- ─────────────────────────────────────────────────────────────
-- T04 — D6 retour arrière : après annulation, rien ne subsiste
-- ─────────────────────────────────────────────────────────────
DO $t04$
DECLARE t uuid; ba uuid; tx uuid; usr uuid; r record;
BEGIN
  SELECT * FROM _l434_banque('t04') INTO t, ba, tx, usr;
  SELECT * INTO r FROM chain_banc_epreuve(t, 'releve.comptabilise', 'D6');

  PERFORM _rec('T04', 'D6 (retour arrière) : l''annulation de la transaction ne laisse rien',
    r.verdict = 'tenu',
    format('verdict=%s obtenu=%s', r.verdict, COALESCE(r.obtenu,'(null)')));
END $t04$;
-- ─────────────────────────────────────────────────────────────
-- T05 — D7 volume : le p95 est MESURÉ et rapporté
-- ─────────────────────────────────────────────────────────────
DO $t05$
DECLARE t uuid; ba uuid; tx uuid; usr uuid; r record;
BEGIN
  SELECT * FROM _l434_banque('t05') INTO t, ba, tx, usr;
  SELECT * INTO r FROM chain_banc_epreuve(t, 'releve.comptabilise', 'D7');

  PERFORM _rec('T05', 'D7 (volume) : le p95 est mesuré sur 20 tours et comparé au budget G6',
    r.verdict = 'tenu' AND r.mesure IS NOT NULL,
    format('verdict=%s p95=%s obtenu=%s', r.verdict, r.mesure, COALESCE(r.obtenu,'(null)')));
END $t05$;

-- ─────────────────────────────────────────────────────────────
-- T06 — D8 isolation : une VRAIE session, un VRAI changement de société
--
-- C'est ici, et seulement ici, que la preuve est possible : PostgreSQL
-- interdit `SET ROLE` dans une fonction `SECURITY DEFINER`, donc l'épreuve
-- D8 ne peut pas se mesurer toute seule. Le banc produit le lien, la session
-- change de société ET de rôle, compte ce qu'elle voit — et la mesure est
-- ensuite réinjectée dans l'épreuve. Un `tenu` obtenu par une session qui n'a
-- jamais traversé la RLS ne prouverait rien.
-- ─────────────────────────────────────────────────────────────
DO $t06$
DECLARE ta uuid; baa uuid; txa uuid; ua uuid;
        tb uuid; bab uuid; txb uuid; ub uuid;
        v_depuis timestamptz; v_amont text; v_effet text;
        v_visibles bigint; v_proprio bigint; r record;
BEGIN
  SELECT * FROM _l434_banque('t06a') INTO ta, baa, txa, ua;
  v_depuis := clock_timestamp() - interval '1 minute';
  SELECT amont_type, effet INTO v_amont, v_effet
    FROM chain_banc_maillons WHERE code = 'releve.comptabilise';

  -- le maillon produit son lien
  PERFORM chain_banc_epreuve(ta, 'releve.comptabilise', 'D8');

  -- ⚠️ LE TÉMOIN DU PROPRIÉTAIRE, compté HORS RLS et AVANT tout changement de
  --   société. C'est lui qui distingue « la RLS a filtré » de « le propriétaire
  --   n'a rien produit » : D8 exige les deux, sinon elle ne prouve rien.
  --   Compté ici, on est encore en `postgres` — donc on voit toutes les lignes.
  SELECT count(*) INTO v_proprio FROM document_links d
   WHERE d.tenant_id = ta
     AND d.amont_type = v_amont
     AND d.effet = v_effet
     AND d.created_at >= v_depuis;

  -- LA SOCIÉTÉ VOISINE DOIT ÊTRE UN TÉMOIN, PAS UN TIRAGE.
  --
  -- ⚠️ LE DÉFAUT (mesuré le 02/10, session L4). Le choix se faisait par
  --   `LIMIT 1` SANS `ORDER BY` : le voisin était tiré AU HASARD parmi les
  --   sociétés qui ont une identité. Or, dans la base de la suite, PLUSIEURS
  --   sociétés ont déjà des liens — et le voisin tiré en avait 3 à lui. La RLS
  --   les lui rendait LÉGITIMEMENT (ce sont les siens), l'épreuve concluait à
  --   un défaut d'isolation qui n'existait pas, et `T06` rougissait sur
  --   `verdict=rompu liens_visibles_depuis_la_voisine=20`.
  --
  --   Vérifié avant de conclure : politique `document_links` =
  --   `tenant_id = current_tenant_id()`, RLS activée ET forcée ; lecture
  --   directe sous `authenticated` avec le contexte du voisin rend 3 liens —
  --   ceux DU VOISIN. Aucune fuite.
  --
  --   Ce qu'il faut, c'est un voisin **sans lien de ce maillon** : sinon
  --   « le voisin voit N liens » ne se distingue pas de « le voisin voit les
  --   liens du propriétaire ». On trie donc les candidats par nombre de liens
  --   CROISSANT, et on retient le premier qui n'en a aucun.
  SELECT t2.id INTO tb
    FROM tenants t2
   WHERE t2.id <> ta
     AND EXISTS (SELECT 1 FROM tenant_users tu WHERE tu.tenant_id = t2.id)
     -- pas un seul lien de CE maillon, pour CETTE société
     AND NOT EXISTS (
       SELECT 1 FROM document_links d
        WHERE d.tenant_id = t2.id
          AND d.amont_type = v_amont
          AND d.effet = v_effet
          AND d.created_at >= v_depuis)
   ORDER BY (SELECT count(*) FROM document_links d2
              WHERE d2.tenant_id = t2.id) ASC   -- la plus « neutre » d'abord
   LIMIT 1;
  IF tb IS NULL THEN
    -- Aucun voisin sans lien : on ne peut pas prouver l'isolation, et on ne
    -- l'invente pas. `non tenu` serait un mensonge ; on le dit.
    PERFORM _rec('T06', 'D8 (isolation) : sous `authenticated`, la société voisine ne voit aucun lien de ce maillon',
      false, 'aucune société voisine SANS lien de ce maillon : le témoin serait pollue par ses propres liens, et l épreuve ne prouverait rien (mesuré le 02/10)');
    RETURN;
  END IF;
  SELECT auth_id INTO ub FROM tenant_users WHERE tenant_id = tb LIMIT 1;

  -- LA session change de société et de rôle. C'est la seule étape qui met
  -- réellement la RLS en jeu ; sans elle, le comptage lirait tout.
  PERFORM _l434_revenir(tb, ub);
  SET LOCAL ROLE authenticated;
  SELECT chain_banc_liens_visibles(v_amont, v_effet, v_depuis) INTO v_visibles;
  RESET ROLE;

  -- ⚠️ On revient à l'identité de la société PROPRIÉTAIRE avant de réinjecter
  -- la mesure. `current_tenant_id()` se lit dans un GUC de session : le
  -- maillon cherche sa ligne de relevé dans la société courante, et sous
  -- l'identité du voisin il l'aurait cherchée chez le voisin — « Ligne de
  -- relevé introuvable ». La mesure d'isolation se prend chez le voisin,
  -- mais la production se fait chez le propriétaire.
  PERFORM _l434_revenir(ta, ua);

  -- la mesure réelle est réinjectée dans l'épreuve
  SELECT * INTO r FROM chain_banc_epreuve(ta, 'releve.comptabilise', 'D8', v_visibles);

  -- ⚠️ LES DEUX NOMBRES, TOUJOURS (mesuré le 02/10). Sans le nombre de liens
  --   du PROPRIÉTAIRE, un rouge reste non attribuable : « le voisin voit 0 »
  --   peut vouloir dire que la RLS filtre, ou que le propriétaire n'a rien
  --   produit — et D8 exige les DEUX (le maillon doit avoir produit, sinon
  --   l'épreuve ne prouve rien). On affiche donc les deux, toujours.
  PERFORM _rec('T06', 'D8 (isolation) : sous `authenticated`, la société voisine ne voit aucun lien de ce maillon',
    r.verdict = 'tenu' AND v_visibles = 0,
    format('verdict=%s | liens visibles depuis la voisine=%s (0 attendu) | liens du propriétaire=%s (>0 attendu : sans production, l épreuve ne prouve rien) | voisin choisi SANS lien de ce maillon | obtenu=%s',
           r.verdict, v_visibles, v_proprio, COALESCE(r.obtenu,'(null)')));
END $t06$;

-- ─────────────────────────────────────────────────────────────
-- T07 — D2, D3 ET D5 SONT NOMMÉES NON JOUÉES, AVEC LEUR RAISON
--    C'est LE cœur de la méthode, et le test le plus important de cette
--    suite : un banc qui déclare `tenu` ce qu'il n'a pas éprouvé ne prouve
--    rien. Ces trois épreuves exigent une seconde connexion, un point
--    d'échec instrumenté, ou un chemin de réouverture décrit — le schéma
--    ne les a pas, donc elles ne sont pas tenues.
-- ─────────────────────────────────────────────────────────────
DO $t07$
DECLARE t uuid; ba uuid; tx uuid; usr uuid;
        r_d2 record; r_d3 record; r_d5 record; n_nj int;
BEGIN
  SELECT * FROM _l434_banque('t07') INTO t, ba, tx, usr;

  SELECT * INTO r_d2 FROM chain_banc_epreuve(t, 'releve.comptabilise', 'D2');
  SELECT * INTO r_d3 FROM chain_banc_epreuve(t, 'releve.comptabilise', 'D3');
  SELECT * INTO r_d5 FROM chain_banc_epreuve(t, 'releve.comptabilise', 'D5');

  -- et AUCUNE des huit ne doit être « tenue » par défaut
  SELECT count(*) INTO n_nj FROM chain_banc_resultats
   WHERE tenant_id = t AND code = 'releve.comptabilise' AND verdict = 'tenu'
     AND epreuve IN ('D2','D3','D5');

  PERFORM _rec('T07', 'D2, D3 et D5 sont NON JOUÉES avec une raison — jamais vertes par défaut',
    r_d2.verdict = 'non_joue' AND btrim(COALESCE(r_d2.raison,'')) <> ''
    AND r_d3.verdict = 'non_joue' AND btrim(COALESCE(r_d3.raison,'')) <> ''
    AND r_d5.verdict = 'non_joue' AND btrim(COALESCE(r_d5.raison,'')) <> ''
    AND n_nj = 0,
    format('D2=%s D3=%s D5=%s tenues_par_défaut=%s', r_d2.verdict, r_d3.verdict, r_d5.verdict, n_nj));
END $t07$;

-- ─────────────────────────────────────────────────────────────
-- T08 — STRUCTURE : les trois fonctions existent, et le rapport garde
--    l'historique des passages (un rapport qui ne garde que le dernier
--    verdict ne dit pas si un défaut est ancien ou nouveau).
-- ─────────────────────────────────────────────────────────────
DO $t08$
DECLARE t uuid; ba uuid; tx uuid; usr uuid; n_fonc int; n_passages int;
BEGIN
  SELECT * FROM _l434_banque('t08') INTO t, ba, tx, usr;
  PERFORM chain_banc_lancer(t, 'releve.comptabilise');

  -- Quatre fonctions : les trois de la campagne, plus la lecture sous rôle
  -- applicatif — c'est elle qui rend la preuve d'isolation possible, donc
  -- elle fait partie du banc au même titre que les autres.
  SELECT count(*) INTO n_fonc FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
   WHERE p.proname IN ('chain_banc_appeler','chain_banc_epreuve','chain_banc_lancer',
                       'chain_banc_liens_visibles');

  -- plusieurs passages = plusieurs horodatages distincts dans le rapport
  SELECT count(DISTINCT r.joue_le) INTO n_passages
    FROM chain_banc_resultats r
   WHERE r.tenant_id = t AND r.code = 'releve.comptabilise';

  PERFORM _rec('T08', 'les quatre fonctions du banc existent et le rapport conserve les passages datés',
    n_fonc = 4 AND n_passages >= 1,
    format('fonctions=%s passages_distincts=%s', n_fonc, n_passages));
END $t08$;

-- ─────────────────────────────────────────────────────────────
-- Verdict de la suite
-- ─────────────────────────────────────────────────────────────
SELECT _audit_assert('434');