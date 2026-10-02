-- ============================================================
-- 432_chain_l3_releve_bancaire_tests.sql — L3 : LE RELEVÉ BANCAIRE MANUEL,
--   ses trois maillons — ce que la doctrine 320 change pour le troisième
--
-- Source : recomptage de la tâche 3.1 — lignes `post_bank_statement_line`,
-- `reconcile_bank_statement_line`, `unreconcile_bank_statement_line`.
--
--   T01  la comptabilisation d'une ligne de relevé produit l'écriture, le lien
--        `generated_entry`, la trace `applique` et l'événement ;
--   T02  le pointage manuel : lien `reconciled_with` vers l'ÉCRITURE (la ligne
--        est au payload) — c'est ce que le dé-lettrage rouvrira ;
--   T03  LE DÉ-LETTRAGE ROMPT LE LIEN (doctrine 320), il ne le réécrit pas, et
--        il n'écrit AUCUNE trace `applique` — un dé-lettrage qui produirait un
--        effet dirait le contraire de ce qu'il fait ;
--   T04  le dé-lettrage ferme AUSSI le lien du pointage manuel (`manually_
--        reconciled`), pas seulement celui de la comptabilisation ;
--   T05  les deux gestes sont DISTINCTS : l'automatique (316) et le manuel
--        (432) ne partagent pas de nom d'effet — les confondre empêcherait de
--        savoir qui a pointé ;
--   T06  le montant et le sens sont vérifiés par le corps : un pointage sur une
--        écriture du mauvais montant lève, et RIEN n'est lié ;
--   T07  STRUCTURE : les trois corps `_inner` ne sont pas exécutables par
--        `authenticated` ; les trois wrappers sont SECURITY DEFINER ; les deux
--        contrats existent et sont ACTIFS ; le dé-lettrage n'a PAS de contrat ;
--   T08  CLOISONNEMENT : la société voisine ne voit ni les liens ni les traces.
-- ============================================================
\ir ci/audit_helpers.sql
\ir ci/ledger_fixture.sql
SELECT set_config('audit.file', '432', false);
DELETE FROM _audit_results WHERE file = '432';

-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier (préfixé `_`)
-- ─────────────────────────────────────────────────────────────

-- Une société, une banque (avec son compte comptable), une ligne de relevé.
-- Le plan est semé et les comptes du cas sont posés par `_ledger_fixture`.
DROP FUNCTION IF EXISTS _l432_banque(text, text);
CREATE OR REPLACE FUNCTION _l432_banque(p_nom text, p_type text DEFAULT 'debit',
  OUT t uuid, OUT ba uuid, OUT acc text, OUT tx uuid, OUT usr uuid)
LANGUAGE plpgsql AS $fn$
DECLARE v_date date := DATE '2026-03-15';
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant(p_nom, false);
  usr := auth.uid();
  PERFORM _ledger_fixture(t, ARRAY['512100','627000','768000','411000','401000']);

  -- ⚠️ PAS D'EXERCICE CRÉÉ ICI : `_ledger_fixture` en pose un (le « TEST »
  -- de l'exercice 2026). Le créer une seconde fois fait échouer la contrainte
  -- de non-chevauchement — mesuré. Le décor s'appuie donc sur celui du
  -- fixture, comme les suites compta le font.

  INSERT INTO journals (tenant_id, code, name, type, status, next_number)
  VALUES (t, 'BQ', 'Banque', 'bank', 'active', 1)
  ON CONFLICT DO NOTHING;

  -- ⚠️ LE SCHÉMA DE `bank_accounts` N'A NI `iban` NI `opening_balance` — mesuré
  -- sur la base neuve : les colonnes sont `account_number`, `sort_code`,
  -- `balance`, `account_code` (le compte COMPTABLE, indispensable au maillon :
  -- il refuse une banque sans compte comptable), `journal_code`.
  INSERT INTO bank_accounts (tenant_id, name, account_number, sort_code, balance,
                             currency, account_code, journal_code, type)
  VALUES (t, 'Compte ' || p_nom, '00000012345', '123', 0,
          'EUR', '512100', 'BQ', 'chequing')
  RETURNING id INTO ba;
  acc := '512100';

  -- `bank_accounts_type_check` n'admet que ('chequing','savings',
  -- 'credit_card','cash','loan','other') — mesuré sur la base neuve.
  -- La ligne de relevé : `kind = 'statement'` (c'est la seule que les trois
  -- maillons acceptent), non pointée, d'un montant strictement positif.
  INSERT INTO bank_transactions (tenant_id, bank_account_id, date, description,
                                 amount, type, kind, matched, reconciled)
  VALUES (t, ba, v_date, 'Frais bancaires ' || p_nom, 42.00, p_type, 'statement', false, false)
  RETURNING id INTO tx;
