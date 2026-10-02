-- ============================================================
-- 318_ocr_consent_tests.sql — le consentement OCR (D-5) : une trace, pas un drapeau
--
-- Source : décision D-5 (AUD-H04) — « garder l'OCR, avec un consentement
-- explicite par société ». La pratique du marché (Pennylane, Dext, Qonto, Sage
-- AutoEntry, NetSuite) est un réglage PAR DOSSIER, adossé à un contrat de
-- sous-traitance.
--
--   T01  une société neuve n'a RIEN consenti — et l'absence de trace le dit
--        (date et auteur nuls, pas des zéros) ;
--   T02  le passage à « consenti » est DATÉ et SIGNÉ par la base : les valeurs
--        que le client soumet sont IGNORÉES (une preuve que le client écrit ne
--        prouve rien) ;
--   T03  retirer son consentement l'efface — et le refus redevient la règle ;
--   T04  un enregistrement des paramètres qui NE TOUCHE PAS au consentement ne
--        réécrit pas la preuve (ni la date, ni l'auteur) ;
--   T05  le consentement est PAR SOCIÉTÉ : A qui a consenti ne consent rien pour B.
--
-- Ce fichier s'exécute comme les autres suites d'audit : contexte de société
-- posé, puis rôle `authenticated` — un utilisateur réel, sous RLS.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '318', false);
DELETE FROM _audit_results WHERE file = '318';

-- ─────────────────────────────────────────────────────────────
-- Outillage propre au fichier (table TEMPORAIRE : les contrôles de schéma ne
-- doivent pas voir un artefact de test)
-- ─────────────────────────────────────────────────────────────
CREATE TEMP TABLE IF NOT EXISTS _p318 (k text PRIMARY KEY, v uuid);
DELETE FROM _p318;

CREATE OR REPLACE FUNCTION _p318_claims(p_user uuid, p_tenant uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_user::text, false);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, false);
  PERFORM set_config('app.active_tenant_id', p_tenant::text, false);
END $$;

-- Deux sociétés, chacune avec son administrateur.
DO $$
DECLARE a uuid; b uuid;
BEGIN
  a := _mk_tenant('P318A');
  INSERT INTO _p318 VALUES ('A', a), ('ADMIN_A', auth.uid());
  b := _mk_tenant('P318B');
  INSERT INTO _p318 VALUES ('B', b), ('ADMIN_B', auth.uid());
END $$;


