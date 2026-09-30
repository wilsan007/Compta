-- ============================================================
-- 310_chain_l1_maillons_tests.sql — L1 (tranche 1) : ce que le traçage des
--   maillons de la chaîne ventes → trésorerie → comptabilité garantit
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md, lot L1 (§3.6,
-- §4.1, §4.3) ; référentiel, parties A.2 (les 19 artères) et A.3 (les 16
-- maillons les plus fragiles : idempotence 9/62, trace 7/62).
--
--   T01  facture validée → UN lien invoices → journal_entries, UN événement, et
--        UNE SEULE trace `applique` (depuis L7 le contrat est déclaré ; avant la
--        313, la même exécution traçait `tolere` PUIS `applique`) ;
--   T02  le fait générateur ne se rejoue pas : une mise à jour qui ne change pas
--        l'état ne crée ni second lien ni seconde trace ;
--   T03  le rejeu EXPLICITE de `chain_avant` sur le même effet rend false et
--        trace `ignore` — l'idempotence du traçage est structurelle ;
--   T04  avoir client validé → lien credit_notes → journal_entries ;
--   T05  un avoir resté BROUILLON ne trace rien (le fait générateur est l'état) ;
--   T06  un rejeu du maillon ne double ni le lien ni l'événement (count = 1) ;
--   T07  décaissement fournisseur → lien supplier_payments → journal_entries ;
--   T08  encaissement client → lien customer_payments → journal_entries ;
--   T09  compte de trésorerie → DEUX liens (journals ET chart_accounts) et un
--        événement : le maillon noté 1/7 entre enfin dans la chaîne ;
--   T10  l'ordre des déclencheurs est prouvé : le lien existe dans la MÊME
--        transaction que l'instruction métier, donc le compagnon `zz_` s'exécute
--        bien après le déclencheur métier ;
--   T11  la mesure existe : `chain_traces` porte durée, lignes écrites, résultat —
--        et, l'effet étant ÉTEINT pour la société, le message du contrat manquant ;
--   T12  le drapeau `actif` du contrat change le verdict : éteint pour la société
--        → `chain_autorise` faux et la trace dit « sans contrat » ; rallumé →
--        vrai, et la trace ne le dit plus ;
--   T13  en mode `refuse`, un effet ÉTEINT (donc non autorisé) bloque l'opération
--        métier, avec un message qui nomme document, date, règle et module ;
--   T14  la société voisine ne voit ni le lien ni l'événement (RLS) ;
--   T15  les maillons compagnons ne sont pas des points d'entrée (aucun EXECUTE).
--
-- Ce fichier s'exécute comme les autres suites d'audit : contexte de société
-- posé, puis rôle `authenticated` — un utilisateur réel, sous RLS.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '310', false);
DELETE FROM _audit_results WHERE file = '310';

-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier (préfixé `_`, hors contrôle des droits)
-- ─────────────────────────────────────────────────────────────

-- Une facture cliente prête à valider — avec sa ligne (la validation refuse une
-- facture sans ligne, mesuré au premier passage de cette suite).
CREATE OR REPLACE FUNCTION _l1_facture(p_t uuid, p_num text, p_cust uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE i uuid;
BEGIN
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date,
                        status, subtotal, vat_total, total, amount_paid, amount_due)
  VALUES (p_t, p_num, p_cust, 'Client L1', '2026-03-01', '2026-03-31',
          'draft', 100, 20, 120, 0, 120)
  RETURNING id INTO i;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price,
                             vat_rate, total, vat_code, vat_amount)
  VALUES (p_t, i, 'Prestation L1', 1, 100, 20, 100, 'FR20', 20);
  RETURN i;
END $$;

-- Le lien attendu, lu comme l'écran le lira (RLS de la société).
CREATE OR REPLACE FUNCTION _l1_lien(p_t uuid, p_amont_type text, p_amont_id uuid, p_effet text)
RETURNS TABLE(aval_type text, aval_id uuid, link_type text, payload jsonb, created_at timestamptz)
LANGUAGE sql AS $$
  SELECT dl.aval_type, dl.aval_id, dl.link_type, dl.payload, dl.created_at
  FROM document_links dl
  WHERE dl.tenant_id = p_t AND dl.amont_type = p_amont_type
    AND dl.amont_id = p_amont_id AND dl.effet = p_effet
