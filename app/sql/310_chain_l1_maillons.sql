-- ============================================================
-- 310_chain_l1_maillons.sql — L1 (tranche 1) : les maillons de la
--   chaîne ventes → trésorerie → comptabilité sont TRACÉS
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md, lot L1
-- (§3.6 « rétro-instrumentation des 62 chaînages ») et
-- doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md (parties A.2, A.3).
--
-- ÉTAT D'ENTRÉE, MESURÉ. Le socle (252, lot L0) est en place et VIDE : aucune
-- fonction `chain_*` n'est appelée par un maillon — `grep -rl 'chain_avant\|
-- link_documents\|emit_domain_event' app/sql` ne rendait que la 252 et sa suite.
-- Le référentiel a mesuré, sur les 62 chaînages existants : idempotence 9/62
-- (15 %), trace de référence 7/62 (11 %). L1 fait passer le TRACÉ de 0/62 à ce
-- que cette tranche couvre.
--
-- CE QUE CE FICHIER FAIT — et la décision d'ingénierie qui le porte
--
-- Le plan écrit : « on n'ajoute que `link_documents(...)` et
-- `emit_domain_event(...)` dans les maillons existants, **sans changer leur
-- logique** ». Réécrire le corps de six déclencheurs métier (157 lignes pour la
-- seule `create_journal_on_invoice_validate`) pour y insérer trois appels est le
-- chemin le plus court vers une régression silencieuse : un `CREATE OR REPLACE`
-- qui recopie mal une ligne change le comportement, et rien ne le dirait.
--
-- Le traçage est donc porté par un **maillon compagnon** : un déclencheur
-- additif posé sur la MÊME table et le MÊME événement que le déclencheur métier,
-- nommé `zz_l1_…`. PostgreSQL déclenche, pour un même événement, les
-- déclencheurs par ordre **alphabétique de leur nom** : `zz_` passe après
-- `create_journal_invoice`, `tg_credit_note_after_validate` et
-- `tg_bank_account_journal`, et l'aval (« l'écriture produite ») existe donc
-- quand le compagnon s'exécute.
--
-- Ce que le compagnon apporte, sans toucher au maillon :
--   1. l'entrée du maillon — `chain_avant` : rejeu (rend false et trace
--      `ignore`), contrat (M-05), drapeau de la société (`observe` par défaut,
--      §3.6). Un maillon REJOUÉ ne produit ni second lien ni second événement :
--      l'idempotence du traçage est structurelle (index unique du socle) ;
--   2. le lien amont → aval (`link_documents`, M-10/M-11/M-12) : l'ascendance et
--      la descendance, que la vue chaîne (L6) et l'analyse d'impact liront ;
--   3. l'événement lisible (`emit_domain_event`, M-13/I-06) ;
--   4. la mesure (`chain_apres`) : durée, lignes écrites, résultat.
--
-- LIMITE DITE, ET ELLE EST RÉELLE. Le compagnon s'exécute APRÈS l'effet : il ne
-- peut pas empêcher un maillon métier de produire deux fois son effet si ce
-- maillon n'a pas sa propre garde. `chain_avant` protège donc le TRACÉ, pas
-- l'ÉCRITURE du maillon. C'est la limite de la rétro-instrumentation par
-- compagnon, et elle est mesurée par T06 (un rejeu du traçage ne double rien) ;
-- l'idempotence de l'effet lui-même est l'objet du lot L3 (banc d'épreuve D1→D8)
-- et des règles R-001 → R-062 de la phase D, qui réécrivent les maillons.
--
-- CE QUE CE FICHIER NE FAIT PAS
--   * il n'instrumente PAS les 62 chaînages — six effets de la tranche 1,
--     nommés ci-dessous ; l'inventaire des 30 fonctions de la tranche (19 artères
--     + 16 fragiles, dédoublonnées) et la méthode pour les 32 restantes vivent
--     dans doc/audit/INVENTAIRE-CHAINAGES-L1-2026-09-29.md ;
--   * il ne DÉCLARE aucun contrat d'effet (`document_effects`) : c'est le lot
--     L7. En mode `observe` (défaut), `chain_autorise` rend faux et l'effet est
--     appliqué ET tracé `tolere` — aucune société existante n'est bloquée ;
--   * il ne réécrit aucun corps de maillon : c'est la doctrine de la tranche 1.
--
-- LES SIX EFFETS DE LA TRANCHE 1
--   T-1  invoices          `validated` → journal_entries  `sale.invoice.generated_entry`
--   T-2  credit_notes      `validated` → journal_entries  `sale.credit_note.generated_entry`
--   T-3  supplier_payments `recorded`  → journal_entries  `purchase.payment.generated_entry`
--   T-4  customer_payments `recorded`  → journal_entries  `sale.payment.generated_entry`
--   T-5  bank_accounts     `created`   → journals          `treasury.bank_account.journal`
--   T-6  bank_accounts     `created`   → chart_accounts    `treasury.bank_account.account`
--
-- VOCABULAIRE POSÉ ICI (et qui sera celui des contrats du lot L7)
--   `document_type` = le nom de la TABLE du document amont (`invoices`,
--   `credit_notes`, `supplier_payments`, `customer_payments`, `bank_accounts`) ;
--   `evenement` = l'état atteint (`validated`, `recorded`, `created`) ;
--   `effet` = `<module>.<document>.<effet>` ; `link_type` ∈ les huit du socle
--   (252, M-11) — ici `generated_entry`.
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- T-1 — Facture de vente validée → écriture VT
--   Maillon métier : déclencheur `create_journal_invoice` (AFTER UPDATE ON
--   invoices) → `create_journal_on_invoice_validate`, qui renseigne
--   `invoices.transferred_entry_id` (210 : dernier état du maillon).
--   L'aval est relu DANS LA TABLE, jamais dans `NEW` : PostgreSQL ne fait pas
--   remonter dans `NEW` les modifications qu'un autre déclencheur AFTER vient
--   d'écrire. C'est la même raison pour T-3 et T-4 (déclencheurs AFTER INSERT).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l1_invoice_entry()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut  timestamptz := clock_timestamp();
  v_aval   uuid;
  v_lignes integer := 0;
