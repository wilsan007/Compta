-- ============================================================
-- check_effects_contract.sql — G2 : le contrat d'effet, confronté au réel
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md, porte
-- **G2** (§4.2) : « pour chaque type de document et chaque événement déclaré, un
-- test exécute le document et compare le réel à la déclaration » — le défaut
-- qu'elle rend impossible est **M-05** (un effet caché ou absent).
--
-- LE DÉFAUT QUE CE CONTRÔLE FERME. Le socle (252) a un contrat d'effet
-- (`document_effects`) et il est **fermé par défaut** : `chain_autorise` rend
-- faux pour tout ce qui n'est pas déclaré. Conséquence mesurée par le lot L1
-- (VAGUE-L1 §4 et §6.5) : **0 contrat déclaré**, donc **chaque** exécution des
-- 14 effets tracés écrivait une trace `tolere` PUIS `applique` — mesuré sur la
-- base de test au 30/09/2026 : **1 132 `tolere` pour 1 117 `applique`**. Rien
-- n'interdisait non plus à un maillon neuf d'arriver avec un effet que PERSONNE
-- n'avait déclaré — et c'est exactement ce qui a produit les 62 chaînages notés
-- 3,65/7 du référentiel.
-- **Fermé le même jour par la migration 313 (lot L7)** : les 14 contrats
-- standard sont déclarés, `chain_autorise` rend vrai pour eux, et une exécution
-- de maillon n'écrit plus qu'**une** trace, `applique`. Ce contrôle reste :
-- c'est lui qui empêche le défaut de revenir avec le 15ᵉ effet.
--
-- CE QUE LE CONTRÔLE MESURE, ET COMMENT. Il lit `pg_proc` — pas les fichiers :
-- ce qui compte est ce qui est COMPILÉ en base. Deux extractions, les seules
-- qui soient littérales donc décidables :
--   * `chain_avant(<expr>, 'document', 'événement', 'effet', …)` → un **COUPLE**
--     (document, événement, effet) : c'est la clé exacte du contrat ;
--   * `link_documents(<expr>, '…', <expr>, '…', <expr>, 'effet', …)` → un
--     **EFFET** : les maillons réécrits (M-09, lien par ligne) n'appellent pas
--     toujours `chain_avant`, mais ils nomment leur effet.
-- Sont exclus : les fonctions du SOCLE (elles ne sont pas des maillons) et
-- l'outillage de test (`_…`, convention du dépôt — sinon les suites se
-- dénonceraient elles-mêmes).
--
-- LES DEUX SENS, ET LEUR ASYMÉTRIE ASSUMÉE.
--   1. **Un effet appelé mais non déclaré → la CI échoue**, sauf s'il figure au
--      registre ci-dessous (le plafond daté du 30/09/2026 : les 14 effets de
--      L1). C'est le sens qui protège : un maillon neuf sans contrat casse.
--   2. **Un effet déclaré mais jamais appelé → simple NOTICE, jamais un échec.**
--      Une déclaration peut précéder son maillon : le point 1 de la définition
--      de « terminé » (§4.1) demande de déclarer même un effet « aucun », et
--      refuser cela interdirait de déclarer avant d'implémenter. Le décompte est
--      publié pour que l'écart reste visible, il n'est pas caché.
--
-- LE REGISTRE EST **VIDE depuis le 30/09/2026** — c'est l'état visé, pas un
-- hasard : il a porté les **25 défauts** de L1 (14 effets + 11 couples) le temps
-- que le lot **L7** (migration 313) déclare les contrats. Même contrat que
-- `ci/expected_failures.sql` (AUD-A02) et que `check_tenant_guard.sql` : une
-- ligne s'inscrit ici quand un effet doit vivre **sans** contrat — avec sa
-- raison — et se retire dans le commit qui le déclare (ou qui retire l'appel).
-- Une ligne devenue inutile **casse** la CI : c'est ce qui empêche le registre de
-- pourrir, et c'est cette moitié qui a été vue à l'œuvre le 30/09 (les 25 lignes
-- ont été refusées par le contrôle dès la 313 appliquée, puis retirées).
--
-- CE QUE LE CONTRÔLE NE PROUVE PAS. Il lit des signatures, pas des
-- comportements : il ne dit pas que l'effet déclaré EST celui qui est produit
-- (c'est le rôle des suites d'acceptation, 310/311/312) ni qu'un effet déclaré
-- « actif » est bien exercé. Il dit que rien n'arrive dans la chaîne sans avoir
-- été NOMMÉ — c'est la porte que le plan appelle G2.
--
-- Le contrôle s'auto-teste (fixtures jouées puis annulées) et échoue s'il n'a
-- pu décider de rien : un vert doit signifier « vérifié », pas « rien vu ».
--
-- ORDRE D'EXÉCUTION — la note a changé le 30/09/2026 : la CI lance les contrôles
-- AVANT les suites, et depuis que les 14 contrats sont déclarés par la **313**,
-- l'ordre ne change plus **aucun verdict** de ce contrôle. Il ne change qu'un
-- décompte **publié** : des contrats « jamais appelés par un maillon », que les
-- suites alimentent avec leurs contrats de test (`contrat.standard`,
-- `gabarit.test`). Un écart publié, jamais un échec.
-- ============================================================

\set ON_ERROR_STOP on

-- ─────────────────────────────────────────────────────────────
-- 1. Le corpus : les maillons, c'est-à-dire les fonctions qui appellent le socle
--    (hors socle lui-même, hors outillage `_…` des suites)
-- ─────────────────────────────────────────────────────────────
CREATE TEMP TABLE g2_socle (nom text);
INSERT INTO g2_socle (nom) VALUES
  ('link_documents'), ('emit_domain_event'),
  ('chain_avant'), ('chain_apres'), ('chain_trace'), ('chain_deja_fait'),
  ('chain_integrity_ok'), ('chain_autorise'), ('chain_regenerate'),
  ('chain_enforcement_mode'), ('chain_set_enforcement'),
  ('chain_ensure_partitions'), ('chain_ensure_partitions_table'),
  ('chain_lien_actif'), ('chain_lien_tour'), ('chain_lien_fermer'),
  ('chain_lien_remplacer'), ('chain_lien_rompre'), ('chain_liens_fermer');

-- ─────────────────────────────────────────────────────────────
-- 2. Le registre des effets appelés sans contrat — **VIDE depuis le 30/09/2026**
--    Il a porté les 25 défauts de L1 (14 effets + 11 couples) le temps que le
--    lot **L7** déclare les contrats (migration **313**). Il est vide : un effet
--    appelé sans contrat casse donc la CI **immédiatement**, sans échappatoire
--    inscrite — c'est l'état visé par la doctrine M-05.
-- ─────────────────────────────────────────────────────────────
CREATE TEMP TABLE g2_registre (sens text, cle text, raison text);

-- VIDE depuis le 30/09/2026 : les 14 contrats sont déclarés par la **313**
-- (lot L7). Une ligne s'inscrit ici quand un effet doit vivre SANS contrat —
-- avec sa raison — et se retire dans le commit qui le déclare, ou qui retire
-- l'appel. Même règle que `ci/expected_failures.sql` : un registre qui ne se
-- nettoie pas pourrit, et un plafond qui ne se met pas à jour ment.
-- Les 25 lignes qui ont vécu ici (14 effets + 11 couples, du 30/09 au 30/09)
-- sont l'historique du lot L1 : elles sont citées dans VAGUE-L2-PORTES-CI.

-- ─────────────────────────────────────────────────────────────
-- 3. L'extraction, écrite UNE fois (le contrôle et son auto-test l'utilisent)
--    Aucune heuristique : deux motifs littéraux, et rien d'autre.
-- ─────────────────────────────────────────────────────────────
CREATE FUNCTION pg_temp.g2_constats(p_nom text, p_src text)
RETURNS TABLE(sens text, cle text)
LANGUAGE sql IMMUTABLE AS $fn$
  SELECT 'COUPLE'::text, m[1] || ' / ' || m[2] || ' / ' || m[3]
  FROM regexp_matches(p_src,
    'chain_avant\s*\(\s*[^,]+,\s*''([^'']+)''\s*,\s*''([^'']+)''\s*,\s*''([^'']+)''', 'g') m
  UNION
  SELECT 'EFFET'::text, m[1]
  FROM regexp_matches(p_src,
    'link_documents\s*\(\s*[^,]+,\s*''[^'']*''\s*,\s*[^,]+,\s*''[^'']*''\s*,\s*[^,]+,\s*''([^'']+)''', 'g') m
