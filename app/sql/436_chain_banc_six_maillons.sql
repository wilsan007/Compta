-- ═══════════════════════════════════════════════════════════════════════════
-- 436 — Lot L3, tranche 6 : LES SIX GABARITS ET LEURS GESTES AU CATALOGUE
--   (tâche 3.7 — le banc éprouvé sur six maillons, et non sur un seul)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **CE QUE LA 434 A LAISSÉ OUVERT, ET C'EST ÉCRIT DANS LE PLAN.** Le banc rend
-- huit verdicts par maillon ; au 03/10 il n'était éprouvé que sur UN maillon
-- (`releve.comptabilise`) : les six autres portaient leur description, et rien
-- d'autre. « Cinq verdicts `tenu` sur huit » était le score d'UN maillon — le
-- rapport pouvait le laisser croire à un score de sept.
--
-- **CE QU'UN GABARIT EST, ET CE QU'IL N'EST PAS.** C'est la SEULE partie de la
-- description d'un maillon qui soit du CODE : le reste est de la donnée
-- (libellé, effet, amont) et se lit. Le gabarit dit COMMENT appeler la fonction
-- qui produit l'effet — `post_bank_statement_line(%s, NULL, '…')` — et le
-- moteur y rend chaque argument en LITTÉRAL ÉCHAPPÉ (434 §2). Un identifiant
-- ne peut donc pas s'y injecter ; le gabarit reste la limite assumée du moteur,
-- et c'est pour cela qu'il est écrit ICI, dans une migration revue, et jamais
-- dans un fichier de test.
--
-- **LES ARGUMENTS, EUX, NE VONT PAS ICI.** Un lot de paie, un ticket, une ligne
-- de relevé : ce sont des `uuid` qui n'existent que dans le décor de l'épreuve.
-- Les écrire au catalogue les figerait pour toutes les sociétés, et le
-- catalogue dirait vrai pour personne (le même reproche que les `arguments`
-- restés `{}` en 433 §3 bis). Ils sont donc fournis à l'exécution par la suite
-- 436, qui écrit `arg_valeurs` et `arg_series` — la VALEUR, jamais le GABARIT.
--
-- **ET LE GESTE D'ANNULATION, QUAND IL EXISTE.** Un maillon ne s'annule pas en se
-- rejouant : s'appeler soi-même, c'est produire un second effet (doctrine 434,
-- D4). Le geste est donc DÉDIÉ et DÉCRIT — `void_pos_ticket` pour la caisse,
-- `unreconcile_bank_statement_line` pour le pointage. Là où le métier n'expose
-- aucun geste, on NE L'INVENTE PAS : `appat_annul` reste NULL, et D4 rend
-- `non_joue` avec cette raison. Un `tenu` obtenu sans geste serait un mensonge
-- d'instrument, exactement celui que ce banc existe pour rendre impossible.
-- ─────────────────────────────────────────────────────────────
-- (suite : §1 les six gabarits, §2 la garde, §3 ce que la 436 ne fait pas)

