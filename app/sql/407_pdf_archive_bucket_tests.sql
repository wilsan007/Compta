-- ============================================================
-- 317_pdf_archive_bucket_tests.sql — le bucket d'archive des PDF serveur
--
-- Source : décision D-4 (option A, « rebrancher ») et le défaut mesuré le 30/09
-- — `generate-pdf` écrivait dans `storage.from("documents")`, un bucket qui
-- n'existe nulle part : l'`upload` échouait, l'erreur n'était pas lue, et la
-- fonction rendait `success: true` avec `url: null`.
--
--   T01  le bucket existe, il est PRIVÉ, il n'accepte que du PDF, et sa limite
--        de taille est posée (25 Mo) ;
--   T02  UNE seule politique existe sur ce bucket, et c'est la LECTURE : les
--        trois autres commandes sont absentes PAR DÉCISION (PostgreSQL ne sait
--        pas exprimer un refus autrement que par l'absence de politique) ;
--   T03  l'administrateur de la société lit la pièce de SA société ;
--   T04  il ne lit PAS celle de la société voisine (cloisonnement) ;
--   T05  un commercial SANS le module RH ne lit pas le bulletin de paie — mais
--        lit le devis de sa société : la politique tient par le MODULE, pas
--        seulement par la société ;
--   T06  un segment de module inconnu, ou absent, ne rend pas l'accès PLUS
--        large : l'échec est fermé (ce qui n'est pas nommé n'est pas permis) ;
--   T07  un utilisateur ne peut ni FABRIQUER une pièce (INSERT refusé par la
--        RLS), ni la RÉÉCRIRE (UPDATE 0 ligne), ni l'EFFACER (DELETE 0 ligne) ;
--   T08  la clé de service, elle, écrit et purge — c'est le seul écrivain, et
--        c'est pourquoi l'absence des trois politiques n'est pas un oubli ;
--   T09  `anon` ne lit rien, même dans le bon dossier de société : le
--        `TO authenticated` de la politique est vérifié, pas supposé.
--
-- Ce fichier s'exécute comme les autres suites d'audit : contexte de société
-- posé, puis rôle `authenticated` — un utilisateur réel, sous RLS.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '317', false);
DELETE FROM _audit_results WHERE file = '317';

-- ─────────────────────────────────────────────────────────────
-- Décor : deux sociétés, et un commercial SANS le module RH dans la première.
-- Table TEMPORAIRE : les contrôles de schéma (grille BT, tables inutilisées)
-- ne doivent pas voir un artefact de test.
-- ─────────────────────────────────────────────────────────────
CREATE TEMP TABLE IF NOT EXISTS _p317 (k text PRIMARY KEY, v uuid);
DELETE FROM _p317;

CREATE OR REPLACE FUNCTION _p317_commercial(p_t uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE u uuid := uuid_generate_v4();
BEGIN
  -- `custom` + un rôle de module, comme un vrai membre non administrateur
  -- (les rôles autorisés vont de `admin` à `custom`, et `custom` est le seul
  -- qui n'apporte aucun droit par lui-même).
  INSERT INTO auth.users (id, email) VALUES (u, 'commercial-317@audit.test');
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status, module_roles, created_at)
  VALUES (p_t, u, 'commercial-317@audit.test', 'Commercial', 'custom', 'active',
          '{"commercial":"sales_rep"}'::jsonb, now());
  RETURN u;
END $$;

CREATE OR REPLACE FUNCTION _p317_claims(p_user uuid, p_tenant uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_user::text, false);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, false);
  PERFORM set_config('app.active_tenant_id', p_tenant::text, false);
END $$;

-- Les sociétés (superutilisateur : `_mk_tenant` écrit dans `auth.users`).
-- `_mk_tenant` laisse le contexte posé sur la DERNIÈRE société créée : le décor
-- est donc monté d'abord, les mesures ensuite (aucune mesure ne dépend de
-- l'ordre des insertions).
DO $$
DECLARE a uuid; b uuid; c uuid;
BEGIN
  a := _mk_tenant('P317A');
  INSERT INTO _p317 VALUES ('A', a), ('ADMIN_A', auth.uid());
  c := _p317_commercial(a);
  INSERT INTO _p317 VALUES ('COMMERCIAL_A', c);

  b := _mk_tenant('P317B');
  INSERT INTO _p317 VALUES ('B', b), ('ADMIN_B', auth.uid());

  -- Les quatre pièces du décor : deux chez A (comptable et RH), une chez A
  -- (devis), une chez B. Écrites en superutilisateur : la fabrique d'état
  -- hostile ne passe pas par la politique qu'elle vérifie.
  INSERT INTO storage.objects (bucket_id, name) VALUES
    ('generated-pdfs', a::text || '/accounting/invoice/invoice_A_1.pdf'),
    ('generated-pdfs', a::text || '/hr/payslip/payslip_A_1.pdf'),
    ('generated-pdfs', a::text || '/commercial/quote/quote_A_1.pdf'),
    ('generated-pdfs', b::text || '/accounting/invoice/invoice_B_1.pdf');
