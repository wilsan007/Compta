-- ============================================================
-- 250_pos_nf525_immutability_tests.sql — POS-01, POS-02, POS-03, POS-04
--
-- Audit des modules hors comptabilité (23/09), § Caisse, mesuré le 24/09 en
-- rejouant `doc/audit/scenarios/POS_inalterabilite_nf525.sql` sur base neuve :
--
--   A1 écriture de clôture : créée — 531000 D=120 | 707000 C=100 | 445711 C=20
--   A2 sortie de stock : 1 mouvement, stock article = 99
--   B1 ⚠️ ticket ramené de 120 € à 12 € SANS REFUS ; hachage inchangé
--   B2 ⚠️ 1 ligne de ticket supprimée sans refus
--   B3 journal NF-525 : 3 événements, aucun ne mentionne la modification
--
--   POS-01  `pos_tickets` porte une garde en suppression et un hachage chaîné
--           à l'insertion, mais AUCUN déclencheur en modification : le montant
--           d'un ticket signé se réécrit, et comme l'empreinte n'est pas
--           recalculée, la chaîne « valide » le ticket falsifié. C'est la
--           dissimulation de recettes que la NF-525 existe pour empêcher.
--   POS-02  `pos_ticket_lines` n'a que `set_tenant_id` : ses lignes se
--           suppriment et se modifient librement.
--   POS-03  Aucun index unique sur (société, caisse, numéro) et le numéro est
--           calculé par MAX+1 sans verrou (mesuré : 0 verrou advisory pris) :
--           deux encaissements simultanés prennent le même numéro et la
--           chaîne fourche.
--   POS-04  `created_at`, fourni par le client, entre dans le hachage : un
--           ticket antidaté produit une empreinte cohérente — et un ticket
--           dont le client a omis `tenant_id` reçoit un hachage calculé sur
--           NULL, donc une empreinte que `verify_pos_ticket_chain` déclare
--           invalide (0 ticket valide sur 1).
--   Et le statut n'a AUCUNE contrainte `CHECK` : un ticket dont le statut
--   n'est pas exactement 'completed' sort de l'écriture de clôture en silence.
--
-- Ce fichier est l'acceptation de la migration 250. Mesuré AVANT elle, sur
-- base neuve (221 migrations) : 11 scénarios, 0 vert — T01 (réécriture
-- acceptée), T02/T03 (ligne modifiée, ligne supprimée), T04 (`void_pos_ticket`
-- n'existe pas), T05 (aucun verrou), T06 (aucune unicité), T07 (ticket daté
-- 2020 conservé), T08 (statut inconnu accepté), T09 (clôture sans effet),
-- T10 (empreinte invalide), T11 (reprise absente). T04 mesure la sortie
-- honnête : sans elle, la garde serait contournée ailleurs dans le produit.
-- ============================================================
\ir ci/audit_helpers.sql
\ir ci/ledger_fixture.sql
SELECT set_config('audit.file', '250', false);
DELETE FROM _audit_results WHERE file = '250';

-- Une caisse utilisable : société comptablement complète (journaux, comptes de
-- la clôture), un terminal, une session ouverte, un article, un moyen de
-- paiement.
CREATE OR REPLACE FUNCTION _mk_caisse250(p_nom text,
  OUT t uuid, OUT term uuid, OUT sess uuid, OUT prod uuid, OUT pm uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);   -- l'exercice vient de _ledger_fixture (un seul)
  PERFORM _ledger_fixture(t, ARRAY['531000','707000','445710','445711','758000','658000']);
  INSERT INTO pos_terminals (tenant_id, name) VALUES (t, 'Caisse ' || p_nom) RETURNING id INTO term;
  INSERT INTO pos_sessions (tenant_id, terminal_id, user_email, opening_amount, status)
    VALUES (t, term, 'caissier@audit.test', 100, 'open') RETURNING id INTO sess;
  INSERT INTO products (tenant_id, name, sku, type, sale_price, cost_price, stock_quantity)
    VALUES (t, 'Article ' || p_nom, 'SKU-' || p_nom, 'stock', 120, 50, 100) RETURNING id INTO prod;
  INSERT INTO pos_payment_methods (tenant_id, name, type, account_code, is_active)
    VALUES (t, 'Espèces', 'cash', '531000', true) RETURNING id INTO pm;
END $$;

