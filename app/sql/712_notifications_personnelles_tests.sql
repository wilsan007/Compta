-- ============================================================
-- 712_notifications_personnelles_tests.sql — F.6 / NOT-01 :
--   UNE NOTIFICATION PERSONNELLE, TENUE PAR LA BASE
--
--   T01  RLS FORCÉE sur `notifications` (le mur ne se lève pas)
--   T02  `anon` ne lit pas et n'écrit pas — AUCUN droit du tout
--   T03  `authenticated` n'écrit plus en direct (lecture seule)
--   T04  les QUATRE politiques RLS bornent au DESTINATAIRE
--   T05  A ne voit PAS la notification de B (la fuite est fermée)
--   T06  … mais il VOIT la diffusion (`user_id IS NULL`)
--   T07  A ne peut pas marquer lue la notification de B
--   T08  le compteur SANS argument compte « moi » (+ diffusion), pas la société
--   T09  « tout marquer lu » ne marque que les miennes (+ diffusion)
--   T10  `create_notification` : soi-même oui, un AUTRE non, diffuser non
--   T11  un destinataire qui n'est pas un compte redevient DIFFUSION
--   T12  le bulletin de paie part au COMPTE du salarié (`auth_user_id`)
--   T13  A ne voit rien de la société voisine (cloisonnement)
--
--   T05→T10 et T13 sont joués SOUS LE RÔLE `authenticated` (le seul endroit
--   où la RLS parle) ; `_audit_results` est ouvert à ce rôle — helper de la
--   maison, cf. `105_rls_tests.sql`.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '712', false);
DELETE FROM _audit_results WHERE file = '712';

DROP TABLE IF EXISTS t712;
CREATE TEMP TABLE t712 (k text PRIMARY KEY, v uuid);
GRANT SELECT, INSERT, UPDATE ON t712 TO authenticated;

-- ------------------------------------------------------------
-- Décor (superutilisateur) : une société, DEUX comptes, une diffusion,
-- un destinataire fantôme, une société voisine — et de quoi produire
-- un bulletin de paie.
-- ------------------------------------------------------------
DO $$
DECLARE
  ta uuid; tb uuid; aA uuid; aB uuid; nA uuid; nB uuid; nO uuid; nF uuid;
  emp uuid; ps uuid;
