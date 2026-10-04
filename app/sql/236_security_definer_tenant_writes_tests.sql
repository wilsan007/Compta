-- ============================================================
-- 236_security_definer_tenant_writes_tests.sql — ISO-01 : écrire chez le voisin
--
-- Constat de l'audit du 23/09 (`scenarios/ISO_ecriture_inter_societes.sql`),
-- rejoué ici sous le vrai rôle `authenticated` avec les identifiants d'un
-- utilisateur de la société A :
--
--   Y0  la lecture croisée tient       : le client de B est invisible depuis A (RLS) ;
--   Y1  la facture de A vise le client de B : refusée      (ISO-02, 237) ;
--   Y2  la sous-tâche de A vise la tâche de B : refusée    (ISO-02, 237) ;
--   Y3  et le statut de la tâche de B ne bouge pas         (ISO-01, ici).
--
-- ÉTAT APRÈS LA 237 (24/09/2026). Les deux insertions ci-dessus, mesurées
-- « acceptées » par le constat d'origine, sont désormais REFUSÉES par les clés
-- étrangères composites — c'est le `T02` de ce fichier, qui passe du rouge au
-- vert et dont le registre des échecs attendus perd la ligne dans le même
-- commit. Les scénarios qui ont besoin d'un état hostile (une ligne de A qui
-- désigne une ligne de B) le fabriquent donc clés neutralisées, avec `_ref236`
-- et sa raison écrite : la garde de la 236 doit tenir contre cet état, quel
-- qu'en soit l'auteur.
--
-- Ces scénarios mesurent la PROPRIÉTÉ (« la donnée de B n'a pas bougé ») et non
-- l'interdiction de l'insertion : c'est la 237 qui interdit la référence, la
-- 236 empêche l'ÉCRITURE chez le voisin par un déclencheur `SECURITY DEFINER`.
-- Les deux verrous sont mesurés séparément, dans deux fichiers.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '236', false);
DELETE FROM _audit_results WHERE file = '236';

-- L'utilisateur de la société demandée, par le même chemin que le scénario de
-- constat : JWT + en-tête `x-tenant-id`. Le rôle est POSÉ, jamais supposé.
--
-- PIÈGE MESURÉ, qui a coûté deux passes : `set_config(nom, valeur, true)` sur un
-- GUC personnalisé (nom contenant un point) laisse le placeholder à **chaîne
-- vide** — et non à NULL — après le commit de la transaction :
--     BEGIN; SELECT set_config('zz.test','{"a":1}',true); COMMIT;
--     SELECT current_setting('zz.test', true) IS NULL;  -- false
--     SELECT quote_nullable(current_setting('zz.test', true));  -- ''
-- Or `current_tenant_id()` fait `current_setting('request.headers', true)::json` :
-- le test suivant mourait sur « invalid input syntax for type json ». L'en-tête
-- est donc posé au niveau SESSION (false), comme le font `_mk_tenant` et les
-- scénarios de constat. Le rôle, lui, reste LOCAL : il doit redevenir `postgres`
-- à la fin du bloc pour que la MESURE ne soit pas aveuglée par la RLS.
CREATE OR REPLACE FUNCTION _as236(p_tenant uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_user uuid;
BEGIN
  -- L'appelant est l'ADMINISTRATEUR de la société — celui que `_mk_tenant` crée —
  -- parce que c'est lui, dans le produit, qui appelle `auto_revoke_expired_auditors()`
  -- (`src/lib/auth.tsx`). Ne jamais trier sur `created_at` seul : `_mk_tenant` le
  -- pose à `now()`, et les auditeurs de T12/T13 sont insérés dans la MÊME
  -- transaction — même horodatage. MESURÉ le 24/09/2026 : 2 utilisateurs actifs,
  -- **un seul** horodatage distinct ; l'ordre rendu est alors un ex æquo tranché
  -- par le plan. Une exécution retenait l'auditeur, et `prevent_role_escalation`
  -- refusait alors « Cannot change own status » : T12/T13 mouraient hors registre
  -- et la suite entière avec eux. Une exécution identique retenait
  -- l'administrateur et rendait 17/17. Le rôle départage donc d'abord, puis
  -- `created_at` et `id` pour que le choix soit déterministe.
  SELECT auth_id INTO v_user FROM tenant_users
  WHERE tenant_id = p_tenant AND status = 'active'
  ORDER BY (role = 'admin') DESC, created_at, id LIMIT 1;
  IF v_user IS NULL THEN RAISE EXCEPTION 'Aucun utilisateur actif pour la société %', p_tenant; END IF;
  PERFORM set_config('request.jwt.claim.sub', v_user::text, false);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text, false);
  PERFORM set_config('request.headers',
    json_build_object('x-tenant-id', p_tenant::text)::text, false);
  PERFORM set_config('app.active_tenant_id', p_tenant::text, true);
  PERFORM set_config('role', 'authenticated', true);
  IF current_tenant_id() IS DISTINCT FROM p_tenant THEN
    RAISE EXCEPTION 'Contexte tenant non établi — le test ne prouverait rien';
  END IF;
  RETURN v_user;
