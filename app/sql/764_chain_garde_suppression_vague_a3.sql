-- 764 — chain_garde_suppression_vague_a3
-- Numéro pris le 2026-10-11T16:27:49.991Z par migration-numero.mjs (ligne « plan6 A3 L16 (familles restantes) », branche plan6/a3-moteur).

-- ═══════════════════════════════════════════════════════════════════════════
-- 764 — LA GARDE DE SUPPRESSION sur les types que la vague A3 a inscrits
--       (et le contrôle DÉGELÉ qui empêche que ça recommence en silence)
-- ═══════════════════════════════════════════════════════════════════════════
-- DÉFAUT MESURÉ le 11/10/2026, base neuve (349 migrations), en lançant la suite
-- d'intégrité référentielle de la Partie 5 — que la vague A3 n'avait JAMAIS
-- lancée (elle ne rejouait que les cinq portes : G2, G7, tenant, anon, G8) :
--
--   [450] ❌ T01 — « types=37 (27) » : l'assertion GELAIT le compte du 02/10 ;
--   [450] ❌ T11 — sans garde = quotes, quote_lines, payment_orders,
--                 mrp_proposals, purchase_orders, purchase_order_lines,
--                 purchase_credit_notes, purchase_credit_lines,
--                 collection_reminders, lettrage_groups, pay_slips,
--                 fiscal_years, product_batches — « gardes posées = 32 (32) ».
--
-- LE DÉFAUT DE FOND. `453` a posé la garde sur les **27** types du registre du
-- 02/10 — sa boucle s'exécute **UNE fois**, au déploiement. Dix maillons de la
-- vague A3 ont ensuite inscrit **10 types et 3 tables de lignes** (493, 498,
-- 499, 751, 756, 757, 758, 759, 760, 761) **sans reposer la garde**, alors que
-- la règle est écrite noir sur blanc dans l'en-tête de `450` :
--   « tout nouveau maillon qui emploie un type absent d'ici l'inscrit DANS LA
--     MÊME MIGRATION, et pose la garde de suppression (453) sur sa table.
--     La suite 450 (T01, T11) échoue sinon. »
-- Le contrôle EXISTAIT donc. Il était **gelé** par un compte figé (27, 32), et
-- personne ne l'avait lancé — deux façons de ne pas contrôler. La leçon de ce
-- fichier est là : **un contrôle gelé ne contrôle rien.**
--
-- CE QUE LE DÉFAUT OUVERAIT, exactement : D1 à D5 de la `453` sont ROUVERTS pour
-- ces types. Un devis transformé, une commande d'achat, un avoir fournisseur,
-- une relance, un groupe de lettrage, un bulletin comptabilisé, un exercice, un
-- lot de stock, un ordre de paiement, une proposition MRP... pouvaient être
-- SUPPRIMÉS alors qu'un lien ACTIF les tient : l'aval reste, l'amont disparaît,
-- et la frise pointe vers rien (INV-19).
--
-- CE QUE CE FICHIER POSE : la garde de `453` sur **tout type du registre qui ne
-- l'a pas** — la boucle est PILOTÉE PAR LE REGISTRE, jamais par une liste
-- recopiée — puis il VÉRIFIE sa propre couverture et échoue s'il en manque un.
-- Le contrôle `450` T11, **dégelé dans le même commit**, refuse désormais tout
-- type inscrit sans sa garde : le prochain maillon sera arrêté par la porte, et
-- non par la distraction d'un relecteur.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le corps de la garde : exigé, pas supposé ───────────────────────────
-- `453` le pose ; on ne le suppose pas : sans lui, la couverture ne peut pas
-- être posée et le fichier doit le DIRE au déploiement, pas à l'exécution.
DO $$
BEGIN
  IF to_regprocedure('public.chain_refuser_suppression_liee()') IS NULL THEN
    RAISE EXCEPTION '764 : le corps de la garde (453, chain_refuser_suppression_liee) est absent — la couverture ne peut pas être posée'
      USING ERRCODE = 'check_violation';
  END IF;
END $$;