END $$;

-- ─────────────────────────────────────────────────────────────
-- Outillage : la lecture mesurée passe par cette fonction NON `SECURITY DEFINER`
-- — elle s'exécute donc sous le rôle de l'appelant, et c'est la RLS qui décide.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION _p317_lit(p_path text) RETURNS int LANGUAGE sql AS $$
  SELECT count(*)::int FROM storage.objects
   WHERE bucket_id = 'generated-pdfs' AND name = p_path
$$;

-- ─────────────────────────────────────────────────────────────
-- T01 — le bucket : privé, PDF seulement, borné
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_public boolean; v_mimes text[]; v_limite bigint; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM storage.buckets WHERE id = 'generated-pdfs';
  SELECT public, allowed_mime_types, file_size_limit INTO v_public, v_mimes, v_limite
    FROM storage.buckets WHERE id = 'generated-pdfs';

  PERFORM _rec('T01',
    'le bucket d''archive existe, il est PRIVÉ, il n''accepte que du PDF et sa taille est bornée — une pièce de vente ou de paie ne peut pas être servie par une URL publique',
    v_n = 1 AND v_public IS FALSE AND v_mimes = ARRAY['application/pdf'] AND v_limite = 26214400,
    format('bucket(s)=%s, public=%s, mimes=%s, limite=%s', v_n, v_public, v_mimes, v_limite));
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 — une seule politique, et c'est la lecture
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE n_select int; n_autre int; v_detail text;
BEGIN
  SELECT count(*) FILTER (WHERE cmd = 'SELECT'),
         count(*) FILTER (WHERE cmd <> 'SELECT'),
         string_agg(cmd || ':' || policyname, ', ' ORDER BY cmd)
    INTO n_select, n_autre, v_detail
  FROM pg_policies
  WHERE schemaname = 'storage' AND tablename = 'objects'
    AND policyname LIKE 'generated_pdfs_%';

  PERFORM _rec('T02',
    'UNE seule politique sur ce bucket, et c''est la LECTURE : INSERT, UPDATE et DELETE sont absents PAR DÉCISION (l''absence de politique est le seul refus que PostgreSQL sait exprimer ici)',
    n_select = 1 AND n_autre = 0,
    format('lecture=%s, autre(s)=%s — %s', n_select, n_autre, coalesce(v_detail, 'aucune politique')));
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — l'administrateur lit la pièce de SA société
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE a uuid; u uuid; n int;
BEGIN
  SELECT v INTO a FROM _p317 WHERE k = 'A';
  SELECT v INTO u FROM _p317 WHERE k = 'ADMIN_A';
  PERFORM _p317_claims(u, a);
  PERFORM set_config('role', 'authenticated', true);   -- local à la transaction

  n := _p317_lit(a::text || '/accounting/invoice/invoice_A_1.pdf');

  PERFORM _rec('T03',
    'un administrateur lit la facture archivée de sa société : le chemin {société}/{module}/… ouvre bien la lecture à qui a le droit',
    n = 1, format('lignes visibles=%s (1 attendue)', n));
END $$;



-- ─────────────────────────────────────────────────────────────
-- T04 — la pièce de la société voisine reste invisible
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE a uuid; b uuid; u uuid; n_interdite int; n_la_sienne int;
BEGIN
  SELECT v INTO a FROM _p317 WHERE k = 'A';
  SELECT v INTO b FROM _p317 WHERE k = 'B';
  SELECT v INTO u FROM _p317 WHERE k = 'ADMIN_A';
  PERFORM _p317_claims(u, a);
  PERFORM set_config('role', 'authenticated', true);

  n_interdite := _p317_lit(b::text || '/accounting/invoice/invoice_B_1.pdf');
  n_la_sienne := _p317_lit(a::text || '/accounting/invoice/invoice_A_1.pdf');

  PERFORM _rec('T04',
    'l''administrateur de A ne voit PAS la pièce de B, et voit toujours la sienne : le premier segment du chemin est la société, et il ne se contourne pas',
    n_interdite = 0 AND n_la_sienne = 1,
    format('pièce de B visible=%s (0 attendue), pièce de A visible=%s (1 attendue)', n_interdite, n_la_sienne));