END $$;

-- Reprend le rôle privilégié pour MESURER : sous `authenticated`, la lecture
-- croisée est refusée par la RLS et l'assertion serait vraie par aveuglement.
CREATE OR REPLACE FUNCTION _mesure236() RETURNS void LANGUAGE sql AS $$
  SELECT set_config('role', 'postgres', true)
$$;

-- FABRIQUER UNE RÉFÉRENCE INTER-SOCIÉTÉ — ce que la 237 a rendu impossible.
-- Cinq scénarios ci-dessous doivent partir d'un état que l'application ne peut
-- plus produire : une ligne de A qui désigne une ligne de B, et qui doit ENCORE
-- pouvoir être modifiée par A pour déclencher la garde mesurée. Depuis la 237,
-- la clé composite refuse l'insertion ET toute modification ultérieure de cette
-- ligne : `session_replication_role = replica` ne suffirait donc pas (le
-- déclencheur mesuré serait éteint en même temps que la clé).
-- Les déclencheurs INTERNES de la table — les clés étrangères, et elles seules —
-- sont donc désactivés le temps du scénario : les déclencheurs utilisateur, dont
-- ceux de la 236, restent actifs, et c'est leur portée qui est mesurée.
-- Ce n'est pas un contournement du correctif : c'est le seul moyen de fabriquer
-- l'état hostile contre lequel la garde de la 236 doit tenir, quel qu'en soit
-- l'auteur. Les déclencheurs sont réarmés dans le même scénario.
CREATE OR REPLACE FUNCTION _fk236(p_table text, p_on boolean) RETURNS void LANGUAGE plpgsql AS $$
DECLARE t record;
BEGIN
  FOR t IN SELECT tgname FROM pg_trigger
           WHERE tgrelid = ('public.' || p_table)::regclass AND tgisinternal
  LOOP
    EXECUTE format('ALTER TABLE public.%I %s TRIGGER %I',
                   p_table, CASE WHEN p_on THEN 'ENABLE' ELSE 'DISABLE' END, t.tgname);
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION _fixture236(p_tenant uuid)
RETURNS TABLE (projet uuid, tache uuid, jalon uuid, facture uuid)
LANGUAGE plpgsql AS $$
DECLARE v_projet uuid; v_tache uuid; v_jalon uuid; v_facture uuid;
BEGIN
  INSERT INTO projects (tenant_id, name) VALUES (p_tenant, 'Projet ' || left(p_tenant::text, 8))
  RETURNING id INTO v_projet;
  INSERT INTO project_tasks (tenant_id, project_id, title, status, progress)
  VALUES (p_tenant, v_projet, 'Tâche racine', 'todo', 0) RETURNING id INTO v_tache;
  INSERT INTO project_milestones (tenant_id, project_id, name)
  VALUES (p_tenant, v_projet, 'Jalon') RETURNING id INTO v_jalon;
  INSERT INTO invoices (tenant_id, number, due_date, status, validation_status,
                        subtotal, vat_total, total)
  VALUES (p_tenant, 'FAC-' || left(p_tenant::text, 8), '2026-04-01', 'draft', 'draft', 0, 0, 0)
  RETURNING id INTO v_facture;
  projet := v_projet; tache := v_tache; jalon := v_jalon; facture := v_facture;
  RETURN NEXT;