-- Un ticket encaissé : en-tête + une ligne + un paiement, comme l'écran.
CREATE OR REPLACE FUNCTION _tk250(p_t uuid, p_sess uuid, p_prod uuid, p_pm uuid,
  p_num text, p_ht numeric DEFAULT 100)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE k uuid; v_vat numeric := round(p_ht * 20 / 100, 2);
BEGIN
  INSERT INTO pos_tickets (tenant_id, number, session_id, terminal_id, date, subtotal, vat_total,
                           total, payment_method, amount_paid, status)
  SELECT p_t, p_num, ps.id, ps.terminal_id, CURRENT_DATE, p_ht, v_vat, p_ht + v_vat, 'cash',
         p_ht + v_vat, 'completed'
  FROM pos_sessions ps WHERE ps.id = p_sess AND ps.tenant_id = p_t
  RETURNING id INTO k;
  INSERT INTO pos_ticket_lines (tenant_id, ticket_id, product_id, description, quantity,
                                unit_price, vat_rate, line_total)
  VALUES (p_t, k, p_prod, 'Article caisse', 1, p_ht, 20, p_ht);
  INSERT INTO pos_payments (tenant_id, ticket_id, payment_method_id, amount)
  VALUES (p_t, k, p_pm, p_ht + v_vat);
  RETURN k;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T01 — POS-01 : le montant d'un ticket signé ne se réécrit pas
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; tk uuid; state text; err text := '—'; n int;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_caisse250('POS250T1')) x;
  tk := _tk250(v.t, v.sess, v.prod, v.pm, 'TK-T01');

  PERFORM _as_user();
  BEGIN
    UPDATE pos_tickets SET total = 12, subtotal = 10, vat_total = 2, amount_paid = 12 WHERE id = tk;
  EXCEPTION WHEN others THEN state := SQLSTATE; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM pos_tickets WHERE id = tk AND total = 120 AND subtotal = 100;
  PERFORM _rec('T01', 'un ticket signé ne se réécrit pas (120 € → 12 € refusé)',
    state = '42501' AND n = 1,
    format('SQLSTATE=%s, ticket intact=%s (1 attendu) | %s', COALESCE(state, 'aucune erreur'), n, left(err, 90)));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — POS-02 : une ligne de ticket ne se modifie pas
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; tk uuid; state text; err text := '—'; n int;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_caisse250('POS250T2')) x;
  tk := _tk250(v.t, v.sess, v.prod, v.pm, 'TK-T02');

  PERFORM _as_user();
  BEGIN
    UPDATE pos_ticket_lines SET line_total = 12, unit_price = 12 WHERE ticket_id = tk;
  EXCEPTION WHEN others THEN state := SQLSTATE; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM pos_ticket_lines WHERE ticket_id = tk AND line_total = 100 AND unit_price = 100;
  PERFORM _rec('T02', 'une ligne de ticket signé ne se modifie pas',
    state = '42501' AND n = 1,
    format('SQLSTATE=%s, ligne intacte=%s (1 attendue) | %s', COALESCE(state, 'aucune erreur'), n, left(err, 90)));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T03 — POS-02 : une ligne de ticket ne se supprime pas
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; tk uuid; state text; err text := '—'; n int;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_caisse250('POS250T3')) x;
  tk := _tk250(v.t, v.sess, v.prod, v.pm, 'TK-T03');

  PERFORM _as_user();
  BEGIN
    DELETE FROM pos_ticket_lines WHERE ticket_id = tk;
  EXCEPTION WHEN others THEN state := SQLSTATE; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM pos_ticket_lines WHERE ticket_id = tk;
  PERFORM _rec('T03', 'une ligne de ticket signé ne se supprime pas',
    state = '42501' AND n = 1,
    format('SQLSTATE=%s, lignes restantes=%s (1 attendue) | %s', COALESCE(state, 'aucune erreur'), n, left(err, 90)));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T04 — POS-01 : la sortie honnête existe — annuler AVANT la clôture