$$;

CREATE OR REPLACE FUNCTION _l1_liens(p_t uuid, p_amont_type text, p_amont_id uuid)
RETURNS integer LANGUAGE sql AS $$
  SELECT count(*)::int FROM document_links dl
  WHERE dl.tenant_id = p_t AND dl.amont_type = p_amont_type AND dl.amont_id = p_amont_id
$$;

CREATE OR REPLACE FUNCTION _l1_evenements(p_t uuid, p_nom text, p_agregat uuid)
RETURNS integer LANGUAGE sql AS $$
  SELECT count(*)::int FROM domain_events de
  WHERE de.tenant_id = p_t AND de.event_name = p_nom AND de.aggregate_id = p_agregat
$$;

CREATE OR REPLACE FUNCTION _l1_traces(p_t uuid, p_effet text)
RETURNS TABLE(resultat text, duree_ms integer, lignes_ecrites integer)
LANGUAGE sql AS $$
  SELECT ct.resultat, ct.duree_ms, ct.lignes_ecrites FROM chain_traces ct
  WHERE ct.tenant_id = p_t AND ct.effet = p_effet ORDER BY ct.id
$$;

-- ═════════════════════════════════════════════════════════════
-- T01 — Facture validée : le lien, l'événement, la trace
--
-- ⚠️ Verdict attendu CHANGÉ le 30/09/2026 par le lot **L7** (migration 313) :
-- avant les contrats, l'exécution écrivait DEUX traces — `tolere` (« contrat non
-- déclaré », mode observe) puis `applique`. Depuis que le contrat standard est
-- déclaré, il n'en reste qu'UNE : `applique`. L'assertion est donc passée de
-- `n_tolere = 1` à `n_tolere = 0` — ce n'est pas un test affaibli, c'est un test
-- qui mesure un comportement qui a changé, et le détail le publie (`tolere=0`).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L1A'); c uuid; inv uuid; v record; n_lien int; n_evt int;
        n_tolere int; n_applique int;
BEGIN
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES (t, 'Client L1', 'L1001') RETURNING id INTO c;
  inv := _l1_facture(t, 'F-L1-1', c);
  PERFORM _as_user();
  BEGIN
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
    SELECT * INTO v FROM _l1_lien(t, 'invoices', inv, 'sale.invoice.generated_entry');
    n_lien := _l1_liens(t, 'invoices', inv);
    n_evt  := _l1_evenements(t, 'invoices.validated', inv);
    SELECT count(*) FILTER (WHERE resultat = 'tolere'),
           count(*) FILTER (WHERE resultat = 'applique')
      INTO n_tolere, n_applique FROM _l1_traces(t, 'sale.invoice.generated_entry');
    PERFORM _rec('T01',
      'facture validée → un lien invoices → journal_entries, un événement, et UNE SEULE trace `applique` (contrat déclaré par la 313)',
      n_lien = 1 AND n_evt = 1 AND v.aval_type = 'journal_entries'
        AND v.link_type = 'generated_entry' AND v.aval_id IS NOT NULL
        AND n_tolere = 0 AND n_applique = 1,
      format('liens=%s aval=%s type=%s payload=%s événements=%s tolere=%s applique=%s',
             n_lien, v.aval_type, v.link_type, v.payload, n_evt, n_tolere, n_applique));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T01',
      'facture validée → un lien invoices → journal_entries, un événement, et UNE SEULE trace `applique` (contrat déclaré par la 313)',
      false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 et T03 — l'idempotence du traçage
--   T02 : une mise à jour qui NE change PAS l'état ne trace rien de plus (le
--         fait générateur est l'état, pas l'écriture).
--   T03 : le rejeu explicite de l'entrée du maillon (`chain_avant`, appelée ici
--         par le propriétaire, puisque le socle n'est pas une API) rend false et
--         trace `ignore` — l'index unique du socle fait le travail.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L1B'); c uuid; inv uuid; n_traces int; n_liens int;
        e uuid; v_deja boolean;