END $$;


-- ── T01 : la tâche du voisin n'est plus fermée (le Y3 du constat) ─────────
-- Depuis la 237, la sous-tâche de A qui désigne la tâche de B est refusée : la
-- référence est donc fabriquée déclencheurs neutralisés, puis A fait son geste
-- légitime — fermer SA sous-tâche — sous son vrai rôle. C'est ce geste qui,
-- avant la 236, fermait la tâche de B.
DO $$
DECLARE ta uuid; tb uuid; fb record; v_sous uuid; v_statut text; v_ref boolean := false;
BEGIN
  ta := _mk_tenant('ISO236A1'); tb := _mk_tenant('ISO236B1');
  PERFORM _fixture236(ta);
  SELECT * INTO fb FROM _fixture236(tb);
  PERFORM _fk236('project_tasks', false);
  -- le déclencheur de journal recopie la référence dans `project_activity_log` :
  -- sa clé composite la refuserait aussi — elle est donc neutralisée le temps du
  -- scénario, comme celle de `project_tasks`
  PERFORM _fk236('project_activity_log', false);
  INSERT INTO project_tasks (tenant_id, parent_id, title, status, progress)
  VALUES (ta, fb.tache, 'Sous-tâche de A sur la tâche de B', 'todo', 0)
  RETURNING id INTO v_sous;
  v_ref := true;
  PERFORM _as236(ta);
  UPDATE project_tasks SET status = 'done', progress = 100 WHERE id = v_sous;
  PERFORM _mesure236();
  PERFORM _fk236('project_tasks', true);
  PERFORM _fk236('project_activity_log', true);
  SELECT status INTO v_statut FROM project_tasks WHERE id = fb.tache;
  PERFORM _rec('T01', 'fermer sa sous-tâche ne ferme plus la tâche du voisin',
    v_ref AND v_statut IS NOT DISTINCT FROM 'todo',
    format('référence hostile fabriquée=%s, statut de la tâche de B=%s (attendu todo)',
           v_ref, COALESCE(v_statut, 'NULL')));
END $$;

-- ── T02 : l'insertion inter-sociétés est désormais REFUSÉE (ISO-02, 237) ───
-- Ce scénario mesurait le trou : « l'insertion reste acceptée tant que les clés
-- composites n'existent pas ». La 237 existe : le verdict s'inverse, et le
-- registre des échecs attendus perd sa ligne dans le même commit — la CI
-- l'exige, c'est ce qui empêche un défaut corrigé de rester inscrit.
-- L'assertion reste ici parce qu'elle mesure une PROPRIÉTÉ de la base, et non
-- une ligne de code : le jour où une clé composite sauterait, elle repasserait
-- au rouge.
DO $$
DECLARE ta uuid; tb uuid; fb record; v_state text := NULL; v_err text := '—';
BEGIN
  ta := _mk_tenant('ISO236A2'); tb := _mk_tenant('ISO236B2');
  PERFORM _fixture236(ta);
  SELECT * INTO fb FROM _fixture236(tb);
  PERFORM _as236(ta);
  BEGIN
    INSERT INTO project_tasks (tenant_id, project_id, parent_id, title, status, progress)
    VALUES (ta, NULL, fb.tache, 'Sous-tâche de A sur la tâche de B', 'todo', 0);
  EXCEPTION WHEN OTHERS THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  PERFORM _mesure236();
  PERFORM _rec('T02', 'une ligne de A ne peut pas référencer une ligne de B (clé étrangère composite, ISO-02)',
    v_state = '23503',
    format('SQLSTATE=%s (attendu 23503) | %s',
           COALESCE(v_state, 'aucune erreur — la référence inter-sociétés est acceptée'),
           left(v_err, 90)));