END $$;

-- ─────────────────────────────────────────────────────────────
-- T05 — le module décide : un commercial ne lit pas un bulletin de paie
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE a uuid; u uuid; n_paie int; n_devis int;
BEGIN
  SELECT v INTO a FROM _p317 WHERE k = 'A';
  SELECT v INTO u FROM _p317 WHERE k = 'COMMERCIAL_A';
  PERFORM _p317_claims(u, a);
  PERFORM set_config('role', 'authenticated', true);

  n_paie  := _p317_lit(a::text || '/hr/payslip/payslip_A_1.pdf');
  n_devis := _p317_lit(a::text || '/commercial/quote/quote_A_1.pdf');

  PERFORM _rec('T05',
    'un membre de la même société, mais SANS le module RH, ne lit pas le bulletin de paie archivé — et lit le devis de son module : la politique tient par le MODULE, pas seulement par la société',
    n_paie = 0 AND n_devis = 1,
    format('bulletin de paie visible=%s (0 attendu), devis visible=%s (1 attendu)', n_paie, n_devis));
END $$;

-- ─────────────────────────────────────────────────────────────
-- T06 — ce qui n'est pas nommé n'est pas permis (échec fermé)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE a uuid; u uuid; n_module_inconnu int; n_sans_module int;
BEGIN
  SELECT v INTO a FROM _p317 WHERE k = 'A';
  SELECT v INTO u FROM _p317 WHERE k = 'COMMERCIAL_A';

  -- Deux chemins qui n'ont PAS de 2e segment exploitable : un module inventé, et
  -- un chemin trop court. Ils sont écrits par le superutilisateur (le décor),
  -- puis lus sous le rôle de l'utilisateur : la politique doit rendre 0, et non
  -- « tout » — un `has_module_access(NULL)` vrai serait une porte ouverte.
  INSERT INTO storage.objects (bucket_id, name) VALUES
    ('generated-pdfs', a::text || '/zzz_inconnu/invoice/faux_1.pdf'),
    ('generated-pdfs', a::text || '/faux_sans_module.pdf')
  ON CONFLICT DO NOTHING;

  PERFORM _p317_claims(u, a);
  PERFORM set_config('role', 'authenticated', true);

  n_module_inconnu := _p317_lit(a::text || '/zzz_inconnu/invoice/faux_1.pdf');
  n_sans_module    := _p317_lit(a::text || '/faux_sans_module.pdf');

  PERFORM _rec('T06',
    'un module inconnu, ou un chemin SANS segment de module, ne rend pas l''accès plus large : l''échec est fermé',
    n_module_inconnu = 0 AND n_sans_module = 0,
    format('module inconnu visible=%s, chemin sans module visible=%s (0 attendu dans les deux cas)',
           n_module_inconnu, n_sans_module));
END $$;


-- ─────────────────────────────────────────────────────────────
-- T07 — un utilisateur ne fabrique, ne réécrit, ni n'efface une pièce
-- ─────────────────────────────────────────────────────────────
-- Trois mesures, trois formes de refus différentes — et c'est voulu :
--   • INSERT sans politique          → ERREUR (42501, RLS) ;
--   • UPDATE et DELETE sans politique → 0 ligne, sans erreur (la ligne est
--     simplement invisible pour cette commande).
-- Mesurer les deux formes (et pas seulement « ça ne marche pas ») garantit que
-- le refus vient bien de la RLS et non d'un privilège manquant.
DO $$
DECLARE a uuid; u uuid; v_faux text; v_path text;
        v_sqlstate text; v_message text;
        n_update int; n_delete int;