--       (statut, drapeau, motif, événement NF-525, montants intacts)
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; tk uuid; err text := '—'; n int; ev1 int; ev2 int; s2 text;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_caisse250('POS250T4')) x;
  tk := _tk250(v.t, v.sess, v.prod, v.pm, 'TK-T04');

  PERFORM _as_user();
  BEGIN
    PERFORM void_pos_ticket(tk, 'Erreur de caisse : client parti');
  EXCEPTION WHEN undefined_function THEN err := 'void_pos_ticket() n''existe pas — aucun chemin d''annulation';
  END;
  PERFORM set_config('role', 'postgres', true);
  -- `void_reason` et `voided_at` naissent avec la 250 : avant elle, la requête
  -- échoue, et c'est la mesure (« la trace de l'annulation n'existe pas »).
  BEGIN
    EXECUTE $q$SELECT count(*) FROM pos_tickets
                 WHERE id = $1 AND status = 'cancelled' AND is_voided
                   AND void_reason LIKE 'Erreur de caisse%' AND voided_at IS NOT NULL
                   AND total = 120 AND subtotal = 100$q$ INTO n USING tk;
  EXCEPTION WHEN undefined_column THEN n := 0; err := 'les colonnes de traçabilité de l''annulation n''existent pas';
  END;
  SELECT count(*) INTO ev1 FROM nf525_event_log
  WHERE tenant_id = v.t AND entity_id = tk AND event_type = 'pos_ticket_voided';

  PERFORM _as_user();
  BEGIN
    PERFORM void_pos_ticket(tk, 'deuxième fois');
  EXCEPTION WHEN others THEN s2 := SQLSTATE; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO ev2 FROM nf525_event_log
  WHERE tenant_id = v.t AND entity_id = tk AND event_type = 'pos_ticket_voided';

  PERFORM _rec('T04', 'annuler un ticket se fait par void_pos_ticket : tracé, une seule fois',
    n = 1 AND ev1 = 1 AND ev2 = 1 AND s2 = '42501',
    format('ticket annulé et intact=%s (1 attendu), événements NF-525=%s puis %s (1/1 attendus), 2ᵉ annulation SQLSTATE=%s | %s',
           n, ev1, ev2, COALESCE(s2, 'aucune erreur'), left(err, 70)));
END $$;


-- ═════════════════════════════════════════════════════════════
-- T05 — POS-03 : numérotation continue par caisse, prise sous verrou
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; t1 uuid; t2 uuid; s1 int; s2 int; v_key bigint; v_low bigint; v_locks int;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_caisse250('POS250T5')) x;
  t1 := _tk250(v.t, v.sess, v.prod, v.pm, 'TK-T05A');
  -- Le verrou est transactionnel : il est encore tenu par cette transaction.
  v_key := hashtext('pos_ticket:' || v.t::text || ':' || v.term::text);
  v_low := (v_key & 4294967295);
  SELECT count(*) INTO v_locks FROM pg_locks
  WHERE locktype = 'advisory' AND granted AND pid = pg_backend_pid()
    AND objsubid = 1 AND objid::bigint = v_low;
  t2 := _tk250(v.t, v.sess, v.prod, v.pm, 'TK-T05B');
  SELECT sequential_number INTO s1 FROM pos_tickets WHERE id = t1;
  SELECT sequential_number INTO s2 FROM pos_tickets WHERE id = t2;
  PERFORM _rec('T05', 'numérotation continue par caisse (1 puis 2), prise sous verrou',
    s1 = 1 AND s2 = 2 AND v_locks >= 1,
    format('numéros = %s puis %s (1/2 attendus), verrou advisory du terminal tenu = %s (≥ 1 attendu)',
           s1, s2, v_locks));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T06 — POS-03 : un même numéro ne peut pas exister deux fois
--       sur une même caisse (la base le refuse)
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; tk uuid; state text; err text := '—'; v_con int;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_caisse250('POS250T6')) x;
  tk := _tk250(v.t, v.sess, v.prod, v.pm, 'TK-T06');
  SELECT count(*) INTO v_con FROM pg_constraint c
  WHERE c.conrelid = 'public.pos_tickets'::regclass AND c.contype = 'u'
    AND pg_get_constraintdef(c.oid) LIKE '%terminal_id%';
  -- État hostile fabriqué : la numérotation automatique est neutralisée pour
  -- forcer le doublon qu'une base d'avant la 250 peut déjà porter.
  ALTER TABLE pos_tickets DISABLE TRIGGER assign_pos_ticket_hash_trigger;
  BEGIN
    INSERT INTO pos_tickets (tenant_id, number, session_id, terminal_id, date, subtotal, vat_total,
                             total, amount_paid, status, sequential_number)
    SELECT v.t, 'TK-T06-BIS', ps.id, ps.terminal_id, CURRENT_DATE, 100, 20, 120, 120, 'completed', 1
    FROM pos_sessions ps WHERE ps.id = v.sess;
  EXCEPTION WHEN others THEN state := SQLSTATE; err := SQLERRM;
  END;
  ALTER TABLE pos_tickets ENABLE TRIGGER assign_pos_ticket_hash_trigger;
  PERFORM _rec('T06', 'unicité (société, caisse, numéro) tenue par la base',
    v_con = 1 AND state = '23505',
    format('contraintes d''unicité sur la caisse = %s (1 attendue), doublon SQLSTATE = %s | %s',
           v_con, COALESCE(state, 'aucune erreur'), left(err, 80)));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T07 — POS-04 : `created_at` est un fait serveur, et l'empreinte