BEGIN
  ta := _mk_tenant('F712A');
  SELECT auth_id INTO aA FROM tenant_users
   WHERE tenant_id = ta AND name = 'Admin' LIMIT 1;

  -- le SECOND compte, dans la MÊME société
  aB := uuid_generate_v4();
  INSERT INTO auth.users (id, email) VALUES (aB, 'b712@audit.test');
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status, created_at)
    VALUES (ta, aB, 'b712@audit.test', 'B', 'admin', 'active', now());
  PERFORM set_config('request.jwt.claim.sub', aA::text, true);

  -- la société voisine (le cloisonnement)
  tb := _mk_tenant('F712B');

  -- destinataires : A, B, DIFFUSION (NULL), et un identifiant qui n'est le
  -- compte de personne (c'est ce que la 93 écrivait pour un bulletin)
  INSERT INTO notifications (tenant_id, user_id, category, severity, title, message)
    VALUES (ta, aA, 'sales', 'info', 'A moi', 'corps') RETURNING id INTO nA;
  INSERT INTO notifications (tenant_id, user_id, category, severity, title, message)
    VALUES (ta, aB, 'sales', 'info', 'A B', 'corps') RETURNING id INTO nB;
  INSERT INTO notifications (tenant_id, user_id, category, severity, title, message)
    VALUES (ta, NULL, 'sales', 'warning', 'A tous', 'corps') RETURNING id INTO nO;
  INSERT INTO notifications (tenant_id, user_id, category, severity, title, message)
    VALUES (ta, uuid_generate_v4(), 'hr', 'info', 'Fantome', 'corps') RETURNING id INTO nF;
  INSERT INTO notifications (tenant_id, user_id, category, severity, title, message)
    VALUES (tb, NULL, 'sales', 'info', 'Societe B', 'corps');

  INSERT INTO t712 (k, v) VALUES
    ('ta', ta), ('tb', tb), ('aA', aA), ('aB', aB),
    ('nA', nA), ('nB', nB), ('nO', nO), ('nF', nF);

  -- Le contexte de la société A AVANT d'écrire : la notification du bulletin
  -- doit naître chez A, pas chez la société voisine (mesuré à l'écriture).
  --
  -- L'en-tête est posé au niveau SESSION (`false`), JAMAIS local — c'est la
  -- doctrine écrite dans la 236 (lignes 36-44) : un GUC personnalisé n'est
  -- jamais « désactivé », et après le COMMIT d'un SET LOCAL le placeholder
  -- reste à la chaîne VIDE. Or `current_tenant_id()` fait
  -- `current_setting('request.headers', true)::json` : le T09 de cette suite
  -- est mort sur « invalid input syntax for type json » avant ce correctif,
  -- mesuré. Le rôle, lui, reste local (il doit redevenir superutilisateur
  -- pour que la mesure ne soit pas aveuglée par la RLS).
  PERFORM set_config('app.active_tenant_id', ta::text, false);
  PERFORM set_config('request.jwt.claim.sub', aA::text, false);
  PERFORM set_config('request.headers',
    json_build_object('x-tenant-id', ta::text)::text, false);

  -- un salarié qui a un COMPTE (aB), et un bulletin en brouillon
  INSERT INTO employees (tenant_id, name, auth_user_id) VALUES (ta, 'Salarie 712', aB)
    RETURNING id INTO emp;
  INSERT INTO pay_slips (tenant_id, number, employee_id, period_start, period_end, status)
    VALUES (ta, 'BS-712', emp, '2026-09-01', '2026-09-30', 'draft')
    RETURNING id INTO ps;
  INSERT INTO t712 (k, v) VALUES ('emp', emp), ('ps', ps);
END $$;

-- ------------------------------------------------------------
-- T01 — le mur RLS reste forcé
-- ------------------------------------------------------------
DO $$
DECLARE v boolean;
BEGIN
  SELECT relforcerowsecurity INTO v FROM pg_class WHERE relname = 'notifications';
  PERFORM _rec('T01', 'RLS FORCÉE sur `notifications`',
    v IS TRUE, format('relforcerowsecurity = %s', COALESCE(v::text, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'RLS forcée', false, SQLERRM);
END $$;

-- ------------------------------------------------------------
-- T02 / T03 — les droits : `anon` rien, `authenticated` en LECTURE seule
-- ------------------------------------------------------------
DO $$
DECLARE anon_privs text; ecrit text; lecture boolean;
BEGIN
  SELECT string_agg(p, ',' ORDER BY p) INTO anon_privs
    FROM unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES']) p
   WHERE has_table_privilege('anon', 'notifications', p);
  PERFORM _rec('T02', '`anon` n''a AUCUN droit sur les notifications',
    anon_privs IS NULL, format('droits d''anon = %s', COALESCE(anon_privs, 'aucun')));

  SELECT string_agg(p, ',' ORDER BY p) INTO ecrit
    FROM unnest(ARRAY['INSERT','UPDATE','DELETE','TRUNCATE']) p
   WHERE has_table_privilege('authenticated', 'notifications', p);
  lecture := has_table_privilege('authenticated', 'notifications', 'SELECT');
  PERFORM _rec('T03', '`authenticated` n''écrit plus en direct (lecture seule : les fonctions sont les seules plumes)',
    ecrit IS NULL AND lecture,
    format('écritures directes = %s ; SELECT = %s', COALESCE(ecrit, 'aucune'), lecture));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'anon sans droits', false, SQLERRM);
  PERFORM _rec('T03', 'authenticated en lecture seule', false, SQLERRM);
END $$;

-- ------------------------------------------------------------
-- T04 — les quatre politiques bornent au destinataire
-- ------------------------------------------------------------
DO $$
DECLARE n int; sans_uid text; cmds text;
BEGIN
  SELECT count(*), string_agg(DISTINCT cmd, ',' ORDER BY cmd) INTO n, cmds
    FROM pg_policies WHERE tablename = 'notifications';
  SELECT string_agg(policyname, ', ') INTO sans_uid
    FROM pg_policies
   WHERE tablename = 'notifications'
     AND COALESCE(qual, '') || ' ' || COALESCE(with_check, '') NOT LIKE '%auth.uid()%';
  PERFORM _rec('T04', 'les 4 politiques RLS bornent au DESTINATAIRE (auth.uid())',
    n = 4 AND sans_uid IS NULL,
    format('politiques = %s (%s) ; sans borne utilisateur = %s',
           n, COALESCE(cmds, '-'), COALESCE(sans_uid, 'aucune')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'politiques bornées', false, SQLERRM);
END $$;

-- ------------------------------------------------------------
-- T05 → T10, T13 — LE COMPORTEMENT, sous le rôle `authenticated`
--   (le seul endroit où la RLS parle ; `_audit_results` lui est ouvert)
--   T07 et T09 n'enregistrent pas ici : leurs ACTES sont joués ci-dessous,
--   leurs VERDICTS se lisent après, en superutilisateur (un utilisateur ne
--   peut pas voir si la boîte d'un autre a bougé — c'est le point).
-- ------------------------------------------------------------
BEGIN;
DO $$
DECLARE
  aA uuid; aB uuid; tb uuid; nB uuid;
  n int; ok_soi boolean := false; ok_autre boolean := false; ok_diff boolean := false;
BEGIN
  SELECT v INTO aA FROM t712 WHERE k = 'aA';
  SELECT v INTO aB FROM t712 WHERE k = 'aB';
  SELECT v INTO tb FROM t712 WHERE k = 'tb';
  SELECT v INTO nB FROM t712 WHERE k = 'nB';

  PERFORM _as_user();
  PERFORM set_config('request.jwt.claim.sub', aA::text, true);

  -- T05 — la fuite : A ne voit PAS la notification de B
  SELECT count(*) INTO n FROM notifications WHERE user_id = aB;
  PERFORM _rec('T05', 'A ne voit PAS la notification de B (la fuite est fermée)',
    n = 0, format('lignes de B visibles par A = %s (attendu 0)', n));

  -- T06 — … mais il voit LA SIENNE et la DIFFUSION
  SELECT count(*) INTO n FROM notifications WHERE title IN ('A moi', 'A tous');
  PERFORM _rec('T06', 'A voit SA notification et la DIFFUSION',
    n = 2, format('visibles parmi « A moi » et « A tous » = %s (attendu 2)', n));

  -- T07 (l'acte : A essaie d'ouvrir le courrier de B — le verdict est lu
  --      après le COMMIT, en superutilisateur)
  PERFORM mark_notification_read(nB);

  -- T08 — le compteur sans argument veut dire « moi »
  --   décor : 1 pour A + 2 diffusions + 1 pour B + 1 pour la société voisine
  SELECT get_unread_notification_count() INTO n;
  PERFORM _rec('T08', 'le compteur SANS argument compte « moi » (+ diffusion), pas la société',
    n = 3,
    format('compteur pour A = %s (attendu 3 : la sienne + 2 diffusions, jamais celle de B)', n));

  -- (T09 est joué dans son propre bloc, APRÈS le verdict de T07 : deux actes,
  --  deux verdicts — sinon le second cacherait le premier.)

  -- T10 — écrire : soi-même oui, un autre non, diffuser non
  BEGIN
    PERFORM create_notification('sales', 'Pour moi', 'corps', aA, 'info', NULL, '{}'::jsonb);
    ok_soi := true;
  EXCEPTION WHEN OTHERS THEN ok_soi := false;
  END;
  BEGIN
    PERFORM create_notification('sales', 'Pour B', 'corps', aB, 'info', NULL, '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN ok_autre := SQLERRM LIKE '%NOTIFICATION_DESTINATAIRE_REFUSE%';
  END;
  BEGIN
    PERFORM create_notification('sales', 'Pour tous', 'corps', NULL, 'info', NULL, '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN ok_diff := SQLERRM LIKE '%NOTIFICATION_DESTINATAIRE_REFUSE%';
  END;
  PERFORM _rec('T10', '`create_notification` : soi-même oui, un AUTRE non, diffuser non',
    ok_soi AND ok_autre AND ok_diff,
    format('soi-même = %s ; un autre refusé (NOTIFICATION_DESTINATAIRE_REFUSE) = %s ; diffusion refusée = %s',
           ok_soi, ok_autre, ok_diff));

  -- T13 — un en-tête falsifié ne fait pas voir la société voisine
  --   (l'en-tête de SESSION nomme A ; on le surcharge LOCALEMENT ici, et il
  --    revient à A au COMMIT — c'est ce qui laisse T09 jouer juste après)
  PERFORM set_config('request.headers', json_build_object('x-tenant-id', tb)::text, true);
  SELECT count(*) INTO n FROM notifications WHERE tenant_id = tb;
  PERFORM _rec('T13', 'A ne voit RIEN de la société voisine (en-tête falsifié) — non-régression',
    n = 0, format('lignes de la société B visibles = %s (attendu 0)', n));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'fuite fermée', false, SQLERRM);
  PERFORM _rec('T06', 'diffusion visible', false, SQLERRM);
  PERFORM _rec('T08', 'compteur du destinataire', false, SQLERRM);
  PERFORM _rec('T10', 'écriture bornée', false, SQLERRM);
  PERFORM _rec('T13', 'cloisonnement', false, SQLERRM);
END $$;
COMMIT;

-- ------------------------------------------------------------
-- T07 — le verdict : l'acte de A n'a RIEN changé à la boîte de B
--       (A ne peut pas le constater lui-même — c'est précisément le point)
-- ------------------------------------------------------------
DO $$
DECLARE nB uuid; ok boolean;
BEGIN
  SELECT v INTO nB FROM t712 WHERE k = 'nB';
  SELECT read_at IS NULL INTO ok FROM notifications WHERE id = nB;
  PERFORM _rec('T07', 'A ne peut pas marquer lue la notification de B (elle reste intacte)',
    ok, format('read_at de la notification de B = %s',
               CASE WHEN ok THEN 'NULL — intacte' ELSE 'remplie — quelqu''un l''a ouverte' END));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T07', 'courrier de B intact', false, SQLERRM);
END $$;

-- ------------------------------------------------------------
-- T09 — second acte, dans son propre bloc : « tout marquer lu » SANS argument
-- ------------------------------------------------------------
BEGIN;
DO $$
DECLARE aA uuid;
BEGIN
  SELECT v INTO aA FROM t712 WHERE k = 'aA';
  PERFORM _as_user();
  PERFORM set_config('request.jwt.claim.sub', aA::text, true);
  PERFORM mark_all_notifications_read();
END $$;
COMMIT;

-- ------------------------------------------------------------
-- T09 / T11 / T12 — les verdicts, en superutilisateur
-- ------------------------------------------------------------
DO $$
DECLARE
  ta uuid; emp uuid; aB uuid;
  nA uuid; nO uuid; nF uuid; nB uuid; v_uid uuid;
  n int; ok boolean;
BEGIN
  SELECT v INTO ta FROM t712 WHERE k = 'ta';
  SELECT v INTO emp FROM t712 WHERE k = 'emp';
  SELECT v INTO aB FROM t712 WHERE k = 'aB';
  SELECT v INTO nA FROM t712 WHERE k = 'nA';
  SELECT v INTO nO FROM t712 WHERE k = 'nO';
  SELECT v INTO nF FROM t712 WHERE k = 'nF';
  SELECT v INTO nB FROM t712 WHERE k = 'nB';

  -- T09 — les siennes et les diffusions sont marquées lues… et celle de B NON
  --   (les deux moitiés comptent : l'ancien `mark_all`, appelé sans argument,
  --    marquait lues les notifications de TOUTE la société)
  SELECT count(*) INTO n FROM notifications
   WHERE id IN (nA, nO, nF) AND read_at IS NULL;
  SELECT read_at IS NULL INTO ok FROM notifications WHERE id = nB;
  PERFORM _rec('T09', '« tout marquer lu » marque les miennes ET les diffusions, jamais celle de B',
    n = 0 AND ok,
    format('non lues parmi (A moi, A tous, Fantome) = %s ; celle de B = %s',
           n, CASE WHEN ok THEN 'intacte' ELSE 'MARQUÉE LUE par A' END));

  -- T11 — le destinataire inconnu est devenu une DIFFUSION
  SELECT user_id IS NULL INTO ok FROM notifications WHERE id = nF;
  PERFORM _rec('T11', 'un destinataire qui n''est pas un membre redevient DIFFUSION (jamais perdu)',
    ok, format('« Fantome » user_id = %s',
               CASE WHEN ok THEN 'NULL (diffusion)' ELSE 'un identifiant que personne ne lit' END));

  -- T12 — le bulletin part au COMPTE du salarié, plus au salarié
  SELECT user_id INTO v_uid FROM notifications
   WHERE tenant_id = ta AND link = '/pay-slips/' || (SELECT v::text FROM t712 WHERE k = 'ps')
   ORDER BY created_at DESC LIMIT 1;
  PERFORM _rec('T12', 'le bulletin de paie va au COMPTE du salarié (`auth_user_id`)',
    v_uid IS NOT NULL AND v_uid = aB AND v_uid <> emp,
    format('destinataire = %s (compte du salarié attendu %s ; salarié %s)',
           COALESCE(v_uid::text, 'NULL — aucun bulletin notifié'), aB, emp));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T09', 'tout marquer lu borné', false, SQLERRM);
  PERFORM _rec('T11', 'destinataire inconnu = diffusion', false, SQLERRM);
  PERFORM _rec('T12', 'bulletin au compte du salarié', false, SQLERRM);
END $$;

-- Garde-fou anti-faux-vert : la suite EXIGE ses 13 verdicts
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _audit_results WHERE file = '712';
  IF n <> 13 THEN
    RAISE EXCEPTION '[712] % verdict(s) enregistré(s) au lieu de 13 — un scénario n''a pas été joué', n;
  END IF;
END $$;

SELECT _audit_assert('712');