END $$;

-- ── T03 : la fonction fait toujours son travail dans sa propre société ────
DO $$
DECLARE ta uuid; fa record; v_statut text;
BEGIN
  ta := _mk_tenant('ISO236A3');
  SELECT * INTO fa FROM _fixture236(ta);
  PERFORM _as236(ta);
  INSERT INTO project_tasks (tenant_id, project_id, parent_id, title, status, progress)
  VALUES (ta, fa.projet, fa.tache, 'Sous-tâche de A', 'done', 100);
  PERFORM _mesure236();
  SELECT status INTO v_statut FROM project_tasks WHERE id = fa.tache;
  PERFORM _rec('T03', 'dans sa propre société, la dernière sous-tâche fermée ferme la tâche parente',
    v_statut IS NOT DISTINCT FROM 'done',
    format('statut du parent=%s (attendu done)', COALESCE(v_statut, 'NULL')));
END $$;

-- ── T04 : l'avancement du projet du voisin n'est pas recalculé ────────────
-- La référence hostile (tâche de A dans le projet de B) est fabriquée
-- déclencheurs neutralisés depuis la 237 ; c'est ensuite la modification de SA
-- tâche par A, sous son vrai rôle, qui déclenche le recalcul mesuré.
DO $$
DECLARE ta uuid; tb uuid; fb record; v_avant integer; v_apres integer; v_tache uuid;
BEGIN
  ta := _mk_tenant('ISO236A4'); tb := _mk_tenant('ISO236B4');
  PERFORM _fixture236(ta);
  SELECT * INTO fb FROM _fixture236(tb);
  PERFORM _mesure236();
  SELECT progress INTO v_avant FROM projects WHERE id = fb.projet;
  PERFORM _fk236('project_tasks', false);
  PERFORM _fk236('project_activity_log', false);
  INSERT INTO project_tasks (tenant_id, project_id, title, status, progress)
  VALUES (ta, fb.projet, 'Tâche de A dans le projet de B', 'todo', 0)
  RETURNING id INTO v_tache;
  PERFORM _as236(ta);
  UPDATE project_tasks SET progress = 100 WHERE id = v_tache;
  PERFORM _mesure236();
  PERFORM _fk236('project_tasks', true);
  PERFORM _fk236('project_activity_log', true);
  SELECT progress INTO v_apres FROM projects WHERE id = fb.projet;
  PERFORM _rec('T04', 'l''avancement du projet d''une autre société n''est pas recalculé',
    v_apres IS NOT DISTINCT FROM v_avant,
    format('avant=%s après=%s (attendu identique)', v_avant, v_apres));
END $$;

