-- ============================================================
-- 219_pos_vat_cash_tests.sql — R-13 : TVA par taux et écart de caisse
--
-- Avant la 219, la clôture créditait UNE ligne « 445710 » avec le total de TVA
-- de la session : une session mêlant 20 % et 10 % déclarait tout en 20 %, et la
-- CA3 était fausse. Et l'écart de comptage n'était jamais comptabilisé — un
-- manquant de 5 laissait la caisse fausse de 5.
--
-- G13a — deux taux (20 % et 10 %) → deux comptes de TVA, 445711 et 445712
-- G13b — comptage inférieur à l'attendu → D 658000 / C 530000
-- G13c — comptage supérieur                → D 530000 / C 758000
-- G13d — un ticket par CARTE ne compte pas dans le tiroir, et un taux sans
--        correspondance va au repli 445710 (pas au compte de 20 %)
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '219', false);
DELETE FROM _audit_results WHERE file = '219';

-- Société de caisse prête à clôturer : une caisse, deux moyens de paiement
-- (espèces → 530000, carte → 512000) et une session ouverte. Les tickets sont
-- sans article : le stock n'entre pas dans ce qui est vérifié ici.
CREATE OR REPLACE FUNCTION _pos219(p_name text, OUT t uuid, OUT sess uuid, OUT cash uuid, OUT card uuid)
LANGUAGE plpgsql AS $$
DECLARE term uuid;
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant(p_name);
  PERFORM ensure_standard_journals(t);
  PERFORM _as_user();
  INSERT INTO pos_terminals (tenant_id, name) VALUES (t, 'Caisse ' || p_name) RETURNING id INTO term;
  INSERT INTO pos_payment_methods (tenant_id, name, type, account_code)
    VALUES (t, 'Espèces', 'cash', '530000') RETURNING id INTO cash;
  INSERT INTO pos_payment_methods (tenant_id, name, type, account_code)
    VALUES (t, 'Carte', 'card', '512000') RETURNING id INTO card;
  INSERT INTO pos_sessions (tenant_id, terminal_id, user_email, opening_amount, status)
    VALUES (t, term, 'caisse@audit.test', 0, 'open') RETURNING id INTO sess;
END $$;

-- Un ticket d'une ligne à un taux donné, réglé par un moyen donné
CREATE OR REPLACE FUNCTION _ticket219(p_t uuid, p_sess uuid, p_num text, p_base numeric, p_rate numeric,
  p_method uuid, p_amount numeric)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE k uuid;
BEGIN
  INSERT INTO pos_tickets (tenant_id, number, session_id, terminal_id, subtotal, vat_total, total,
                           amount_paid, status)
  SELECT p_t, p_num, p_sess, ps.terminal_id, p_base, round(p_base * p_rate / 100, 2),
         p_base + round(p_base * p_rate / 100, 2), p_amount, 'completed'
  FROM pos_sessions ps WHERE ps.id = p_sess
  RETURNING id INTO k;
  INSERT INTO pos_ticket_lines (tenant_id, ticket_id, description, quantity, unit_price, vat_rate, line_total)
  VALUES (p_t, k, 'Article ' || p_rate || ' %', 1, p_base, p_rate, p_base);
  INSERT INTO pos_payments (tenant_id, ticket_id, payment_method_id, amount) VALUES (p_t, k, p_method, p_amount);
END $$;

-- Clôture la session à la date du dernier jour de l'exercice 2026
CREATE OR REPLACE FUNCTION _cloture219(p_sess uuid, p_compte numeric)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE pos_sessions SET status = 'closed', closing_amount = p_compte, closed_at = '2026-03-31T20:00:00Z'
  WHERE id = p_sess;
END $$;

-- Lignes de l'écriture de clôture d'une session
CREATE OR REPLACE FUNCTION _lignes219(p_t uuid)
RETURNS TABLE (statut text, d numeric, c numeric, equilibre numeric, c445711 numeric, c445712 numeric,
               c445710 numeric, d530 numeric, c530 numeric, d658 numeric, c758 numeric)
LANGUAGE sql AS $$
  SELECT max(je.status),
         COALESCE(sum(jl.debit), 0), COALESCE(sum(jl.credit), 0),
         COALESCE(sum(jl.debit - jl.credit), 0),
         COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '445711'), 0),
         COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '445712'), 0),
         COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '445710'), 0),
         COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '530000'), 0),
         COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '530000'), 0),
         COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '658000'), 0),
         COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '758000'), 0)
  FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
  WHERE je.tenant_id = p_t AND je.journal_code = 'POS';
$$;