BEGIN
  -- 0. Le fait générateur : la facture vient de passer à « validée ».
  IF NEW.validation_status IS NOT DISTINCT FROM OLD.validation_status
     OR NEW.validation_status IS DISTINCT FROM 'validated' THEN
    RETURN NULL;
  END IF;
  -- Cloisonnement fermé : un document sans société n'entre pas dans la chaîne.
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- 1. L'aval, produit par le maillon métier (exécuté avant : `zz_` > `create_`).
  SELECT i.transferred_entry_id INTO v_aval
  FROM invoices i WHERE i.id = NEW.id AND i.tenant_id = NEW.tenant_id;
  -- Rien n'a été produit : il n'y a rien à tracer, et on ne trace pas un vide.
  IF v_aval IS NULL THEN
    RETURN NULL;
  END IF;

  -- 2. ENTRÉE — rejeu, contrat, drapeau.
  IF NOT chain_avant(NEW.tenant_id, 'invoices', 'validated', 'sale.invoice.generated_entry',
                     'invoices', NEW.id, NULL,
                     format('Facture %s du %s : l''écriture de vente n''a pas été produite (règle sale.invoice.generated_entry, module ventes).',
                            NEW.number, to_char(NEW.date, 'DD/MM/YYYY'))) THEN
    RETURN NULL;
  END IF;

  -- 3. LE LIEN — l'ascendance de l'écriture (vue chaîne, analyse d'impact).
  PERFORM link_documents(NEW.tenant_id, 'invoices', NEW.id, 'journal_entries', v_aval,
                         'sale.invoice.generated_entry', 'generated_entry',
                         jsonb_build_object('number', NEW.number, 'journal_code', 'VT', 'total', NEW.total));
  v_lignes := v_lignes + 1;

  -- 4. L'ÉVÉNEMENT — lu par les automatisations et les webhooks (I-06).
  PERFORM emit_domain_event(NEW.tenant_id, 'invoices.validated', 'invoices', NEW.id,
                            jsonb_build_object('entry_id', v_aval, 'total', NEW.total), NULL);

  -- 5. LA MESURE (§3.4) — budget §3.3 : ≤ 50 ms pour un maillon simple.
  PERFORM chain_apres(NEW.tenant_id, 'sale.invoice.generated_entry', 'invoices', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l1_invoice_entry() IS
  'L1 (310) : maillon compagnon de la validation d''une facture de vente — trace le lien invoices → journal_entries (sale.invoice.generated_entry) et l''événement invoices.validated, sans toucher au maillon métier.';

DROP TRIGGER IF EXISTS zz_l1_invoice_entry ON invoices;
CREATE TRIGGER zz_l1_invoice_entry
  AFTER UPDATE ON invoices
  FOR EACH ROW EXECUTE FUNCTION public.chain_l1_invoice_entry();
REVOKE ALL ON FUNCTION public.chain_l1_invoice_entry() FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- T-2 — Avoir client validé → écriture d'avoir
--   Maillon métier : `tg_credit_note_guard` (BEFORE) → `credit_note_guard`
--   (213 : dernier état), qui renseigne `credit_notes.transferred_entry_id`.
--   Le fait générateur est le passage de `draft` à `validated` / `applied`.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l1_credit_note_entry()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut  timestamptz := clock_timestamp();
  v_aval   uuid;
  v_lignes integer := 0;
BEGIN
  IF OLD.status IS DISTINCT FROM 'draft'
     OR NEW.status NOT IN ('validated', 'applied') THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT c.transferred_entry_id INTO v_aval
  FROM credit_notes c WHERE c.id = NEW.id AND c.tenant_id = NEW.tenant_id;
  IF v_aval IS NULL THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'credit_notes', 'validated', 'sale.credit_note.generated_entry',
                     'credit_notes', NEW.id, NULL,
                     format('Avoir %s du %s : l''écriture d''avoir n''a pas été produite (règle sale.credit_note.generated_entry, module ventes).',
                            NEW.number, to_char(NEW.date, 'DD/MM/YYYY'))) THEN
    RETURN NULL;
  END IF;

  PERFORM link_documents(NEW.tenant_id, 'credit_notes', NEW.id, 'journal_entries', v_aval,
                         'sale.credit_note.generated_entry', 'generated_entry',
                         jsonb_build_object('number', NEW.number, 'journal_code', 'VT',
                                            'total', NEW.total, 'invoice_id', NEW.invoice_id));
  v_lignes := v_lignes + 1;

  PERFORM emit_domain_event(NEW.tenant_id, 'credit_notes.validated', 'credit_notes', NEW.id,
                            jsonb_build_object('entry_id', v_aval, 'total', NEW.total,
                                               'invoice_id', NEW.invoice_id), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'sale.credit_note.generated_entry', 'credit_notes', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l1_credit_note_entry() IS
  'L1 (310) : maillon compagnon de la validation d''un avoir client — trace le lien credit_notes → journal_entries (sale.credit_note.generated_entry) et l''événement credit_notes.validated.';

DROP TRIGGER IF EXISTS zz_l1_credit_note_entry ON credit_notes;
CREATE TRIGGER zz_l1_credit_note_entry
  AFTER UPDATE ON credit_notes
  FOR EACH ROW EXECUTE FUNCTION public.chain_l1_credit_note_entry();
REVOKE ALL ON FUNCTION public.chain_l1_credit_note_entry() FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- T-3 — Décaissement fournisseur → écriture de trésorerie
--   Maillon métier : `create_journal_supplier_payment` (AFTER INSERT ON
--   supplier_payments) → `create_journal_on_supplier_payment`, qui renseigne
--   `supplier_payments.transferred_entry_id`.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l1_supplier_payment_entry()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut  timestamptz := clock_timestamp();
  v_aval   uuid;
  v_lignes integer := 0;
BEGIN
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT p.transferred_entry_id INTO v_aval
  FROM supplier_payments p WHERE p.id = NEW.id AND p.tenant_id = NEW.tenant_id;
  IF v_aval IS NULL THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'supplier_payments', 'recorded', 'purchase.payment.generated_entry',
                     'supplier_payments', NEW.id, NULL,
                     format('Règlement fournisseur %s du %s : l''écriture de décaissement n''a pas été produite (règle purchase.payment.generated_entry, module achats).',
                            NEW.number, to_char(NEW.payment_date, 'DD/MM/YYYY'))) THEN
    RETURN NULL;
  END IF;

  PERFORM link_documents(NEW.tenant_id, 'supplier_payments', NEW.id, 'journal_entries', v_aval,
                         'purchase.payment.generated_entry', 'generated_entry',
                         jsonb_build_object('number', NEW.number, 'amount', NEW.amount,
                                            'method', NEW.method));
  v_lignes := v_lignes + 1;

  PERFORM emit_domain_event(NEW.tenant_id, 'supplier_payments.recorded', 'supplier_payments', NEW.id,
                            jsonb_build_object('entry_id', v_aval, 'amount', NEW.amount), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'purchase.payment.generated_entry', 'supplier_payments', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l1_supplier_payment_entry() IS
  'L1 (310) : maillon compagnon d''un décaissement fournisseur — trace le lien supplier_payments → journal_entries (purchase.payment.generated_entry) et l''événement supplier_payments.recorded.';

DROP TRIGGER IF EXISTS zz_l1_supplier_payment_entry ON supplier_payments;
CREATE TRIGGER zz_l1_supplier_payment_entry
  AFTER INSERT ON supplier_payments
  FOR EACH ROW EXECUTE FUNCTION public.chain_l1_supplier_payment_entry();
REVOKE ALL ON FUNCTION public.chain_l1_supplier_payment_entry() FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- T-4 — Encaissement client → écriture de trésorerie
--   Maillon métier : `create_journal_customer_payment` (AFTER INSERT ON
--   customer_payments) → `create_journal_on_customer_payment`, qui renseigne
--   `customer_payments.transferred_entry_id`. Symétrique du T-3 : sans lui, la
--   trésorerie n'aurait qu'une moitié de chaîne tracée.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l1_customer_payment_entry()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut  timestamptz := clock_timestamp();
  v_aval   uuid;
  v_lignes integer := 0;
BEGIN
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT p.transferred_entry_id INTO v_aval
  FROM customer_payments p WHERE p.id = NEW.id AND p.tenant_id = NEW.tenant_id;
  IF v_aval IS NULL THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'customer_payments', 'recorded', 'sale.payment.generated_entry',
                     'customer_payments', NEW.id, NULL,
                     format('Encaissement %s du %s : l''écriture de trésorerie n''a pas été produite (règle sale.payment.generated_entry, module trésorerie).',
                            NEW.number, to_char(NEW.payment_date, 'DD/MM/YYYY'))) THEN
    RETURN NULL;
  END IF;

  PERFORM link_documents(NEW.tenant_id, 'customer_payments', NEW.id, 'journal_entries', v_aval,
                         'sale.payment.generated_entry', 'generated_entry',
                         jsonb_build_object('number', NEW.number, 'amount', NEW.amount,
                                            'method', NEW.method, 'invoice_id', NEW.invoice_id));
  v_lignes := v_lignes + 1;

  PERFORM emit_domain_event(NEW.tenant_id, 'customer_payments.recorded', 'customer_payments', NEW.id,
                            jsonb_build_object('entry_id', v_aval, 'amount', NEW.amount,
                                               'invoice_id', NEW.invoice_id), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'sale.payment.generated_entry', 'customer_payments', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l1_customer_payment_entry() IS
  'L1 (310) : maillon compagnon d''un encaissement client — trace le lien customer_payments → journal_entries (sale.payment.generated_entry) et l''événement customer_payments.recorded.';

DROP TRIGGER IF EXISTS zz_l1_customer_payment_entry ON customer_payments;
CREATE TRIGGER zz_l1_customer_payment_entry
  AFTER INSERT ON customer_payments
  FOR EACH ROW EXECUTE FUNCTION public.chain_l1_customer_payment_entry();
REVOKE ALL ON FUNCTION public.chain_l1_customer_payment_entry() FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- T-5 et T-6 — Compte de trésorerie → journal ET compte comptable
--   Maillon métier : `tg_bank_account_assign_ledger` (BEFORE, attribue le code
--   de compte et le journal) puis `tg_bank_account_journal` (AFTER) →
--   `bank_account_ensure_journal`, le maillon du référentiel noté **1/7** — le
--   plus fragile des 62, celui qui n'avait ni garde d'idempotence, ni trace, ni
--   refus explicite. Un déclencheur, deux effets : c'est ce que le socle permet
--   là où une colonne `reference_*` ne le pouvait pas.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l1_bank_account_ledger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut  timestamptz := clock_timestamp();
  v_journal uuid;
  v_compte  uuid;
  v_lignes  integer := 0;
BEGIN
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Les deux avals, produits par les déclencheurs métier (exécutés avant).
  SELECT j.id INTO v_journal
  FROM journals j
  WHERE j.tenant_id = NEW.tenant_id AND j.bank_account_id = NEW.id
  LIMIT 1;

  SELECT c.id INTO v_compte
  FROM chart_accounts c
  WHERE c.tenant_id = NEW.tenant_id AND c.code = NEW.account_code
  LIMIT 1;

  -- Aucun des deux n'existe : il n'y a rien à tracer.
  IF v_journal IS NULL AND v_compte IS NULL THEN
    RETURN NULL;
  END IF;

  -- T-5 : le JOURNAL de trésorerie (il porte le rapprochement bancaire).
  IF v_journal IS NOT NULL
     AND chain_avant(NEW.tenant_id, 'bank_accounts', 'created', 'treasury.bank_account.journal',
                     'bank_accounts', NEW.id, NULL,
                     format('Compte %s du %s : le journal de trésorerie n''a pas été créé (règle treasury.bank_account.journal, module trésorerie).',
                            COALESCE(NEW.name, NEW.account_code), to_char(now(), 'DD/MM/YYYY'))) THEN
    PERFORM link_documents(NEW.tenant_id, 'bank_accounts', NEW.id, 'journals', v_journal,
                           'treasury.bank_account.journal', 'generated_entry',
                           jsonb_build_object('journal_code', NEW.journal_code,
                                              'account_code', NEW.account_code));
    v_lignes := v_lignes + 1;
  END IF;

  -- T-6 : le COMPTE comptable de trésorerie (le grand livre de la banque).
  IF v_compte IS NOT NULL
     AND chain_avant(NEW.tenant_id, 'bank_accounts', 'created', 'treasury.bank_account.account',
                     'bank_accounts', NEW.id, NULL,
                     format('Compte %s du %s : le compte comptable de trésorerie n''a pas été créé (règle treasury.bank_account.account, module trésorerie).',
                            COALESCE(NEW.name, NEW.account_code), to_char(now(), 'DD/MM/YYYY'))) THEN
    PERFORM link_documents(NEW.tenant_id, 'bank_accounts', NEW.id, 'chart_accounts', v_compte,
                           'treasury.bank_account.account', 'generated_entry',
                           jsonb_build_object('account_code', NEW.account_code));
    v_lignes := v_lignes + 1;
  END IF;

  -- Un événement pour les DEUX effets : c'est le même fait métier.
  PERFORM emit_domain_event(NEW.tenant_id, 'bank_accounts.ledger_attached', 'bank_accounts', NEW.id,
                            jsonb_build_object('journal_id', v_journal, 'account_id', v_compte,
                                               'journal_code', NEW.journal_code,
                                               'account_code', NEW.account_code), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'treasury.bank_account.ledger', 'bank_accounts', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l1_bank_account_ledger() IS
  'L1 (310) : maillon compagnon d''un compte de trésorerie — trace les deux effets (journals et chart_accounts) et l''événement bank_accounts.ledger_attached, sans toucher au maillon métier.';

DROP TRIGGER IF EXISTS zz_l1_bank_account_ledger ON bank_accounts;
CREATE TRIGGER zz_l1_bank_account_ledger
  AFTER INSERT OR UPDATE OF account_code, journal_code ON bank_accounts
  FOR EACH ROW EXECUTE FUNCTION public.chain_l1_bank_account_ledger();
REVOKE ALL ON FUNCTION public.chain_l1_bank_account_ledger() FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- POURQUOI L'ORDRE DES DÉCLENCHEURS EST UNE PROPRIÉTÉ PROUVÉE
--
-- PostgreSQL exécute, pour un même événement sur une même table, les
-- déclencheurs par ordre alphabétique de leur nom (doc. CREATE TRIGGER, « les
-- déclencheurs de même nature sont exécutés par ordre alphabétique »). Le
-- compagnon, nommé `zz_l1_…`, passe donc après `create_journal_…` (c),
-- `create_stock_…` (c), `tg_credit_note_…` (t) et `tg_bank_account_…` (t).
--
-- La suite 310 ne croit pas ce commentaire sur parole : elle vérifie que le
-- lien amont → aval EXISTE juste après l'instruction métier (T01, T04, T07,
-- T10, T13), ce qui n'est vrai que si l'aval a déjà été produit.
--
-- CE QUI RESTE À INSTRUMENTER (tranche 2 et au-delà) — inventaire et méthode
-- dans doc/audit/INVENTAIRE-CHAINAGES-L1-2026-09-29.md : les effets à
-- PLUSIEURS lignes (`delivery_notes` → `stock_movements`, `sales_orders` →
-- `stock_reservations`, `st_shipments` / `st_receipts` → `stock_movements`),
-- que la granularité ligne du socle (`amont_ligne_id`, M-09) traite maillon par
-- maillon, et les maillons multi-effets de la caisse
-- (`post_pos_session_on_close`, 13 écritures) et de la production.
-- ─────────────────────────────────────────────────────────────