BEGIN
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES (t, 'Client L1', 'L1002') RETURNING id INTO c;
  inv := _l1_facture(t, 'F-L1-2', c);
  PERFORM _as_user();
  BEGIN
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
    SELECT count(*) INTO n_traces FROM _l1_traces(t, 'sale.invoice.generated_entry');
    -- Un changement qui ne touche pas l'état : les notes de la facture.
    UPDATE invoices SET notes = 'passage sans changement d''état' WHERE id = inv;
    SELECT count(*) INTO n_liens FROM _l1_liens(t, 'invoices', inv);
    PERFORM _rec('T02',
      'une mise à jour qui ne change pas l''état ne crée ni second lien ni seconde trace',
      n_liens = 1 AND (SELECT count(*) FROM _l1_traces(t, 'sale.invoice.generated_entry')) = n_traces,
      format('liens=%s traces avant=%s après=%s',
             n_liens, n_traces, (SELECT count(*) FROM _l1_traces(t, 'sale.invoice.generated_entry'))));

    -- T03 : le rejeu explicite de l'entrée du maillon, sous la société de la facture.
    -- Le socle n'est pas une API : `chain_avant` n'est appelable que par le
    -- propriétaire. La session reste donc sous ce rôle à la fin du bloc — chaque
    -- bloc `DO` de cette suite s'ouvre de toute façon sous ce rôle.
    EXECUTE 'RESET ROLE';
    SELECT i.transferred_entry_id INTO e FROM invoices i WHERE i.id = inv;
    v_deja := chain_avant(t, 'invoices', 'validated', 'sale.invoice.generated_entry',
                          'invoices', inv, NULL, NULL);
    SELECT count(*) INTO n_traces FROM _l1_traces(t, 'sale.invoice.generated_entry')
     WHERE resultat = 'ignore';
    PERFORM _rec('T03',
      'le rejeu explicite rend false et trace `ignore` : l''idempotence du traçage est structurelle',
      v_deja = false AND n_traces >= 1,
      format('chain_avant rendu=%s, traces `ignore`=%s, aval=%s', v_deja, n_traces, e));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T02', 'une mise à jour qui ne change pas l''état ne crée ni second lien ni seconde trace', false, SQLERRM);
    PERFORM _rec('T03', 'le rejeu explicite rend false et trace `ignore` : l''idempotence du traçage est structurelle', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T04 à T06 — l'avoir client : le fait générateur, le brouillon muet, le rejeu
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L1C'); c uuid; cn uuid; cn2 uuid; v record; n int; n_evt int;
        n_liens int; n_evt2 int; ok_refus boolean := false;
BEGIN
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES (t, 'Client AV L1', 'L1003') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    -- T04 : un avoir validé (draft → applied) produit son écriture, donc son lien.
    INSERT INTO credit_notes (tenant_id, number, customer_id, customer_name, date, status,
                              subtotal, vat_total, total)
    VALUES (t, 'AV-L1-1', c, 'Client AV L1', '2026-03-02', 'draft', 100, 20, 120)
    RETURNING id INTO cn;
    UPDATE credit_notes SET status = 'applied' WHERE id = cn;
    SELECT * INTO v FROM _l1_lien(t, 'credit_notes', cn, 'sale.credit_note.generated_entry');
    n_evt := _l1_evenements(t, 'credit_notes.validated', cn);
    PERFORM _rec('T04',
      'avoir client appliqué → un lien credit_notes → journal_entries et un événement credit_notes.validated',
      v.aval_type = 'journal_entries' AND v.aval_id IS NOT NULL AND n_evt = 1,
      format('aval=%s type=%s événements=%s payload=%s', v.aval_type, v.link_type, n_evt, v.payload));

    -- T05 : un avoir resté BROUILLON ne trace rien — le fait générateur est l'état.
    INSERT INTO credit_notes (tenant_id, number, customer_id, customer_name, date, status,
                              subtotal, vat_total, total)
    VALUES (t, 'AV-L1-2', c, 'Client AV L1', '2026-03-03', 'draft', 50, 10, 60)
    RETURNING id INTO cn2;
    n := _l1_liens(t, 'credit_notes', cn2);
    PERFORM _rec('T05', 'un avoir resté brouillon ne trace ni lien ni événement',
      n = 0 AND _l1_evenements(t, 'credit_notes.validated', cn2) = 0,
      format('liens=%s événements=%s', n, _l1_evenements(t, 'credit_notes.validated', cn2)));

    -- T06 : une seconde transition du même avoir ne double ni le lien ni l'événement.
    BEGIN
      UPDATE credit_notes SET status = 'draft' WHERE id = cn;
      UPDATE credit_notes SET status = 'applied' WHERE id = cn;
    EXCEPTION WHEN OTHERS THEN
      ok_refus := true;   -- le maillon refuse le retour en arrière : c'est une réponse acceptable
    END;
    n_liens := _l1_liens(t, 'credit_notes', cn);
    n_evt2  := _l1_evenements(t, 'credit_notes.validated', cn);
    PERFORM _rec('T06',
      'un second passage dans l''état ne double ni le lien ni l''événement (ou le retour à brouillon est refusé)',
      n_liens = 1 AND n_evt2 = 1,
      format('liens=%s événements=%s retour à brouillon refusé=%s', n_liens, n_evt2, ok_refus));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T04', 'avoir client appliqué → un lien credit_notes → journal_entries et un événement credit_notes.validated', false, SQLERRM);
    PERFORM _rec('T05', 'un avoir resté brouillon ne trace ni lien ni événement', false, SQLERRM);
    PERFORM _rec('T06', 'un second passage dans l''état ne double ni le lien ni l''événement (ou le retour à brouillon est refusé)', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T07 et T08 — la trésorerie : les deux sens du règlement
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L1D'); c uuid; s uuid; inv uuid; v record; n_evt int; n int;
        sp uuid; cp uuid;
BEGIN
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES (t, 'Client TR L1', 'L1004') RETURNING id INTO c;
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Fournisseur TR L1', 'F1004') RETURNING id INTO s;
  inv := _l1_facture(t, 'F-L1-TR', c);
  PERFORM _as_user();
  BEGIN
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;

    -- T07 : décaissement fournisseur (déclencheur AFTER INSERT).
    INSERT INTO supplier_payments (tenant_id, number, supplier_id, payment_date, amount, method)
    VALUES (t, 'DP-L1-1', s, '2026-03-10', 240, 'transfer') RETURNING id INTO sp;
    SELECT * INTO v FROM _l1_lien(t, 'supplier_payments', sp, 'purchase.payment.generated_entry');
    n_evt := _l1_evenements(t, 'supplier_payments.recorded', sp);
    PERFORM _rec('T07',
      'décaissement fournisseur → un lien supplier_payments → journal_entries et un événement supplier_payments.recorded',
      v.aval_type = 'journal_entries' AND v.aval_id IS NOT NULL AND n_evt = 1,
      format('aval=%s type=%s événements=%s payload=%s', v.aval_type, v.link_type, n_evt, v.payload));

    -- T08 : encaissement client.
    INSERT INTO customer_payments (tenant_id, number, customer_id, invoice_id, payment_date, amount, method)
    VALUES (t, 'RG-L1-1', c, inv, '2026-03-05', 120, 'transfer') RETURNING id INTO cp;
    SELECT * INTO v FROM _l1_lien(t, 'customer_payments', cp, 'sale.payment.generated_entry');
    n_evt := _l1_evenements(t, 'customer_payments.recorded', cp);
    PERFORM _rec('T08',
      'encaissement client → un lien customer_payments → journal_entries et un événement customer_payments.recorded',
      v.aval_type = 'journal_entries' AND v.aval_id IS NOT NULL AND n_evt = 1,
      format('aval=%s type=%s événements=%s payload=%s', v.aval_type, v.link_type, n_evt, v.payload));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T07', 'décaissement fournisseur → un lien supplier_payments → journal_entries et un événement supplier_payments.recorded', false, SQLERRM);
    PERFORM _rec('T08', 'encaissement client → un lien customer_payments → journal_entries et un événement customer_payments.recorded', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T09 — le compte de trésorerie entre dans la chaîne (le maillon noté 1/7)
--   Un déclencheur, DEUX effets : le journal (rapprochement bancaire) et le
--   compte comptable (grand livre de la banque). C'est exactement ce que le
--   socle permet et qu'une colonne `reference_*` ne savait pas dire.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L1E'); b uuid; n_liens int; n_journal int; n_compte int; n_evt int;
BEGIN
  PERFORM _as_user();
  BEGIN
    INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Banque L1', 'chequing')
    RETURNING id INTO b;
    n_liens := _l1_liens(t, 'bank_accounts', b);
    SELECT count(*) INTO n_journal FROM _l1_lien(t, 'bank_accounts', b, 'treasury.bank_account.journal');
    SELECT count(*) INTO n_compte  FROM _l1_lien(t, 'bank_accounts', b, 'treasury.bank_account.account');
    n_evt := _l1_evenements(t, 'bank_accounts.ledger_attached', b);
    PERFORM _rec('T09',
      'compte de trésorerie → deux liens (journals ET chart_accounts) et un événement bank_accounts.ledger_attached',
      n_liens = 2 AND n_journal = 1 AND n_compte = 1 AND n_evt = 1,
      format('liens=%s journal=%s compte=%s événements=%s', n_liens, n_journal, n_compte, n_evt));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T09', 'compte de trésorerie → deux liens (journals ET chart_accounts) et un événement bank_accounts.ledger_attached', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T10 — l'ordre des déclencheurs, prouvé par la structure
--   PostgreSQL exécute les déclencheurs d'un même événement par ordre
--   alphabétique. Le compagnon doit donc porter un nom PLUS GRAND que tous les
--   déclencheurs métier du même événement : sinon il s'exécuterait avant qu'ils
--   n'aient produit l'aval, et il ne tracerait rien (en silence).
--   T01, T04, T07, T08 et T09 prouvent le résultat ; T10 prouve la cause.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v_compagnons int; v_avant int; v_grand int; v_apres int; v_tranche1 int;
BEGIN
  SELECT count(*) INTO v_compagnons FROM pg_trigger WHERE tgname LIKE 'zz_l1_%' AND NOT tgisinternal;
  -- Les cinq compagnons de CETTE tranche, nommés : le compte global grandit avec
  -- les tranches suivantes (la 311 en ajoute trois), il n'est donc pas figé ici.
  SELECT count(*) INTO v_tranche1 FROM pg_trigger
  WHERE NOT tgisinternal AND tgname IN ('zz_l1_invoice_entry', 'zz_l1_credit_note_entry',
        'zz_l1_supplier_payment_entry', 'zz_l1_customer_payment_entry', 'zz_l1_bank_account_ledger');
  -- Tous les compagnons sont des déclencheurs APRÈS (bits : 2 = BEFORE, 1 = ROW).
  SELECT count(*) INTO v_apres FROM pg_trigger
  WHERE tgname LIKE 'zz_l1_%' AND NOT tgisinternal AND (tgtype & 2) = 0 AND (tgtype & 1) = 1;
  -- Chacun a AU MOINS un frère métier de MÊME événement dont le nom trie AVANT
  -- lui (une table peut en porter plusieurs : le compte est un minimum, pas une
  -- égalité).
  SELECT count(*) INTO v_avant FROM pg_trigger z
   WHERE z.tgname LIKE 'zz_l1_%' AND NOT z.tgisinternal
     AND EXISTS (SELECT 1 FROM pg_trigger m
                 WHERE m.tgrelid = z.tgrelid AND m.tgtype = z.tgtype
                   AND NOT m.tgisinternal AND m.tgname < z.tgname);
  -- Et aucun frère MÉTIER de même événement ne trie APRÈS lui (sinon l'ordre
  -- serait inversé par un nom futur).
  -- ⚠️ Adapté le 30/09/2026 par la tranche 5 (migration 316) : la mesure portait
  -- sur TOUT déclencheur de nom plus grand, compagnons L1 compris. Or une table
  -- peut légitimement en porter plusieurs — `bank_transactions` porte
  -- `zz_l1_bank_reconciliation` (tranche 1) puis `zz_l1_statement_line_matched`
  -- (tranche 5), `pay_runs` porte les rappels puis les acomptes — et leur ordre
  -- relatif est SANS EFFET : chacun ne lit que les marqueurs de son propre
  -- maillon. La propriété qui compte, et qui reste exigée, est « après tout
  -- déclencheur MÉTIER » : c'est elle qui garantit que le compagnon voit l'aval
  -- (trouvé rouge sur base neuve par la suite 316, qui exige la même chose).
  -- À noter : l'étiquette de ce scénario disait déjà « frère métier » — c'est la
  -- MESURE qui était plus large que son étiquette, et qui laissait donc passer une
  -- contrainte que personne n'avait décidée.
  SELECT count(*) INTO v_grand FROM pg_trigger z
   WHERE z.tgname LIKE 'zz_l1_%' AND NOT z.tgisinternal
     AND EXISTS (SELECT 1 FROM pg_trigger m
                 WHERE m.tgrelid = z.tgrelid AND m.tgtype = z.tgtype
                   AND NOT m.tgisinternal AND m.tgname > z.tgname
                   AND m.tgname NOT LIKE 'zz_l1\_%');

  PERFORM _rec('T10',
    'les cinq compagnons de la tranche 1 sont des déclencheurs APRÈS, aucun frère métier de même événement ne trie après eux',
    v_tranche1 = 5 AND v_compagnons >= 5 AND v_apres = v_compagnons AND v_avant >= 5 AND v_grand = 0,
    format('compagnons=%s (tranche 1 nommés=%s) après=%s frères avant=%s frères après=%s',
           v_compagnons, v_tranche1, v_apres, v_avant, v_grand));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T11 — la mesure : durée, lignes écrites, et le message quand le contrat manque
--
-- ⚠️ Adapté le 30/09/2026 par le lot **L7** (migration 313) : depuis que le
-- contrat standard est déclaré, l'absence de contrat ne se montre plus avec un
-- effet jamais déclaré — elle se montre en **éteignant** l'effet pour une
-- société (`actif = false`), qui est le geste offert à un client qui refuse un
-- chaînage. Le message nominatif du maillon reste mesuré mot pour mot.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L1F'); c uuid; inv uuid; inv2 uuid; v record;
        n_complet int; n_msg int;
BEGIN
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES (t, 'Client MS L1', 'L1005') RETURNING id INTO c;
  inv := _l1_facture(t, 'F-L1-MS', c);
  inv2 := _l1_facture(t, 'F-L1-MS2', c);
  PERFORM _as_user();
  BEGIN
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
    SELECT * INTO v FROM _l1_traces(t, 'sale.invoice.generated_entry') LIMIT 1;
    SELECT count(*) INTO n_complet FROM chain_traces ct
    WHERE ct.tenant_id = t AND ct.effet = 'sale.invoice.generated_entry'
      AND ct.resultat = 'applique' AND ct.duree_ms IS NOT NULL AND ct.lignes_ecrites >= 1;

    -- L'effet est éteint pour cette société : le contrat manque à nouveau.
    EXECUTE 'RESET ROLE';
    INSERT INTO document_effects (tenant_id, document_type, evenement, effet, actif)
    VALUES (t, 'invoices', 'validated', 'sale.invoice.generated_entry', false)
    ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
                 document_type, evenement, effet)
    DO UPDATE SET actif = false;

    PERFORM _as_user();
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv2;
    SELECT count(*) INTO n_msg FROM chain_traces ct
    WHERE ct.tenant_id = t AND ct.effet = 'sale.invoice.generated_entry'
      AND ct.amont_id = inv2 AND ct.resultat = 'tolere'
      AND ct.message LIKE '%sale.invoice.generated_entry%'
      AND ct.message LIKE '%module ventes%';
    PERFORM _rec('T11',
      'chaque exécution est mesurée (durée, lignes écrites) et, effet éteint pour la société, le contrat manquant est dit dans un message nominatif',
      n_complet = 1 AND n_msg = 1,
      format('traces complètes=%s messages de contrat=%s première=%s', n_complet, n_msg, v));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T11', 'chaque exécution est mesurée (durée, lignes écrites) et, effet éteint pour la société, le contrat manquant est dit dans un message nominatif', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T12 — le drapeau `actif` du contrat change le verdict (L7 s'y branche)
