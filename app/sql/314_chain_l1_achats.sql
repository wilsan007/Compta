-- ============================================================
-- 314_chain_l1_achats.sql — L1, tranche 4 : la chaîne ACHATS → STOCK →
--   COMPTABILITÉ, et les notes de frais (RH → comptabilité + paie)
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md (lot L1) et
-- l'inventaire §3 : « les 32 chaînages restants ont leur méthode ». La méthode a
-- été **rejouée** sur la base du 30/09/2026 (schéma compilé, pas les fichiers) :
--   * **99 fonctions** touchent au moins deux modules (le référentiel en comptait
--     **62** le 24/09 — le schéma a grandi, et la carte de modules est une
--     heuristique assumée, comme la sienne) ;
--   * **32** d'entre elles ÉCRIVENT dans au moins deux modules : ce sont les
--     effets qui traversent vraiment (les 67 autres ne font que lire en
--     transverse) ;
--   * les 12 maillons déjà tracés par les 310/311 sont dedans, et les 17
--     restants se répartissent en : paramétrage de société (3), recalculs de
--     clôture (5), API de service (2), actes d'import (1), caisse (2),
--     relevé bancaire (4). Chacun a son verdict dans
--     `doc/audit/INVENTAIRE-CHAINAGES-L1-TRANCHE4-2026-09-30.md`.
--
-- CE QUE CETTE TRANCHE TRACE — trois effets, choisis parce qu'ils remplissent les
-- DEUX conditions de la doctrine de la 310 : leur maillon est un **déclencheur
-- `AFTER`** (donc un compagnon `zz_l1_` peut s'exécuter après lui), et son aval
-- est **identifiable par une clé mesurée dans son propre corps** :
--
--   `purchase.invoice.generated_entry`   purchase_invoices / approved
--        → journal_entries, clé `invoice_ref = number` + `journal_code = 'AC'`
--          (c'est la clé d'idempotence du maillon lui-même)
--   `expense.report.generated_entry`     expense_reports / approved
--        → journal_entries, clé `reference = 'EXPENSE-' || number`
--   `expense.report.payroll_element`     expense_reports / approved
--        → payroll_variable_elements, clé `source = 'expense_report'` + `source_id`
--
-- Pourquoi ces trois-là d'abord : la matrice du référentiel donne
-- **achats → comptabilité** et **commercial → comptabilité** comme les liens les
-- plus chargés du produit (13 chacun), et la facture d'achat validée était le
-- **symétrique exact** de la facture de vente — tracée depuis la 310, elle. Un
-- chaînage que le client voit des deux côtés d'un même flux, mais dont un seul
-- côté est dans le registre, est le genre d'asymétrie qui fait perdre confiance
-- dans une vue chaîne.
--
-- CE QUE CETTE TRANCHE NE TRACE PAS, ET POURQUOI (écrit, pas caché) :
--   * la **réception de marchandise** (`create_stock_on_goods_receipt`) produit N
--     mouvements à partir de N lignes : la correspondance ligne → ligne ne se
--     devine pas de l'extérieur. C'est la doctrine de la 311, et cela demande la
--     **réécriture du corps** — donc une tranche à elle seule ;
--   * la **caisse** (`pos_refund_ticket`) est une RPC (elle rend un `uuid`), pas
--     un déclencheur : un compagnon ne peut pas s'y accrocher. Elle sera tracée
--     par ses propres chemins d'appel (lot L3) ;
--   * les **recalculs de clôture** (`revaluate_currency_balances`,
--     `post_deferred_charge`, `close_fiscal_year`, `apply_chart_pack`) et le
--     **paramétrage** (`bootstrap_tenant`, `create_tenant_for_current_user`) ne
--     sont pas des transitions d'état d'un document : ce sont des actes
--     paramétriques, et le référentiel a tranché le 29/09 (inventaire §2) ;
--   * le **relevé bancaire** (4 fonctions) et les **lettrages** : ils relèvent du
--     rapprochement, dont l'effet déjà tracé (`treasury.bank_transaction.reconciled`,
--     lot 311) couvre le maillon automatique ; les trois autres attendent leur
--     propre tranche.
--
-- LA LIMITE DU SOCLE, DITE ICI. Le vocabulaire de `chain_traces.resultat`
-- (`applique`, `ignore`, `tolere`, `refuse`, `regenere`) n'a **pas** de valeur
-- pour « maillon exécuté, aucun effet produit ». Les compagnons de cette tranche
-- n'écrivent donc **ni lien ni trace** quand l'aval est absent (une note de frais
-- à 0 € n'écrit pas d'écriture : le maillon le fait exprès) — inventer un lien
-- vers rien, ou une trace qui dit « applique » sur un effet absent, serait un
-- mensonge que la vue chaîne lirait. C'est une entrée pour la tranche qui
-- ajoutera le vocabulaire, pas un silence.
--
-- REJOUABLE : les trois contrats passent par `ON CONFLICT` (clé de la 252), les
-- deux déclencheurs sont créés par `DROP … IF EXISTS` puis `CREATE`, et les deux
-- fonctions par `CREATE OR REPLACE`. Aucun corps de maillon métier n'est touché.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. Les trois contrats d'effet — déclarés DANS la tranche qui les trace
--    (la porte G2 refuse désormais tout effet appelé sans contrat : c'est elle
--    qui impose que le contrat arrive avec le maillon, et c'est le but).
--    Les drapeaux sont mesurés sur les écritures réelles :
--      * la facture d'achat écrit journal_entries + journal_lines (code « AC ») ;
--      * la note de frais écrit journal_entries + journal_lines (code « OD ») et
--        un élément de paie (payroll_variable_elements) — deux effets distincts,
--        donc deux contrats, comme la 310 l'a fait pour le compte de trésorerie.
-- ─────────────────────────────────────────────────────────────
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES
  (NULL, 'purchase_invoices', 'approved', 'purchase.invoice.generated_entry',
   true, 'AC', false, false, true, true, true,
   'L1/tranche 4 : create_journal_on_purchase_invoice_validate écrit journal_entries + journal_lines, code « AC » (mesuré). Réversible par avoir fournisseur ; même flux que la facture de vente (310).'),
  (NULL, 'expense_reports', 'approved', 'expense.report.generated_entry',
   true, 'OD', false, false, true, true, true,
   'L1/tranche 4 : integrate_expense_report_on_approval écrit journal_entries + journal_lines, code « OD » (mesuré). Écriture NON produite quand le total est nul : le compagnon ne pose alors aucun lien (limite du vocabulaire de trace, dite dans l''en-tête).'),
  (NULL, 'expense_reports', 'approved', 'expense.report.payroll_element',
   false, NULL, false, true, true, false, true,
   'L1/tranche 4 : même maillon, écrit payroll_variable_elements (remboursement dû au salarié, source = expense_report, source_id = la note) — RH-07. Réversible : la note annulée retire l''élément.')
ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
             document_type, evenement, effet)