END $fn$;

-- Crée une écriture VALIDÉE au compte de banque, du bon montant, pour éprouver
-- le pointage manuel. Renvoie l'id de l'ÉCRITURE et celui de sa LIGNE bancaire.
DROP FUNCTION IF EXISTS _l432_ecriture(uuid, numeric, text);
CREATE OR REPLACE FUNCTION _l432_ecriture(p_t uuid, p_montant numeric, p_sens text DEFAULT 'debit',
  OUT je uuid, OUT jl uuid)
LANGUAGE plpgsql AS $fn$
BEGIN
  je := _entry(p_t, 'ECH-' || upper(left(gen_random_uuid()::text, 8)), DATE '2026-03-14',
    CASE WHEN p_sens = 'debit'
      THEN jsonb_build_array(
             jsonb_build_object('a','627000','d',p_montant,'c',0),
             jsonb_build_object('a','512100','d',0,'c',p_montant))
      ELSE jsonb_build_array(
             jsonb_build_object('a','512100','d',p_montant,'c',0),
             jsonb_build_object('a','768000','d',0,'c',p_montant))
    END,
    true, 'BQ');
  SELECT id INTO jl FROM journal_lines
   WHERE journal_id = je AND account_code = '512100' LIMIT 1;
END $fn$;

DROP FUNCTION IF EXISTS _l432_liens(uuid, text);
CREATE OR REPLACE FUNCTION _l432_liens(p_tx uuid, p_effet text)
RETURNS TABLE (lien uuid, aval uuid, etat text, ouvert boolean, payload jsonb)
LANGUAGE sql STABLE AS $fn$
  SELECT l.id, l.aval_id, l.etat, (l.etat = 'actif'), l.payload
  FROM document_links l
  WHERE l.tenant_id = current_tenant_id() AND l.amont_type = 'bank_transactions'
    AND l.amont_id = p_tx AND l.effet = p_effet
$fn$;

DROP FUNCTION IF EXISTS _l432_traces(uuid, text);
CREATE OR REPLACE FUNCTION _l432_traces(p_tx uuid, p_effet text)
RETURNS TABLE (resultat text, lignes integer)
LANGUAGE sql STABLE AS $fn$
  SELECT c.resultat, c.lignes_ecrites
  FROM chain_traces c
  WHERE c.tenant_id = current_tenant_id() AND c.amont_type = 'bank_transactions'
    AND c.amont_id = p_tx AND c.effet = p_effet
$fn$;

-- Retourne au contexte d'une société (identité + société) : `current_tenant_id()`
-- exige que `auth.uid()` soit membre de la société visée — mesuré en 3.2 (T09).
DROP FUNCTION IF EXISTS _l432_revenir(uuid, uuid);
CREATE OR REPLACE FUNCTION _l432_revenir(p_t uuid, p_usr uuid)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_usr::text, false);
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', p_usr, 'role', 'authenticated')::text, false);
  PERFORM set_config('app.active_tenant_id', p_t::text, false);
END $fn$;