--
-- ⚠️ Réécrit le 30/09/2026 par le lot **L7** (migration 313). Avant les contrats,
-- le cas « sans contrat » se montrait avec l'effet standard jamais déclaré ; il
-- est maintenant déclaré, donc le cas se montre en **ÉTEIGNANT** le contrat pour
-- la société — ce qui est aussi le geste offert à un client, et la raison d'être
-- du drapeau `actif` (le seul de `document_effects` que `chain_autorise` lit).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L1G'); c uuid; inv1 uuid; inv2 uuid;
        n_tolere1 int; n_tolere2 int; n_applique2 int; v_autorise1 boolean; v_autorise2 boolean;
BEGIN
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES (t, 'Client CT L1', 'L1006') RETURNING id INTO c;
  inv1 := _l1_facture(t, 'F-L1-CT1', c);
  inv2 := _l1_facture(t, 'F-L1-CT2', c);

  -- Le contrat de CETTE société, ÉTEINT : une ligne de société l'emporte sur le
  -- contrat standard (mesuré par la suite 252, T06), et `chain_autorise` doit
  -- rendre faux. Elle est portée par la société du scénario, et non par le
  -- contrat standard : une suite se rejoue, et aucun autre scénario ne doit
  -- dépendre de ce que celui-ci laisse derrière lui.
  EXECUTE 'RESET ROLE';
  INSERT INTO document_effects (tenant_id, document_type, evenement, effet, actif)
  VALUES (t, 'invoices', 'validated', 'sale.invoice.generated_entry', false)
  ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
               document_type, evenement, effet)
  DO UPDATE SET actif = false;
  v_autorise1 := chain_autorise(t, 'invoices', 'validated', 'sale.invoice.generated_entry');

  -- Contrat éteint, mode `observe` (le défaut) : l'effet est produit quand même,
  -- et la trace dit que le contrat manque.
  PERFORM _as_user();
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv1;
  SELECT count(*) INTO n_tolere1 FROM chain_traces
  WHERE tenant_id = t AND effet = 'sale.invoice.generated_entry'
    AND amont_id = inv1 AND resultat = 'tolere';

  -- On RALLUME le contrat pour la société : `chain_autorise` rend vrai, et la
  -- trace ne dit plus « sans contrat ».
  EXECUTE 'RESET ROLE';
  UPDATE document_effects SET actif = true
  WHERE tenant_id = t AND document_type = 'invoices' AND evenement = 'validated'
    AND effet = 'sale.invoice.generated_entry';
  v_autorise2 := chain_autorise(t, 'invoices', 'validated', 'sale.invoice.generated_entry');

  PERFORM _as_user();
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv2;
  SELECT count(*) INTO n_tolere2 FROM chain_traces
  WHERE tenant_id = t AND effet = 'sale.invoice.generated_entry'
    AND amont_id = inv2 AND resultat = 'tolere';
  SELECT count(*) INTO n_applique2 FROM chain_traces
  WHERE tenant_id = t AND effet = 'sale.invoice.generated_entry'
    AND amont_id = inv2 AND resultat = 'applique';
  PERFORM _rec('T12',
    'contrat éteint pour la société : `chain_autorise` faux et la trace dit « sans contrat » ; rallumé : vrai, et la trace ne le dit plus',
    NOT v_autorise1 AND n_tolere1 = 1 AND v_autorise2 AND n_tolere2 = 0 AND n_applique2 = 1,
    format('éteint autorise=%s tolere=%s | rallumé autorise=%s tolere=%s applique=%s',
           v_autorise1, n_tolere1, v_autorise2, n_tolere2, n_applique2));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T12', 'contrat éteint pour la société : `chain_autorise` faux et la trace dit « sans contrat » ; rallumé : vrai, et la trace ne le dit plus', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T13 — mode `refuse` : un effet non déclaré BLOQUE l'opération métier