-- ── T05 : le jalon du voisin n'est pas déclaré atteint ────────────────────
-- Même fabrication : la tâche de A rattachée au jalon de B est posée
-- déclencheurs neutralisés, puis A termine SA tâche sous son vrai rôle. Le
-- jalon de B n'a aucune autre tâche : sans le filtre de la 236, celle-ci suffit
-- à le déclarer atteint.
DO $$
DECLARE ta uuid; tb uuid; fb record; v_apres boolean; v_tache uuid;
BEGIN
  ta := _mk_tenant('ISO236A5'); tb := _mk_tenant('ISO236B5');
  PERFORM _fixture236(ta);
  SELECT * INTO fb FROM _fixture236(tb);
  PERFORM _fk236('project_tasks', false);
  PERFORM _fk236('project_activity_log', false);
  INSERT INTO project_tasks (tenant_id, milestone_id, title, status, progress)
  VALUES (ta, fb.jalon, 'Tâche de A sur le jalon de B', 'todo', 0)
  RETURNING id INTO v_tache;
  PERFORM _as236(ta);
  UPDATE project_tasks SET status = 'done', progress = 100 WHERE id = v_tache;
  PERFORM _mesure236();
  PERFORM _fk236('project_tasks', true);
  PERFORM _fk236('project_activity_log', true);
  SELECT is_reached INTO v_apres FROM project_milestones WHERE id = fb.jalon;
  PERFORM _rec('T05', 'un jalon d''une autre société n''est pas déclaré atteint',
    v_apres IS NOT DISTINCT FROM false,
    format('is_reached=%s (attendu false)', v_apres));
END $$;

-- ── T06 : dans sa propre société, le jalon est bien atteint ───────────────
DO $$
DECLARE ta uuid; fa record; v_apres boolean;
BEGIN
  ta := _mk_tenant('ISO236A6');
  SELECT * INTO fa FROM _fixture236(ta);
  PERFORM _as236(ta);
  INSERT INTO project_tasks (tenant_id, milestone_id, title, status, progress)
  VALUES (ta, fa.jalon, 'Tâche de A sur son jalon', 'done', 100);
  PERFORM _mesure236();
  SELECT is_reached INTO v_apres FROM project_milestones WHERE id = fa.jalon;
  PERFORM _rec('T06', 'dans sa propre société, la dernière tâche terminée atteint le jalon',
    v_apres IS NOT DISTINCT FROM true,
    format('is_reached=%s (attendu true)', v_apres));
END $$;