-- G13a — deux taux dans la même session : deux comptes de TVA
DO $$
DECLARE t uuid; sess uuid; cash uuid; card uuid; r record;
BEGIN
  BEGIN
    SELECT * INTO t, sess, cash, card FROM _pos219('G13a');
    PERFORM _ticket219(t, sess, 'T1', 100, 20, cash, 120);
    PERFORM _ticket219(t, sess, 'T2', 100, 10, cash, 110);
    PERFORM _cloture219(sess, 230);
    SELECT * INTO r FROM _lignes219(t);
    PERFORM _rec('G13a', 'TVA 20 % → 445711 et 10 % → 445712 ; plus rien au compte unique 445710',
      r.statut = 'posted' AND r.c445711 = 20 AND r.c445712 = 10 AND r.c445710 = 0
        AND r.d530 = 230 AND r.equilibre = 0,
      format('statut=%s D530=%s TVA20=%s TVA10=%s repli=%s équilibre=%s',
             r.statut, r.d530, r.c445711, r.c445712, r.c445710, r.equilibre));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('G13a', 'TVA 20 % → 445711 et 10 % → 445712 ; plus rien au compte unique 445710', false, SQLERRM); END;
END $$;

-- G13b — manquant de 5 dans le tiroir : charge 658, contrepartie caisse
DO $$
DECLARE t uuid; sess uuid; cash uuid; card uuid; r record; s record;
BEGIN
  BEGIN
    SELECT * INTO t, sess, cash, card FROM _pos219('G13b');
    PERFORM _ticket219(t, sess, 'T1', 100, 20, cash, 120);
    PERFORM _ticket219(t, sess, 'T2', 100, 10, cash, 110);
    PERFORM _cloture219(sess, 225);   -- 230 attendus, 225 comptés
    SELECT * INTO r FROM _lignes219(t);
    SELECT expected_amount, difference INTO s FROM pos_sessions WHERE id = sess;
    PERFORM _rec('G13b', 'manquant de 5 : D 658000 / C caisse, session à 230 attendus et −5 d''écart',
      r.d658 = 5 AND r.c530 = 5 AND r.equilibre = 0
        AND s.expected_amount = 230 AND s.difference = -5,
      format('D658=%s C530=%s équilibre=%s attendu=%s écart=%s',
             r.d658, r.c530, r.equilibre, s.expected_amount, s.difference));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('G13b', 'manquant de 5 : D 658000 / C caisse, session à 230 attendus et −5 d''écart', false, SQLERRM); END;
END $$;

-- G13c — excédent de 3 : produit 758, contrepartie caisse
DO $$
DECLARE t uuid; sess uuid; cash uuid; card uuid; r record;
BEGIN
  BEGIN
    SELECT * INTO t, sess, cash, card FROM _pos219('G13c');
    PERFORM _ticket219(t, sess, 'T1', 100, 20, cash, 120);
    PERFORM _ticket219(t, sess, 'T2', 100, 10, cash, 110);
    PERFORM _cloture219(sess, 233);   -- 230 attendus, 233 comptés
    SELECT * INTO r FROM _lignes219(t);
    PERFORM _rec('G13c', 'excédent de 3 : D caisse / C 758000, écriture équilibrée',
      r.c758 = 3 AND r.d530 = 233 AND r.equilibre = 0 AND r.d658 = 0,
      format('C758=%s D530=%s équilibre=%s D658=%s', r.c758, r.d530, r.equilibre, r.d658));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('G13c', 'excédent de 3 : D caisse / C 758000, écriture équilibrée', false, SQLERRM); END;
END $$;

-- G13d — un règlement par CARTE ne compte pas dans le tiroir, et un taux sans
-- correspondance ne part PAS sur le compte de 20 %
DO $$
DECLARE t uuid; sess uuid; cash uuid; card uuid; r record; s record;
BEGIN
  BEGIN
    SELECT * INTO t, sess, cash, card FROM _pos219('G13d');
    PERFORM _ticket219(t, sess, 'T1', 100, 20, card, 120);    -- carte : hors tiroir
    PERFORM _ticket219(t, sess, 'T2', 100, 7.7, cash, 107.7);  -- taux sans correspondance
    PERFORM _cloture219(sess, 107.7);   -- seul l'espèces est attendu dans le tiroir
    SELECT * INTO r FROM _lignes219(t);
    SELECT expected_amount, difference INTO s FROM pos_sessions WHERE id = sess;
    PERFORM _rec('G13d', 'carte exclue de l''attendu (107,70 attendus, aucun écart) et taux 7,7 % au repli 445710',
      s.expected_amount = 107.7 AND s.difference = 0
        AND r.d658 = 0 AND r.c758 = 0
        AND r.c445710 = 7.7 AND r.c445711 = 20 AND r.c445712 = 0
        AND r.equilibre = 0,
      format('attendu=%s écart=%s repli=%s TVA20=%s TVA10=%s D658=%s C758=%s équilibre=%s',
             s.expected_amount, s.difference, r.c445710, r.c445711, r.c445712, r.d658, r.c758, r.equilibre));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('G13d', 'carte exclue de l''attendu (107,70 attendus, aucun écart) et taux 7,7 % au repli 445710', false, SQLERRM); END;
END $$;

DROP FUNCTION _pos219(text);
DROP FUNCTION _ticket219(uuid, uuid, text, numeric, numeric, uuid, numeric);
DROP FUNCTION _cloture219(uuid, numeric);
DROP FUNCTION _lignes219(uuid);

SELECT _audit_assert('219');