BEGIN
  SELECT v INTO a FROM _p317 WHERE k = 'A';
  SELECT v INTO u FROM _p317 WHERE k = 'ADMIN_A';
  v_path := a::text || '/accounting/invoice/invoice_A_1.pdf';
  v_faux := a::text || '/accounting/invoice/fabriquee_par_l_utilisateur.pdf';

  PERFORM _p317_claims(u, a);
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    INSERT INTO storage.objects (bucket_id, name) VALUES ('generated-pdfs', v_faux);
    v_sqlstate := 'AUCUNE ERREUR';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_message = MESSAGE_TEXT;
  END;

  UPDATE storage.objects SET name = v_path || '.reecrit'
   WHERE bucket_id = 'generated-pdfs' AND name = v_path;
  GET DIAGNOSTICS n_update = ROW_COUNT;

  DELETE FROM storage.objects
   WHERE bucket_id = 'generated-pdfs' AND name = v_path;
  GET DIAGNOSTICS n_delete = ROW_COUNT;

  PERFORM _rec('T07',
    'un administrateur — le rôle le plus haut d''une société — ne peut ni FABRIQUER une pièce d''archive (RLS), ni la RÉÉCRIRE, ni l''EFFACER : la pièce produite par le serveur est inaltérable par l''application',
    v_sqlstate = '42501' AND n_update = 0 AND n_delete = 0,
    format('INSERT → %s (%s) ; UPDATE → %s ligne(s) ; DELETE → %s ligne(s)',
           v_sqlstate, coalesce(left(v_message, 80), ''), n_update, n_delete));
END $$;

-- ─────────────────────────────────────────────────────────────
-- T08 — la clé de service écrit et purge : le seul écrivain
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE a uuid; v_tmp text; v_ok int := 0; v_purge int := 0;
BEGIN
  SELECT v INTO a FROM _p317 WHERE k = 'A';
  v_tmp := a::text || '/accounting/invoice/serveur_1.pdf';

  PERFORM set_config('role', 'service_role', true);

  BEGIN
    INSERT INTO storage.objects (bucket_id, name) VALUES ('generated-pdfs', v_tmp);
    v_ok := 1;
  EXCEPTION WHEN OTHERS THEN
    v_ok := 0;
  END;

  DELETE FROM storage.objects WHERE bucket_id = 'generated-pdfs' AND name = v_tmp;
  GET DIAGNOSTICS v_purge = ROW_COUNT;

  PERFORM _rec('T08',
    'la clé de service — le seul écrivain, puisque l''application n''a pas de politique d''écriture — dépose une pièce ET la purge : l''absence des trois politiques est une décision, pas un oubli',
    v_ok = 1 AND v_purge = 1,
    format('dépôt par le serveur=%s, purge par le serveur=%s ligne(s)', v_ok, v_purge));
END $$;

-- ─────────────────────────────────────────────────────────────
-- T09 — `anon` n'obtient pas la pièce, et la politique ne le vise pas
-- ─────────────────────────────────────────────────────────────
-- DEUX mesures, parce que la seconde forme de refus n'est pas de ce fichier :
--   1. la politique `generated_pdfs_download` porte `TO authenticated` et rien
--      d'autre — vérifié sur son DÉFINITION, pas supposé ;
--   2. la lecture par `anon` n'aboutit pas. Elle peut échouer de deux façons, et
--      les deux sont un non-partage : soit 0 ligne, soit une erreur de droit
--      (42501). Mesuré le 30/09 : c'est l'erreur qui sort, et elle ne vient PAS
--      de ce bucket — les politiques de la `68` ne nomment aucun rôle, donc
--      `anon` les évalue aussi, et `current_user_role()` n'est pas exécutable
--      par lui (`27_multi_tenant_switching.sql` ne l'accorde qu'à
--      `authenticated`). C'est un fait préexistant, hors du périmètre de la 317 :
--      il est NOMMÉ ici, dans le détail du verdict, jamais tu.
DO $$
DECLARE a uuid; n int := -1; v_state text; v_roles text[];
BEGIN
  SELECT v INTO a FROM _p317 WHERE k = 'A';

  SELECT roles INTO v_roles FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects'
     AND policyname = 'generated_pdfs_download';

  BEGIN
    PERFORM set_config('role', 'anon', true);
    n := _p317_lit(a::text || '/accounting/invoice/invoice_A_1.pdf');
    v_state := 'lecture aboutie';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;

  PERFORM _rec('T09',
    'la politique d''archive est réservée à `authenticated` (vérifié sur sa définition), et un visiteur non connecté n''obtient PAS la pièce — 0 ligne ou refus (42501), les deux formes étant un non-partage',
    v_roles = ARRAY['authenticated'] AND (n = 0 OR v_state = '42501'),
    format('rôles de la politique=%s ; lecture par anon → %s', v_roles, coalesce(v_state, '0 ligne')));
END $$;

SELECT _audit_assert('317');