$fn$;

-- ─────────────────────────────────────────────────────────────
-- 4. Le contrôle réel
-- ─────────────────────────────────────────────────────────────
CREATE TEMP TABLE g2_constats AS
SELECT c.sens, c.cle, p.proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
CROSS JOIN LATERAL pg_temp.g2_constats(p.proname, p.prosrc) c
LEFT JOIN pg_temp.g2_socle s ON s.nom = p.proname
LEFT JOIN LATERAL (SELECT true AS test_helper) th ON p.proname LIKE '\_%'
WHERE p.prokind = 'f'
  AND s.nom IS NULL        -- les fonctions du socle ne sont pas des maillons
  AND th.test_helper IS NULL;

-- Le verdict par constat : le couple se juge sur le COUPLE, l'effet sur l'EFFET.
CREATE TEMP TABLE g2_verdicts AS
SELECT f.sens, f.cle,
       CASE WHEN f.sens = 'EFFET' THEN
         EXISTS (SELECT 1 FROM document_effects e WHERE e.effet = f.cle)
       ELSE
         EXISTS (SELECT 1 FROM document_effects e
                  WHERE e.document_type || ' / ' || e.evenement || ' / ' || e.effet = f.cle)
       END AS declare,
       EXISTS (SELECT 1 FROM g2_registre r WHERE r.sens = f.sens AND r.cle = f.cle) AS inscrit