-- ── T07 : les heures imputées au projet du voisin ne le touchent pas ──────
-- Le chemin est déjà fermé en amont par `check_time_entry_tenant` (migration 231,
-- trouvé à l'exécution le 24/09). L'assertion porte donc sur la PROPRIÉTÉ — B n'a
-- pas bougé — et le détail dit si l'écriture a été refusée ou acceptée.
DO $$
DECLARE ta uuid; tb uuid; fb record; v_avant numeric; v_apres numeric;
        v_refuse boolean := false; err text := '—';
BEGIN
  ta := _mk_tenant('ISO236A7'); tb := _mk_tenant('ISO236B7');
  PERFORM _fixture236(ta);
  SELECT * INTO fb FROM _fixture236(tb);
  PERFORM _mesure236();
  SELECT total_hours_spent INTO v_avant FROM projects WHERE id = fb.projet;
  PERFORM _as236(ta);
  BEGIN
    INSERT INTO project_time_entries (tenant_id, project_id, duration_seconds, description)
    VALUES (ta, fb.projet, 7200, 'Temps de A imputé au projet de B');
  EXCEPTION WHEN OTHERS THEN v_refuse := true; err := SQLERRM;
  END;
  PERFORM _mesure236();
  SELECT total_hours_spent INTO v_apres FROM projects WHERE id = fb.projet;
  PERFORM _rec('T07', 'les heures d''une société ne s''ajoutent pas au projet d''une autre',
    v_apres IS NOT DISTINCT FROM v_avant,
    format('avant=%s après=%s — écriture %s', COALESCE(v_avant::text,'NULL'), COALESCE(v_apres::text,'NULL'),
           CASE WHEN v_refuse THEN 'refusée en amont : ' || left(err, 60) ELSE 'acceptée' END));
END $$;

-- ── T08 : le temps imputé à son propre projet compte bien ────────────────
DO $$
DECLARE ta uuid; fa record; v_apres numeric;
BEGIN
  ta := _mk_tenant('ISO236A8');
  SELECT * INTO fa FROM _fixture236(ta);
  PERFORM _as236(ta);
  INSERT INTO project_time_entries (tenant_id, project_id, duration_seconds, description)
  VALUES (ta, fa.projet, 7200, 'Temps de A sur son projet');
  PERFORM _mesure236();
  SELECT total_hours_spent INTO v_apres FROM projects WHERE id = fa.projet;
  PERFORM _rec('T08', 'dans sa propre société, deux heures de temps passé font deux heures',
    v_apres IS NOT DISTINCT FROM 2,
    format('total_hours_spent=%s (attendu 2)', COALESCE(v_apres::text, 'NULL')));
END $$;

-- ── T09 : les totaux de la facture du voisin ne sont pas réécrits ─────────
-- La ligne de facture est recalculée par `invoice_line_compute` (BEFORE) : le
-- montant se pose en quantité × prix unitaire. Le chemin est déjà refusé en amont
-- par la politique RLS « par le parent » de `invoice_lines` — cette politique
-- bloque `authenticated`, ni `service_role` ni un déclencheur, d'où la 236.
DO $$
DECLARE ta uuid; tb uuid; fb record; v_avant numeric; v_apres numeric;
        v_refuse boolean := false; err text := '—';
BEGIN
  ta := _mk_tenant('ISO236A9'); tb := _mk_tenant('ISO236B9');
  PERFORM _fixture236(ta);
  SELECT * INTO fb FROM _fixture236(tb);
  PERFORM _mesure236();
  SELECT total INTO v_avant FROM invoices WHERE id = fb.facture;
  PERFORM _as236(ta);
  BEGIN
    INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate)
    VALUES (ta, fb.facture, 'Ligne de A sur la facture de B', 10, 100, 20);
  EXCEPTION WHEN OTHERS THEN v_refuse := true; err := SQLERRM;
  END;
  PERFORM _mesure236();
  SELECT total INTO v_apres FROM invoices WHERE id = fb.facture;
  PERFORM _rec('T09', 'une ligne d''une société ne réécrit pas les totaux de la facture d''une autre',
    v_apres IS NOT DISTINCT FROM v_avant,
    format('total avant=%s après=%s — écriture %s', COALESCE(v_avant::text,'NULL'), COALESCE(v_apres::text,'NULL'),
           CASE WHEN v_refuse THEN 'refusée en amont : ' || left(err, 60) ELSE 'acceptée' END));
END $$;

-- ── T10 : les totaux de sa propre facture suivent bien ses lignes ─────────
DO $$
DECLARE ta uuid; fa record; v_ht numeric; v_tva numeric; v_total numeric;
BEGIN
  ta := _mk_tenant('ISO236A10');
  SELECT * INTO fa FROM _fixture236(ta);
  PERFORM _as236(ta);
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate)
  VALUES (ta, fa.facture, 'Ligne de A', 10, 100, 20);
  PERFORM _mesure236();
  SELECT subtotal, vat_total, total INTO v_ht, v_tva, v_total FROM invoices WHERE id = fa.facture;
  PERFORM _rec('T10', 'dans sa propre société, les totaux de la facture suivent ses lignes',
    v_ht IS NOT DISTINCT FROM 1000 AND v_tva IS NOT DISTINCT FROM 200 AND v_total IS NOT DISTINCT FROM 1200,
    format('subtotal=%s vat_total=%s total=%s (attendu 1000/200/1200)',
           COALESCE(v_ht::text,'NULL'), COALESCE(v_tva::text,'NULL'), COALESCE(v_total::text,'NULL')));
END $$;