--   C'est la promesse du §3.6 : le drapeau est par société, et une société qui
--   demande `refuse` obtient un refus nominatif — document, date, règle, module —
--   au lieu d'un chaînage muet. Le document ne doit pas être validé.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L1H'); c uuid; inv uuid; msg text := 'ACCEPTÉ'; statut text;
        n_lien int; n_avant int;
BEGIN
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES (t, 'Client RF L1', 'L1007') RETURNING id INTO c;
  inv := _l1_facture(t, 'F-L1-RF', c);
  SELECT count(*) INTO n_avant FROM document_links WHERE amont_id = inv;
  -- La société ÉTEINT l'effet pour elle (une ligne de société l'emporte sur le
  -- contrat standard, `actif = false` — c'est le cas mesuré par la suite 252, T06),
  -- puis demande le mode `refuse`. Le refus ne dépend donc d'aucune déclaration
  -- laissée par un autre scénario.
  INSERT INTO document_effects (tenant_id, document_type, evenement, effet, actif)
  VALUES (t, 'invoices', 'validated', 'sale.invoice.generated_entry', false)
  ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
               document_type, evenement, effet)
  DO UPDATE SET actif = false;
  INSERT INTO chain_settings (tenant_id, enforcement) VALUES (t, 'refuse')
  ON CONFLICT (tenant_id) DO UPDATE SET enforcement = 'refuse';
  PERFORM _as_user();
  BEGIN
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  EXCEPTION WHEN OTHERS THEN
    msg := SQLERRM;
  END;
  SELECT validation_status INTO statut FROM invoices WHERE id = inv;
  n_lien := _l1_liens(t, 'invoices', inv);
  PERFORM _rec('T13',
    'mode refuse : l''effet non déclaré bloque l''opération, le message nomme la règle, le module et la date, et rien n''est tracé',
    msg <> 'ACCEPTÉ' AND msg LIKE '%sale.invoice.generated_entry%'
      AND msg LIKE '%module ventes%' AND msg LIKE '%01/03/2026%' AND msg LIKE '%Facture%'
      AND statut IS DISTINCT FROM 'validated' AND n_lien = 0 AND n_avant = 0,
    format('message=« %s » statut=%s liens=%s', left(msg, 220), statut, n_lien));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T14 — la société voisine ne voit rien
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid := _mk_tenant('L1I'); tb uuid; c uuid; inv uuid; n_liens int; n_evt int;
BEGIN
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES (ta, 'Client VO L1', 'L1008') RETURNING id INTO c;
  inv := _l1_facture(ta, 'F-L1-VO', c);
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  -- La société voisine devient le contexte de session.
  tb := _mk_tenant('L1J');
  PERFORM _as_user();
  BEGIN
    SELECT count(*) INTO n_liens FROM document_links WHERE amont_id = inv;
    SELECT count(*) INTO n_evt FROM domain_events WHERE aggregate_id = inv;
    PERFORM _rec('T14',
      'la société voisine ne voit ni le lien ni l''événement de la première société (RLS)',
      n_liens = 0 AND n_evt = 0,
      format('contexte=%s liens visibles=%s événements visibles=%s', tb, n_liens, n_evt));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T14', 'la société voisine ne voit ni le lien ni l''événement de la première société (RLS)', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T15 — les maillons compagnons ne sont pas des points d'entrée