FROM (SELECT DISTINCT sens, cle FROM g2_constats) f;

DO $$
DECLARE
  v_constats int; v_declares int; v_inscrits int; v_sans_registre text; v_perimes text;
  v_declares_jamais_appeles int; v_contrats int; v_maillons int; v_sans_registre_n int;
BEGIN
  SELECT count(DISTINCT proname) INTO v_maillons FROM g2_constats;
  SELECT count(*), count(*) FILTER (WHERE declare), count(*) FILTER (WHERE inscrit)
    INTO v_constats, v_declares, v_inscrits FROM g2_verdicts;

  SELECT count(*) INTO v_contrats FROM document_effects;

  -- Un contrôle qui n'examine rien ne prouve rien (leçon du 18/09, B3).
  IF v_constats = 0 THEN
    RAISE EXCEPTION 'check_effects_contract : aucun effet extrait du code — le contrôle ne vérifie rien (motifs à revoir).';
  END IF;

  SELECT count(*) INTO v_sans_registre_n FROM g2_verdicts WHERE NOT declare AND NOT inscrit;
  IF v_sans_registre_n > 0 THEN
    SELECT string_agg(sens || ' « ' || cle || ' »', E'\n  ' ORDER BY sens, cle)
      INTO v_sans_registre FROM g2_verdicts WHERE NOT declare AND NOT inscrit;
    RAISE EXCEPTION E'check_effects_contract : % effet(s)/couple(s) appelés par un maillon sans contrat déclaré ni raison au registre :\n  %\n'
      '  Déclarez-le dans document_effects (lot L7), ou inscrivez-le au registre de ci/check_effects_contract.sql avec sa raison.',
      v_sans_registre_n, v_sans_registre;
  END IF;

  -- La moitié qui empêche le registre de pourrir : une ligne devenue inutile
  -- (effet déclaré, ou effet plus appelé) doit disparaître dans le même commit.
  SELECT string_agg(r.sens || ' « ' || r.cle || ' »', ', ' ORDER BY r.sens, r.cle) INTO v_perimes
  FROM g2_registre r
  WHERE NOT EXISTS (
    SELECT 1 FROM g2_verdicts v WHERE v.sens = r.sens AND v.cle = r.cle AND NOT v.declare);
  IF v_perimes IS NOT NULL THEN
    RAISE EXCEPTION 'check_effects_contract : % entrée(s) du registre sont périmées (l''effet est déclaré, ou il n''est plus appelé) — retirez-les dans le même commit : %  (C''est l''effet attendu d''une déclaration : le lot L7 a vidé les 25 lignes de L1 ainsi, le 30/09/2026.)',
      (SELECT count(*) FROM g2_registre r WHERE NOT EXISTS (
         SELECT 1 FROM g2_verdicts v WHERE v.sens = r.sens AND v.cle = r.cle AND NOT v.declare)),
      v_perimes;
  END IF;

  -- Direction 2 : déclaré mais jamais appelé — publié, jamais bloquant.
  SELECT count(*) INTO v_declares_jamais_appeles FROM document_effects e
  WHERE NOT EXISTS (SELECT 1 FROM g2_verdicts v WHERE v.sens = 'EFFET' AND v.cle = e.effet);

  RAISE NOTICE 'Contrat d''effet : % maillon(s) lus, % constat(s) — % déclaré(s), % au registre.',
    v_maillons, v_constats, v_declares, v_inscrits;
  RAISE NOTICE 'Contrats en base : % — dont % déclaré(s) jamais appelé(s) par un maillon (une déclaration peut précéder son maillon : ce n''est pas un échec, c''est un écart publié).',
    v_contrats, v_declares_jamais_appeles;
  RAISE NOTICE 'check_effects_contract : OK — aucun effet n''arrive dans la chaîne sans contrat ni raison inscrite.';
