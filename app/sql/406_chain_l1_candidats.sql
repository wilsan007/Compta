-- ============================================================
-- 316_chain_l1_candidats.sql — L1, tranche 5 : LES CINQ CANDIDATS DIRECTS
--
-- Source : doc/audit/INVENTAIRE-CHAINAGES-L1-TRANCHE4-2026-09-30.md §2 — les cinq
-- fonctions qui remplissent les **deux conditions** de la doctrine compagnon
-- (maillon `AFTER` + aval identifiable par une clé mesurée dans son corps) :
--
--   | Effet | Document / événement | Maillon, et l'aval qu'il produit |
--   |---|---|---|
--   | `sale.payment.exchange_gain_loss` | customer_payments / recorded | `post_exchange_gain_loss_on_payment` → écriture d'écart de change (`journal_entries` + `exchange_gain_loss_entries`), et le marqueur `customer_payments.exchange_gain_loss` |
--   | `project.time.billed` | project_time_entries / created | `create_billable_line_on_timesheet_stop` → une ligne de facture BROUILLON (`invoice_lines.time_entry_id`) |
--   | `payroll.pay_recall.integrated` | pay_runs / processing | `integrate_pay_recalls_on_payrun` → un élément de paie par rappel (`payroll_variable_elements.source_id = pay_recalls.id`) |
--   | `payroll.salary_advance.integrated` | pay_runs / processing | `integrate_salary_advances_on_payrun` → un élément de paie par acompte (`source_id = salary_advances.id`) |
--   | `treasury.statement_line.matched` | bank_transactions / created | `statement_line_ledger_match` → une LIGNE du grand livre rapprochée (`journal_lines.reconciled`), et le marqueur `bank_transactions.reconciled_entry_id` |
--
-- **Ce que la doctrine impose, et comment chaque cas s'y plie** :
--   * les cinq maillons sont des déclencheurs **APRÈS** (mesuré) et leur nom trie
--     avant `zz_l1_` — l'ordre des compagnons est donc garanti ;
--   * l'aval se **lit**, il ne se devine pas : la clé de chaque effet est celle
--     que le maillon écrit lui-même (le `time_entry_id` de la ligne de facture,
--     le `source_id` de l'élément de paie, le `reconciled_entry_id` de l'opération
--     bancaire, le marqueur `exchange_gain_loss` du règlement) ;
--   * pour les **deux effets de paie**, le maillon traite **N rappels** ou
--     **N acomptes** en boucle. Le lien est donc posé **au niveau du document**,
--     avec le **décompte** et les identifiants dans le `payload`
--     (`lien_par_ligne = false`) — c'est la décision de la tranche 2 pour les
--     effets sans ligne amont : l'élément amont (un rappel, un acompte) n'est pas
--     une LIGNE du document porteur (le lot de paie), et l'y inscrire serait une
--     correspondance inventée que la vue chaîne lirait de travers ;
--   * quand l'aval est **absent** (rien à lier), le compagnon trace
--     `sans_effet` — la valeur ajoutée par la **315** — au lieu de se taire.
--
-- **Ce que cette tranche ne fait pas** : elle ne touche à aucun corps de maillon
-- métier (les cinq compagnons s'ajoutent à côté), et elle ne traite pas les neuf
-- maillons **RPC** (caisse, paie versée, relevé manuel) : un compagnon ne peut
-- pas s'accrocher à un appel de fonction — c'est la tranche suivante (L3).
--
-- REJOUABLE : contrats par `ON CONFLICT` (clé de la 252), déclencheurs par
-- `DROP … IF EXISTS` puis `CREATE`, fonctions par `CREATE OR REPLACE`.
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- 1. Les cinq contrats d'effet — déclarés ici, comme la porte G2 l'exige
-- ─────────────────────────────────────────────────────────────
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES
  (NULL, 'customer_payments', 'recorded', 'sale.payment.exchange_gain_loss',
   true, NULL, false, false, true, false, true,
   'L1/tr5 : post_exchange_gain_loss_on_payment écrit une écriture d''écart de change (journal_entries + journal_lines, mesuré) et la marque sur le règlement (customer_payments.exchange_gain_loss). Réversible par contre-passation ; le code du journal est calculé, pas littéral.'),
  (NULL, 'project_time_entries', 'created', 'project.time.billed',
   false, NULL, false, false, true, false, true,
   'L1/tr5 : create_billable_line_on_timesheet_stop crée une ligne de facture BROUILLON (invoice_lines.time_entry_id — la clé d''unicité posée par la 301, mesurée). Aucune écriture comptable à ce stade : la facture n''est pas validée. La notification au chef de projet est une AVIS, pas un effet : elle n''est pas liée.'),
  (NULL, 'pay_runs', 'processing', 'payroll.pay_recall.integrated',
   false, NULL, false, true, true, false, true,
   'L1/tr5 : integrate_pay_recalls_on_payrun porte un élément de paie par rappel (payroll_variable_elements.source_id = pay_recalls.id, mesuré), au passage du lot à `processing`. N éléments en un passage : le lien est au niveau du document, avec le décompte au payload.'),
  (NULL, 'pay_runs', 'processing', 'payroll.salary_advance.integrated',
   false, NULL, false, true, true, false, true,
   'L1/tr5 : integrate_salary_advances_on_payrun retient un acompte par élément de paie (source_id = salary_advances.id, mesuré), même événement que les rappels. Réversible : l''acompte repris cesse d''être retenu.'),
  (NULL, 'bank_transactions', 'created', 'treasury.statement_line.matched',
   false, NULL, false, false, true, false, true,
   'L1/tr5 : statement_line_ledger_match rapproche une LIGNE du grand livre existante (journal_lines.reconciled) et marque l''opération (bank_transactions.reconciled_entry_id, mesuré). Aucune écriture créée — le rapprochement relie, il ne comptabilise pas. Réversible par dé-rapprochement (unreconcile_bank_statement_line).')
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
-- 2. L'ÉCART DE CHANGE AU RÈGLEMENT (309) — effet CONDITIONNEL, tracé par son
--    RÉSULTAT mesuré (`customer_payments.exchange_gain_loss`), jamais par une
--    règle déduite : un règlement en devise de tenue n'a pas d'écart, et il n'y a
--    alors rien à tracer (le maillon n'a rien produit, et c'est normal).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l1_payment_exchange_gain_loss()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut  timestamptz := clock_timestamp();
  v_ecriture uuid;
  v_ecart  numeric;
  v_type   text;
  v_lignes integer := 0;
BEGIN
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Le fait générateur, mesuré : le maillon a posé un écart non nul. ⚠️ Le
  -- marqueur se RELIT dans la table, jamais dans `NEW` : le maillon le pose par un
  -- `UPDATE` à l'intérieur de SON déclencheur `AFTER INSERT`, et la copie `NEW`
  -- de mon déclencheur — qui s'exécute après lui, mais sur la même instruction —
  -- ne porte pas encore cette valeur (défaut mesuré au premier passage de la
  -- suite : le lien n'était jamais posé).
  SELECT COALESCE(cp.exchange_gain_loss, 0) INTO v_ecart
  FROM customer_payments cp
  WHERE cp.id = NEW.id AND cp.tenant_id = NEW.tenant_id;

  IF v_ecart = 0 THEN
    RETURN NULL;   -- pas d'écart : aucun effet, et c'est le cas ordinaire
  END IF;

  -- L'aval : l'écriture d'écart de change, reliée au règlement par la table du
  -- maillon (exchange_gain_loss_entries.payment_id — mesuré).
  SELECT egl.journal_entry_id, egl.type INTO v_ecriture, v_type
  FROM exchange_gain_loss_entries egl
  WHERE egl.tenant_id = NEW.tenant_id AND egl.payment_id = NEW.id
  LIMIT 1;

  IF v_ecriture IS NULL THEN
    PERFORM chain_apres(NEW.tenant_id, 'sale.payment.exchange_gain_loss', 'customer_payments', NEW.id,
                        v_debut, 0, 'sans_effet',
                        format('Règlement %s : écart de change posé (%s) mais aucune écriture d''écart trouvée.', NEW.number, v_ecart),
                        NULL, NULL);
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'customer_payments', 'recorded',
                     'sale.payment.exchange_gain_loss', 'customer_payments', NEW.id, NULL,
                     format('Règlement %s du %s : l''écriture d''écart de change n''a pas été produite (règle sale.payment.exchange_gain_loss, module trésorerie).',
                            NEW.number, to_char(NEW.payment_date, 'DD/MM/YYYY'))) THEN
    RETURN NULL;
  END IF;

  PERFORM link_documents(NEW.tenant_id, 'customer_payments', NEW.id, 'journal_entries', v_ecriture,
                         'sale.payment.exchange_gain_loss', 'adjusted_by',
                         jsonb_build_object('number', NEW.number, 'ecart', v_ecart, 'sens', v_type,
                                            'devise', NEW.currency_code));
  v_lignes := v_lignes + 1;

  PERFORM emit_domain_event(NEW.tenant_id, 'customer_payments.exchange_gain_loss_posted',
                            'customer_payments', NEW.id,
                            jsonb_build_object('entry_id', v_ecriture, 'ecart', v_ecart), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'sale.payment.exchange_gain_loss', 'customer_payments', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l1_payment_exchange_gain_loss() IS
  'L1 (316) : maillon compagnon de l''écart de change au règlement — trace le lien customer_payments → journal_entries (sale.payment.exchange_gain_loss) quand le maillon a posé un écart non nul.';

DROP TRIGGER IF EXISTS zz_l1_payment_exchange_gain_loss ON customer_payments;
CREATE TRIGGER zz_l1_payment_exchange_gain_loss
  AFTER INSERT ON customer_payments
  FOR EACH ROW EXECUTE FUNCTION public.chain_l1_payment_exchange_gain_loss();
REVOKE ALL ON FUNCTION public.chain_l1_payment_exchange_gain_loss() FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- 3. LA FACTURATION DES TEMPS (301) — l'aval est la LIGNE de facture, et sa clé
--    est celle que la 301 a posée : `invoice_lines.time_entry_id`.
--    Un temps NON facturable (ou un projet qui ne l'est pas) est le cas
--    ordinaire : le maillon ne produit rien, et on ne trace rien — `sans_effet`
--    est réservé à ce qui DEVRAIT exister et n'existe pas.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l1_time_entry_billed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut  timestamptz := clock_timestamp();
  v_ligne  uuid;
  v_facture uuid;
  v_heures numeric;
  v_lignes integer := 0;
BEGIN
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- L'aval : la ligne de facture rattachée à ce temps.
  SELECT il.id, il.invoice_id INTO v_ligne, v_facture
  FROM invoice_lines il
  WHERE il.tenant_id = NEW.tenant_id AND il.time_entry_id = NEW.id
  LIMIT 1;

  IF v_ligne IS NULL THEN
    -- Temps non facturable, projet sans facturation, ou chronomètre non arrêté :
    -- c'est le cas ordinaire, il n'y a rien à tracer.
    RETURN NULL;
  END IF;

  v_heures := round(COALESCE(NEW.duration_seconds, 0)::numeric / 3600, 2);

  IF NOT chain_avant(NEW.tenant_id, 'project_time_entries', 'created',
                     'project.time.billed', 'project_time_entries', NEW.id, NULL,
                     format('Temps %s du %s : la ligne de facture n''a pas été créée (règle project.time.billed, module projets).',
                            NEW.id, to_char(NEW.start_time, 'DD/MM/YYYY'))) THEN
    RETURN NULL;
  END IF;

  PERFORM link_documents(NEW.tenant_id, 'project_time_entries', NEW.id, 'invoice_lines', v_ligne,
                         'project.time.billed', 'invoiced_by',
                         jsonb_build_object('invoice_id', v_facture, 'heures', v_heures,
                                            'taux', NEW.hourly_rate, 'facturable', NEW.is_billable));
  v_lignes := v_lignes + 1;

  PERFORM emit_domain_event(NEW.tenant_id, 'project_time_entries.billed',
                            'project_time_entries', NEW.id,
                            jsonb_build_object('invoice_id', v_facture, 'line_id', v_ligne,
                                               'heures', v_heures), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'project.time.billed', 'project_time_entries', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l1_time_entry_billed() IS
  'L1 (316) : maillon compagnon de la facturation des temps — trace le lien project_time_entries → invoice_lines (project.time.billed) quand le maillon a créé la ligne de facture.';

DROP TRIGGER IF EXISTS zz_l1_time_entry_billed ON project_time_entries;
CREATE TRIGGER zz_l1_time_entry_billed
  AFTER INSERT ON project_time_entries
  FOR EACH ROW EXECUTE FUNCTION public.chain_l1_time_entry_billed();
REVOKE ALL ON FUNCTION public.chain_l1_time_entry_billed() FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- 4. LES RAPPELS DE PAIE — N rappels intégrés en un passage
--    Lien au niveau du DOCUMENT, avec le décompte et les identifiants au payload
--    (`lien_par_ligne = false`), exactement la décision de la tranche 2 pour les
--    effets sans ligne amont : un rappel n'est PAS une ligne du lot de paie, et
--    l'inscrire dans `amont_ligne_id` produirait un lien que la vue chaîne ne
--    saurait pas résoudre. L'aval de référence est l'élément de **plus petit
--    identifiant** — un choix déterministe, pour qu'un rejeu désigne le même.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l1_pay_recall_integration()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut    timestamptz := clock_timestamp();
  v_element  uuid;
  v_n        integer;
  v_recalls  jsonb;
  v_traites  integer;
  v_lignes   integer := 0;
BEGIN
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;
  -- Le fait générateur : le lot entre en préparation (mesuré : `processing`).
  IF NOT (NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'processing') THEN
    RETURN NULL;
  END IF;

  -- L'aval : les éléments de paie portés par ce lot pour les rappels.
  -- `min(uuid)` n'existe pas en PostgreSQL (défaut mesuré par la suite 316 dès son
  -- premier passage : le compagnon levait `function min(uuid) does not exist`) :
  -- l'aval de référence est le plus PETIT identifiant, obtenu par un tri explicite
  -- — même choix qu'annoncé, et déterministe pour un rejeu.
  SELECT count(*) INTO v_n
  FROM payroll_variable_elements pve
  WHERE pve.tenant_id = NEW.tenant_id AND pve.pay_run_id = NEW.id
    AND pve.element_type = 'pay_recall';
  SELECT pve.id INTO v_element
  FROM payroll_variable_elements pve
  WHERE pve.tenant_id = NEW.tenant_id AND pve.pay_run_id = NEW.id
    AND pve.element_type = 'pay_recall'
  ORDER BY pve.id LIMIT 1;

  IF v_element IS NULL THEN
    -- Le maillon DIT avoir traité des rappels (son propre marqueur, mesuré :
    -- `processed_pay_run_id`) mais aucun élément n'existe : c'est l'anomalie que
    -- la 315 rend visible. Sans ce marqueur, c'est le cas ordinaire (aucun rappel
    -- à intégrer) et on ne trace rien.
    SELECT count(*) INTO v_traites FROM pay_recalls pc
    WHERE pc.tenant_id = NEW.tenant_id AND pc.processed_pay_run_id = NEW.id;
    IF v_traites > 0 THEN
      PERFORM chain_apres(NEW.tenant_id, 'payroll.pay_recall.integrated', 'pay_runs', NEW.id,
                          v_debut, 0, 'sans_effet',
                          format('Lot %s : %s rappel(s) marqué(s) traité(s) par le métier, aucun élément de paie trouvé.',
                                 NEW.number, v_traites),
                          NULL, NULL);
    END IF;
    RETURN NULL;
  END IF;

  SELECT jsonb_agg(pc.id) INTO v_recalls FROM pay_recalls pc
  WHERE pc.tenant_id = NEW.tenant_id AND pc.processed_pay_run_id = NEW.id;

  IF NOT chain_avant(NEW.tenant_id, 'pay_runs', 'processing',
                     'payroll.pay_recall.integrated', 'pay_runs', NEW.id, NULL,
                     format('Lot de paie %s du %s : les rappels n''ont pas été intégrés (règle payroll.pay_recall.integrated, module RH).',
                            NEW.number, to_char(NEW.period_start, 'DD/MM/YYYY'))) THEN
    RETURN NULL;
  END IF;

  PERFORM link_documents(NEW.tenant_id, 'pay_runs', NEW.id, 'payroll_variable_elements', v_element,
                         'payroll.pay_recall.integrated', 'generated_entry',
                         jsonb_build_object('elements', v_n, 'lien_par_ligne', false,
                                            'recall_ids', COALESCE(v_recalls, '[]'::jsonb),
                                            'periode', to_char(NEW.period_start, 'YYYY-MM')));
  v_lignes := v_lignes + 1;

  PERFORM emit_domain_event(NEW.tenant_id, 'pay_runs.pay_recalls_integrated', 'pay_runs', NEW.id,
                            jsonb_build_object('elements', v_n), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'payroll.pay_recall.integrated', 'pay_runs', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l1_pay_recall_integration() IS
  'L1 (316) : maillon compagnon de l''intégration des rappels de paie — trace le lien pay_runs → payroll_variable_elements (payroll.pay_recall.integrated), décompte au payload.';

DROP TRIGGER IF EXISTS zz_l1_pay_recall_integration ON pay_runs;
CREATE TRIGGER zz_l1_pay_recall_integration
  AFTER UPDATE ON pay_runs
  FOR EACH ROW EXECUTE FUNCTION public.chain_l1_pay_recall_integration();
REVOKE ALL ON FUNCTION public.chain_l1_pay_recall_integration() FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- 5. LES ACOMPTES DE PAIE — même forme, même événement que les rappels
--    Différence, et elle est dite : le maillon marque l'acompte `deducted` SANS
--    porter le lot sur la ligne (`salary_advances` n'a pas d'identifiant de lot,
--    mesuré). Le marqueur d'anomalie est donc plus faible — « un acompte retenu
--    pour ce mois, aucun élément dans ce lot » — et il est écrit comme tel dans
--    le message de la trace, plutôt que présenté comme une preuve.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l1_salary_advance_integration()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut   timestamptz := clock_timestamp();
  v_element uuid;
  v_n       integer;
  v_avances jsonb;
  v_retenus integer;
  v_lignes  integer := 0;
BEGIN
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;
  IF NOT (NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'processing') THEN
    RETURN NULL;
  END IF;

  -- Même correction que pour les rappels : `min(uuid)` n'existe pas ; l'aval de
  -- référence est le plus petit identifiant, par tri explicite.
  SELECT count(*) INTO v_n
  FROM payroll_variable_elements pve
  WHERE pve.tenant_id = NEW.tenant_id AND pve.pay_run_id = NEW.id
    AND pve.element_type = 'advance_deduction';
  SELECT pve.id INTO v_element
  FROM payroll_variable_elements pve
  WHERE pve.tenant_id = NEW.tenant_id AND pve.pay_run_id = NEW.id
    AND pve.element_type = 'advance_deduction'
  ORDER BY pve.id LIMIT 1;

  IF v_element IS NULL THEN
    SELECT count(*) INTO v_retenus FROM salary_advances sa
    WHERE sa.tenant_id = NEW.tenant_id AND sa.status = 'deducted'
      AND sa.deduction_month IS NOT NULL
      AND to_char(sa.deduction_month, 'YYYY-MM') = to_char(NEW.period_start, 'YYYY-MM');
    IF v_retenus > 0 THEN
      PERFORM chain_apres(NEW.tenant_id, 'payroll.salary_advance.integrated', 'pay_runs', NEW.id,
                          v_debut, 0, 'sans_effet',
                          format('Lot %s : %s acompte(s) marqué(s) retenu(s) pour ce mois, aucun élément dans le lot (marqueur non porté par le lot — indice, pas preuve).',
                                 NEW.number, v_retenus),
                          NULL, NULL);
    END IF;
    RETURN NULL;
  END IF;

  SELECT jsonb_agg(sa.id) INTO v_avances FROM salary_advances sa
  WHERE sa.tenant_id = NEW.tenant_id AND sa.status = 'deducted'
    AND sa.deduction_month IS NOT NULL
    AND to_char(sa.deduction_month, 'YYYY-MM') = to_char(NEW.period_start, 'YYYY-MM');

  IF NOT chain_avant(NEW.tenant_id, 'pay_runs', 'processing',
                     'payroll.salary_advance.integrated', 'pay_runs', NEW.id, NULL,
                     format('Lot de paie %s du %s : les acomptes n''ont pas été retenus (règle payroll.salary_advance.integrated, module RH).',
                            NEW.number, to_char(NEW.period_start, 'DD/MM/YYYY'))) THEN
    RETURN NULL;
  END IF;

  PERFORM link_documents(NEW.tenant_id, 'pay_runs', NEW.id, 'payroll_variable_elements', v_element,
                         'payroll.salary_advance.integrated', 'generated_entry',
                         jsonb_build_object('elements', v_n, 'lien_par_ligne', false,
                                            'advance_ids', COALESCE(v_avances, '[]'::jsonb),
                                            'periode', to_char(NEW.period_start, 'YYYY-MM')));
  v_lignes := v_lignes + 1;

  PERFORM emit_domain_event(NEW.tenant_id, 'pay_runs.salary_advances_deducted', 'pay_runs', NEW.id,
                            jsonb_build_object('elements', v_n), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'payroll.salary_advance.integrated', 'pay_runs', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l1_salary_advance_integration() IS
  'L1 (316) : maillon compagnon de la retenue des acomptes de paie — trace le lien pay_runs → payroll_variable_elements (payroll.salary_advance.integrated), décompte au payload.';

DROP TRIGGER IF EXISTS zz_l1_salary_advance_integration ON pay_runs;
CREATE TRIGGER zz_l1_salary_advance_integration
  AFTER UPDATE ON pay_runs
  FOR EACH ROW EXECUTE FUNCTION public.chain_l1_salary_advance_integration();
REVOKE ALL ON FUNCTION public.chain_l1_salary_advance_integration() FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- 6. L'APPARIEMENT D'UNE LIGNE DE RELEVÉ — le rapprochement RELIE, il ne
--    comptabilise pas : l'aval est une LIGNE du grand livre marquée rapprochée,
--    et le fait générateur est le marqueur posé par le maillon
--    (`bank_transactions.reconciled_entry_id`, mesuré).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l1_statement_line_matched()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut   timestamptz := clock_timestamp();
  v_matched boolean;
  v_entree  uuid;
  v_ligne   uuid;
  v_compte  text;
  v_lignes  integer := 0;
BEGIN
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Le maillon a-t-il rapproché cette opération ? (son propre marqueur, relu)
  SELECT bt.matched, bt.reconciled_entry_id, bt.matched_account_code
    INTO v_matched, v_entree, v_compte
  FROM bank_transactions bt
  WHERE bt.id = NEW.id AND bt.tenant_id = NEW.tenant_id;

  IF NOT COALESCE(v_matched, false) OR v_entree IS NULL THEN
    RETURN NULL;   -- aucune ligne du grand livre ne correspond : cas ordinaire
  END IF;

  SELECT jl.id INTO v_ligne FROM journal_lines jl
  WHERE jl.tenant_id = NEW.tenant_id AND jl.journal_id = v_entree AND jl.reconciled
  ORDER BY jl.id LIMIT 1;

  IF v_ligne IS NULL THEN
    PERFORM chain_apres(NEW.tenant_id, 'treasury.statement_line.matched', 'bank_transactions', NEW.id,
                        v_debut, 0, 'sans_effet',
                        format('Opération bancaire %s : rapprochée (écriture %s) mais aucune ligne du grand livre marquée.', NEW.reference, v_entree),
                        NULL, NULL);
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'bank_transactions', 'created',
                     'treasury.statement_line.matched', 'bank_transactions', NEW.id, NULL,
                     format('Opération bancaire %s du %s : le rapprochement au grand livre n''a pas été posé (règle treasury.statement_line.matched, module trésorerie).',
                            NEW.reference, to_char(NEW.date, 'DD/MM/YYYY'))) THEN
    RETURN NULL;
  END IF;

  PERFORM link_documents(NEW.tenant_id, 'bank_transactions', NEW.id, 'journal_lines', v_ligne,
                         'treasury.statement_line.matched', 'created_from',
                         jsonb_build_object('reference', NEW.reference, 'montant', NEW.amount,
                                            'compte', v_compte, 'entry_id', v_entree));
  v_lignes := v_lignes + 1;

  PERFORM emit_domain_event(NEW.tenant_id, 'bank_transactions.matched', 'bank_transactions', NEW.id,
                            jsonb_build_object('entry_id', v_entree, 'line_id', v_ligne), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'treasury.statement_line.matched', 'bank_transactions', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l1_statement_line_matched() IS
  'L1 (316) : maillon compagnon de l''appariement automatique d''une ligne de relevé — trace le lien bank_transactions → journal_lines (treasury.statement_line.matched).';

DROP TRIGGER IF EXISTS zz_l1_statement_line_matched ON bank_transactions;
CREATE TRIGGER zz_l1_statement_line_matched
  AFTER INSERT ON bank_transactions
  FOR EACH ROW EXECUTE FUNCTION public.chain_l1_statement_line_matched();
REVOKE ALL ON FUNCTION public.chain_l1_statement_line_matched() FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- 7. Ce que la migration constate (un compte, jamais un silence)
-- ─────────────────────────────────────────────────────────────
DO $bloc$
DECLARE v_contrats int; v_compagnons int; v_declencheurs int; v_exposes int;
BEGIN
  SELECT count(*) INTO v_contrats FROM document_effects
  WHERE tenant_id IS NULL AND actif AND effet IN (
    'sale.payment.exchange_gain_loss', 'project.time.billed',
    'payroll.pay_recall.integrated', 'payroll.salary_advance.integrated',
    'treasury.statement_line.matched');

  SELECT count(*) INTO v_compagnons FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
  WHERE p.proname IN ('chain_l1_payment_exchange_gain_loss', 'chain_l1_time_entry_billed',
                      'chain_l1_pay_recall_integration', 'chain_l1_salary_advance_integration',
                      'chain_l1_statement_line_matched');

  SELECT count(*) INTO v_declencheurs FROM pg_trigger t
  WHERE NOT t.tgisinternal AND t.tgname IN (
    'zz_l1_payment_exchange_gain_loss', 'zz_l1_time_entry_billed',
    'zz_l1_pay_recall_integration', 'zz_l1_salary_advance_integration',
    'zz_l1_statement_line_matched');

  SELECT count(*) INTO v_exposes FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
  WHERE p.proname IN ('chain_l1_payment_exchange_gain_loss', 'chain_l1_time_entry_billed',
                      'chain_l1_pay_recall_integration', 'chain_l1_salary_advance_integration',
                      'chain_l1_statement_line_matched')
    AND has_function_privilege('authenticated', p.oid, 'EXECUTE');

  RAISE NOTICE 'L1 tranche 5 : % contrat(s) déclaré(s), % compagnon(s), % déclencheur(s), % exposé(s) à `authenticated`.',
    v_contrats, v_compagnons, v_declencheurs, v_exposes;

  IF v_contrats <> 5 OR v_compagnons <> 5 OR v_declencheurs <> 5 OR v_exposes <> 0 THEN
    RAISE EXCEPTION 'L1 tranche 5 incomplète : % contrat(s) (5 attendus), % compagnon(s) (5), % déclencheur(s) (5), % exposé(s) (0 attendus).',
      v_contrats, v_compagnons, v_declencheurs, v_exposes;
  END IF;
END $bloc$;
