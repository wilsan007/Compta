-- ═══════════════════════════════════════════════════════════════════════════
-- 766_chain_regenerer_en_cascade.sql — L20 · tranche 2 : LA RÉGÉNÉRATION
--       EN CASCADE (corriger la racine recompose ses effets, un par un)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- LE LOT. M-04 (plan, phase F) : « tout effet paramétrique se régénère ; on
-- ne corrige jamais une ligne à la main ». La tranche 1 (422) a livré la
-- moitié qui PROTÈGE — le retour arrière, avec historique ; cette 766 livre
-- la moitié qui EXÉCUTE : `chain_regenerer_en_cascade` rejoue les effets
-- d'une racine corrigée, chacun par le repreneur déclaré pour SON effet —
-- et le rapport dit, en trois listes, ce qui a été régénéré, ce qui n'avait
-- pas de repreneur, et où la chaîne s'est rompue.
--
-- DÉFAUT ROUGE MESURÉ (suite 766, T01 avant cette migration) : la fonction
-- n'existe pas — « function chain_regenerer_en_cascade(uuid, text, uuid,
-- text) does not exist » (SQLSTATE 42883). La répartition des frais de la
-- 765 est donc un aller simple : corriger `landed_costs.total_amount` ne
-- rejoue rien, et la CUMP reste à 55,00 au lieu de repasser à 60,00.
--
-- CE QUE CE FICHIER POSE :
--   1. Le registre `chain_repreneurs` (effet → RPC de régénération), global,
--      lu en lecture seule par l'écran, écrit par les migrations — c'est lui
--      qui dit « cet effet se régénère, et par quoi ». Sans nom, un effet ne
--      peut pas être contrôlé : même doctrine que le contrat L7 et le
--      registre `chain_document_types` de la 450.
--   2. `chain_repreneur_landed_cost`, le premier repreneur : il INVERSE la
--      répartition antérieure (part exacte, aucun arrondi accumulé), remet
--      le frais à `pending` et relance `distribute_landed_cost` — la 765
--      reste le SEUL moteur de répartition, l'effet régénéré par appui.
--   3. `chain_regenerer_en_cascade(tenant, amont_type, amont_id, cause)` :
--      la cascade — garde de société, garde de cause, garde de lien (les
--      trois refus de la suite), puis pour chaque effet de la racine :
--      liens actifs → fermeture `remplace` (motif = cause) AVANT l'exécution
--      (sinon `link_documents` fusionnerait dans l'ancien lien et la
--      génération ne monterait pas de tour), repreneur, journal
--      (`chain_regenerate` : avant/après + événement `chain.regenerated`),
--      descente par les liens ACTIFS de l'effet vers leurs aval, avec
--      anti-cycle (ensemble des nœuds déjà vus) et borne de profondeur (8
--      niveaux, la borne du dépôt depuis la 302).
--   4. L'événement `chain.cascade_regenerated` au catalogue (porte 415) et
--      son émetteur — le rapport complet en payload.
--
-- CE QUI N'EST PAS SUIVI, ET POURQUOI (M-03 : passer ne répare pas) :
--   * un effet SANS repreneur déclaré : NOMMÉ dans le rapport
--     (`sans_repreneur`), liens intacts — 766 T07 ;
--   * un lien ROMPU : la cascade ne le suit pas, elle NOMME la rupture
--     (`ruptures`) — 766 T08 ;
--   * un document sans AUCUN lien : refus, parce qu'un effet jamais produit
--     n'a rien à rejouer — 766 T04 ;
--   * un effet dont aucun lien n'est actif (rompu, ou remplacé sans
--     renouvellement) : nommé aussi dans `ruptures`, jamais tu.
--
-- LIMITES DITES :
--   * le journal est écrit par `chain_regenerate` (un seul moteur par
--     grandeur) : son `avant` agrège TOUS les payloads des liens de l'effet,
--     générations remplacées comprises (elles conservent leur payload) ;
--     `apres` porte le rapport du repreneur, déclaré comme dans la 422 ;
--   * le retour arrière de la 422 est positionnel sur les payloads : une
--     cascade a changé le NOMBRE de liens (une génération fermée, une
--     créée), il refuse donc (« remise impossible », ou « déjà dans l'état
--     antérieur ») — il ne corrompt pas, c'est son garde-fou qui parle ; la
--     limite est écrite ici pour qu'on ne la cherche pas ailleurs ;
--   * l'inverse de répartition est exact si la CUMP n'a pas bougé entre-temps
--     (un autre mouvement sur le même article) : la part retirée est celle
--     qui a été ajoutée, pas un recalcul depuis zéro ;
--   * la borne de profondeur (8) arrête une cascade anormalement profonde
--     sans la faire échouer : `profondeur` dans le rapport dit le niveau
--     atteint — au-delà, la descente se tait et le reste est au rapport.
--
-- ROUGE D'ABORD — la suite 766 (T01→T08) est le contrat : T01 mesure la CUMP
-- 55,00 → 60,00 après correction 100 → 200, les fermetures ET les créations
-- de liens, la ligne de journal avec sa cause ; T02→T04 les trois refus ;
-- T05 le triplet journal/événement/catalogue ; T06 le rejeu REFUSÉ nommé
-- (contrat unifié 658 + 765 — la suite est réécrite pour le mesurer) ; T07
-- et T08 les deux non-suivis nommés.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le registre des repreneurs (effet → RPC de régénération) ─────────────
-- Même forme que `chain_document_types` (450) : global (pas de `tenant_id`),
-- RLS en lecture pour l'écran, aucune politique ni droit d'écriture — les
-- migrations sont les seules à y écrire. La CHECK sur `fonction` dit que le
-- registre ne contient que des identifiants (l'appel se fait par `%I`).
CREATE TABLE IF NOT EXISTS public.chain_repreneurs (
  effet      text PRIMARY KEY,
  fonction   text NOT NULL,
  libelle_fr text NOT NULL,
  actif      boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chain_repreneurs_fonction_check CHECK (fonction ~ '^[a-z_][a-z_0-9]*$'),
  CONSTRAINT chain_repreneurs_libelle_check  CHECK (btrim(libelle_fr) <> '')
);

COMMENT ON TABLE public.chain_repreneurs IS
  '766 : registre des repreneurs de régénération — un effet (document_links.effet) qui se régénère, et la fonction qui le régénère. Lu par chain_regenerer_en_cascade (766), en lecture seule pour l''écran ; écrit par les migrations. Un effet absent du registre est NOMMÉ « sans_repreneur » dans le rapport de cascade, jamais tu.';

ALTER TABLE public.chain_repreneurs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chain_repreneurs_lecture ON public.chain_repreneurs;
CREATE POLICY chain_repreneurs_lecture ON public.chain_repreneurs
  FOR SELECT TO authenticated USING (true);
REVOKE ALL ON public.chain_repreneurs FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.chain_repreneurs TO authenticated;

-- Première ligne : la répartition des frais accessoires (765) est le premier
-- effet régénérable du dépôt — c'est le défaut mesuré par la suite 766.
INSERT INTO public.chain_repreneurs (effet, fonction, libelle_fr, actif)
VALUES (
  'stock.landed_cost.distributed',
  'chain_repreneur_landed_cost',
  'Inverse la répartition antérieure (part exacte sur la CUMP) puis relance distribute_landed_cost sur le total corrigé.',
  true)
ON CONFLICT (effet) DO UPDATE SET
  fonction   = EXCLUDED.fonction,
  libelle_fr = EXCLUDED.libelle_fr,
  actif      = EXCLUDED.actif;

-- ── 2. Le premier repreneur : la CUMP des frais accessoires ─────────────────
-- Signature UNIFORME des repreneurs : (société, type amont, identifiant amont,
-- cause) → jsonb — c'est cette forme que le moteur de cascade appelle par
-- `%I` depuis le registre. Le jsonb rendu devient l'`apres` du journal.
CREATE OR REPLACE FUNCTION public.chain_repreneur_landed_cost(
  p_tenant uuid,
  p_amont_type text,
  p_amont_id uuid,
  p_cause text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_lc       landed_costs%ROWTYPE;
  v_ligne    record;
  v_nb       integer := 0;
  v_produits jsonb;
BEGIN
  -- Cloisonnement (règle 1 de check_tenant_guard : `current_tenant_id()` est
  -- lu ici) — le repreneur écrit dans le stock, il vérifie la société.
  IF p_tenant IS NULL OR current_tenant_id() IS DISTINCT FROM p_tenant THEN
    RAISE EXCEPTION 'Régénération refusée : aucune société ou société hors contexte de l''appelant (cloisonnement fermé).'
      USING ERRCODE = '23514';
  END IF;
  IF p_amont_type IS DISTINCT FROM 'landed_costs' THEN
    RAISE EXCEPTION 'Régénération refusée : ce repreneur ne régénère que des frais accessoires (landed_costs), pas « % ».', p_amont_type
      USING ERRCODE = '23514';
  END IF;

  SELECT * INTO v_lc FROM landed_costs
   WHERE id = p_amont_id AND tenant_id = p_tenant;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Régénération refusée : frais accessoire % introuvable dans cette société — rien à régénérer.', p_amont_id
      USING ERRCODE = '23514';
  END IF;
  IF v_lc.status = 'cancelled' THEN
    RAISE EXCEPTION 'Régénération refusée : frais accessoire annulé — une cascade ne relance pas un frais annulé.'
      USING ERRCODE = '23514';
  END IF;

  -- 1. INVERSION de la répartition antérieure. Chaque ligne avait ajouté
  --    (nouveau − original) au coût unitaire du produit : on retire
  --    EXACTEMENT cette part. L'inverse exact conserve la propriété — après
  --    l'inversion, l'état est celui d'avant la première répartition, sans
  --    arrondi accumulé (une soustraction de la même différence).
  FOR v_ligne IN
    SELECT l.product_id, l.original_unit_cost, l.new_unit_cost
      FROM landed_cost_lines l
     WHERE l.landed_cost_id = p_amont_id
       AND l.tenant_id = p_tenant
  LOOP
    UPDATE stock_quantities
       SET unit_cost  = unit_cost - (v_ligne.new_unit_cost - v_ligne.original_unit_cost),
           updated_at = now()
     WHERE product_id = v_ligne.product_id
       AND tenant_id = p_tenant;
  END LOOP;

  DELETE FROM landed_cost_lines
   WHERE landed_cost_id = p_amont_id
     AND tenant_id = p_tenant;

  -- 2. Le frais repasse à `pending` : un frais DÉJÀ réparti est REFUSÉ
  --    nommé (contrat unifié 658 + 765) — le repreneur remet donc l'état
  --    à zro (lignes effacées ci-dessus) avant de relancer, sur le total
  --    AYANT ÉTÉ CORRIGÉ.
  UPDATE landed_costs
     SET status = 'pending'
   WHERE id = p_amont_id
     AND tenant_id = p_tenant;

  -- 3. RÉPARTITION sur le total corrigé — par le maillon 765 lui-même : la
  --    base est recalculée depuis les mouvements (immuables), les lignes sont
  --    réécrites, la CUMP réajustée et les liens retracés (les anciens sont
  --    déjà en `remplace`, le tour monte).
  PERFORM distribute_landed_cost(p_amont_id);

  SELECT count(*) INTO v_nb
    FROM landed_cost_lines
   WHERE landed_cost_id = p_amont_id
     AND tenant_id = p_tenant;

  -- Les faits rendus au journal : quels articles, avec quelle CUMP en sortie.
  SELECT COALESCE(jsonb_agg(jsonb_build_object('article', pr.sku, 'cump', sq.unit_cost)
                            ORDER BY pr.sku), '[]'::jsonb)
    INTO v_produits
    FROM stock_quantities sq
    JOIN products pr ON pr.id = sq.product_id
   WHERE sq.tenant_id = p_tenant
     AND EXISTS (SELECT 1 FROM landed_cost_lines l
                  WHERE l.landed_cost_id = p_amont_id
                    AND l.product_id = sq.product_id);

  RETURN jsonb_build_object(
    'success',       true,
    'repreneur',     'chain_repreneur_landed_cost',
    'landed_cost_id', p_amont_id,
    'cause',         p_cause,
    'lignes',        v_nb,
    'total_reparti', v_lc.total_amount,
    'cumps',         v_produits);
END;
$$;

-- Fonction INTERNE : appelée par le moteur de cascade (SECURITY DEFINER) en
-- contexte propriétaire ; elle n'est exposée à personne (et sort donc du
-- périmètre « exposée + uuid » de check_tenant_guard, règle 1).
REVOKE ALL ON FUNCTION public.chain_repreneur_landed_cost(uuid, text, uuid, text)
  FROM PUBLIC, anon, authenticated;

-- ── 3. Le moteur : la marche de cascade ─────────────────────────────────────
-- Fonction INTERNE (non exposée) : elle ne décide rien de la société — la
-- racine est gardée par l'appelant — elle ne fait que marcher. Le rapport est
-- un jsonb MUTABLE de proche en proche : les compteurs s'y ajoutent, et
-- l'ensemble des nœuds déjà vus y voyage sous la clé interne `_vus`
-- (retirée à la sortie par l'appelant) : c'est l'anti-cycle, il coupe tout
-- retour à un document déjà visité, même par un autre chemin.
CREATE OR REPLACE FUNCTION public._chain_regen_marcher(
  p_tenant uuid,
  p_amont_type text,
  p_amont_id uuid,
  p_cause text,
  p_profondeur integer,
  p_rapport jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_effets text[];
  v_effet  text;
  v_actifs integer;
  v_rompus integer;
  v_fn     text;
  v_apres  jsonb;
  v_aval   record;
  v_ligne  record;
  v_cle    text;
BEGIN
  -- Borne de profondeur (8) : la cascade descend au plus huit niveaux sous la
  -- racine — même borne que l'éclatement de nomenclature (302). Au-delà, on
  -- se TAIT (le rapport porte `profondeur`) plutôt que de faire échouer une
  -- régulation légitime pour cause de graphe anormalement profond.
  IF p_profondeur >= 8 THEN
    RETURN p_rapport;
  END IF;

  SELECT array_agg(DISTINCT dl.effet) INTO v_effets
    FROM document_links dl
   WHERE dl.tenant_id = p_tenant
     AND dl.amont_type = p_amont_type
     AND dl.amont_id   = p_amont_id;

  -- Un nœud imbriqué sans lien : la branche s'y termine. Le refus « rien à
  -- régénérer » est celui de la RACINE (766 T04), pas celui d'une feuille.
  IF v_effets IS NULL THEN
    RETURN p_rapport;
  END IF;

  FOREACH v_effet IN ARRAY v_effets LOOP
    SELECT count(*) FILTER (WHERE dl.etat = 'actif'),
           count(*) FILTER (WHERE dl.etat = 'rompu')
      INTO v_actifs, v_rompus
      FROM document_links dl
     WHERE dl.tenant_id = p_tenant
       AND dl.amont_type = p_amont_type
       AND dl.amont_id   = p_amont_id
       AND dl.effet      = v_effet;

    -- Aucun lien actif : la cascade ne suit pas, elle NOMME (M-03). Rompu
    -- comme remplacé-sans-renouvellement atterrissent ici — passer sous
    -- silence laisserait un trou dans le rapport.
    IF v_actifs = 0 THEN
      p_rapport := p_rapport || jsonb_build_object(
        'ruptures', (p_rapport -> 'ruptures') || jsonb_build_array(v_effet));
      CONTINUE;
    END IF;

    -- Le repreneur déclaré au registre pour CET effet.
    SELECT fonction INTO v_fn
      FROM chain_repreneurs
     WHERE effet = v_effet
       AND actif;

    IF v_fn IS NULL THEN
      -- Sans repreneur : NOMMÉ, liens intacts — régénérer à moitié (fermer
      -- sans savoir rejouer) laisserait la chaîne pire qu'avant (766 T07).
      p_rapport := p_rapport || jsonb_build_object(
        'sans_repreneur', (p_rapport -> 'sans_repreneur') || jsonb_build_array(v_effet));
      CONTINUE;
    END IF;

    -- 1. FERMER les liens actifs (REMPLACE, motif = cause) AVANT l'exécution.
    --    L'ordre est la clause de la fusion : encore actifs, les liens neufs
    --    se fusionneraient dans les anciens (link_documents, clé partielle
    --    `etat = 'actif'`) et la génération ne monterait pas de tour.
    --    GROUPÉ PAR LIGNE AMONT : un maillon qui lie par ligne (réception de
    --    la 319) a autant de fermetures que de lignes, et fermer « au niveau
    --    en-tête » ne trouverait AUCUN lien actif (leur `amont_ligne_id` est
    --    renseigné) — le socle lèverait « rien à fermer ».
    FOR v_ligne IN
      SELECT DISTINCT dl.amont_ligne_id
        FROM document_links dl
       WHERE dl.tenant_id = p_tenant
         AND dl.amont_type = p_amont_type
         AND dl.amont_id   = p_amont_id
         AND dl.effet      = v_effet
         AND dl.etat       = 'actif'
    LOOP
      PERFORM chain_lien_remplacer(p_tenant, p_amont_type, p_amont_id,
                                   v_effet, p_cause, v_ligne.amont_ligne_id);
    END LOOP;

    -- 2. Rejouer l'effet par sa fonction du registre (appel par identifiant,
    --    `%I` : le nom est un identifiant, la CHECK du registre l'a gardé tel).
    EXECUTE format('SELECT %I($1, $2, $3, $4)', v_fn)
      INTO v_apres
      USING p_tenant, p_amont_type, p_amont_id, p_cause;

    -- 3. Le journal — par le socle (un seul moteur par grandeur) : il photographie
    --    les payloads des liens de l'effet, écrit l'entrée et émet
    --    `chain.regenerated`. `apres` est le rapport du repreneur (déclaré,
    --    comme dans la 422 — le socle le dit lui-même).
    PERFORM chain_regenerate(p_tenant, v_effet, p_amont_type, p_amont_id, p_cause, v_apres);

    p_rapport := p_rapport || jsonb_build_object(
      'regeneres', (p_rapport ->> 'regeneres')::int + 1);

    -- 4. Descente par les liens ACTIFS de l'effet régénéré : chaque aval
    --    devient racine de son sous-arbre (le même traitement, plus bas).
    --    Les liens ROMPU ne sont pas suivis (ils sont déjà nommés) ; un
    --    lien de `sans_repreneur` non plus — rien n'a changé en amont.
    FOR v_aval IN
      SELECT DISTINCT dl.aval_type, dl.aval_id
        FROM document_links dl
       WHERE dl.tenant_id = p_tenant
         AND dl.amont_type = p_amont_type
         AND dl.amont_id   = p_amont_id
         AND dl.effet      = v_effet
         AND dl.etat       = 'actif'
    LOOP
      v_cle := v_aval.aval_type || ':' || v_aval.aval_id;
      IF (p_rapport -> '_vus') @> jsonb_build_array(v_cle) THEN
        CONTINUE;  -- déjà vu : un graphe en boucle ne tourne pas (anti-cycle)
      END IF;
      p_rapport := p_rapport || jsonb_build_object(
        '_vus', (p_rapport -> '_vus') || jsonb_build_array(v_cle));
      p_rapport := public._chain_regen_marcher(
        p_tenant, v_aval.aval_type, v_aval.aval_id, p_cause,
        p_profondeur + 1, p_rapport);
    END LOOP;
  END LOOP;

  p_rapport := p_rapport || jsonb_build_object(
    'profondeur', GREATEST((p_rapport ->> 'profondeur')::int, p_profondeur));

  RETURN p_rapport;
END;
$$;

REVOKE ALL ON FUNCTION public._chain_regen_marcher(uuid, text, uuid, text, integer, jsonb)
  FROM PUBLIC, anon, authenticated;

-- ── 4. La porte publique : la cascade ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_regenerer_en_cascade(
  p_tenant uuid,
  p_amont_type text,
  p_amont_id uuid,
  p_cause text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_liens   bigint;
  v_rapport jsonb;
BEGIN
  -- 1. CLOISONNEMENT. La société demandée doit être celle du contexte
  --    connecté — `current_tenant_id()` est lu ici, la garde ne se laisse pas
  --    écraser (check_tenant_guard, règle 1). Un contexte ABSENT ne passe
  --    pas : le repreneur qui suit lit lui aussi le contexte (la 765
  --    s'appuie sur `current_tenant_id()`), mieux vaut le refuser à la porte
  --    que de le voir échouer au milieu, en plein écriture.
  IF p_tenant IS NULL OR current_tenant_id() IS DISTINCT FROM p_tenant THEN
    RAISE EXCEPTION 'Régénération en cascade refusée : aucune société ou société hors contexte de l''appelant (cloisonnement fermé).'
      USING ERRCODE = '23514';
  END IF;

  -- 2. LA CAUSE. Une cascade sans cause est une régénération muette : la
  --    cause devient le motif de fermeture des liens, la cause du journal et
  --    la clé du rapport — les trois la portent, aucune ne l'invente.
  IF COALESCE(btrim(p_cause), '') = '' THEN
    RAISE EXCEPTION 'Régénération en cascade refusée : cause vide — une régénération sans cause n''est pas explicable (M-04).'
      USING ERRCODE = '23514';
  END IF;

  -- 3. LA RACINE est complète.
  IF p_amont_id IS NULL OR COALESCE(btrim(p_amont_type), '') = '' THEN
    RAISE EXCEPTION 'Régénération en cascade refusée : racine incomplète (type de document ou identifiant manquant).'
      USING ERRCODE = '23514';
  END IF;

  -- 4. LA RACINE A-T-ELLE DÉJÀ PRODUIT ? Aucun lien (ni actif, ni fermé) :
  --    il n'y a rien à régénérer — un effet jamais produit ne se rejoue pas
  --    (766 T04 : le refus nomme le lien).
  SELECT count(*) INTO v_liens
    FROM document_links dl
   WHERE dl.tenant_id = p_tenant
     AND dl.amont_type = p_amont_type
     AND dl.amont_id   = p_amont_id;

  IF v_liens = 0 THEN
    RAISE EXCEPTION 'Régénération en cascade refusée : aucun lien sur % % — il n''y a rien à régénérer : le maillon doit d''abord produire son effet (link_documents).',
      p_amont_type, p_amont_id
      USING ERRCODE = '23514';
  END IF;

  v_rapport := jsonb_build_object(
    'regeneres',      0,
    'sans_repreneur', jsonb_build_array(),
    'ruptures',       jsonb_build_array(),
    'cause',          p_cause,
    'racine',         jsonb_build_object('type', p_amont_type, 'id', p_amont_id),
    'profondeur',     0,
    '_vus',           jsonb_build_array(p_amont_type || ':' || p_amont_id));

  v_rapport := public._chain_regen_marcher(
    p_tenant, p_amont_type, p_amont_id, p_cause, 0, v_rapport);

  -- La clé interne de la marche ne SORT pas : le rapport promis au lecteur
  -- est regeneres / sans_repreneur / ruptures / cause / racine / profondeur.
  v_rapport := v_rapport - '_vus';

  -- L'événement de synthèse (catalogue : chain.cascade_regenerated). Son
  -- payload EST le rapport — un abonné voit d'un coup où la cascade a
  -- régénéré, où elle s'est tue et où elle s'est rompue.
  PERFORM emit_domain_event(p_tenant, 'chain.cascade_regenerated',
    p_amont_type, p_amont_id, v_rapport, NULL);

  RETURN v_rapport;
END;
$$;

COMMENT ON FUNCTION public.chain_regenerer_en_cascade(uuid, text, uuid, text) IS
  '766 (L20 tranche 2) : régénère en cascade les effets d''une racine corrigée — garde société/cause/lien, fermeture des liens actifs (remplace, motif = cause), repreneur du registre chain_repreneurs, journal chain_regenerate, descente par les liens actifs (anti-cycle, profondeur max 8). Rend le rapport : regeneres, sans_repreneur, ruptures, cause, racine, profondeur.';

REVOKE ALL ON FUNCTION public.chain_regenerer_en_cascade(uuid, text, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chain_regenerer_en_cascade(uuid, text, uuid, text)
  TO authenticated;

-- ── 5. Le catalogue des événements (porte 415) ──────────────────────────────
-- Un événement émis par une fonction du produit doit être au catalogue, sous
-- peine du rouge auto-entretenu de la 415 T05 (les deux sens) : produit sans
-- ligne, ou ligne sans producteur — ici la ligne et son émetteur arrivent
-- dans le MÊME fichier.
INSERT INTO public.webhook_event_catalog (event_name, description, category, is_active)
VALUES (
  'chain.cascade_regenerated',
  'L20 : une régénération en cascade a recomposé les effets d''une racine corrigée. Le payload EST le rapport de cascade — regeneres, sans_repreneur, ruptures, cause, racine, profondeur.',
  'chain',
  true)
ON CONFLICT (event_name) DO UPDATE SET
  description = EXCLUDED.description,
  category    = EXCLUDED.category,
  is_active   = EXCLUDED.is_active;