END $$;

-- ─────────────────────────────────────────────────────────────
-- 5. L'auto-test : un vert doit signifier « vérifié », pas « rien vu »
--    Trois fixtures, jouées puis ANNULÉES (transaction interrompue) :
--      Z1 — un maillon qui appelle un effet NON DÉCLARÉ est vu, et jugé non déclaré ;
--      Z2 — le même appel avec un effet DÉCLARÉ dans la transaction ne l'est pas ;
--      Z3 — le corpus réel ne fuit pas : aucun nom du socle, aucun outillage `_…`.
--    Sans Z1 et Z2, le contrôle pourrait passer au vert en ne sachant rien
--    décider (c'est le défaut trouvé sur `check_trigger_reachability` en
--    septembre : un garde-fou qui n'assertait rien).
-- ─────────────────────────────────────────────────────────────
BEGIN;

CREATE OR REPLACE FUNCTION public.zz_g2_fixture(p_tenant uuid, p_id uuid)
RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  PERFORM chain_avant(p_tenant, 'zz_document', 'zz_evenement', 'zz.effet.non.declare',
                      'zz_document', p_id);
END $f$;

INSERT INTO document_effects (tenant_id, document_type, evenement, effet)
VALUES (NULL, 'zz_document', 'zz_evenement', 'zz.effet.declare');

CREATE OR REPLACE FUNCTION public.zz_g2_fixture_declare(p_tenant uuid, p_id uuid)
RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  PERFORM chain_avant(p_tenant, 'zz_document', 'zz_evenement', 'zz.effet.declare',
                      'zz_document', p_id);
END $f$;

DO $$
DECLARE
  v_non_vus int; v_non_declares int; v_declares int; v_fuite_socle int; v_fuite_test int;
  v_registre int; v_constats int; v_msg text; v_orphelins int;
BEGIN
  -- Z1 : le fixture non déclaré est VU, et jugé non déclaré.
  SELECT count(*), count(*) FILTER (WHERE NOT declare)
    INTO v_non_vus, v_non_declares
  FROM (
    SELECT k.sens, k.cle,
           CASE WHEN k.sens = 'EFFET' THEN
             EXISTS (SELECT 1 FROM document_effects e WHERE e.effet = k.cle)
           ELSE
             EXISTS (SELECT 1 FROM document_effects e
                      WHERE e.document_type || ' / ' || e.evenement || ' / ' || e.effet = k.cle)
           END AS declare
    FROM pg_proc p CROSS JOIN LATERAL pg_temp.g2_constats(p.proname, p.prosrc) k
    WHERE p.proname = 'zz_g2_fixture'
  ) f;

  -- Z2 : le fixture déclaré est vu ET jugé déclaré (aucun faux positif).
  SELECT count(*), count(*) FILTER (WHERE declare)
    INTO v_non_vus, v_declares
  FROM (
    SELECT k.sens, k.cle,
           CASE WHEN k.sens = 'EFFET' THEN
             EXISTS (SELECT 1 FROM document_effects e WHERE e.effet = k.cle)
           ELSE
             EXISTS (SELECT 1 FROM document_effects e
                      WHERE e.document_type || ' / ' || e.evenement || ' / ' || e.effet = k.cle)
           END AS declare
    FROM pg_proc p CROSS JOIN LATERAL pg_temp.g2_constats(p.proname, p.prosrc) k
    WHERE p.proname = 'zz_g2_fixture_declare'
  ) f;

  -- Z3 : le corpus réel ne porte ni nom du socle ni outillage de test.
  SELECT count(*) INTO v_fuite_socle FROM g2_constats WHERE proname IN (SELECT nom FROM g2_socle);
  SELECT count(*) INTO v_fuite_test  FROM g2_constats WHERE proname LIKE '\_%';
  SELECT count(*) INTO v_registre FROM g2_registre;
  SELECT count(DISTINCT (sens, cle)) INTO v_constats FROM g2_constats;
  -- Un registre est cohérent quand AUCUNE de ses lignes n'est orpheline : une
  -- entrée qui ne correspond à aucun constat est une ligne morte, et une ligne
  -- morte est exactement ce qui fait qu'un registre ne veut plus rien dire.
  SELECT count(*) INTO v_orphelins FROM g2_registre r
  WHERE NOT EXISTS (SELECT 1 FROM g2_constats c WHERE c.sens = r.sens AND c.cle = r.cle);

  -- Les messages sont CONSTRUITS puis remis à RAISE avec un seul placeholder :
  -- plpgsql perd le fil d'une liste d'arguments quand le message est long et
  -- suit plusieurs instructions (mesuré : « mismatched parentheses at or near ) »
  -- sur les formes longues ci-dessous, jamais sur les courtes). Un contrôle qui
  -- parle au lieu de mourir vaut mieux qu'une jolie phrase qui ne compile pas.
  IF v_non_declares = 0 THEN
    v_msg := format('AUTO-TEST Z1 : le fixture non déclaré est VU mais jugé déclaré — %s constat(s), contrôle sans valeur.', v_non_vus);
    RAISE EXCEPTION '%', v_msg;
  END IF;
  IF v_declares = 0 THEN
    RAISE EXCEPTION '%', 'AUTO-TEST Z2 : le fixture déclaré n''est pas jugé déclaré — faux positif possible.';
  END IF;
  IF v_fuite_socle > 0 OR v_fuite_test > 0 THEN
    v_msg := format('AUTO-TEST Z3 : le corpus fuit — %s nom(s) du socle, %s outillage(s) de test.', v_fuite_socle, v_fuite_test);
    RAISE EXCEPTION '%', v_msg;
  END IF;
  IF v_orphelins > 0 THEN
    RAISE EXCEPTION 'AUTO-TEST Z3 : le registre porte % entrée(s) sans constat correspondant — lignes mortes, à retirer.', v_orphelins;
  END IF;

  v_msg := format('Auto-test : OK — Z1 non déclaré vu et refusé, Z2 déclaré accepté, Z3 sans fuite : %s constat(s), %s au registre.', v_constats, v_registre);
  RAISE NOTICE '%', v_msg;
END $$;

ROLLBACK;