--       du ticket reste vérifiable
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; tk uuid; v_created timestamptz; v_ok int;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_caisse250('POS250T7')) x;
  INSERT INTO pos_tickets (tenant_id, number, session_id, terminal_id, date, created_at,
                           subtotal, vat_total, total, amount_paid, status)
  SELECT v.t, 'TK-T07', ps.id, ps.terminal_id, '2020-01-01T08:00:00Z', '2020-01-01T08:00:00Z',
         100, 20, 120, 120, 'completed'
  FROM pos_sessions ps WHERE ps.id = v.sess RETURNING id INTO tk;
  SELECT created_at INTO v_created FROM pos_tickets WHERE id = tk;
  SELECT count(*) INTO v_ok FROM verify_pos_ticket_chain(v.term, CURRENT_DATE) WHERE is_valid;
  PERFORM _rec('T07', 'la date du ticket est posée par le serveur : un ticket antidaté est impossible',
    v_created::date = CURRENT_DATE AND v_ok >= 1,
    format('created_at = %s (aujourd''hui attendu), tickets dont l''empreinte se vérifie = %s (≥ 1 attendu)',
           v_created::date, v_ok));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T08 — POS-01, la cause silencieuse : le statut est contraint
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; tk uuid; s1 text; s2 text; err text := '—';
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_caisse250('POS250T8')) x;
  tk := _tk250(v.t, v.sess, v.prod, v.pm, 'TK-T08');
  BEGIN
    INSERT INTO pos_tickets (tenant_id, number, session_id, terminal_id, date, subtotal, vat_total,
                             total, amount_paid, status)
    SELECT v.t, 'TK-T08-BIS', ps.id, ps.terminal_id, CURRENT_DATE, 100, 20, 120, 120, 'en_cours'
    FROM pos_sessions ps WHERE ps.id = v.sess;
  EXCEPTION WHEN others THEN s1 := SQLSTATE; err := SQLERRM;
  END;
  PERFORM _as_user();
  BEGIN
    UPDATE pos_tickets SET status = 'en_cours' WHERE id = tk;
  EXCEPTION WHEN others THEN s2 := SQLSTATE; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('T08', 'un statut hors (completed, cancelled, refunded) est refusé : la vente ne sort plus de la clôture en silence',
    s1 = '23514' AND s2 IN ('23514', '42501'),
    format('insertion d''un statut inconnu SQLSTATE = %s, modification SQLSTATE = %s | %s',
           COALESCE(s1, 'aucune erreur'), COALESCE(s2, 'aucune erreur'), left(err, 80)));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T09 — la clôture ferme le ticket : l'avoir devient le seul chemin
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; tk uuid; s1 text; s2 text; err text := '—'; n int;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_caisse250('POS250T9')) x;
  tk := _tk250(v.t, v.sess, v.prod, v.pm, 'TK-T09');
  UPDATE pos_sessions SET status = 'closed', closing_amount = 120, closed_at = now() WHERE id = v.sess;

  PERFORM _as_user();
  BEGIN
    PERFORM void_pos_ticket(tk, 'annulation tardive');
  EXCEPTION WHEN others THEN s1 := SQLSTATE; err := SQLERRM;
  END;
  BEGIN
    INSERT INTO pos_ticket_lines (tenant_id, ticket_id, description, quantity, unit_price, vat_rate, line_total)
    VALUES (v.t, tk, 'Ligne ajoutée après clôture', 1, 10, 20, 10);
  EXCEPTION WHEN others THEN s2 := SQLSTATE; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM pos_tickets WHERE id = tk AND status = 'completed';
  PERFORM _rec('T09', 'après la clôture de caisse, le ticket ne bouge plus : un avoir, pas une réécriture',
    s1 = '42501' AND s2 = '42501' AND n = 1,
    format('annulation SQLSTATE = %s, ajout de ligne SQLSTATE = %s, ticket toujours au statut vente = %s | %s',
           COALESCE(s1, 'aucune erreur'), COALESCE(s2, 'aucune erreur'), n, left(err, 70)));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T10 — la société vient du contexte : un ticket sans société est
