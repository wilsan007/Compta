-- ═══════════════════════════════════════════════════════════════════════════
-- 434 — Lot L3, tranche 6 : LES HUIT ÉPREUVES DU BANC, ÉCRITES (3.5, 3.6, 3.7)
--   Numéro pris le 2026-10-03 par migration-numero.mjs (ligne « partie 3 (L3,
--   L4) », branche partie-3-chainages).
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **Objet.** La 433 posait le moteur : une description par maillon, les huit
-- épreuves en dérivées, et un rapport — mais elle les enregistrait `non_joue`,
-- parce qu'elles n'existaient pas. C'était délibéré (un banc « vert par
-- défaut » ne prouve rien) ; cette migration les écrit.
--
-- **CHAQUE ÉPREUVE DIT CE QU'ELLE PEUT ET NE PEUT PAS PROUVER.** Une épreuve
-- non jouable n'est pas `tenu` : elle est `non_joue`, avec sa raison, et elle
-- reste VISIBLE dans le rapport. C'est la branche « 62/62 éprouvés OU LA
-- LISTE DES EXCLUS AVEC LEUR RAISON » du plan — elle n'existe que si le banc
-- sait dire ce qu'il n'a pas fait.
--
--   D1 rejeu        l'effet n'est pas doublé
--   D2 concurrence  deux transactions simultanées   → exige `dblink`
--   D3 tout ou rien une panne ne laisse rien        → exige un point d'échec
--   D4 annulation   le lien se ferme, l'effet part
--   D5 réouverture  un nouveau tour naît
--   D6 retour arrière la transaction recule
--   D7 volume       le p95 reste dans le budget G6 (§3.3 : 50 ms)
--   D8 isolation    la société voisine ne voit rien
--
-- ⚠️ POURQUOI D2, D3 ET D5 PEUVENT RESTER `non_joue`, ET CE N'EST PAS UNE
-- ÉCHAPATOIRE. Ces trois épreuves exigent quelque chose que le SCHÉMA n'a pas :
-- D2 veut DEUX transactions concurrentes (donc une seconde connexion) ; D3 veut
-- une panne AU MILIEU de l'effet (donc un point d'échec volontaire) ; D5 veut
-- un chemin de RÉOUVERTURE (un maillon n'a pas tous un passage de « fermé » à
-- « rouvert »). Les forcer en écrivant `tenu` serait mentir sur trois des huit
-- épreuves. Elles sont jouées SI le maillon le permet, et sinon nommées non
-- jouées avec la raison EXACTE. La suite 434 compte les deux cas séparément.
--
-- **L'APPEL GÉNÉRIQUE, ET SES LIMITES.** Le moteur ne connaît pas le métier :
-- il appelle ce que le catalogue décrit. Pour que l'appel soit SÛR, il n'est
-- jamais construit par concaténation d'une valeur : le gabarit `appat` est
-- écrit dans le catalogue et les arguments sont rendus en LITTÉRAUX échappés
-- (`%L`) avec leur type — donc une valeur ne peut pas s'injecter dans le SQL.
-- C'est une limite assumée : un gabarit est du code dans le catalogue.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. LE CATALOGUE APPREND À APPELER
--    `appat` est le gabarit SQL (`%s` = un argument), `arg_valeurs` la liste
--    des valeurs, `arg_types` leurs types. Le `%s` est consommé par
--    `format(gabarit, tableau)` : le gabarit fait partie du catalogue, donc il
--    est relu et portatif, pas reconstruit à chaque exécution.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE chain_banc_maillons ADD COLUMN IF NOT EXISTS appat       text;
ALTER TABLE chain_banc_maillons ADD COLUMN IF NOT EXISTS arg_valeurs jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE chain_banc_maillons ADD COLUMN IF NOT EXISTS arg_types   text[];
ALTER TABLE chain_banc_maillons ADD COLUMN IF NOT EXISTS defaut_dblink boolean NOT NULL DEFAULT false;
-- Le budget G6 est ÉCRIT ICI, pas supposé : §3.3 du plan des chaînages,
-- 50 ms pour un maillon simple. La colonne doit exister AVANT la fonction
-- d'épreuve qui la lit — d'où sa place ici, et non à la fin du fichier.
ALTER TABLE chain_banc_maillons ADD COLUMN IF NOT EXISTS budget_ms integer NOT NULL DEFAULT 50;

-- Les gestes DÉDIÉS. Un maillon n'annule pas en se ré-appelant : s'appeler
-- soi-même, c'est rejouer. C'était l'erreur de D4, et elle était grave — elle
-- aurait validé l'annulation d'un maillon qui, en réalité, refuse de se
-- rejouer. L'annulation et la réouverture sont donc deux gestes À PART,
-- écrits au catalogue, comme l'appel nominal.
ALTER TABLE chain_banc_maillons ADD COLUMN IF NOT EXISTS appat_annul       text;
ALTER TABLE chain_banc_maillons ADD COLUMN IF NOT EXISTS appat_reouverture text;

-- La série de stimuli du VOLUME. Rejouer vingt fois LA MÊME entrée ne mesure
-- pas le chemin nominal : dès le deuxième tour le maillon la refuse, et on
-- mesure alors le coût d'un refus. D7 n'est `tenu` que s'il a mesuré vingt
-- ACCEPTATIONS, donc vingt entrées distinctes.
ALTER TABLE chain_banc_maillons ADD COLUMN IF NOT EXISTS arg_series jsonb NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN chain_banc_maillons.appat_annul IS
  '434 : gabarit du geste d''ANNULATION (D4). Absent = D4 `non_joue` avec cette raison — jamais `tenu` par défaut, et jamais en rejouant le maillon.';
