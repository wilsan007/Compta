-- ============================================================
-- 321_chain_l1_paie_contrepassation.sql — L1 (tranche 6) : LA CONTRAPASSATION
--   DE PAIE — le sixième candidat direct, celui que la tranche 5 a laissé
--
-- Source : doc/audit/INVENTAIRE-CHAINAGES-L1-TRANCHE4-2026-09-30.md §2. La table
-- des 32 fonctions qui écrivent dans ≥ 2 modules marque SIX fois le verdict
-- « candidat direct » (un maillon déclencheur APRÈS dont l'aval est identifiable
-- par une clé mesurée dans son corps) :
--
--   | # | Fonction | État dans l'inventaire |
--   |---:|---|---|
--   | 4  | post_exchange_gain_loss_on_payment     | candidat direct |
--   | 9  | create_billable_line_on_timesheet_stop | candidat direct |
--   | 18 | integrate_pay_recalls_on_payrun        | candidat direct |
--   | 19 | integrate_salary_advances_on_payrun    | candidat direct |
--   | 22 | PAYROLL_REVERSE_POSTED_RUN             | candidat direct ← oublié |
--   | 31 | statement_line_ledger_match            | candidat direct |
--
-- La tranche 5 (migration 316) en a tracé CINQ ; son en-tête §1, le compte du
-- §2 (« 5 candidats directs ») et le §5 de sa preuve répètent ce chiffre. Mais la
-- LIGNE 22 du tableau porte le verdict « candidat direct », et la mesure le
-- confirme : `payroll_reverse_posted_run` n'a **ni trace ni contrat** (aucune
-- migration L1 ne le nomme). L'incohérence est dans l'inventaire lui-même — et
-- c'est elle qui rend le sixième visible. Ce fichier ferme l'écart : le reste de
-- L1, sur les candidats directs, s'arrête ici.
--
-- LA DOCTRINE (les deux conditions de la 310), vérifiée pour ce maillon :
--   1. c'est un déclencheur APRÈS — MESURÉ : la 248 pose
--      `payroll_reverse_posted_run_trg AFTER UPDATE OF status ON pay_runs`,
--      et `zz_l1_payroll_run_reversal` trie APRÈS lui (ordre ASCII du nom :
--      « payroll_… » < « zz_l1_… »), donc le compagnon voit ce que le maillon
--      vient d'écrire ;
--   2. l'aval se LIT, il ne se devine pas — la clé est celle que le maillon
--      écrit lui-même : `journal_entries.reference = 'PAYROLL-REV-' || <numéro
--      du lot>`. C'est déjà sa GARDE D'IDEMPOTENCE (« déjà contrepassée : ne pas
--      le faire deux fois »), donc une clé stable et mesurée dans son corps.
--
-- LE CAS ORDINAIRE, ET L'ANOMALIE — la distinction de la 315.
--   * Un lot annulé qui n'a JAMAIS été comptabilisé ne produit AUCUNE
--     contrepassation : le maillon le décide (pont absent, ou sans écriture),
--     et il n'y a rien à lier. C'est le cas ordinaire et le compagnon **ne le
--     trace pas** — sinon chaque annulation d'un brouillon ferait du bruit.
--     (Même retenue que la 316 §T02/T09 : le cas ordinaire ne se trace pas,
--     `sans_effet` est réservé à l'anomalie.)
--   * L'anomalie, elle, SE TRACE : un lot qui PORTE une écriture de paie
--     (pont `payroll_accounting_entries.journal_entry_id` non nul, écriture
--     pointée `posted`) dont l'annulation n'a produit AUCUNE contrepassation.
--     Un effet ATTENDU et ABSENT — exactement ce que la valeur **`sans_effet`**
--     (315) a été ajoutée pour dire, plutôt que de se taire.
--
-- CE QUE CE FICHIER NE FAIT PAS : il ne touche à aucun corps de maillon métier
-- (le compagnon s'ajoute à côté ; le recopier serait le chemin le plus court
-- vers une régression silencieuse), et il ne traite pas les neuf maillons RPC de
-- l'inventaire (caisse, paie versée, relevé manuel) : un compagnon ne peut pas
-- s'accrocher à un appel de fonction — c'est le lot L3.
--
-- REJOUABLE : contrat par `ON CONFLICT` (clé de la 252), déclencheur par
-- `DROP … IF EXISTS` puis `CREATE`, fonction par `CREATE OR REPLACE`.
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- 1. Le contrat d'effet — déclaré ici, comme la porte G2 l'exige depuis L7
-- ─────────────────────────────────────────────────────────────
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES
  (NULL, 'pay_runs', 'cancelled', 'payroll.run.reversed',
   true, 'PAIE', false, true, true, false, true,
   'L1/tr6 : payroll_reverse_posted_run (248) contrepasse au journal PAIE un lot de paie comptabilisé, par une écriture de référence PAYROLL-REV-<numéro du lot> (clé d''idempotence du maillon, mesurée). L''écriture d''origine reste intacte (valeur probante). Effet CONDITIONNEL : un lot jamais comptabilisé n''a rien à contrepasser, et le compagnon ne trace alors rien — sauf l''ANOMALIE (écriture de paie pointée « posted » sans contrepassation), tracée `sans_effet`.')
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
-- 2. Le compagnon — il CONSTATE, il ne décide de rien
--    Il s'exécute après le maillon métier (nom `zz_l1_`, ordre ASCII) et se
--    contente de LIRE ce que le maillon a écrit : l'écriture PAYROLL-REV-<n°>.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l1_payroll_run_reversal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $compagnon$
DECLARE
  v_debut    timestamptz := clock_timestamp();
  v_contrep  uuid;
  v_ecriture uuid;
  v_lignes   integer := 0;
BEGIN
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;
  -- Le fait générateur : le lot vient d'être annulé (même garde que le maillon).
  IF NOT (NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'cancelled') THEN
    RETURN NULL;
  END IF;

  -- L'aval, RELU dans la table (jamais dans `NEW`) : l'écriture de contrepassation
  -- que le maillon nomme lui-même — `PAYROLL-REV-<numéro du lot>`.
  SELECT je.id INTO v_contrep
  FROM journal_entries je
  WHERE je.tenant_id = NEW.tenant_id
    AND je.reference = 'PAYROLL-REV-' || NEW.number
  ORDER BY je.id LIMIT 1;

  IF v_contrep IS NULL THEN
    -- Aucune contrepassation. Cas ordinaire, ou anomalie ? Le lot PORTE-t-il une
    -- écriture de paie (le pont la pointe, et elle est `posted`) ? Si oui, le
    -- maillon AURAIT dû contrepasser : c'est l'effet attendu et absent.
    SELECT pae.journal_entry_id INTO v_ecriture
    FROM payroll_accounting_entries pae
    JOIN journal_entries je
      ON je.id = pae.journal_entry_id AND je.tenant_id = pae.tenant_id
    WHERE pae.tenant_id = NEW.tenant_id AND pae.pay_run_id = NEW.id
      AND je.status = 'posted'
    ORDER BY pae.journal_entry_id LIMIT 1;

    IF v_ecriture IS NOT NULL THEN
      PERFORM chain_apres(NEW.tenant_id, 'payroll.run.reversed', 'pay_runs', NEW.id,
                          v_debut, 0, 'sans_effet',
                          format('Lot %s : une écriture de paie (n° %s, pointée « posted ») existe, mais l''annulation n''a produit aucune contrepassation PAYROLL-REV-%s — l''effet attendu est absent.',
                                 NEW.number, v_ecriture, NEW.number),
                          NULL, NULL);
    END IF;
    RETURN NULL;
  END IF;

  -- L'entrée du maillon : rejeu détecté (trace `ignore`, on ne relie pas une
  -- seconde fois) ou contrat lu. C'est `chain_avant` qui le décide.
  IF NOT chain_avant(NEW.tenant_id, 'pay_runs', 'cancelled', 'payroll.run.reversed',
                     'pay_runs', NEW.id, NULL,
                     format('Lot de paie %s annulé : la contrepassation n''a pas été portée au journal PAIE (règle payroll.run.reversed, module Paie).',
                            NEW.number)) THEN
    RETURN NULL;
  END IF;

  PERFORM link_documents(NEW.tenant_id, 'pay_runs', NEW.id, 'journal_entries', v_contrep,
                         'payroll.run.reversed', 'reversed_by',
                         jsonb_build_object('reference', 'PAYROLL-REV-' || NEW.number,
                                            'lien_par_ligne', false));
  v_lignes := v_lignes + 1;

  PERFORM emit_domain_event(NEW.tenant_id, 'pay_runs.reversed', 'pay_runs', NEW.id,
                            jsonb_build_object('contrepassation', v_contrep,
                                               'reference', 'PAYROLL-REV-' || NEW.number), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'payroll.run.reversed', 'pay_runs', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $compagnon$;

COMMENT ON FUNCTION public.chain_l1_payroll_run_reversal() IS
  'L1/tr6 (321) : maillon compagnon de la contrepassation de paie — trace le lien pay_runs → journal_entries (payroll.run.reversed, link_type `reversed_by`) quand payroll_reverse_posted_run (248) porte l''écriture PAYROLL-REV-<numéro>. Cas ordinaire (lot jamais comptabilisé) non tracé ; anomalie (écriture de paie « posted » sans contrepassation) tracée `sans_effet`.';

DROP TRIGGER IF EXISTS zz_l1_payroll_run_reversal ON pay_runs;
CREATE TRIGGER zz_l1_payroll_run_reversal
  AFTER UPDATE OF status ON pay_runs
  FOR EACH ROW
  WHEN (NEW.status = 'cancelled' AND COALESCE(OLD.status, 'draft') <> 'cancelled')
  EXECUTE FUNCTION public.chain_l1_payroll_run_reversal();
REVOKE ALL ON FUNCTION public.chain_l1_payroll_run_reversal() FROM PUBLIC, anon, authenticated;