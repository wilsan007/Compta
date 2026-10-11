-- ============================================================
-- 770_chain_certificat_integrite_tests.sql — P1 : l'attestation d'intégrité
--
--   T01  la forme : un `jsonb` non nul, ses sections présentes ;
--   T02  sans relevé, AUCUN invariant n'est `tenu` (tout `non_mesure`) ;
--   T03  un invariant `rompu` est NOMMÉ dans `ecarts` (code, lignes en écart) ;
--   T04  le banc compte les 8 épreuves d'un maillon, `non_joue` compris ;
--   T05  sans caisse, l'empreinte NF-525 est `sans_objet` (pas un faux « 0 ») ;
--   T06  c'est une LECTURE : deux appels de suite rendent le même certificat ;
--   T07  la garde : on n'atteste pas la société d'un autre (refus 42501).
--
-- Ce que cette suite NE prouve PAS : que le certificat soit JUSTE vis-à-vis d'un
-- tiers. C'est le rôle de l'écran (deux lectures) et de l'expert-comptable.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '770', false);
DELETE FROM _audit_results WHERE file = '770';

DO $t$
DECLARE
  t uuid;
  autre uuid;
  v jsonb;
  v2 jsonb;
  n_liens int;
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant('cert-770', false);

  -- ── T01 — LA FORME ─────────────────────────────────────────
  v := chain_certificat_integrite(t);
  PERFORM _rec('T01', 'la fonction rend un jsonb non nul, avec invariants / ecarts / banc / nf525',
    v IS NOT NULL AND v ? 'invariants' AND v ? 'ecarts' AND v ? 'banc' AND v ? 'nf525' AND v ? 'emis_le',
    format('clés=%s', (SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(v) AS k)));

  -- ── T02 — AUCUN `tenu` SANS RELEVÉ ─────────────────────────
  PERFORM _rec('T02', 'sans relevé, aucun invariant n''est `tenu` (tout est `non_mesure`)',
    (v->'invariants'->>'tenu')::int = 0
    AND (v->'invariants'->>'rompu')::int = 0
    AND (v->'invariants'->>'non_mesure')::int = (v->'invariants'->>'total')::int
    AND (v->'invariants'->>'total')::int > 0,
    format('invariants=%s', v->'invariants'));

  -- ── T03 — UN ÉCART EST NOMMÉ ───────────────────────────────
  INSERT INTO chain_invariant_results (tenant_id, code, verdict, ecart, lignes_en_ecart)
    VALUES (t, 'INV-01', 'rompu', 12.34, 3);
  v := chain_certificat_integrite(t);
  PERFORM _rec('T03', 'un invariant rompu apparaît dans `ecarts`, avec son code et ses lignes en écart',
    (v->'invariants'->>'rompu')::int = 1
    AND jsonb_array_length(v->'ecarts') = 1
    AND (v->'ecarts'->0->>'code') = 'INV-01'
    AND (v->'ecarts'->0->>'lignes_en_ecart')::int = 3,
    format('rompu=%s ecarts=%s', v->'invariants'->>'rompu', v->'ecarts'));

  -- ── T04 — LE BANC, `non_joue` COMPRIS ──────────────────────
  INSERT INTO chain_banc_resultats (code, epreuve, tenant_id, verdict, raison) VALUES
    ('caisse.ticket', 'D1', t, 'tenu',     NULL),
    ('caisse.ticket', 'D2', t, 'tenu',     NULL),
    ('caisse.ticket', 'D3', t, 'tenu',     NULL),
    ('caisse.ticket', 'D4', t, 'tenu',     NULL),
    ('caisse.ticket', 'D5', t, 'rompu',    NULL),
    ('caisse.ticket', 'D6', t, 'rompu',    NULL),
    ('caisse.ticket', 'D7', t, 'non_joue', 'pas de série de stimuli'),
    ('caisse.ticket', 'D8', t, 'non_joue', 'pas de mesure externe');
  v := chain_certificat_integrite(t);
  PERFORM _rec('T04', 'le banc compte les 8 épreuves du maillon, `non_joue` compris',
    (v->'banc'->>'tenues')::int = 4
    AND (v->'banc'->>'rompues')::int = 2
    AND (v->'banc'->>'non_jouees')::int = 2
    AND (v->'banc'->>'total')::int = 8
    AND (v->'banc'->>'maillons')::int > 0
    AND (v->'banc'->>'epreuves_par_maillon')::int = 8,
    format('banc=%s', v->'banc'));

  -- ── T05 — « SANS OBJET », JAMAIS « 0 ÉVÉNEMENT » ───────────
  PERFORM _rec('T05', 'sans caisse, l''empreinte NF-525 est `sans_objet` (et non un faux « 0 événement »)',
    (v->'nf525'->>'sans_objet')::boolean = true,
    format('total_events=%s sans_objet=%s', v->'nf525'->>'total_events', v->'nf525'->>'sans_objet'));

  -- ── T06 — UNE LECTURE, PAS UNE ÉCRITURE ────────────────────
  SELECT count(*) INTO n_liens FROM document_links;
  v2 := chain_certificat_integrite(t);
  PERFORM _rec('T06', 'le certificat est une LECTURE : deux appels de suite, même contenu (hors horodatage)',
    (v2 - 'emis_le') = (chain_certificat_integrite(t) - 'emis_le')
    AND (SELECT count(*) FROM document_links) = n_liens,
    format('liens_avant=%s', n_liens));

  -- ── T07 — LA GARDE DE SOCIÉTÉ ──────────────────────────────
  autre := _mk_tenant('cert-770-voisin', false);
  BEGIN
    PERFORM chain_certificat_integrite(t);   -- t ≠ société courante (autre)
    PERFORM _rec('T07', 'attester une AUTRE société est refusé (42501)', false, 'aucune exception levée');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM _rec('T07', 'attester une AUTRE société est refusé (42501)', true, 'refus 42501');
  END;
END $t$;

SELECT _audit_assert('770');