-- ── 2. La couverture : la garde sur TOUT type du registre ─────────────────
-- La boucle est celle de `453`, à l'argument près : le type du registre sert de
-- clé au message de refus. Les deux NOMS de déclencheurs sont ceux de `453` —
-- un type qui les portait déjà est simplement reposé (DROP IF EXISTS puis
-- CREATE) : il n'y a donc jamais deux gardes sur la même table, et rejouer ce
-- fichier ne change rien (c'est la même propriété que `453`).
DO $$
DECLARE r record; v_pose int := 0;
BEGIN
  FOR r IN SELECT code, table_name, ligne_table FROM public.chain_document_types ORDER BY code LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS zz_garde_p5_suppression ON public.%I', r.table_name);
    EXECUTE format('CREATE TRIGGER zz_garde_p5_suppression BEFORE DELETE ON public.%I '
                   'FOR EACH ROW EXECUTE FUNCTION public.chain_refuser_suppression_liee(%L, %L)',
                   r.table_name, r.code, 'document');
    v_pose := v_pose + 1;
    IF r.ligne_table IS NOT NULL THEN
      EXECUTE format('DROP TRIGGER IF EXISTS zz_garde_p5_suppression_ligne ON public.%I', r.ligne_table);
      EXECUTE format('CREATE TRIGGER zz_garde_p5_suppression_ligne BEFORE DELETE ON public.%I '
                     'FOR EACH ROW EXECUTE FUNCTION public.chain_refuser_suppression_liee(%L, %L)',
                     r.ligne_table, r.code, 'ligne');
      v_pose := v_pose + 1;
    END IF;
  END LOOP;
  RAISE NOTICE '764 : garde de suppression posée sur % type(s) — % déclencheur(s).',
    (SELECT count(*) FROM chain_document_types), v_pose;
END $$;

-- ── 3. La VÉRIFICATION : la couverture est complète, ou ce fichier échoue ──
-- Un fichier qui POSE une garde sans vérifier qu'il l'a posée partout est un
-- fichier qui « devrait » marcher : c'est exactement le défaut qu'il corrige.
DO $$
DECLARE v_sans text; v_attendu int; v_pose int; v_types int; v_lignes int; v_doubles text;
BEGIN
  SELECT string_agg(x.tbl, ', ' ORDER BY x.tbl) INTO v_sans
  FROM chain_document_types t
  CROSS JOIN LATERAL (VALUES (t.table_name, 'zz_garde_p5_suppression'),
                             (t.ligne_table, 'zz_garde_p5_suppression_ligne')) x(tbl, trig)
  WHERE x.tbl IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM pg_trigger g
                     WHERE g.tgrelid = to_regclass('public.' || x.tbl)
                       AND g.tgname = x.trig AND g.tgenabled <> 'D');
  IF v_sans IS NOT NULL THEN
    RAISE EXCEPTION '764 : % sans garde de suppression — le registre et la garde ont divergé', v_sans
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT count(*) INTO v_types FROM chain_document_types;
  SELECT count(*) INTO v_lignes FROM chain_document_types WHERE ligne_table IS NOT NULL;
  v_attendu := v_types + v_lignes;
  SELECT count(*) INTO v_pose FROM pg_trigger WHERE tgname LIKE 'zz_garde_p5_suppression%';
  IF v_pose <> v_attendu THEN
    RAISE EXCEPTION '764 : % déclencheur(s) pour % table(s) attendue(s) (% types + % tables de lignes)',
      v_pose, v_attendu, v_types, v_lignes USING ERRCODE = 'check_violation';
  END IF;

  -- Une table ne porte jamais DEUX gardes du même mode : le DROP IF EXISTS de la
  -- boucle le garantit — cette ligne le PROUVE au lieu de le croire.
  SELECT string_agg(t.tgrelid::regclass::text || '/' || t.tgname, ', ') INTO v_doubles
  FROM pg_trigger t
  WHERE t.tgname LIKE 'zz_garde_p5_suppression%'
  GROUP BY t.tgrelid, t.tgname
  HAVING count(*) > 1;
  IF v_doubles IS NOT NULL THEN
    RAISE EXCEPTION '764 : garde en double — %', v_doubles USING ERRCODE = 'check_violation';
  END IF;

  RAISE NOTICE '764 : couverture vérifiée — % déclencheur(s) = % type(s) + % table(s) de lignes, aucun doublon.',
    v_pose, v_types, v_lignes;
END $$;