-- ─────────────────────────────────────────────────────────────
-- T01 — une société neuve n'a rien consenti
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE a uuid; u uuid; c boolean; t timestamptz; p uuid;
BEGIN
  SELECT v INTO a FROM _p318 WHERE k = 'A';
  SELECT v INTO u FROM _p318 WHERE k = 'ADMIN_A';
  PERFORM _p318_claims(u, a);
  PERFORM set_config('role', 'authenticated', true);

  SELECT ocr_consent, ocr_consent_at, ocr_consent_by INTO c, t, p
    FROM company_settings WHERE tenant_id = a;

  PERFORM _rec('T01',
    'une société neuve n''a RIEN consenti : le refus est le défaut, et l''absence de consentement se lit sur l''absence de trace (pas sur un zéro)',
    c IS FALSE AND t IS NULL AND p IS NULL,
    format('consentement=%s, date=%s, auteur=%s', c, t, p));
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 — la date et l'auteur sont écrits par la BASE, pas par le client
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE a uuid; u uuid; t timestamptz; p uuid;
BEGIN
  SELECT v INTO a FROM _p318 WHERE k = 'A';
  SELECT v INTO u FROM _p318 WHERE k = 'ADMIN_A';
  PERFORM _p318_claims(u, a);
  PERFORM set_config('role', 'authenticated', true);

  -- Le client TENTE de fournir sa propre preuve : une date de 2000 et un auteur
  -- qui n'est personne. Le déclencheur doit imposer la sienne.
  UPDATE company_settings
     SET ocr_consent = true,
         ocr_consent_at = '2000-01-01 00:00:00+00',
         ocr_consent_by = '00000000-0000-0000-0000-000000000000'
   WHERE tenant_id = a;

  SELECT ocr_consent_at, ocr_consent_by INTO t, p
    FROM company_settings WHERE tenant_id = a;

  PERFORM _rec('T02',
    'le consentement est DATÉ et SIGNÉ par la base : les valeurs soumises par le client sont ignorées — une preuve qu''un client écrit ne prouve rien',
    t > now() - interval '1 minute' AND p = u,
    format('date=%s (aujourd''hui attendu, 2000 refusé), auteur=%s (l''appelant %s attendu)', t, p, u));
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — retirer son consentement l'efface
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE a uuid; u uuid; c boolean; t timestamptz; p uuid;
BEGIN
  SELECT v INTO a FROM _p318 WHERE k = 'A';
  SELECT v INTO u FROM _p318 WHERE k = 'ADMIN_A';
  PERFORM _p318_claims(u, a);
  PERFORM set_config('role', 'authenticated', true);

  UPDATE company_settings SET ocr_consent = false WHERE tenant_id = a;

  SELECT ocr_consent, ocr_consent_at, ocr_consent_by INTO c, t, p
    FROM company_settings WHERE tenant_id = a;

  PERFORM _rec('T03',
    'retirer son consentement le retire vraiment : le drapeau retombe et la trace est effacée — le refus redevient la règle',
    c IS FALSE AND t IS NULL AND p IS NULL,
    format('consentement=%s, date=%s, auteur=%s', c, t, p));
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — un enregistrement des paramètres ne réécrit pas la preuve
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE a uuid; u uuid; t1 timestamptz; p1 uuid; t2 timestamptz; p2 uuid;
BEGIN
  SELECT v INTO a FROM _p318 WHERE k = 'A';
  SELECT v INTO u FROM _p318 WHERE k = 'ADMIN_A';
  PERFORM _p318_claims(u, a);
  PERFORM set_config('role', 'authenticated', true);

  UPDATE company_settings SET ocr_consent = true WHERE tenant_id = a;
  SELECT ocr_consent_at, ocr_consent_by INTO t1, p1 FROM company_settings WHERE tenant_id = a;

  -- L'écran des paramètres enregistre la ligne ENTIÈRE, plusieurs fois par jour :
  -- sans cette garantie, chaque « Enregistrer » réécrirait la date du
  -- consentement, et il daterait de la dernière visite — plus d'aucun fait.
  UPDATE company_settings SET name = name WHERE tenant_id = a;
  SELECT ocr_consent_at, ocr_consent_by INTO t2, p2 FROM company_settings WHERE tenant_id = a;

  PERFORM _rec('T04',
    'un enregistrement des paramètres qui ne touche pas au consentement ne réécrit NI la date NI l''auteur : la preuve ne se rafraîchit pas à chaque « Enregistrer »',
    t1 = t2 AND p1 = p2 AND t1 IS NOT NULL,
    format('avant=%s / %s, après=%s / %s', t1, p1, t2, p2));
END $$;

-- ─────────────────────────────────────────────────────────────
-- T05 — le consentement est PAR SOCIÉTÉ
-- ─────────────────────────────────────────────────────────────
-- Mesuré DEPUIS CHAQUE SIÈGE, et non par une lecture croisée : la RLS cache la
-- ligne de l'autre société, et c'est tant mieux — un consentement qu'on pourrait
-- lire chez le voisin ne serait déjà plus cloisonné. La première version de ce
-- scénario lisait A depuis le siège de B, et recevait `NULL` : le test mesurait
-- sa propre erreur, pas le produit.
DO $$
DECLARE a uuid; b uuid; ua uuid; ub uuid; ca boolean; cb boolean; vues_de_b int;
BEGIN
  SELECT v INTO a FROM _p318 WHERE k = 'A';
  SELECT v INTO b FROM _p318 WHERE k = 'B';
  SELECT v INTO ua FROM _p318 WHERE k = 'ADMIN_A';
  SELECT v INTO ub FROM _p318 WHERE k = 'ADMIN_B';

  -- Au siège de A : A a consenti (T04), et la société B n'est même pas visible
  PERFORM _p318_claims(ua, a);
  PERFORM set_config('role', 'authenticated', true);
  SELECT ocr_consent INTO ca FROM company_settings WHERE tenant_id = a;
  SELECT count(*) INTO vues_de_b FROM company_settings WHERE tenant_id = b;

  -- Au siège de B : B n'a rien signé
  PERFORM _p318_claims(ub, b);
  SELECT ocr_consent INTO cb FROM company_settings WHERE tenant_id = b;

  PERFORM _rec('T05',
    'le consentement est PAR SOCIÉTÉ : A qui a consenti ne consent rien pour B — et depuis le siège de A, la ligne de B n''est même pas lisible',
    ca IS TRUE AND cb IS FALSE AND vues_de_b = 0,
    format('A=%s (vrai attendu), B=%s (faux attendu), lignes de B vues depuis A=%s (0 attendue)', ca, cb, vues_de_b));
END $$;

SELECT _audit_assert('318');