DO UPDATE SET
  ecrit_comptable = EXCLUDED.ecrit_comptable,
  journal_code    = EXCLUDED.journal_code,
  touche_stock    = EXCLUDED.touche_stock,
  touche_paie     = EXCLUDED.touche_paie,
  reversible      = EXCLUDED.reversible,
  obligatoire     = EXCLUDED.obligatoire,
  actif           = EXCLUDED.actif,
  note            = EXCLUDED.note;


-- ─────────────────────────────────────────────────────────────
-- 2. LE COMPAGNON DE LA FACTURE D'ACHAT (doctrine de la 310 : même table, même
--    événement, nom qui trie APRÈS le maillon métier — `create_journal_purchase_invoice`
--    < `zz_l1_purchase_invoice_entry` — donc l'aval existe quand il s'exécute).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l1_purchase_invoice_entry()
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
  -- 0. Le fait générateur : la facture vient de passer à « approuvée » (c'est la
  --    condition même du maillon métier, relevée dans son corps).
  IF NEW.approval_status IS NOT DISTINCT FROM OLD.approval_status
     OR NEW.approval_status IS DISTINCT FROM 'approved' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- 1. L'aval, produit par le maillon métier (exécuté avant : `zz_` > `create_`).
  --    La clé est celle de SON idempotence : invoice_ref + journal_code 'AC'.
  SELECT je.id INTO v_aval
  FROM journal_entries je
  WHERE je.tenant_id = NEW.tenant_id
    AND je.invoice_ref = NEW.number
    AND je.journal_code = 'AC'
  LIMIT 1;
  -- Rien n'a été produit : il n'y a rien à tracer, et on ne trace pas un vide.
  IF v_aval IS NULL THEN
    RETURN NULL;
  END IF;

  -- 2. ENTRÉE — rejeu, contrat, drapeau.
  IF NOT chain_avant(NEW.tenant_id, 'purchase_invoices', 'approved',
                     'purchase.invoice.generated_entry', 'purchase_invoices', NEW.id, NULL,
                     format('Facture achat %s du %s : l''écriture d''achat n''a pas été produite (règle purchase.invoice.generated_entry, module achats).',
                            NEW.number, to_char(NEW.date, 'DD/MM/YYYY'))) THEN
    RETURN NULL;
  END IF;

  -- 3. LE LIEN — l'ascendance de l'écriture d'achat (vue chaîne, analyse d'impact).
  PERFORM link_documents(NEW.tenant_id, 'purchase_invoices', NEW.id, 'journal_entries', v_aval,
                         'purchase.invoice.generated_entry', 'generated_entry',
                         jsonb_build_object('number', NEW.number, 'journal_code', 'AC',
                                            'total', NEW.total));
  v_lignes := v_lignes + 1;

  -- 4. L'ÉVÉNEMENT — lu par les automatisations et les webhooks (I-06).
  PERFORM emit_domain_event(NEW.tenant_id, 'purchase_invoices.approved', 'purchase_invoices', NEW.id,
                            jsonb_build_object('entry_id', v_aval, 'total', NEW.total), NULL);

  -- 5. LA MESURE (§3.4) — budget §3.3 : ≤ 50 ms pour un maillon simple.
  PERFORM chain_apres(NEW.tenant_id, 'purchase.invoice.generated_entry', 'purchase_invoices', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l1_purchase_invoice_entry() IS
  'L1 (314) : maillon compagnon de l''approbation d''une facture d''achat — trace le lien purchase_invoices → journal_entries (purchase.invoice.generated_entry) et l''événement purchase_invoices.approved, sans toucher au maillon métier.';

DROP TRIGGER IF EXISTS zz_l1_purchase_invoice_entry ON purchase_invoices;
CREATE TRIGGER zz_l1_purchase_invoice_entry
  AFTER UPDATE ON purchase_invoices
  FOR EACH ROW EXECUTE FUNCTION public.chain_l1_purchase_invoice_entry();
REVOKE ALL ON FUNCTION public.chain_l1_purchase_invoice_entry() FROM PUBLIC, anon, authenticated;


-- ─────────────────────────────────────────────────────────────
-- 3. LE COMPAGNON DE LA NOTE DE FRAIS — DEUX effets, un seul fait métier
--    (gabarit de la 310 pour `bank_account_ensure_journal` : deux avals, deux
--    liens, un événement, une mesure).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l1_expense_report_integration()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut     timestamptz := clock_timestamp();
  v_ecriture  uuid;
  v_element   uuid;
  v_lignes    integer := 0;
BEGIN
  -- 0. Le fait générateur : la note de frais vient de passer à « approuvée ».
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     OR NEW.status IS DISTINCT FROM 'approved' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- 1. Les DEUX avals, produits par le maillon métier (exécuté avant).
  --    * l'écriture OD, portée par sa référence (`EXPENSE-<numéro>`) ;
  --    * l'élément de paie (remboursement dû au salarié), clé (source, source_id).
  SELECT je.id INTO v_ecriture
  FROM journal_entries je
  WHERE je.tenant_id = NEW.tenant_id
    AND je.reference = 'EXPENSE-' || NEW.number
  LIMIT 1;

  SELECT pve.id INTO v_element
  FROM payroll_variable_elements pve
  WHERE pve.tenant_id = NEW.tenant_id
    AND pve.source = 'expense_report'
    AND pve.source_id = NEW.id
  LIMIT 1;

  -- Aucun des deux n'existe (note à 0 €, ou annulée avant écriture) : rien à tracer.
  IF v_ecriture IS NULL AND v_element IS NULL THEN
    RETURN NULL;
  END IF;

  -- 2. L'ÉCRITURE (RH-08).
  IF v_ecriture IS NOT NULL
     AND chain_avant(NEW.tenant_id, 'expense_reports', 'approved', 'expense.report.generated_entry',
                     'expense_reports', NEW.id, NULL,
                     format('Note de frais %s du %s : l''écriture de remboursement n''a pas été produite (règle expense.report.generated_entry, module RH).',
                            NEW.number, to_char(COALESCE(NEW.approved_at, now()), 'DD/MM/YYYY'))) THEN
    PERFORM link_documents(NEW.tenant_id, 'expense_reports', NEW.id, 'journal_entries', v_ecriture,
                           'expense.report.generated_entry', 'generated_entry',
                           jsonb_build_object('number', NEW.number, 'journal_code', 'OD',
                                              'reference', 'EXPENSE-' || NEW.number,
                                              'total', NEW.total_amount));
    v_lignes := v_lignes + 1;
  END IF;

  -- 3. L'ÉLÉMENT DE PAIE (RH-07 : le remboursement TTC dû au salarié).
  IF v_element IS NOT NULL
     AND chain_avant(NEW.tenant_id, 'expense_reports', 'approved', 'expense.report.payroll_element',
                     'expense_reports', NEW.id, NULL,
                     format('Note de frais %s du %s : l''élément de remboursement n''a pas été porté à la paie (règle expense.report.payroll_element, module RH).',
                            NEW.number, to_char(COALESCE(NEW.approved_at, now()), 'DD/MM/YYYY'))) THEN
    PERFORM link_documents(NEW.tenant_id, 'expense_reports', NEW.id, 'payroll_variable_elements', v_element,
                           'expense.report.payroll_element', 'consumed_by_absence',
                           jsonb_build_object('number', NEW.number, 'period', NEW.period,
                                              'total', NEW.total_amount));
    v_lignes := v_lignes + 1;
  END IF;

  -- 4. Un événement pour les DEUX effets : c'est le même fait métier.
  PERFORM emit_domain_event(NEW.tenant_id, 'expense_reports.approved', 'expense_reports', NEW.id,
                            jsonb_build_object('entry_id', v_ecriture, 'element_id', v_element,
                                               'total', NEW.total_amount), NULL);

  -- 5. La mesure, sous le nom du fait métier (l'écriture et l'élément de paie
  --    sont deux effets d'un même passage — même convention que la 310).
  PERFORM chain_apres(NEW.tenant_id, 'expense.report.integration', 'expense_reports', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l1_expense_report_integration() IS
  'L1 (314) : maillon compagnon de l''approbation d''une note de frais — trace DEUX liens (expense.report.generated_entry vers journal_entries, expense.report.payroll_element vers payroll_variable_elements) et l''événement expense_reports.approved.';

DROP TRIGGER IF EXISTS zz_l1_expense_report_integration ON expense_reports;
CREATE TRIGGER zz_l1_expense_report_integration
  AFTER UPDATE ON expense_reports
  FOR EACH ROW EXECUTE FUNCTION public.chain_l1_expense_report_integration();
REVOKE ALL ON FUNCTION public.chain_l1_expense_report_integration() FROM PUBLIC, anon, authenticated;


-- ─────────────────────────────────────────────────────────────
-- 4. Ce que la migration constate (un compte, jamais un silence)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_contrats int; v_compagnons int; v_declencheurs int; v_pas_exposes int;
BEGIN
  SELECT count(*) INTO v_contrats FROM document_effects
  WHERE tenant_id IS NULL AND effet IN ('purchase.invoice.generated_entry',
                                        'expense.report.generated_entry',
                                        'expense.report.payroll_element');

  SELECT count(*) INTO v_compagnons FROM pg_proc
  WHERE proname IN ('chain_l1_purchase_invoice_entry', 'chain_l1_expense_report_integration');

  SELECT count(*) INTO v_declencheurs FROM pg_trigger t
  WHERE NOT t.tgisinternal
    AND t.tgname IN ('zz_l1_purchase_invoice_entry', 'zz_l1_expense_report_integration')
    AND t.tgrelid IN ('purchase_invoices'::regclass, 'expense_reports'::regclass);

  -- Le socle n'est pas une API : aucune des deux fonctions n'est exécutable par
  -- un visiteur ni par un utilisateur connecté (même exigence que la 310, T15).
  SELECT count(*) INTO v_pas_exposes FROM pg_proc p
  WHERE p.proname IN ('chain_l1_purchase_invoice_entry', 'chain_l1_expense_report_integration')
    AND has_function_privilege('authenticated', p.oid, 'EXECUTE');

  RAISE NOTICE 'L1 tranche 4 : % contrat(s) déclaré(s), % fonction(s) compagnon, % déclencheur(s) compagnon, % exposée(s) à `authenticated`.',
    v_contrats, v_compagnons, v_declencheurs, v_pas_exposes;

  IF v_contrats <> 3 OR v_compagnons <> 2 OR v_declencheurs <> 2 OR v_pas_exposes <> 0 THEN
    RAISE EXCEPTION 'L1 tranche 4 incomplète : % contrat(s) (3 attendus), % compagnon(s) (2), % déclencheur(s) (2), % exposée(s) (0 attendues).',
      v_contrats, v_compagnons, v_declencheurs, v_pas_exposes;
  END IF;
END $$;