-- ── T11 : l'avancement de la tâche du voisin n'est pas recalculé ──────────
-- Même fabrication : l'action de A rattachée à la tâche de B est posée
-- déclencheurs neutralisés, puis A la termine sous son vrai rôle.
DO $$
DECLARE ta uuid; tb uuid; fb record; v_apres integer; v_action uuid;
BEGIN
  ta := _mk_tenant('ISO236A11'); tb := _mk_tenant('ISO236B11');
  PERFORM _fixture236(ta);
  SELECT * INTO fb FROM _fixture236(tb);
  PERFORM _fk236('task_actions', false);
  INSERT INTO task_actions (tenant_id, task_id, title, weight_percentage, is_done)
  VALUES (ta, fb.tache, 'Action de A sur la tâche de B', 100, false)
  RETURNING id INTO v_action;
  PERFORM _as236(ta);
  UPDATE task_actions SET is_done = true WHERE id = v_action;
  PERFORM _mesure236();
  PERFORM _fk236('task_actions', true);
  SELECT progress INTO v_apres FROM project_tasks WHERE id = fb.tache;
  PERFORM _rec('T11', 'une action d''une société ne recalcule pas l''avancement de la tâche d''une autre',
    v_apres IS NOT DISTINCT FROM 0,
    format('progress=%s (attendu 0)', v_apres));
END $$;


-- ── T12/T13 : révocation des auditeurs expirés ────────────────────────────
-- La fonction est appelée au chargement de l'application (`auth.tsx:62`) :
-- chaque connexion révoquait donc les auditeurs expirés de TOUTES les sociétés.
DO $$
DECLARE ta uuid; tb uuid; ua_aud uuid; ub_aud uuid; v_b text; v_a text;
BEGIN
  ta := _mk_tenant('ISO236A12'); tb := _mk_tenant('ISO236B12');
  PERFORM _fixture236(ta);
  PERFORM _fixture236(tb);
  -- l'identifiant d'authentification doit exister : `tenant_users.auth_id` est une
  -- clé étrangère vers `auth.users`. Les identifiants sont fixes pour que la
  -- suite soit rejouable : la seconde exécution ne les recrée pas.
  INSERT INTO auth.users (id, email) VALUES
    ('77000000-0000-0000-0000-00000000a222', 'aud-a12@iso.test'),
    ('77000000-0000-0000-0000-00000000b222', 'aud-b12@iso.test')
  ON CONFLICT (id) DO NOTHING;
  -- Les fiches sont posées NON expirées : `tenant_users` porte un déclencheur
  -- (`trigger_revoke_expired_auditors`) qui révoque à l'écriture, ce qui
  -- mesurerait le déclencheur et non la fonction visée. Elles deviennent
  -- expirées par un UPDATE posé déclencheurs neutralisés — la technique que les
  -- suites 179 et 218 emploient déjà pour fabriquer un état sans effet de bord.
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status, valid_until)
  VALUES (ta, '77000000-0000-0000-0000-00000000a222', 'aud-a12@iso.test', 'Auditeur A', 'auditor', 'active', CURRENT_DATE + 30)
  RETURNING id INTO ua_aud;
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status, valid_until)
  VALUES (tb, '77000000-0000-0000-0000-00000000b222', 'aud-b12@iso.test', 'Auditeur B', 'auditor', 'active', CURRENT_DATE + 30)
  RETURNING id INTO ub_aud;
  SET LOCAL session_replication_role = replica;
  UPDATE tenant_users SET valid_until = CURRENT_DATE - 1 WHERE id IN (ua_aud, ub_aud);
  SET LOCAL session_replication_role = origin;

  PERFORM _as236(ta);
  PERFORM auto_revoke_expired_auditors();
  PERFORM _mesure236();

  SELECT status INTO v_b FROM tenant_users WHERE id = ub_aud;
  SELECT status INTO v_a FROM tenant_users WHERE id = ua_aud;
  PERFORM _rec('T12', 'la révocation des auditeurs expirés ne sort pas de la société de l''appelant',
    v_b IS NOT DISTINCT FROM 'active',
    format('auditeur de B=%s (attendu active)', COALESCE(v_b, 'NULL')));
  PERFORM _rec('T13', 'dans sa propre société, l''auditeur expiré est bien révoqué',
    v_a IS NOT DISTINCT FROM 'revoked',
    format('auditeur de A=%s (attendu revoked)', COALESCE(v_a, 'NULL')));