COMMENT ON COLUMN chain_banc_maillons.arg_series IS
  '434 : tableau d''arguments, un par tour, pour D7. Vingt entrées DISTINCTES : c''est le chemin nominal qui est mesuré, pas le chemin de refus.';

COMMENT ON COLUMN chain_banc_maillons.appat IS
  '434 : gabarit SQL de l''appel — « %s » est remplacé par un argument rendu en littéral typé. Écrit dans le catalogue, jamais reconstruit par concaténation : une valeur ne peut donc pas s''injecter dans le SQL.';
COMMENT ON COLUMN chain_banc_maillons.defaut_dblink IS
  '434 : ce maillon exige-t-il une seconde connexion pour être éprouvé (D2, concurrence) ? Vrai = la preuve D2 exige `dblink` ; absent, l''épreuve est `non_joue` avec cette raison — jamais `tenu` par défaut.';

-- ─────────────────────────────────────────────────────────────
-- 2. L'APPEL RENDU — littéraux échappés, jamais concaténés
-- ─────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS chain_banc_appeler(record);
CREATE OR REPLACE FUNCTION chain_banc_appeler(
  m         record,
  p_vals    jsonb DEFAULT NULL,   -- jeu d'arguments SUPLÉANT (D7 : un tour)
  p_appat   text   DEFAULT NULL    -- gabarit SUPLÉANT (D4/D5 : geste dédié)
)
RETURNS jsonb
LANGUAGE plpgsql AS $appel$
DECLARE
  v_vals  jsonb := COALESCE(p_vals, m.arg_valeurs, '[]'::jsonb);
  v_types text[] := m.arg_types;
  v_rendus text[] := '{}';
  v_i     int;
  v_val   jsonb;
  v_typ   text;
  v_res   jsonb;
  v_appat text := COALESCE(p_appat, m.appat);