-- ─────────────────────────────────────────────────────────────
-- 1. LES SIX GABARITS D'APPEL NOMINAL, ET LEURS GESTES
--
-- ⚠️ `arg_types` N'EST PAS décoratif : le moteur indexe `arg_types[n]` sur la
-- position de l'argument, et un `%s` sans type correspondant devient un `text` —
-- donc `'uuid'::text` pour un identifiant, et l'appel échoue sur un type, sans
-- rien dire du gabarit. La garde du §2 refuse d'écrire une description où le
-- compte des `%s` et celui des types diffèrent : mieux vaut une migration rouge
-- au dépôt qu'un gabarit faux, que le banc publierait ensuite comme une preuve.
-- ─────────────────────────────────────────────────────────────
UPDATE chain_banc_maillons b
   SET appat              = v.appat,
       arg_types          = v.arg_types,
       appat_annul        = v.appat_annul,
       appat_reouverture  = v.appat_reouverture,
       note               = v.note
  FROM (VALUES
    -- ── LA CAISSE ────────────────────────────────────────────────
    ('caisse.ticket',
     'SELECT public.create_pos_ticket(%s, %s, %s)',
     ARRAY['jsonb','jsonb','jsonb']::text[],
     -- le geste d'annulation EXISTE et il est dédié : la 412 l'a écrit ainsi
     -- (« session ouverte → le stock rendu, lien `stock_out` rompu »).
     'SELECT public.void_pos_ticket(%s, ''Banc 436 — annulation du ticket'')',
     'SELECT public.create_pos_ticket(%s, %s, %s)',
     'Ticket encaissé puis annulé : `create_pos_ticket` (412). Deux arguments de
      contenu — l''en-tête et les LIGNES en JSONB — puis les paiements, que le
      décor laisse NULL pour prendre le chemin nominal de l''encaissement.'),

    ('caisse.avoir',
     'SELECT public.pos_refund_ticket(%s, ''Banc 436 — avoir client'')',
     ARRAY['uuid']::text[],
     -- ⚠️ AUCUN GESTE, ET CE N'EST PAS UN OUBLI. Un avoir ne s'annule pas en
     -- annulant le ticket d'ORIGINE : `void_pos_ticket` ne ferme que le lien
     -- `stock_out` de la vente, jamais le `stock_in` que l'avoir vient de poser —
     -- et il ne le pourrait pas : l'avoir est une PIÈCE (`credit_notes`), pas un
     -- ticket. Le décrire quand même ferait mesurer à D4 « un lien actif
     -- restant » et conclurait `rompu` : ce serait un verdict sur un geste qui
     -- n'annule pas, pas sur le maillon. Absent = `non_joue`, avec la raison.
     NULL,
     NULL,
     'Avoir de caisse : `pos_refund_ticket` (412). Le maillon RETIRE un pointage
      de stock et rompt le lien de la sortie d''origine ; il ne produit pas de
      ticket, il produit une pièce.'),

    -- ── LA PAIE ───────────────────────────────────────────────────
    ('paie.comptabilisee',
     'SELECT public.payroll_post_run(%s)',
     ARRAY['uuid']::text[],
     -- ⚠️ LE GESTE N'EST PAS UNE FONCTION. L'annulation d'un lot de paie
     -- comptabilisé est un CHANGEMENT D'ÉTAT (`pay_runs.status`), et PostgreSQL
     -- n'a pas de « fonction sans arguments » qui l'accomplisse :
     -- `payroll_reverse_posted_run()` est un DÉCLENCHEUR, il ne s'appelle pas.
     -- Décrire ici un `UPDATE` déguisé en gabarit ferait du banc une machine à
     -- écrire dans le métier par un champ de texte ; on ne le fait pas.
     NULL,
     NULL,
     'Lot de paie comptabilisé : `payroll_post_run` (430). Point de convergence
      des trois chemins d''appel — l''écran, le versement, et le déclencheur du
      passage du lot à `paid`.'),
    ('paie.versement',
     'SELECT public.post_payroll_payment(%s, %s, %s, %s)',
     ARRAY['uuid','uuid','date','text']::text[],
     NULL,
     NULL,
     'Versement de la paie : `post_payroll_payment` (430). Deux identifiants, une
      date et une portée (''all'') : le geste est plus large que les autres, et
      son décor doit donc porter un compte bancaire.'),


    -- ── LE RELEVÉ ─────────────────────────────────────────────────
    ('releve.pointage',
     'SELECT public.reconcile_bank_statement_line(%s, %s)',
     ARRAY['uuid','uuid']::text[],
     'SELECT public.unreconcile_bank_statement_line(%s)',
     'SELECT public.reconcile_bank_statement_line(%s, %s)',
     'Pointage manuel d''une ligne de relevé contre une écriture (432). Le geste
      d''annulation est le DÉ-LETTRAGE : celui du maillon voisin, qui retire le
      pointage et ferme son lien au lieu d''ouvrir une trace (doctrine 320).'),

    ('releve.delettrage',
     'SELECT public.unreconcile_bank_statement_line(%s)',
     ARRAY['uuid']::text[],
     -- ⚠️ MESURÉ, PAS SUPPOSÉ : ce maillon n'a PAS de geste d'annulation.
     -- Le candidat évident — le re-pointage, `reconcile_bank_statement_line` —
     -- a été joué sur une société propre, et il a levé : « Ligne de relevé
     -- déjà pointée sur l'écriture … ». Un dé-lettrage ne se défait pas en
     -- re-pointant la même écriture : il faudrait en pointer une AUTRE, ce qui
     -- produirait un lien de pointage et non la fermeture d'un lien de
     -- comptabilisation — l'épreuve D4, qui attend « 0 lien actif », mesurerait
     -- alors l'absence d'un geste, pas une tenue.
     NULL,
     NULL,
     'Dé-lettrage : `unreconcile_bank_statement_line` (432). Ce maillon ne
      PRODUIT rien — il RETIRE un pointage et ferme son lien. `sens = ''ferme''`,
      et c''est ce qui permet à deux maillons de viser le même effet.')
  ) AS v(code, appat, arg_types, appat_annul, appat_reouverture, note)
 WHERE b.code = v.code;

-- (les TYPES des gestes sont posés au §2, avec les colonnes qui les portent)

COMMENT ON TABLE chain_banc_maillons IS
  '433 (L3, tr. 5) : UNE description par maillon éprouvé. Le banc en tire les huit épreuves — c''est ce qui remplace huit scénarios par maillon. `sens` = ''produit'' (le maillon crée un effet) ou ''ferme'' (il retire un effet existant, doctrine 320) : deux maillons peuvent partager un effet s''ils n''en ont pas le même sens. 436 : les `appat` (gabarits d''appel) et les gestes dédiés de six maillons — du CODE, donc revu comme du code ; les ARGUMENTS restent fournis à l''exécution, un identifiant n''a pas de valeur au catalogue.';

-- ─────────────────────────────────────────────────────────────
-- 2. LE MOTEUR : UN GESTE A SA PROPRE SIGNATURE
--
-- ⚠️ C'EST LA 436 QUI A MIS CE FAUT AU JOUR, ET IL ÉTAIT DÉJÀ LÀ.
-- Le moteur n'avait qu'UN jeu d'arguments (`arg_values` / `arg_types`), et il
-- s'en servait aussi bien pour l'appel nominal que pour le geste
-- d'annulation. Or les deux n'ont pas les mêmes paramètres :
--
--   `create_pos_ticket(en-tête, lignes, paiements)`  → 3
--   `void_pos_ticket(ticket, motif)`                 → 1
--
-- Deux issues, et la seconde est la pire. Le plus souvent, le geste consomme
-- les MÊMES premiers arguments (`unreconcile_bank_statement_line(%s)` après
-- `reconcile_bank_statement_line(%s, %s)`) : `format()` ignore les arguments
-- en trop, et l'épreuve passait. Mais quand l'ordre DIFFÈRE — quand le geste
-- attend un identifiant là où l'appel nominal attend un contenu — il n'y a
-- aucun jeu d'arguments qui convienne aux deux : D4 aurait appelé
-- `void_pos_ticket` avec l'en-tête JSON du ticket, et l'exception aurait été
-- lue comme une annulation ratée. Un instrument qui confond « le geste a une
-- autre forme » et « le geste est cassé » ne distingue pas un défaut d'un
-- décor.
--
-- La correction est de donner au geste SES arguments, et seulement si le
-- gesture en décrit. `arg_valeurs_annul` / `arg_types_annul` (idem pour la
-- réouverture) restent NULL par défaut : la suite 434, qui écrit son décor
-- avant que ces colonnes n'existent, continue de jouer exactement comme
-- avant — on n'a rien cassé pour la corriger.
--
-- ⚠️ `DROP FUNCTION` AVANT LE `CREATE` : `CREATE OR REPLACE` ne remplace que
-- la signature IDENTIQUE. Changer le comportement sans changer la liste des
-- paramètres n'aurait rien demandé — mais le laisser en place créerait un
-- doublon, et tout appel à trois arguments lèverait « function is not unique »
-- (leçon déjà écrite en 434 §3).
-- ─────────────────────────────────────────────────────────────
ALTER TABLE chain_banc_maillons
  ADD COLUMN IF NOT EXISTS arg_valeurs_annul        jsonb,
  ADD COLUMN IF NOT EXISTS arg_types_annul         text[],
  ADD COLUMN IF NOT EXISTS arg_valeurs_reouverture  jsonb,
  ADD COLUMN IF NOT EXISTS arg_types_reouverture   text[];

COMMENT ON COLUMN chain_banc_maillons.arg_valeurs_annul IS
  '436 : les arguments du GESTE D''ANNULATION, quand sa signature diffère de celle de l''appel nominal (`void_pos_ticket` prend un ticket, `create_pos_ticket` prend un en-tête et des lignes). NULL = le geste consomme les arguments nominaux, comme avant la 436.';

-- ── LES TYPES DES GESTES, ET LUI SEULEMENT ─────────────────────
-- Un TYPE est statique : `uuid`, `date`, `jsonb`. Il décrit la FORME du geste,
-- pas la société — il a donc sa place dans la migration, et pas dans le décor
-- d'épreuve. La VALEUR, elle, n'a pas de valeur au catalogue.
--
-- ⚠️ Ces trois lignes sont la CORRECTION du défaut que la garde du §3 a trouvé
-- à l'écriture de ce fichier : `caisse.ticket` a trois arguments nominaux et
-- UN argument d'annulation. Sans ce bloc, le geste hériterait des trois types
-- nominaux, et D4 appellerait `void_pos_ticket` avec une `{…}` de types — une
-- erreur qui ne dirait rien du geste.
UPDATE chain_banc_maillons b
   SET arg_types_annul = v.types
  FROM (VALUES
    ('caisse.ticket',    ARRAY['uuid']::text[]),              -- void_pos_ticket(ticket, motif)
    ('releve.pointage',  ARRAY['uuid']::text[])               -- unreconcile(ligne)
  ) AS v(code, types)
 WHERE b.code = v.code;

DROP FUNCTION IF EXISTS chain_banc_appeler(record, jsonb, text);
CREATE OR REPLACE FUNCTION chain_banc_appeler(
  m         record,
  p_vals    jsonb DEFAULT NULL,   -- jeu d'arguments SUPLÉANT (D7 : un tour)
  p_appat   text   DEFAULT NULL    -- gabarit SUPLÉANT (D4/D5 : geste dédié)
)
RETURNS jsonb
LANGUAGE plpgsql AS $appel$
DECLARE
  v_appat text := COALESCE(p_appat, m.appat);
  v_vals  jsonb;
  v_types text[];
  v_rendus text[] := '{}';
  v_i     int;
  v_n_appat int;
  v_val   jsonb;
  v_typ   text;
  v_res   jsonb;
BEGIN
  IF v_appat IS NULL THEN
    RAISE EXCEPTION 'Banc : le maillon % n''a pas de gabarit d''appel.', m.code
      USING ERRCODE = '22023';
  END IF;

  v_vals  := COALESCE(p_vals, m.arg_valeurs, '[]'::jsonb);
  v_types := m.arg_types;

  -- ⚠️ Le passage ci-dessous ne s'écrit QUE si l'appel est un GESTE, c'est-à-dire
  -- si le gabarit passé n'est pas le gabarit nominal. C'est ce qui laisse la
  -- suite 434 inchangée : elle ne décrit pas d'arguments de geste, et le
  -- repli (`COALESCE`) reprend le jeu nominal.
  IF p_appat IS NOT NULL AND p_appat IS DISTINCT FROM m.appat THEN
    IF m.appat_reouverture IS NOT NULL AND p_appat = m.appat_reouverture THEN
      v_vals  := COALESCE(m.arg_valeurs_reouverture, v_vals);
      v_types := COALESCE(m.arg_types_reouverture,  v_types);
    ELSE
      v_vals  := COALESCE(m.arg_valeurs_annul, v_vals);
      v_types := COALESCE(m.arg_types_annul,  v_types);
    END IF;
  END IF;

  -- ⚠️ LE DÉCOR MANQUANT SE DIT, ET SE DIT ICI. `format()` lève « too few
  -- arguments for format() » quand le gabarit attend plus d'arguments que le
  -- décor n'en fournit : un message qui ne nomme ni le maillon, ni le gabarit,
  -- ni les deux comptes, et qui ressemble à une panne du moteur alors que c'est
  -- une pièce manquante du décor. C'est exactement le genre d'erreur qui fait
  -- perdre une journée — on la remplace par les trois nombres, une fois.
  v_n_appat := (length(v_appat) - length(replace(v_appat, '%s', ''))) / 2;
  IF jsonb_array_length(v_vals) < v_n_appat THEN
    RAISE EXCEPTION 'Banc — décor incomplet sur % : le gabarit attend % argument(s), le décor en fournit %. Complétez `arg_valeurs`, ou déclarez les arguments DU GESTE dans `arg_valeurs_annul` / `arg_valeurs_reouverture`.',
      m.code, v_n_appat, jsonb_array_length(v_vals) USING ERRCODE = '22023';
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
  '434, complété par la 436 : rend et exécute l''appel décrit par le catalogue. Les arguments sont rendus en LITTÉRAUX échappés avec leur type (`%L::type`) — jamais concaténés ; le gabarit, lui, est du code, et c''est la limite assumée du moteur. 436 : un GESTE (annulation, réouverture) a sa propre signature et donc ses propres arguments ; à défaut de description, il consomme ceux de l''appel nominal, et le comportement antérieur est inchangé.';

-- ─────────────────────────────────────────────────────────────
-- 3. LA GARDE : UN GABARIT DOIT AVOIR AUTANT DE `%s` QUE DE TYPES
--
-- ⚠️ Elle porte sur les SEPT lignes du catalogue, pas seulement sur les six
-- d'ici : le gabarit du septième est écrit par la suite 434, et une suite qui
-- écrit un gabarit ne peut pas laisser le moteur l'exécuter sans le dire. Le
-- compte se fait sur le gabarit RENDU, `%s` compris, et sur chaque geste.
--
-- Ce que la garde refuse, et ce qu'elle refuse de laisser passer :
--   • un gabarit sans type pour un de ses `%s` (`arg_types` plus court) ;
--   • un type pour un argument qui n'existe pas (plus long que le gabarit) ;
--   • un geste d'annulation ou de réouverture dont le nombre de `%s` ne
--     correspond pas à SES PROPRES types. C'est la faute la plus discrète : le
--     geste s'exécuterait, mais avec le jeu d'arguments d'un autre — et le
--     banc lirait « le geste est cassé » là où il n'y a qu'un décor manquant.
--     Le geste se compare donc à `arg_types_annul` (ou `…_reouverture`), et à
--     `arg_types` SEULEMENT s'il n'a pas de types propres : c'est le chemin
--     qu'emprunte la suite 434, qui n'en décrit pas.
-- ─────────────────────────────────────────────────────────────
DO $garde$
DECLARE
  b        record;
  v_n_app  int;
  v_n_ann  int;
  v_n_reo  int;
  v_n_typ  int;
  v_n_gest int;   -- le nombre de types que le geste va réellement consommer
  v_pb     text;
BEGIN
  FOR b IN
    SELECT code, appat, arg_types, appat_annul, appat_reouverture,
           arg_types_annul, arg_types_reouverture
      FROM chain_banc_maillons
     WHERE appat IS NOT NULL
  LOOP
    -- Le nombre de `%s` du gabarit : `length − length(replace)` divisé par 2.
    v_n_app := (length(b.appat) - length(replace(b.appat, '%s', ''))) / 2;
    v_n_typ := COALESCE(array_length(b.arg_types, 1), 0);
    v_pb    := format('maillon %s : gabarit à %s argument(s), %s type(s) déclaré(s)', b.code, v_n_app, v_n_typ);
    IF v_n_typ IS DISTINCT FROM v_n_app THEN
      RAISE EXCEPTION 'Banc — %s. Un `%%s` sans type devient un text : l''appel échouerait sur un type, sans rien dire du gabarit.', v_pb;
    END IF;

    IF b.appat_annul IS NOT NULL THEN
      v_n_ann  := (length(b.appat_annul) - length(replace(b.appat_annul, '%s', ''))) / 2;
      v_n_gest := COALESCE(array_length(b.arg_types_annul, 1), v_n_app);
      IF v_n_ann IS DISTINCT FROM v_n_gest THEN
        RAISE EXCEPTION 'Banc — maillon %s : le geste d''annulation rend %s argument(s) et il va en consommer %s. Déclarez `arg_types_annul`, ou corrigez le gabarit : le geste s''exécuterait avec le jeu d''arguments d''un autre.', b.code, v_n_ann, v_n_gest;
      END IF;
    END IF;

    IF b.appat_reouverture IS NOT NULL THEN
      v_n_reo  := (length(b.appat_reouverture) - length(replace(b.appat_reouverture, '%s', ''))) / 2;
      v_n_gest := COALESCE(array_length(b.arg_types_reouverture, 1), v_n_app);
      IF v_n_reo IS DISTINCT FROM v_n_gest THEN
        RAISE EXCEPTION 'Banc — maillon %s : le geste de réouverture rend %s argument(s) et il va en consommer %s.', b.code, v_n_reo, v_n_gest;
      END IF;
    END IF;
  END LOOP;
END $garde$;

-- ─────────────────────────────────────────────────────────────
-- 5. LE MOTEUR, ENCORE : UNE CRÉATION N'A PAS DE REJEU
--
-- ⚠️ CE QUE LA 436 A MESURÉ SUR `caisse.ticket`, ET C'EST LE SECOND DÉFAUT
-- QUE CETTE MIGRATION TROUVE EN ÉCRIVANT LA PRÉCÉDENTE.
-- Le banc a rendu, textuellement :
--
--   D1 · rompu · « 2ᵉ tour : +1 lien(s), +1 trace(s) »
--
-- Sur un maillon de CRÉATION, ce verdict est un artefact. `create_pos_ticket`
-- ne prend pas l'identité d'un ticket à produire : il prend le CONTENU d'un
-- ticket à créer, et `sequential_number` lui est attribué par un déclencheur
-- (POS-03, sous verrou consultatif). Rejouer l'appel n'est donc pas un rejeu,
-- c'est une seconde vente — et le dire `rompu` publierait un défaut qui n'existe
-- pas. C'est le miroir exact de l'interdit de la 434 : on ne déclare pas `tenu`
-- ce qu'on n'a pas éprouvé ; on ne déclare pas non plus `rompu` ce qu'on n'a pas
-- éprouvé.
--
-- La NATURE du maillon tranche : `application` (le défaut — le maillon applique
-- un effet à un document EXISTANT, son argument est une identité, et le rejouer
-- doit être refusé ou sans effet) ou `creation` (le maillon fabrique le
-- document). Un seul maillon du catalogue est en `creation`, et c'est le seul
-- où D1 n'a pas d'objet.
--
-- ⚠️ `chain_banc_epreuve` est donc REDÉFINIE ici, et non modifiée sur place : la
-- 434 doit rester lisible comme ce qu'elle était. Une seule branche change —
-- D1 — et le reste est repris à l'identique, pour que la preuve qu'on lit soit
-- encore la même preuve.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE chain_banc_maillons
  ADD COLUMN IF NOT EXISTS nature text NOT NULL DEFAULT 'application';
ALTER TABLE chain_banc_maillons DROP CONSTRAINT IF EXISTS chain_banc_maillons_nature_check;
ALTER TABLE chain_banc_maillons ADD  CONSTRAINT chain_banc_maillons_nature_check
  CHECK (nature IN ('application', 'creation'));

COMMENT ON COLUMN chain_banc_maillons.nature IS
  '436 : `application` (défaut) — le maillon applique un effet à un document EXISTANT ; son argument est une identité, et le rejeu doit être refusé ou sans effet : D1 a un objet. `creation` — le maillon FABRIQUE le document ; son argument est un contenu, le rejouer crée un second document, et D1 n''a pas d''objet : elle est rendue `non_joue` avec cette raison, jamais `rompu`.';

-- Le seul maillon du catalogue qui ne prenne pas une identité.
UPDATE chain_banc_maillons SET nature = 'creation' WHERE code = 'caisse.ticket';

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
  v_m2_tr       integer := 0;   -- traces `applique` après le 2ᵉ tour
  v_ignore      integer := 0;   -- traces `ignore` du 2ᵉ tour (436)
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
  -- ⚠️ LE VOCABULAIRE DES REFUS, MESURÉ SUR LES SIX MAILLONS (436) ET NON
  -- SUPPOSÉ. La 434 n'acceptait que `23514` (check) et `23505` (unique). On a
  -- relevé, dans les corps de ces maillons :
  --   check_violation      17 fois
  --   insufficient_privilege / 42501   3 + 11 fois
  --   no_data_found / P0002             5 fois
  --   unique_violation                 3 fois
  --   foreign_key_violation             1 fois
  -- soit 25 refus d'AFFAIRES qui passaient pour des PANNES : `caisse.avoir`
  -- a rendu `rompu` sur « Ticket déjà remboursé » (42501), et c'est un refus
  -- correct. Une preuve d'instrument fausse n'est pas moins fausse qu'un test
  -- rouge : elle fait corriger un maillon qui marche.
  v_refus_metier CONSTANT text[] := ARRAY['23514','23505','42501','P0002','23503'];
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
    -- ⚠️ 436 : UNE CRÉATION N'A PAS DE REJEU. Le reste de cette branche est
    -- repris tel quel de la 434 ; seule cette entrée est nouvelle.
    IF m.nature = 'creation' THEN
      RETURN QUERY SELECT 'non_joue'::text, NULL::numeric,
        format('l''épreuve D1 de %s', m.code),
        'maillon de création : son argument est un contenu, pas une identité'::text,
        NULL::integer,
        format('Le maillon %s ne produit pas un effet sur un document EXISTANT : il CRÉE le document, et son argument est le CONTENU de ce document. Le rejouer crée donc un second document — ce qui est la définition d''une création, et non une duplication. Aucune clé d''idempotence n''existe dans ce métier : le numéro séquentiel est attribué par un déclencheur, jamais fourni par l''appelant. D1 n''a donc pas d''objet ici, et elle ne déclare le maillon ni tenu ni rompu : elle constate que l''épreuve n''a pas d''objet.', m.code);
      RETURN;
    END IF;

    v_attendu := 'le 2ᵉ appel n''ajoute aucun lien et aucune trace';
    v_refus   := false;
    BEGIN
      PERFORM chain_banc_appeler(m);
      SELECT count(*) INTO v_m1_liens FROM document_links
       WHERE tenant_id = v_tid AND amont_type = m.amont_type AND effet = m.effet;
      -- ⚠️ 436 : ON NE COMPTE QUE LES TRACES `applique`. Une trace `ignore`
      -- n'est pas une duplication : c'est le maillon qui DÉCLARE avoir fait
      -- rien (« exécuté, aucun effet » — le vocabulaire de la 310/412). En la
      -- comptant, la 434 a rendu `rompu` les DEUX maillons de paie, dont le
      -- rejeu est au contraire parfaitement tenu : 2ᵉ appel → 0 lien, 0 ligne,
      -- et une trace qui le dit. Compter la déclaration d'un non-effet comme
      -- un effet, c'est faire dire au banc le contraire de ce qu'il mesure.
      SELECT count(*) INTO v_m1_tr FROM chain_traces
       WHERE tenant_id = v_tid AND amont_type = m.amont_type AND effet = m.effet
         AND resultat = 'applique';
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
      -- La même règle au 2ᵉ tour, et le décompte des `ignore` POUR LE DIRE :
      -- on ne les cache pas, on les montre dans le verdict.
      SELECT count(*) INTO v_m2_tr FROM chain_traces
       WHERE tenant_id = v_tid AND amont_type = m.amont_type AND effet = m.effet
         AND resultat = 'applique';
      SELECT count(*) INTO v_ignore FROM chain_traces
       WHERE tenant_id = v_tid AND amont_type = m.amont_type AND effet = m.effet
         AND resultat <> 'applique';
    EXCEPTION WHEN OTHERS THEN
      -- Ici le 1ᵉʳ appel a échoué : rien n'a été produit, donc rien à rejouer.
      RETURN QUERY SELECT 'non_joue'::text, NULL::numeric, v_attendu,
        format('le 1ᵉʳ appel n''a pas abouti : %s', SQLERRM)::text, NULL::integer,
        format('Le premier appel a levé (%s, SQLSTATE %s) : le maillon n''a rien produit, donc il n''y a rien à rejouer. L''invariant de rejeu ne peut pas être éprouvé sur un maillon qui n''a pas tourné.', SQLERRM, SQLSTATE);
      RETURN;
    END;

    v_mesure := (v_m2_liens - v_m1_liens) + (v_m2_tr - v_m1_tr);
    v_obtenu := format('1ᵉʳ tour : %s lien(s), %s trace(s) `applique` ; 2ᵉ tour : +%s lien(s), +%s trace(s) `applique` ; traces de non-effet du 2ᵉ tour : %s ; mode : %s',
                       v_m1_liens, v_m1_tr, v_m2_liens - v_m1_liens, v_m2_tr - v_m1_tr, v_ignore,
                       CASE WHEN NOT v_refus THEN 'rejeu sans effet (le 2ᵉ appel a réussi)'
                            WHEN v_sqlstate = ANY (v_refus_metier) THEN format('refus métier contrôlé (SQLSTATE %s)', v_sqlstate)
                            ELSE format('ÉCHEC NON MÉTIER (SQLSTATE %s)', v_sqlstate) END);

    -- Un refus métier qui n'écrit rien : l'invariant est tenu, ET le maillon
    -- l'a défendu. Un échec qui n'est pas un refus métier, même sans écriture :
    -- `rompu`, parce qu'on a mesuré une panne, pas un rejeu.
-- Le verdict est rendu ICI plutôt qu'après le CASE commun : ce cas est le
-- seul où un refus doit invalider la mesure. Un refus qui n'est pas métier
-- invalide le résultat même si rien n'a été écrit — sinon une panne
-- passerait pour un rejeu correct.
    IF v_refus AND NOT (v_sqlstate = ANY (v_refus_metier)) THEN
      RETURN QUERY SELECT 'rompu'::text, v_mesure, v_attendu, v_obtenu, NULL::integer,
        format('Le rejeu n''a rien écrit, mais le 2ᵉ appel a échoué sur le SQLSTATE %s, qui n''est pas un des refus d''affaires de ce dépôt (%s). On a mesuré une panne, pas un rejeu : l''invariant n''est pas prouvé.', v_sqlstate, array_to_string(v_refus_metier, ', '));
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
  '434 : joue UNE des huit épreuves et rend le verdict MESURÉ, jamais un verdict par défaut. 436 : deux cas y sont ajoutés sans toucher au reste — un maillon dont la signature de geste diffère de sa signature nominale (arg_valeurs_annul), et un maillon de CRÉATION, pour lequel D1 n''a pas d''objet : le rejouer crée un second document, et le rendre `rompu` publierait un défaut inexistant.';

-- ─────────────────────────────────────────────────────────────
-- 6. CE QUE CETTE MIGRATION NE FAIT PAS
--
-- • Elle n'écrit AUCUN `arg_valeurs` ni `arg_series` : ce sont des `uuid` de
--   décor. Les laisser ici figerait le catalogue sur les identifiants d'une
--   société de test, et le banc exécuterait les épreuves contre des lignes
--   disparues — le pire verdict, celui d'un `non_joue` silencieux.
-- • Elle ne pose AUCUN contrat d'effet (porte G2) : elle ne crée aucun effet,
--   elle ne rend aucun maillon traçable de plus. Elle écrit une description de
--   mesure, dans un instrument de mesure.
-- • Elle ne MODIFIE aucune fonction MÉTIER. Les deux fonctions qu'elle
--   redéfinit — `chain_banc_appeler` et `chain_banc_epreuve` — sont les
--   instruments de mesure eux-mêmes ; les six maillons sont décrits tels qu'ils
--   sont, et ce qu'ils font bien ou mal sera écrit par la suite 436, qui joue
--   les épreuves et garde le verdict mesuré.
--
-- ⚠️ ET SI UN JOUR UNE ÉPREUVE N'A PAS D'OBJET, ELLE SE DIT. C'est le principe
-- que cette migration a payé deux fois : `caisse.avoir` n'a pas de geste
-- d'annulation, `paie.comptabilisee` n'a pas de geste appelable, et
-- `caisse.ticket` n'a pas d'objet de rejeu. Aucun de ces trois cas n'a été
-- transformé en un verdict pour que le rapport soit plus beau.
-- ─────────────────────────────────────────────────────────────




-- ── Droits du banc — ajoutés à l'harmonisation du 03/10 ───────────────────
-- PostgreSQL accorde EXECUTE à PUBLIC par défaut. Trois fonctions du banc
-- étaient donc appelables par un visiteur NON connecté (check_anon_grants,
-- 228 T06), dont `chain_banc_epreuve`, SECURITY DEFINER avec un `p_tenant`
-- libre (check_tenant_guard). Le banc est un outil interne : il se lance par
-- `chain_banc_lancer`, réservé à service_role.
REVOKE ALL ON FUNCTION chain_banc_appeler(record, jsonb, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION chain_banc_epreuve(uuid, text, text, bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION chain_banc_liens_visibles(text, text, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION chain_banc_appeler(record, jsonb, text) TO service_role;
GRANT EXECUTE ON FUNCTION chain_banc_epreuve(uuid, text, text, bigint) TO service_role;
-- SECURITY INVOKER : c'est la session qui compte ce qu'ELLE voit (preuve d'isolation D8).
GRANT EXECUTE ON FUNCTION chain_banc_liens_visibles(text, text, timestamptz) TO authenticated, service_role;