--   Mesuré : `check_anon_grants` refuse toute fonction de `public` exécutable
--   par `anon` ou PUBLIC. Ces cinq fonctions doivent donc être révoquées — et
--   c'est sans effet sur les déclencheurs (mesuré : un déclencheur se déclenche
--   même quand le rôle appelant n'a pas EXECUTE sur lui).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v_n int; v_mauvais int; v_detail text; v_tranche1 int;
BEGIN
  SELECT count(*) INTO v_n
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname LIKE 'chain_l1_%';

  -- Les cinq de la tranche 1, nommés : la 311 en ajoute trois, qui doivent elles
  -- aussi être révoquées (mesuré par sa propre suite).
  SELECT count(*) INTO v_tranche1
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname IN ('chain_l1_invoice_entry', 'chain_l1_credit_note_entry',
        'chain_l1_supplier_payment_entry', 'chain_l1_customer_payment_entry', 'chain_l1_bank_account_ledger');

  SELECT count(*), string_agg(p.proname, ', ') INTO v_mauvais, v_detail
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname LIKE 'chain_l1_%'
    AND (p.proacl IS NULL
         OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                    WHERE (a).privilege_type = 'EXECUTE' AND (a).grantee = 0)
         OR has_function_privilege('anon', p.oid, 'EXECUTE')
         OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));

  PERFORM _rec('T15',
    'les cinq maillons compagnons de la tranche 1 existent et AUCUN `chain_l1_` n''est exécutable par PUBLIC, anon ou authenticated',
    v_tranche1 = 5 AND v_n >= 5 AND v_mauvais = 0,
    format('fonctions chain_l1_=%s (tranche 1 nommées=%s), exposées=%s %s', v_n, v_tranche1, v_mauvais, COALESCE(v_detail, '')));
END $$;

SELECT _audit_assert('310');