END $$;

-- ── T14/T15 : file de webhooks — reprise des envois interrompus ───────────
DO $$
DECLARE ta uuid; tb uuid; qa uuid; qb uuid; v_b text; v_a text; epa uuid; epb uuid;
BEGIN
  ta := _mk_tenant('ISO236A14'); tb := _mk_tenant('ISO236B14');
  PERFORM _fixture236(ta);
  PERFORM _fixture236(tb);
  INSERT INTO webhook_endpoints (tenant_id, name, url, secret)
  VALUES (ta, 'Point A', 'https://a14.izo.test/hook', 's') RETURNING id INTO epa;
  INSERT INTO webhook_endpoints (tenant_id, name, url, secret)
  VALUES (tb, 'Point B', 'https://b14.izo.test/hook', 's') RETURNING id INTO epb;
  INSERT INTO webhook_delivery_queue (tenant_id, endpoint_id, url, event, payload, status, attempts, last_attempt_at)
  VALUES (ta, epa, 'https://a14.izo.test/hook', 'invoice.created', '{}'::jsonb, 'sending', 1, now() - interval '1 hour')
  RETURNING id INTO qa;
  INSERT INTO webhook_delivery_queue (tenant_id, endpoint_id, url, event, payload, status, attempts, last_attempt_at)
  VALUES (tb, epb, 'https://b14.izo.test/hook', 'invoice.created', '{}'::jsonb, 'sending', 1, now() - interval '1 hour')
  RETURNING id INTO qb;

  PERFORM _as236(ta);
  PERFORM requeue_stale_webhook_deliveries();
  PERFORM _mesure236();

  SELECT status INTO v_b FROM webhook_delivery_queue WHERE id = qb;
  SELECT status INTO v_a FROM webhook_delivery_queue WHERE id = qa;
  PERFORM _rec('T14', 'la reprise des envois interrompus ne touche pas la file d''une autre société',
    v_b IS NOT DISTINCT FROM 'sending',
    format('envoi de B=%s (attendu sending)', COALESCE(v_b, 'NULL')));
  PERFORM _rec('T15', 'dans sa propre société, l''envoi abandonné est remis en file',
    v_a IS NOT DISTINCT FROM 'retry',
    format('envoi de A=%s (attendu retry)', COALESCE(v_a, 'NULL')));
END $$;

-- ── T16/T17 : purge des enregistrements d'idempotence ────────────────────
DO $$
DECLARE ta uuid; tb uuid; v_b int; v_a int;
BEGIN
  ta := _mk_tenant('ISO236A16'); tb := _mk_tenant('ISO236B16');
  PERFORM _fixture236(ta);
  PERFORM _fixture236(tb);
  INSERT INTO idempotency_records (tenant_id, idempotency_key, response, status, expires_at)
  VALUES (ta, 'iso-a16', '{}'::jsonb, 200, now() - interval '1 hour'),
         (tb, 'iso-b16', '{}'::jsonb, 200, now() - interval '1 hour');

  PERFORM _as236(ta);
  PERFORM cleanup_expired_idempotency();
  PERFORM _mesure236();

  SELECT count(*) INTO v_b FROM idempotency_records WHERE tenant_id = tb AND idempotency_key = 'iso-b16';
  SELECT count(*) INTO v_a FROM idempotency_records WHERE tenant_id = ta AND idempotency_key = 'iso-a16';
  PERFORM _rec('T16', 'la purge des enregistrements d''idempotence ne vide pas celle d''une autre société',
    v_b = 1,
    format('lignes restantes chez B=%s (attendu 1)', v_b));
  PERFORM _rec('T17', 'dans sa propre société, l''enregistrement expiré est purgé',
    v_a = 0,
    format('lignes restantes chez A=%s (attendu 0)', v_a));
END $$;

SELECT _audit_assert('236');