-- ─────────────────────────────────────────────────────────────
-- T01 — la comptabilisation produit l'écriture, le lien et la trace
-- ─────────────────────────────────────────────────────────────
DO $t01$
DECLARE t uuid; ba uuid; acc text; tx uuid; usr uuid; v_je uuid; v_ref text;
BEGIN
  SELECT * FROM _l432_banque('t01') INTO t, ba, acc, tx, usr;
  PERFORM post_bank_statement_line(tx, NULL, 'Frais bancaires');

  v_je := (SELECT aval FROM _l432_liens(tx, 'treasury.statement_line.posted'));
  SELECT reference INTO v_ref FROM journal_entries WHERE id = v_je;

  PERFORM _rec('T01', 'la comptabilisation lie la ligne de relevé à son écriture, et trace `applique`',
    (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.posted')) = 1
    AND (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.posted') WHERE ouvert) = 1
    -- l'aval est bien une ÉCRITURE validée, née de CE relevé
    AND (SELECT status FROM journal_entries WHERE id = v_je) = 'posted'
    AND v_ref LIKE 'COMPTA-BQ-%'
    AND (SELECT count(*) FROM _l432_traces(tx, 'treasury.statement_line.posted')
           WHERE resultat = 'applique' AND lignes = 1) = 1
    AND (SELECT count(*) FROM domain_events
           WHERE tenant_id = t AND aggregate_id = tx
             AND event_name = 'bank_transactions.posted') = 1,
    format('liens=%s aval=%s ref=%s traces=%s',
           (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.posted')),
           v_je, v_ref,
           (SELECT count(*) FROM _l432_traces(tx, 'treasury.statement_line.posted'))));
END $t01$;

-- ─────────────────────────────────────────────────────────────
-- T02 — le pointage manuel lie la ligne à l'ÉCRITURE existante
-- ─────────────────────────────────────────────────────────────
DO $t02$
DECLARE t uuid; ba uuid; acc text; tx uuid; usr uuid; je uuid; jl uuid; v_aval uuid;
BEGIN
  SELECT * FROM _l432_banque('t02') INTO t, ba, acc, tx, usr;
  SELECT * FROM _l432_ecriture(t, 42.00, 'debit') INTO je, jl;

  PERFORM reconcile_bank_statement_line(tx, jl);

  SELECT aval INTO v_aval FROM _l432_liens(tx, 'treasury.statement_line.manually_reconciled');

  PERFORM _rec('T02', 'le pointage manuel lie la ligne à l''ÉCRITURE (la ligne est au payload)',
    (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.manually_reconciled')) = 1
    AND v_aval = je
    AND (SELECT (payload->>'journal_line_id')::uuid
           FROM _l432_liens(tx, 'treasury.statement_line.manually_reconciled')) = jl
    AND (SELECT count(*) FROM _l432_traces(tx, 'treasury.statement_line.manually_reconciled')
           WHERE resultat = 'applique') = 1,
    format('liens=%s aval=%s attendu=%s',
           (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.manually_reconciled')),
           v_aval, je));
END $t02$;
-- ─────────────────────────────────────────────────────────────
-- T03 — LE DÉ-LETTRAGE ROMPT LE LIEN, ET N'ÉCRIT AUCUNE TRACE `applique`
--    C'est la doctrine 320 appliquée au troisième maillon : il ne produit pas
--    d'effet, il en retire un. Un dé-lettrage qui écrirait `applique` dirait
--    « on a comptabilisé » là où on vient de défaire un pointage.
-- ─────────────────────────────────────────────────────────────
DO $t03$
DECLARE t uuid; ba uuid; acc text; tx uuid; usr uuid;
BEGIN
  SELECT * FROM _l432_banque('t03') INTO t, ba, acc, tx, usr;
  PERFORM post_bank_statement_line(tx, NULL, 'Frais bancaires');

  -- Le lien est actif avant : sinon le test ne prouverait pas la fermeture.
  IF (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.posted') WHERE ouvert) <> 1 THEN
    RAISE EXCEPTION 'Décor T03 invalide : le lien de comptabilisation n''est pas actif avant le dé-lettrage';
  END IF;

  PERFORM unreconcile_bank_statement_line(tx);

  PERFORM _rec('T03', 'le dé-lettrage ROMPT le lien (doctrine 320) et n''écrit AUCUNE trace `applique`',
    (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.posted')) = 1
    AND (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.posted') WHERE ouvert) = 0
    AND (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.posted')
           WHERE etat = 'rompu') = 1
    -- la SEULE trace `applique` reste celle de la comptabilisation (T01)
    AND (SELECT count(*) FROM _l432_traces(tx, 'treasury.statement_line.posted')
           WHERE resultat = 'applique') = 1,
    format('liens=%s actifs=%s rompus=%s',
           (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.posted')),
           (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.posted') WHERE ouvert),
           (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.posted') WHERE etat = 'rompu')));
END $t03$;

-- ─────────────────────────────────────────────────────────────
-- T04 — le dé-lettrage ferme AUSSI le lien du pointage MANUEL
--    Un dé-lettrage ne sait pas quel chemin a produit le pointage : il défait
--    le pointage, donc tout lien qui le décrivait devient faux. Ce test
--    vérifie que les DEUX chemins sont fermés — un wrapper qui n'en fermerait
--    qu'un laisserait un lien actif sur un pointage qui n'existe plus.
-- ─────────────────────────────────────────────────────────────
DO $t04$
DECLARE t uuid; ba uuid; acc text; tx uuid; usr uuid; je uuid; jl uuid;
BEGIN
  SELECT * FROM _l432_banque('t04') INTO t, ba, acc, tx, usr;
  SELECT * FROM _l432_ecriture(t, 42.00, 'debit') INTO je, jl;
  PERFORM reconcile_bank_statement_line(tx, jl);
  PERFORM unreconcile_bank_statement_line(tx);

  PERFORM _rec('T04', 'le dé-lettrage ferme le lien du pointage MANUEL, comme celui de la comptabilisation',
    (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.manually_reconciled')) = 1
    AND (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.manually_reconciled')
           WHERE ouvert) = 0
    AND (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.manually_reconciled')
           WHERE etat = 'rompu') = 1,
    format('liens=%s actifs=%s rompus=%s',
           (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.manually_reconciled')),
           (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.manually_reconciled') WHERE ouvert),
           (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.manually_reconciled') WHERE etat = 'rompu')));
END $t04$;

-- ─────────────────────────────────────────────────────────────
-- T05 — le pointage MANUEL et l'AUTOMATIQUE ne partagent pas de nom d'effet
--    La 316 trace déjà le rapprochement automatique sous
--    `treasury.bank_transaction.reconciled`. Si le manuel réemployait ce nom,
--    les deux gestes seraient indistinguables dans le registre : on ne
--    saurait plus QUI a pointé. Ce test verrouille la distinction.
-- ─────────────────────────────────────────────────────────────
DO $t05$
BEGIN
  PERFORM _rec('T05', 'le pointage manuel a son PROPRE effet, distinct de celui du rapprochement automatique',
    EXISTS (SELECT 1 FROM document_effects
             WHERE effet = 'treasury.statement_line.manually_reconciled'
               AND document_type = 'bank_transactions' AND evenement = 'reconciled' AND actif)
    AND EXISTS (SELECT 1 FROM document_effects
                 WHERE effet = 'treasury.bank_transaction.reconciled' AND actif),
    format('effets_reconciled=%s',
           (SELECT string_agg(effet, ', ' ORDER BY effet) FROM document_effects
             WHERE document_type = 'bank_transactions' AND evenement = 'reconciled')));
END $t05$;

-- ─────────────────────────────────────────────────────────────

-- T06 — un pointage sur le MAUVAIS montant lève, et RIEN n'est lié
--    Le corps vérifie montant et sens avant de pointer. C'est une garde
--    métier préexistante, mais la chaîne doit la voir passer : si le maillon
--    posait un lien AVANT la vérification, un pointage faux laisserait un lien
--    actif alors que l'appel a levé.
-- ─────────────────────────────────────────────────────────────
DO $t06$
DECLARE t uuid; ba uuid; acc text; tx uuid; usr uuid; je uuid; jl uuid;
        v_leve boolean := false;
BEGIN
  SELECT * FROM _l432_banque('t06') INTO t, ba, acc, tx, usr;
  -- L'écriture vaut 99, la ligne de relevé 42 : le pointage doit être refusé.
  SELECT * FROM _l432_ecriture(t, 99.00, 'debit') INTO je, jl;

  BEGIN
    PERFORM reconcile_bank_statement_line(tx, jl);
  EXCEPTION WHEN OTHERS THEN
    v_leve := true;
  END;

  PERFORM _rec('T06', 'un pointage sur un montant différent lève, et NE LIAIT RIEN (le lien ne précède pas la garde)',
    v_leve
    AND (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.manually_reconciled')) = 0
    AND (SELECT count(*) FROM _l432_traces(tx, 'treasury.statement_line.manually_reconciled')) = 0,
    format('levée=%s liens=%s traces=%s', v_leve,
           (SELECT count(*) FROM _l432_liens(tx, 'treasury.statement_line.manually_reconciled')),
           (SELECT count(*) FROM _l432_traces(tx, 'treasury.statement_line.manually_reconciled'))));
END $t06$;

-- ─────────────────────────────────────────────────────────────
-- T07 — STRUCTURE : trois corps `_inner` non exposés, trois wrappers
--    SECURITY DEFINER, DEUX contrats actifs — et PAS de contrat pour le
--    dé-lettrage, qui ne produit aucun effet (il en retire un).
-- ─────────────────────────────────────────────────────────────
DO $t07$
DECLARE v_ok boolean; v_detail text;
BEGIN
  v_ok := (SELECT count(*) FROM pg_proc p JOIN pg_namespace n
             ON n.oid=p.pronamespace AND n.nspname='public'
            WHERE p.proname IN ('post_bank_statement_line_inner',
                                'reconcile_bank_statement_line_inner',
                                'unreconcile_bank_statement_line_inner')) = 3
     AND NOT has_function_privilege('authenticated','public.post_bank_statement_line_inner(uuid,text,text)','EXECUTE')
     AND NOT has_function_privilege('authenticated','public.reconcile_bank_statement_line_inner(uuid,uuid)','EXECUTE')
     AND NOT has_function_privilege('authenticated','public.unreconcile_bank_statement_line_inner(uuid)','EXECUTE')
     AND (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
           WHERE p.proname IN ('post_bank_statement_line','reconcile_bank_statement_line','unreconcile_bank_statement_line')
             AND p.prosecdef) = 3
     -- le dé-lettrage utilise `chain_lien_rompre`, PAS `chain_avant`
     AND (SELECT prosrc ~ 'chain_lien_rompre' AND prosrc !~ '\mchain_avant'
            FROM pg_proc WHERE proname='unreconcile_bank_statement_line')
     AND (SELECT count(*) FROM document_effects
           WHERE effet IN ('treasury.statement_line.posted','treasury.statement_line.manually_reconciled')
             AND actif) = 2;

  v_detail := format('corps=%s wrappers_secdef=%s contrats=%s',
    (SELECT count(*) FROM pg_proc WHERE proname LIKE '%bank\_statement\_line\_inner'
       OR proname = 'unreconcile_bank_statement_line_inner'),
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
      WHERE p.proname IN ('post_bank_statement_line','reconcile_bank_statement_line','unreconcile_bank_statement_line')
        AND p.prosecdef),
    (SELECT count(*) FROM document_effects
      WHERE effet IN ('treasury.statement_line.posted','treasury.statement_line.manually_reconciled') AND actif));

  PERFORM _rec('T07', 'trois corps `_inner` non exposés, trois wrappers SECURITY DEFINER, deux contrats actifs, et le dé-lettrage ferme sans `chain_avant`',
    v_ok, v_detail);
END $t07$;

-- ─────────────────────────────────────────────────────────────
-- T08 — CLOISONNEMENT : la société voisine ne voit rien du relevé de A
-- ─────────────────────────────────────────────────────────────
DO $t08$
DECLARE ta uuid; baa uuid; acca text; txa uuid; ua uuid;
        tb uuid; bab uuid; accb text; txb uuid; ub uuid;
        v_liens_b integer; v_traces_b integer;
BEGIN
  SELECT * FROM _l432_banque('t08a') INTO ta, baa, acca, txa, ua;
  PERFORM post_bank_statement_line(txa, NULL, 'Opération A');

  SELECT * FROM _l432_banque('t08b') INTO tb, bab, accb, txb, ub;

  SELECT count(*) INTO v_liens_b FROM document_links
   WHERE tenant_id = tb AND amont_type = 'bank_transactions' AND amont_id = txa;
  SELECT count(*) INTO v_traces_b FROM chain_traces
   WHERE tenant_id = tb AND amont_type = 'bank_transactions' AND amont_id = txa;

  -- retour chez A : identité ET société (mesuré en 3.2, T09)
  PERFORM _l432_revenir(ta, ua);

  PERFORM _rec('T08', 'la société voisine ne voit NI lien NI trace du relevé de A — et A voit les siens',
    v_liens_b = 0 AND v_traces_b = 0
    AND (SELECT count(*) FROM _l432_liens(txa, 'treasury.statement_line.posted') WHERE ouvert) = 1,
    format('liens_vus_par_B=%s traces_vues_par_B=%s', v_liens_b, v_traces_b));
END $t08$;


-- ─────────────────────────────────────────────────────────────
-- Verdict de la suite — `_audit_assert` REFUSE un fichier sans verdict.
-- ─────────────────────────────────────────────────────────────
SELECT _audit_assert('432');