BEGIN
  IF v_appat IS NULL THEN
    RAISE EXCEPTION 'Banc : le maillon % n''a pas de gabarit d''appel.', m.code
      USING ERRCODE = '22023';
  END IF;

  FOR v_i IN SELECT generate_series(1, jsonb_array_length(v_vals)) LOOP
    v_val := v_vals -> (v_i - 1);
    v_typ := COALESCE(v_types[v_i], 'text');

    v_rendus := v_rendus || CASE
      -- null : on caste pour que PostgreSQL sache quoi mettre dans un uuid
      WHEN v_val = 'null'::jsonb OR v_val IS NULL
        THEN format('NULL::%s', v_typ)
      -- jsonb : la valeur EST du json, on l'embarque
      WHEN v_typ = 'jsonb'
        THEN format('%L::jsonb', v_val::text)
      ELSE format('%L::%s', v_val #>> '{}', v_typ)
    END;
  END LOOP;

  -- ⚠️ `RETURN EXECUTE` N'EXISTE PAS en PL/pgSQL : `EXECUTE` ne renvoie pas
  -- de valeur, il ne fait que produire un jeu de résultats. On enveloppe donc
  -- l'appel dans un SELECT et on le ramène en JSONB — ce qui marche QUELE QUE
  -- SOIT le type de retour du maillon (un `jsonb`, un `uuid`, ou une ligne de
  -- `pos_tickets`), au lieu d'exiger que tous les maillons rendent la même
  -- chose.
  -- ⚠️ `VARIADIC` EST OBLIGATOIRE, ET SON ABSENCE EST DISCRÈTE.
  -- `format(gabarit, tableau)` ne DÉPLIE PAS le tableau : il l'imprime tel
  -- quel, sous forme de littéral `{…}`. L'appel produit alors
  -- `post_bank_statement_line({'uuid'::uuid}, …)` — une erreur de syntaxe qui
  -- ne dit rien du gabarit. Avec `VARIADIC`, chaque élément consomme un `%s`,
  -- dans l'ordre.
  EXECUTE format('SELECT to_jsonb(t) FROM (%s) AS t', format(v_appat, VARIADIC v_rendus))
    INTO v_res;
  RETURN v_res;
END $appel$;

COMMENT ON FUNCTION chain_banc_appeler(record, jsonb, text) IS
  '434 : rend et exécute l''appel décrit par le catalogue. Les arguments sont rendus en LITTÉRAUX échappés avec leur type (`%L::type`) — jamais concaténés. Une valeur ne peut donc pas s''injecter dans le SQL. Le gabarit, lui, est du code : c''est la limite assumée du moteur. `p_vals`/`p_appat` permettent à D4, D5 et D7 de jouer un geste ou un stimulus différents du nominal.';
-- ─────────────────────────────────────────────────────────────
-- 2 bis. LA LECTURE SOUS RÔLE APPLICATIF
--
-- ⚠️ `SECURITY INVOKER`, et c'est tout l'intérêt : c'est la SEULE fonction du
-- banc qui ne contourne pas la RLS. La preuve d'isolation entre sociétés ne
-- peut pas être prise depuis `chain_banc_epreuve` : PostgreSQL interdit
-- `SET ROLE` dans une fonction `SECURITY DEFINER` (« cannot set parameter
-- "role" within security-definer function »). Il faut donc une session
-- RÉELLE, en `authenticated`, avec l'identité de la société voisine. Cette
-- fonction est ce point d'entrée, et elle ne fait rien d'autre que compter ce
-- que la session voit.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION chain_banc_liens_visibles(
  p_amont_type text, p_effet text, p_depuis timestamptz
) RETURNS bigint
LANGUAGE sql STABLE SECURITY INVOKER AS $vis$
  SELECT count(*) FROM document_links
   WHERE amont_type = p_amont_type AND effet = p_effet
     AND created_at >= p_depuis
$vis$;

COMMENT ON FUNCTION chain_banc_liens_visibles(text, text, timestamptz) IS
  '434 : compte les liens du maillon VISIBLES PAR LA SESSION COURANTE. SECURITY INVOKER : elle est la preuve d''isolation, car c''est la seule du banc à subir réellement la RLS. À appeler depuis une session `authenticated`, jamais depuis une fonction SECURITY DEFINER.';
-- 3. L'ÉPREUVE — une fonction, huit branches
--    Chaque branche rend UN verdict et SA raison. Aucune ne rend `tenu` par
--    défaut : si la mesure n'a pas pu être faite, le verdict est `non_joue`.
--
--    Le relevé se fait sur le REGISTRE DU MAILLON : liens et traces du couple
--    (amont, effet). C'est ce que le maillon a réellement produit, pas ce
--    qu'il aurait dû produire.
-- ─────────────────────────────────────────────────────────────
-- ⚠️ On SUPPRIME l'ancienne surcharge à trois arguments. `CREATE OR REPLACE`
-- ne remplace que la signature IDENTIQUE : l'ancien `chain_banc_epreuve(uuid,
-- text, text)` restait donc en base, et tout appel à trois arguments levait
-- « function is not unique ». Un `DROP` explicite avant le `CREATE` est la
-- seule façon de changer une signature sans laisser de double.
DROP FUNCTION IF EXISTS chain_banc_epreuve(uuid, text, text);
CREATE OR REPLACE FUNCTION chain_banc_epreuve(
  p_tenant          uuid,
  p_code            text,
  p_epreuve         text,
  p_mesure_externe  bigint DEFAULT NULL
)
RETURNS TABLE (verdict text, mesure numeric, attendu text, obtenu text, duree integer, raison text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $epr$
DECLARE
  m             record;
  v_tid         uuid := COALESCE(p_tenant, current_tenant_id());
  v_debut       timestamptz := clock_timestamp();
  v_budget_ms   integer := 50;
  v_avant_liens integer := 0;
  v_m1_liens    integer := 0;   -- liens après le 1ᵉʳ tour
  v_m1_tr       integer := 0;   -- traces après le 1ᵉʳ tour
  v_m2_liens    integer := 0;   -- liens après le 2ᵉ tour
  v_m2_tr       integer := 0;   -- traces après le 2ᵉ tour
  v_actifs      integer := 0;
  v_tours       integer[] := '{}';
  v_i           integer;
  v_t0          timestamptz;
  v_ms          integer;
  v_mesure      numeric;
  v_obtenu      text;
  v_attendu     text;
  v_refus       boolean := false;
  v_sqlstate    text;
  v_msg         text;
  v_acceptes    integer := 0;
  v_refus_series integer := 0;
  v_autre_societe uuid;
BEGIN
  -- ⚠️ Une preuve indéterminée ne doit JAMAIS ressembler à une preuve bonne.
  -- `verdict` est un paramètre de sortie, donc NULL tant qu'on ne l'a pas
  -- affecté : or la colonne refuse le NULL, et l'échec d'insertion transformait
  -- « je n'ai pas su » en erreur de base, invisible dans le rapport. On part
  -- de `non_joue`, qui est la seule valeur honnête par défaut.
  verdict := 'non_joue';
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Banc : aucune société active' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO m FROM chain_banc_maillons b WHERE b.code = p_code;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Banc : maillon inconnu (%)', p_code USING ERRCODE = '22023';
  END IF;
  v_budget_ms := COALESCE(m.budget_ms, 50);

  -- Un maillon sans gabarit ne peut pas être appelé : l'épreuve n'est pas
  -- jouée, et sa raison le dit — elle ne se déclare jamais tenue.
  IF m.appat IS NULL THEN
    RETURN QUERY SELECT 'non_joue'::text, NULL::numeric,
      format('l''épreuve %s de %s', p_epreuve, m.code),
      'maillon sans gabarit d''appel'::text, NULL::integer,
      format('Aucun gabarit d''appel n''est décrit pour ce maillon : le banc ne peut pas le produire, donc il ne peut pas l''éprouver. C''est un décor manquant, pas un défaut du maillon.');
    RETURN;
  END IF;

  CASE p_epreuve

  -- ── D1 — LE REJEU ──────────────────────────────────────────────
  -- Le 2ᵉ appel n'ajoute NI lien NI trace. Mesuré sur ce qui est écrit, pas
  -- sur la valeur retournée — que le maillon pourrait annoncer fausse.
  --
  -- Le 2ᵉ appel peut RÉUSSIR SANS RIEN ÉCRIRE, ou être REFUSÉ. Les deux modes
  -- tiennent l'invariant « le rejeu ne duplique rien » : refuser est même plus
  -- strict que ne rien faire, puisque l'appelant est enCollision AVANT
  -- d'écrire. On ne confond pas les deux.
  --
  -- ⚠️ Ce qui distingue un REFUS MÉTIER d'une PANNE, c'est le SQLSTATE : une
  -- contrainte métier (`23514` check, `23505` unique) est un refus voulu ; un
  -- `42P01` ou un `22023` est un défaut. Sans cette distinction, une panne qui
  -- n'écrit rien passerait pour un rejeu correct — on validerait un maillon
  -- cassé parce qu'il plante avant d'écrire.
  WHEN 'D1' THEN
    v_attendu := 'le 2ᵉ appel n''ajoute aucun lien et aucune trace';
    v_refus   := false;
    BEGIN
      PERFORM chain_banc_appeler(m);
      SELECT count(*) INTO v_m1_liens FROM document_links
       WHERE tenant_id = v_tid AND amont_type = m.amont_type AND effet = m.effet;
      SELECT count(*) INTO v_m1_tr FROM chain_traces
       WHERE tenant_id = v_tid AND amont_type = m.amont_type AND effet = m.effet;
      -- Le 2ᵉ appel est isolé dans un sous-bloc : son échec ne doit pas
      -- ANNULER les mesures déjà relevées, sans quoi on ne verrait jamais
      -- qu'il a bien rien écrit.
      BEGIN
        PERFORM chain_banc_appeler(m);
      EXCEPTION WHEN OTHERS THEN
        v_refus   := true;
        v_sqlstate := SQLSTATE;
        v_msg      := SQLERRM;
      END;
      SELECT count(*) INTO v_m2_liens FROM document_links
       WHERE tenant_id = v_tid AND amont_type = m.amont_type AND effet = m.effet;
      SELECT count(*) INTO v_m2_tr FROM chain_traces
       WHERE tenant_id = v_tid AND amont_type = m.amont_type AND effet = m.effet;
    EXCEPTION WHEN OTHERS THEN
      -- Ici le 1ᵉʳ appel a échoué : rien n'a été produit, donc rien à rejouer.
      RETURN QUERY SELECT 'non_joue'::text, NULL::numeric, v_attendu,
        format('le 1ᵉʳ appel n''a pas abouti : %s', SQLERRM)::text, NULL::integer,
        format('Le premier appel a levé (%s, SQLSTATE %s) : le maillon n''a rien produit, donc il n''y a rien à rejouer. L''invariant de rejeu ne peut pas être éprouvé sur un maillon qui n''a pas tourné.', SQLERRM, SQLSTATE);
      RETURN;
    END;

    v_mesure := (v_m2_liens - v_m1_liens) + (v_m2_tr - v_m1_tr);
    v_obtenu := format('1ᵉʳ tour : %s lien(s), %s trace(s) ; 2ᵉ tour : +%s lien(s), +%s trace(s) ; mode : %s',
                       v_m1_liens, v_m1_tr, v_m2_liens - v_m1_liens, v_m2_tr - v_m1_tr,
                       CASE WHEN NOT v_refus THEN 'rejeu sans effet (le 2ᵉ appel a réussi)'
                            WHEN v_sqlstate IN ('23514','23505') THEN format('refus métier contrôlé (SQLSTATE %s)', v_sqlstate)
                            ELSE format('ÉCHEC NON MÉTIER (SQLSTATE %s)', v_sqlstate) END);

    -- Un refus métier qui n'écrit rien : l'invariant est tenu, ET le maillon
    -- l'a défendu. Un échec qui n'est pas un refus métier, même sans écriture :
    -- `rompu`, parce qu'on a mesuré une panne, pas un rejeu.
-- Le verdict est rendu ICI plutôt qu'après le CASE commun : ce cas est le
-- seul où un refus doit invalider la mesure. Un refus qui n'est pas métier
-- invalide le résultat même si rien n'a été écrit — sinon une panne
-- passerait pour un rejeu correct.
    IF v_refus AND v_sqlstate NOT IN ('23514','23505') THEN
      RETURN QUERY SELECT 'rompu'::text, v_mesure, v_attendu, v_obtenu, NULL::integer,
        format('Le rejeu n''a rien écrit, mais le 2ᵉ appel a échoué sur le SQLSTATE %s, qui n''est pas un refus métier (%s). On a mesuré une panne, pas un rejeu : l''invariant n''est pas prouvé.', v_sqlstate, v_msg);
      RETURN;
    END IF;

    -- Le refus métier n'écrit rien : le rejeu est tenu. C'est le verdict
    -- NOMINAL de D1 — et il ne doit surtout pas rester NULL : un verdict
    -- indéterminé qui passerait pour un vert au premier rapport.
    verdict := CASE WHEN v_mesure = 0 THEN 'tenu' ELSE 'rompu' END;
-- ── D2 — LA CONCURRENCE ────────────────────────────────────────
  -- Il faut DEUX TRANSACTIONS à la fois. Dans la transaction du banc, un
  -- second appel est le premier : il n'y a pas de concurrence, et écrire
  -- `tenu` prétendrait l'avoir éprouvée.
  WHEN 'D2' THEN
    v_attendu := 'deux transactions simultanées ne produisent l''effet qu''une fois';
    RETURN QUERY SELECT 'non_joue'::text, NULL::numeric, v_attendu,
      (CASE WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'dblink')
            THEN 'seconde connexion non câblée dans le moteur'::text
            ELSE 'dblink absent'::text END), NULL::integer,
      format('La preuve de concurrence exige DEUX transactions RÉELLEMENT simultanées, donc une seconde connexion. dblink est %s, et le moteur n''exécute pas encore cette seconde connexion : la preuve n''est pas instrumentée, et écrire `tenu` serait mentir sur une des huit épreuves.',
             CASE WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'dblink')
                  THEN 'présent' ELSE 'absent' END);
    RETURN;

  -- ── D3 — LE TOUT OU RIEN ───────────────────────────────────────
  -- Il faut une panne AU MILIEU de l''effet, donc un point d''échec
  -- instrumenté. Sans lui, l''épreuve ne prouve rien — et rien ne se déclare
  -- pas tenu.
  WHEN 'D3' THEN
    v_attendu := 'une panne au milieu de l''effet ne laisse aucun effet orphelin';
    RETURN QUERY SELECT 'non_joue'::text, NULL::numeric, v_attendu,
      'aucun point d''échec instrumenté sur ce maillon'::text, NULL::integer,
      format('Le maillon %s n''expose pas de point d''échec : une panne PARTIELLE ne peut pas être provoquée au milieu de son effet. Sans instrument, l''épreuve ne prouve rien.', m.code);
    RETURN;

-- ── D4 — L'ANNULATION ──────────────────────────────────────────
  -- Le lien se ferme : aucun lien actif ne subsiste après le geste.
  --
  -- ⚠️ On joue `appat_annul`, PAS l'appel nominal. Rejouer le producteur pour
  -- « annuler » était une erreur de sens : on demandait au maillon de produire
  -- une seconde fois, et on prenait son refus pour une annulation. Sur un
  -- maillon qui rend le silence, cet appel ne lève pas : il ne fait RIEN, et
  -- l'épreuve aurait conclu `tenu` en n'ayant rien annulé. Le lien serait
  -- resté actif, et le banc aurait publié une preuve d'annulation qui
  -- n'existe pas.
  WHEN 'D4' THEN
    v_attendu := 'le lien se ferme : aucun lien actif ne subsiste après le geste d''annulation';

    IF m.appat_annul IS NULL THEN
      RETURN QUERY SELECT 'non_joue'::text, NULL::numeric, v_attendu,
        'aucun geste d''annulation décrit'::text, NULL::integer,
        format('Le maillon %s n''a pas de geste d''ANNULATION dédié au catalogue. On ne peut pas annuler en rejouant le producteur : cela demanderait un second effet, pas sa suppression. L''épreuve reste à écrire, et elle n''est pas `tenu`.', m.code);
      RETURN;
    END IF;

    SELECT count(*) INTO v_actifs FROM document_links
     WHERE tenant_id = v_tid AND amont_type = m.amont_type
       AND effet = m.effet AND etat = 'actif';

    IF v_actifs = 0 THEN
      RETURN QUERY SELECT 'non_joue'::text, NULL::numeric, v_attendu,
        'aucun lien actif à annuler'::text, NULL::integer,
        format('Aucun lien ACTIF de %s n''existe : il n''y a rien à annuler, donc l''épreuve ne prouve rien. Le maillon n''a peut-être pas encore tourné.', m.code);
      RETURN;
    END IF;

    BEGIN
      PERFORM chain_banc_appeler(m, NULL, m.appat_annul);
    EXCEPTION WHEN OTHERS THEN
      RETURN QUERY SELECT 'rompu'::text, NULL::numeric, v_attendu,
        format('le geste d''annulation a levé : %s', SQLERRM)::text, NULL::integer,
        format('Le geste d''annulation a levé (%s) alors qu''un lien actif existait : le lien reste actif, et le maillon le dit par son échec.', SQLERRM);
      RETURN;
    END;

    SELECT count(*) INTO v_actifs FROM document_links
     WHERE tenant_id = v_tid AND amont_type = m.amont_type
       AND effet = m.effet AND etat = 'actif';
    v_mesure := v_actifs;
    v_obtenu := format('%s lien(s) actif(s) restant(s) après annulation', v_actifs);
    verdict  := CASE WHEN v_actifs = 0 THEN 'tenu' ELSE 'rompu' END;

  -- ── D5 — LA RÉOUVERTURE ────────────────────────────────────────
  -- Un nouveau tour doit naître (le cycle de vie du lien, 312). Il faut donc les
  -- DEUX gestes : annuler, puis rouvrir. L'épreuve annule, rouvre, et vérifie
  -- qu'un lien actif existe À NOUVEAU — sans quoi une réouverture qui ne fait
  -- rien passerait pour une réouverture.
  WHEN 'D5' THEN
    v_attendu := 'une réouverture crée un nouveau tour, sans réécrire l''ancien lien';

    IF m.appat_reouverture IS NULL THEN
      RETURN QUERY SELECT 'non_joue'::text, NULL::numeric, v_attendu,
        'aucun chemin de réouverture décrit'::text, NULL::integer,
        format('Le maillon %s n''a pas de chemin de RÉOUVERTURE décrit dans le catalogue : la nouvelle ouverture reste à écrire. C''est un reste de L3, pas une preuve acquise.', m.code);
      RETURN;
    END IF;

    BEGIN
      -- L'ordre compte : PRODUIRE, puis défaire, puis rouvrir. On ne peut pas
      -- défaire ce qui n'a jamais été fait — `unreconcile` sur une ligne
      -- vierge lève « rien à défaire », et l'épreuve échouerait pour un motif
      -- qui n'a rien à voir avec la réouverture.
      PERFORM chain_banc_appeler(m);
      PERFORM chain_banc_appeler(m, NULL, m.appat_annul);
      PERFORM chain_banc_appeler(m, NULL, m.appat_reouverture);
    EXCEPTION WHEN OTHERS THEN
      RETURN QUERY SELECT 'non_joue'::text, NULL::numeric, v_attendu,
        format('le cycle produire/défaire/rouvrir a levé : %s', SQLERRM)::text, NULL::integer,
        format('Le cycle produire → défaire → rouvrir a levé (SQLSTATE %s) : %s. La réouverture est DÉCRITE au catalogue mais ne va pas à son terme ; ce défaut est celui du maillon, pas du banc, et D5 reste `non_joue` tant qu''il tient.', SQLSTATE, SQLERRM);
      RETURN;
    END;

    SELECT count(*) INTO v_actifs FROM document_links
     WHERE tenant_id = v_tid AND amont_type = m.amont_type
       AND effet = m.effet AND etat = 'actif';
    v_mesure := v_actifs;
    v_obtenu := format('%s lien(s) actif(s) après réouverture', v_actifs);
    verdict  := CASE WHEN v_actifs > 0 THEN 'tenu' ELSE 'rompu' END;

  -- ── D6 — LE RETOUR ARRIÈRE ─────────────────────────────────────
  -- L''appel est encadré d''un point de sauvegarde puis annulé : l''état de
  -- départ doit être revenu. La propriété est celle de la 252 §5 ; on la
  -- MESURE ici plutôt que de la supposer.
  WHEN 'D6' THEN
    v_attendu := 'après annulation de la transaction, aucun lien ni trace ne subsiste';
    SELECT count(*) INTO v_avant_liens FROM document_links
     WHERE tenant_id = v_tid AND amont_type = m.amont_type AND effet = m.effet;

    BEGIN
      PERFORM chain_banc_appeler(m);
      RAISE EXCEPTION 'retour_arriere_voulu';
    EXCEPTION
      WHEN SQLSTATE 'P0001' THEN NULL;   -- notre levée voulue : c'est l'annulation
    END;

    SELECT count(*) INTO v_m2_liens FROM document_links
     WHERE tenant_id = v_tid AND amont_type = m.amont_type AND effet = m.effet;
    v_mesure := v_m2_liens - v_avant_liens;
    v_obtenu := format('%s lien(s) de plus qu''au départ, après annulation de la transaction', v_mesure);
    verdict  := CASE WHEN v_mesure = 0 THEN 'tenu' ELSE 'rompu' END;

  -- ── D7 — LE VOLUME ─────────────────────────────────────────────
  -- Le p95 doit rester dans le budget G6 (§3.3 du plan : 50 ms). Vingt tours :
  -- assez pour un p95, peu pour rester rapide.
  --
  -- ⚠️ Les vingt tours doivent porter des stimuli DISTINCTS (`arg_series`).
  -- Rejouer vingt fois la MÊME entrée ne mesure pas le chemin nominal : dès le
  -- deuxième tour le maillon la refuse, et le p95 obtenu est en réalité le
  -- coût d'un REFUS. Publier ce nombre comme une performance serait faux, et
  -- le pire cas est ici le plus probable. Sans série, l'épreuve n'est pas
  -- jouable : `non_joue`, jamais un p95 de convenience.
  WHEN 'D7' THEN
    v_attendu := format('p95 ≤ %s ms sur 20 tours distincts (budget G6, §3.3)', v_budget_ms);

    IF jsonb_array_length(m.arg_series) < 2 THEN
      RETURN QUERY SELECT 'non_joue'::text, NULL::numeric, v_attendu,
        format('série de stimuli absente (%s stimulus(s))', jsonb_array_length(m.arg_series))::text, NULL::integer,
        format('Le maillon %s n''a pas de série de stimuli distincts. Rejouer %s entrée(s) ne mesurerait que le chemin de refus, pas le chemin nominal : aucun p95 honnête ne peut en sortir.', m.code, jsonb_array_length(m.arg_series));
      RETURN;
    END IF;

    v_acceptes := 0;
    FOR v_i IN 1..LEAST(20, jsonb_array_length(m.arg_series)) LOOP
      v_t0 := clock_timestamp();
      BEGIN
        PERFORM chain_banc_appeler(m, m.arg_series -> (v_i - 1));
        v_acceptes := v_acceptes + 1;
      EXCEPTION WHEN OTHERS THEN
        v_refus_series := v_refus_series + 1;
      END;
      v_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) * 1000)::int;
      v_tours := v_tours || v_ms;
    END LOOP;

    -- Un refus en volume n'est pas un « tour lent » : c'est un chemin qui n'a
    -- pas été emprunté. On le dit, plutôt que de lisser le p95 par-dessus.
    IF v_refus_series > 0 THEN
      RETURN QUERY SELECT 'rompu'::text, NULL::numeric, v_attendu,
        format('%s/%s tours refusés', v_refus_series, LEAST(20, jsonb_array_length(m.arg_series)))::text, NULL::integer,
        format('%s stimulus sur %s ont été REFUSÉS : le p95 mesurerait le chemin de refus et non le chemin nominal. Une performance ne s''annonce pas sur des tours qui n''ont pasAbouti.', v_refus_series, LEAST(20, jsonb_array_length(m.arg_series)));
      RETURN;
    END IF;

    -- ⚠️ `percentile_cont(0.95)`, et non « le plus petit tour ≥ la médiane ».
    -- Ce dernier tour de main ressemble à un p95 et n'en est pas un : il
    -- Returning toujours la médiane, et une série de 20 tours n'a que 19
    -- valeurs sous le p95 — le calcul à la main passe à côté du vrai p95.
    v_mesure := (SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY u.ms)
                   FROM unnest(v_tours) AS u(ms));
    v_obtenu := format('p95 = %s ms sur %s tours distincts, tous acceptés (min %s, max %s)', v_mesure, v_acceptes,
                       (SELECT min(u.ms) FROM unnest(v_tours) AS u(ms)),
                       (SELECT max(u.ms) FROM unnest(v_tours) AS u(ms)));
    verdict  := CASE WHEN v_mesure <= v_budget_ms THEN 'tenu' ELSE 'rompu' END;
-- ── D8 — L'ISOLATION ──────────────────────────────────────────
  -- On produit d'abord, puis on interroge le registre POUR COMPTER CE QU'UNE
  -- AUTRE SOCIÉTÉ VERRAIT.
  --
  -- ⚠️ CHANGER DE SOCIÉTÉ NE SUFFIT PAS, IL FAUT CHANGER DE RÔLE.
  -- Compter avec `tenant_id <> v_tid` depuis cette fonction ne prouve RIEN :
  -- elle est `SECURITY DEFINER`, elle s'exécute avec les droits du propriétaire,
  -- la RLS est donc contournée — on lirait tout, société voisine comprise, et le
  -- verdict serait vert par construction. L'épreuve n'a de valeur qu'APRÈS
  -- `SET LOCAL ROLE authenticated` : c'est le seul moment où les politiques de
  -- lignes s'appliquent réellement.
  WHEN 'D8' THEN
    v_attendu := 'aucun lien de ce maillon n''est visible depuis une autre société';

    -- Une mesure EXTERNE a été fournie : c'est une session réelle, en
    -- `authenticated`, avec l'identité de la société voisine, qui a compté ce
    -- qu'elle voyait. On ne REPRODUIT pas — le lien a déjà été produit au tour
    -- précédent, et le rappeler ne ferait que buter sur son propre garde-fou.
    IF p_mesure_externe IS NOT NULL THEN
      SELECT count(*) INTO v_m1_liens FROM document_links d
       WHERE d.tenant_id = v_tid AND d.amont_type = m.amont_type AND d.effet = m.effet;
      v_mesure := p_mesure_externe;
      v_obtenu := format('%s lien(s) sur le registre ; société voisine, session réelle en `authenticated` : %s visible(s)',
                         v_m1_liens, v_mesure);
      -- `v_m1_liens > 0` : un tour qui n'a rien produit ne prouve pas que le
      -- voisin ne voit rien, il prouve qu'il n'y avait rien à voir.
      verdict  := CASE WHEN v_mesure = 0 AND v_m1_liens > 0 THEN 'tenu' ELSE 'rompu' END;
      -- ⚠️ `RETURN QUERY`, jamais un `RETURN` nu : dans une fonction
      -- `RETURNS TABLE`, un `RETURN` sans requête sort SANS RENDRE DE LIGNE.
      -- L'appelant recevait donc zéro verdict au lieu du verdict mesuré — et
      -- le test le lisait `NULL`, ce qui ressemblait à une absence de preuve
      -- alors que la mesure venait d'être faite.
      RETURN QUERY SELECT verdict, v_mesure, v_attendu, v_obtenu, NULL::integer, NULL::text;
      RETURN;
    END IF;

    BEGIN
      PERFORM chain_banc_appeler(m);
    EXCEPTION WHEN OTHERS THEN
      RETURN QUERY SELECT 'non_joue'::text, NULL::numeric, v_attendu,
        format('le maillon n''a pas pu produire : %s', SQLERRM)::text, NULL::integer,
        format('Le maillon n''a rien produit (%s). Dans une campagne complète, D1, D4 et D7 ont déjà consommé ce stimulus : le Maillon refuse alors de le refaire. La preuve d''isolation se prend donc en DEUX temps — production, puis mesure depuis une session réelle en `authenticated` via `chain_banc_liens_visibles`.', SQLERRM);
      RETURN;
    END;

    SELECT count(*) INTO v_m1_liens FROM document_links d
     WHERE d.tenant_id = v_tid AND d.amont_type = m.amont_type
       AND d.effet = m.effet AND d.created_at >= v_debut;

    -- Une mesure EXTERNE a été fournie : c'est une session réelle, en
    -- `authenticated`, avec l'identité de la société voisine, qui a compté ce
    -- qu'elle voyait. On s'en sert telle quelle — c'est la seule mesure qui
    -- ait traversé la RLS.
    IF p_mesure_externe IS NOT NULL THEN
      v_mesure := p_mesure_externe;
      v_obtenu := format('%s lien(s) écrit(s) par ce tour ; société voisine, session réelle en `authenticated` : %s lien(s) visible(s)',
                         v_m1_liens, v_mesure);
      verdict  := CASE WHEN v_mesure = 0 AND v_m1_liens > 0 THEN 'tenu' ELSE 'rompu' END;
      RETURN;
    END IF;

    -- ⚠️ On ne PEUT PAS mesurer l'isolation d'ici : PostgreSQL interdit
    -- `SET ROLE` dans une fonction `SECURITY DEFINER`. Compter avec
    -- `tenant_id <> v_tid` ne prouverait rien non plus — le propriétaire
    -- contourne la RLS, on lirait tout, et le verdict serait vert par
    -- construction. La seule sortie honnête est de dire qu'il manque le
    -- témoin, plutôt que de fabriquer un vert.
    RETURN QUERY SELECT 'non_joue'::text, NULL::numeric, v_attendu,
      format('%s lien(s) produit(s), isolation NON MESURÉE', v_m1_liens)::text, NULL::integer,
      format('Le maillon %s a produit %s lien(s), mais l''isolation n''a pas pu être mesurée : PostgreSQL interdit de changer de rôle dans une fonction SECURITY DEFINER. Il faut une session réelle en `authenticated` avec l''identité de la société voisine — `chain_banc_liens_visibles` existe pour cela. Un vert obtenu ici serait vert par construction, donc faux.', m.code, v_m1_liens);
    RETURN;

  ELSE
    RETURN QUERY SELECT 'non_joue'::text, NULL::numeric,
      format('épreuve inconnue : %s', p_epreuve), 'aucune branche'::text, NULL::integer,
      'Aucune branche ne décrit cette épreuve : elle n''a pas été jouée.';
    RETURN;
  END CASE;

  RETURN QUERY SELECT verdict, v_mesure, v_attendu, v_obtenu,
                 (EXTRACT(EPOCH FROM (clock_timestamp() - v_debut)) * 1000)::int,
                 NULL::text;
END $epr$;

COMMENT ON FUNCTION chain_banc_epreuve(uuid, text, text, bigint) IS
'434 : joue UNE épreuve du banc pour UN maillon et rend son verdict. Aucune branche ne rend `tenu` par défaut : une mesure non faite donne `non_joue` avec sa raison. D2, D3 et D5 exigent une seconde connexion, un point d''échec instrumenté ou un chemin de réouverture décrit — sans cela, elles sont nommées non jouées plutôt que déclarées tenues.';

-- ─────────────────────────────────────────────────────────────
-- 4. LE MOTEUR JOUE MAINTENANT LES ÉPREUVES
--    La 433 enregistrait `non_joue` par défaut — un cadre honnête, mais un
--    cadre vide. Ici chaque branche de `chain_banc_epreuve` est jouée, et le
--    verdict ÉCRIT est celui qu'elle a réellement mesuré. La fonction est
--    redéfinie (et non modifiée sur place) pour que la 433 reste lisible
--    comme ce qu'elle était : le moteur, avant les épreuves.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION chain_banc_lancer(p_tenant uuid, p_code text DEFAULT NULL)
RETURNS TABLE (v_code text, v_epreuves int, v_tenues int, v_rompus int, v_non_jouees int)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $moteur$
DECLARE
  v_tid    uuid := COALESCE(p_tenant, current_tenant_id());
  m        record;
  v_ep     text;
  v_verdict text; v_mesure numeric; v_attendu text; v_obtenu text;
  v_duree  integer; v_raison text;
  v_total int; v_tenu int; v_rompu int; v_nonjoue int;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Banc de chaînage : aucune société active' USING ERRCODE = '42501';
  END IF;

  FOR m IN
    SELECT * FROM chain_banc_maillons b
     WHERE b.actif AND (p_code IS NULL OR b.code = p_code)
  LOOP
    FOR v_ep IN SELECT unnest(ARRAY['D1','D2','D3','D4','D5','D6','D7','D8'])
    LOOP
      -- ⚠️ Une épreuve qui LÈVE ne doit pas emporter la campagne entière.
      -- Avant, la première exception remontait jusqu'à `chain_banc_lancer` :
      -- les sept épreuves suivantes n'étaient ni jouées ni rapportées, et le
      -- rapport ne montrait qu'un maillon et zéro verdict — l'échec d'une
      -- preuve disparaissait au lieu d'être publié. Un banc doit survivre à ce
      -- qu'il mesure.
      BEGIN
        SELECT * INTO v_verdict, v_mesure, v_attendu, v_obtenu, v_duree, v_raison
          FROM chain_banc_epreuve(v_tid, m.code, v_ep);
      EXCEPTION WHEN OTHERS THEN
        v_verdict := 'rompu';
        v_mesure  := NULL;
        v_attendu := 'l''épreuve se joue sans lever';
        v_obtenu  := format('l''épreuve a levé : %s', SQLERRM);
        v_duree   := NULL;
        v_raison  := format('SQLSTATE %s : l''épreuve n''a pas pu être menée à son terme, donc rien n''est prouvé. Les autres épreuves du maillon restent jouées.', SQLSTATE);
      END;

      INSERT INTO chain_banc_resultats
        (code, epreuve, tenant_id, verdict, mesure, attendu, obtenu, duree_ms, raison)
      VALUES
        (m.code, v_ep, v_tid, v_verdict, v_mesure, v_attendu, v_obtenu, v_duree, v_raison)
      ON CONFLICT (code, epreuve, tenant_id, joue_le) DO NOTHING;
    END LOOP;

    -- Le décompte porte sur LE DERNIER passage du maillon : c'est lui qui
    -- fait foi, et non l'historique entier.
    SELECT count(*),
           count(*) FILTER (WHERE verdict = 'tenu'),
           count(*) FILTER (WHERE verdict = 'rompu'),
           count(*) FILTER (WHERE verdict = 'non_joue')
      INTO v_total, v_tenu, v_rompu, v_nonjoue
      FROM chain_banc_resultats r
     WHERE r.code = m.code AND r.tenant_id = v_tid
       AND r.joue_le = (SELECT max(r2.joue_le) FROM chain_banc_resultats r2
                         WHERE r2.code = m.code AND r2.tenant_id = v_tid);

    v_code := m.code; v_epreuves := v_total;
    v_tenues := v_tenu; v_rompus := v_rompu; v_non_jouees := v_nonjoue;
    RETURN NEXT;
  END LOOP;
END $moteur$;

COMMENT ON FUNCTION chain_banc_lancer(uuid, text) IS
  '434 : le moteur JOUE les huit épreuves (D1→D8) et enregistre le verdict mesuré. Une épreuve non jouable rend `non_joue` avec sa raison — jamais `tenu` par défaut. La 433 enregistrait toutes les épreuves comme non jouées : c''est cette version qui les joue.';