--       du chiffre d'affaires que personne ne voit
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; tk uuid; v_tid uuid; v_seq int; v_ok int;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_caisse250('POS250T10')) x;
  PERFORM _as_user();
  -- `tenant_id` omis : c'est ce que fait l'écran quand le contexte suffit.
  INSERT INTO pos_tickets (number, session_id, terminal_id, date, subtotal, vat_total, total,
                           amount_paid, status)
  SELECT 'TK-T10', ps.id, ps.terminal_id, CURRENT_DATE, 100, 20, 120, 120, 'completed'
  FROM pos_sessions ps WHERE ps.id = v.sess RETURNING id INTO tk;
  PERFORM set_config('role', 'postgres', true);
  SELECT tenant_id, sequential_number INTO v_tid, v_seq FROM pos_tickets WHERE id = tk;
  SELECT count(*) INTO v_ok FROM verify_pos_ticket_chain(v.term, CURRENT_DATE) WHERE is_valid;
  PERFORM _rec('T10', 'un ticket sans société reçoit celle du contexte, et sa chaîne d''empreintes se vérifie',
    v_tid = v.t AND v_seq = 1 AND v_ok = 1,
    format('société du ticket = %s (celle du contexte attendue), numéro = %s, empreintes valides = %s (1 attendu)',
           COALESCE(v_tid::text, 'NULL'), v_seq, v_ok));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T11 — la reprise des numéros en doublon répare sans casser la chaîne
--       (c'est elle que la migration 250 exécute avant de poser l'unicité)
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; a uuid; b uuid; n int; v_tot int; v_distinct int; v_bad int; err text := '—';
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_caisse250('POS250T11')) x;
  a := _tk250(v.t, v.sess, v.prod, v.pm, 'TK-T11A');
  b := _tk250(v.t, v.sess, v.prod, v.pm, 'TK-T11B');
  -- État hostile fabriqué : l'unicité retirée, la numérotation neutralisée, un doublon forcé.
  ALTER TABLE pos_tickets DROP CONSTRAINT IF EXISTS pos_tickets_terminal_seq_unique;
  ALTER TABLE pos_tickets DISABLE TRIGGER assign_pos_ticket_hash_trigger;
  -- La garde d'immutabilité naît avec la 250 : l'état hostile fabriqué est
  -- celui d'une base d'avant, où elle n'existait pas.
  ALTER TABLE pos_tickets DISABLE TRIGGER prevent_pos_ticket_modification_trg;
  UPDATE pos_tickets SET sequential_number = 1, ticket_hash = 'orphelin', previous_hash = NULL WHERE id = b;
  ALTER TABLE pos_tickets ENABLE TRIGGER prevent_pos_ticket_modification_trg;
  ALTER TABLE pos_tickets ENABLE TRIGGER assign_pos_ticket_hash_trigger;
  BEGIN
    n := pos_tickets_renumber_duplicates();
  EXCEPTION WHEN undefined_function THEN n := 0; err := 'pos_tickets_renumber_duplicates() n''existe pas';
  END;
  SELECT count(*), count(DISTINCT sequential_number) INTO v_tot, v_distinct
  FROM pos_tickets WHERE tenant_id = v.t AND terminal_id = v.term;
  SELECT count(*) INTO v_bad FROM verify_pos_ticket_chain(v.term, CURRENT_DATE) WHERE NOT is_valid;
  BEGIN
    ALTER TABLE pos_tickets ADD CONSTRAINT pos_tickets_terminal_seq_unique
      UNIQUE (tenant_id, terminal_id, sequential_number);
  EXCEPTION WHEN others THEN err := 'contrainte non reposée : ' || left(SQLERRM, 60);
  END;
  PERFORM _rec('T11', 'des numéros en doublon sont réparés sans casser la chaîne d''empreintes',
    n >= 1 AND v_tot = 2 AND v_distinct = 2 AND v_bad = 0,
    format('lignes renumérotées = %s (≥ 1 attendue), tickets = %s, numéros distincts = %s, empreintes invalides = %s | %s',
           n, v_tot, v_distinct, v_bad, left(err, 60)));
  PERFORM a;   -- la première ligne n'est pas touchée : `v_bad = 0` le mesure
END $$;

DROP FUNCTION _tk250(uuid, uuid, uuid, uuid, text, numeric);
DROP FUNCTION _mk_caisse250(text);

SELECT _audit_assert('250');

