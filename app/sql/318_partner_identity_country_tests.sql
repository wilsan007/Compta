-- ============================================================
-- 318_partner_identity_country_tests.sql — lot A (tiers et comptes
-- auxiliaires)
--
-- Recette /qa du 29/09/2026. A4 (ven-001, ach-002) : la fiche client et la
-- fiche fournisseur ne portaient ni SIRET, ni code postal, ni ville, ni
-- conditions de paiement, et le pays n'existait pas comme donnée : la colonne
-- `country` portait le défaut figé `'France'` (mesuré : 643 clients et 160
-- fournisseurs, tous en 'France', aucun SIRET). Un nom de pays n'est pas un
-- code : rien ne pouvait distinguer un client français d'un client belge, et
-- la facture électronique écrivait 'France' là où le standard attend deux
-- lettres (B3).
--
-- Mesuré sur la base de recette AVANT la 318 (5 scénarios, 1 vert / 4 rouges ;
-- le vert est la non-régression voulue) :
--   T01 ❌ un nom de pays passe à l'écriture (aucune garde)
--   T02 ✅ un code à deux lettres est stocké tel quel (non-régression)
--   T03 ❌ un tiers créé sans pays vaut 'France' (défaut forcé)
--   T04 ❌ les conditions de paiement ne sont pas une liste
--        (colonne `payment_term_id` absente : l'écriture est refusée)
--   T05 ❌ 803 tiers portent encore un nom de pays (643 + 160)
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '318', false);
DELETE FROM _audit_results WHERE file = '318';

DO $$
DECLARE
  t uuid; t2 uuid; c uuid; pt uuid; pt2 uuid;
  v_country text; n_c int; n_s int;
  refuse boolean; msg text;
BEGIN
  t := _mk_tenant('T318');

  -- T01 : le pays est un code ISO à deux lettres, pas un nom
  refuse := false; msg := NULL;
  BEGIN
    INSERT INTO customers (tenant_id, name, country) VALUES (t, 'Client France', 'France');
  EXCEPTION WHEN others THEN refuse := true; msg := SQLERRM; END;
  PERFORM _rec('T01', 'un nom de pays est refusé à l''écriture d''un tiers', refuse,
    format('refus=%s | message=%s', refuse, left(COALESCE(msg, '—'), 120)));

  -- T02 : un code à deux lettres passe et n'est pas réécrit (non-régression)
  v_country := NULL;
  BEGIN
    INSERT INTO customers (tenant_id, name, country) VALUES (t, 'Client Belgique', 'BE') RETURNING id INTO c;
    SELECT country INTO v_country FROM customers WHERE id = c;
  EXCEPTION WHEN others THEN v_country := NULL; msg := SQLERRM; END;
  PERFORM _rec('T02', 'un code ISO à deux lettres est accepté et stocké tel quel',
    v_country = 'BE', format('country=%s (BE attendu)', COALESCE(v_country, '—')));

  -- T03 : un pays non renseigné n'est plus deviné
  v_country := '(absent)';
  BEGIN
    INSERT INTO customers (tenant_id, name) VALUES (t, 'Client sans pays') RETURNING id INTO c;
    SELECT country INTO v_country FROM customers WHERE id = c;
  EXCEPTION WHEN others THEN v_country := 'refus : ' || SQLERRM; END;
  PERFORM _rec('T03', 'un tiers créé sans pays n''a plus « France » par défaut',
    v_country IS NULL, format('country=%s (NULL attendu)', COALESCE(v_country, '—')));

  -- T04 : les conditions de paiement sont choisies dans une liste
  INSERT INTO payment_terms (tenant_id, code, name, type, days_1, pct_1)
    VALUES (t, 'T318', '30 jours', 'fixed', 30, 100) RETURNING id INTO pt;
  refuse := false; msg := NULL;
  BEGIN
    INSERT INTO customers (tenant_id, name, payment_term_id) VALUES (t, 'Client 30 jours', pt);
  EXCEPTION WHEN others THEN refuse := true; msg := SQLERRM; END;
  -- n_c = 1 : la clé étrangère a joué ; n_c = -1 : la colonne n'existe pas encore
  -- (la 318 n'est pas appliquée) — le scénario est alors rouge, pas une erreur.
  n_c := 0;
  BEGIN
    INSERT INTO customers (tenant_id, name, payment_term_id) VALUES (t, 'Client sans condition', uuid_generate_v4());
  EXCEPTION WHEN foreign_key_violation THEN n_c := 1; msg := SQLERRM;
    WHEN undefined_column THEN n_c := -1; msg := SQLERRM;
  END;
  PERFORM _rec('T04', 'les conditions de paiement viennent d''une liste, et une liste inconnue est refusée',
    NOT refuse AND n_c = 1,
    format('condition valide refusée=%s | condition inconnue refusée=%s | message=%s', refuse, n_c = 1, left(COALESCE(msg, '—'), 110)));

  -- T05 : l'existant est normalisé — aucun nom de pays ne subsiste
  SELECT count(*) INTO n_c FROM customers WHERE country IS NOT NULL AND country !~ '^[A-Z]{2}$';
  SELECT count(*) INTO n_s FROM suppliers WHERE country IS NOT NULL AND country !~ '^[A-Z]{2}$';
  PERFORM _rec('T05', 'aucun client ni fournisseur ne porte un nom de pays',
    n_c = 0 AND n_s = 0, format('clients=%s fournisseurs=%s (0 attendu)', n_c, n_s));

  -- T06 : les conditions d'une AUTRE société sont refusées (doctrine 237, T08)
  -- Une clé étrangère mono-colonne sur `payment_term_id` laisserait un client de
  -- la société A pointer vers les conditions de la société B : c'est ce que la
  -- migration 237 interdit, et ce que ce scénario vérifie.
  t2 := _mk_tenant('T318-bis');
  INSERT INTO payment_terms (tenant_id, code, name, type, days_1, pct_1)
    VALUES (t2, 'T318', '30 jours', 'fixed', 30, 100) RETURNING id INTO pt2;
  n_c := 0;
  BEGIN
    INSERT INTO customers (tenant_id, name, payment_term_id) VALUES (t, 'Client-condition etrangere', pt2);
  EXCEPTION WHEN foreign_key_violation THEN n_c := 1; msg := SQLERRM; END;
  PERFORM _rec('T06', 'les conditions de paiement d''une autre société sont refusées',
    n_c = 1, format('refusé=%s | message=%s', n_c = 1, left(COALESCE(msg, '—'), 120)));
END $$;

SELECT _audit_assert('318');
