-- ═══════════════════════════════════════════════════════════════════════════
-- 415 — Lot L3, tranche 3 : LA PAIE VERSÉE ET LA COMPTABILISATION DU BULLETIN,
--   tracées par leur chemin d'appel (tâche 3.2 du plan de la partie 3)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **Objet.** La 412 a tracé la caisse « par son chemin d'appel » : le corps
-- est RENOMMÉ (`_inner`), et un WRAPPER qui porte le nom public tisse la
-- chaîne. C'est la doctrine du lot L3 pour un maillon dont l'entrée est un
-- appel — un compagnon `zz_l…` ne peut pas s'y accrocher, et un compagnon
-- EXCLU de toute écriture ne verrait jamais le geste de l'appelant.
-- Cette migration applique cette doctrine aux DEUX maillons de paie que le
-- recomptage du 02/10 (tâche 3.1, porte `ci/check_chain_rpc_inventory.sql`)
-- a nommés : `payroll_post_run` et `post_payroll_payment`.
--
-- **POURQUOI `payroll_post_run` EST LE BON POINT, ET C'EST MESURÉ.** La
-- comptabilisation du bulletin n'a pas UN chemin d'appel, elle en a TROIS :
--     1. `post_payroll_journal`  — la porte R-17 (`payroll.post`), le front ;
--     2. `payroll_payment_inner` — le versement, via `post_payroll_payment` ;
--     3. un DÉCLENCHEUR sur `pay_runs` (`create_journal_on_payroll_validate`,
--        au passage du lot à `paid`).
-- Les trois convergent sur `payroll_post_run`. C'est donc là — et nulle part
-- ailleurs — que la chaîne se tisse : un seul point couvre les trois chemins,
-- et l'on n'a pas à énumérer les appelants, qui changent.
-- C'est la différence avec une fonction de façade : la façade ne couvre que
-- les appels qui passent par elle.
--
-- **LES DEUX MAILLONS ET LEUR PART :**
--   * `payroll_post_run` → l'effet **`payroll.run.posted`** : l'écriture de paie
--     (`journal_entries` de référence `PAYROLL-<n>`) et son registre
--     (`payroll_accounting_entries`). Le lot devient comptabilisé.
--   * `post_payroll_payment` → l'effet **`payroll.payment.settled`** : les
--     écritures de versement (références `PAYPAY-<n>-<scope>`, jusqu'à quatre :
--     net, social, taxe, acomptes). C'est un effet **N:1** — un lot, quatre
--     écritures — donc lien au NIVEAU DU DOCUMENT, l'aval de référence étant
--     l'écriture de plus petit identifiant, les identifiants et le décompte au
--     `payload` (doctrine 316, appliquée par la 412 à la sortie de stock).
--
-- **LE REJEU NE SE TRACE PAS DEUX FOIS — ET C'EST UN CHOIX, PAS UNE OUBLI.**
-- Les deux effets sont idempotents par construction : `payroll_post_run`
-- renvoie `already_posted`, `payroll_payment_inner` renvoie `already_paid`. Un
-- rejeu ne produit donc AUCUNE écriture. Écrire une seconde trace `applique`
-- compterait deux fois un fait unique et gonflerait l'indice de cohérence d'un
-- tour qui n'a rien fait. On applique donc la retenue de la 316 (« le cas
-- ordinaire ne se trace pas ») :
--   * si le LIEN existe déjà → rien. Le `document_links` EST la preuve du fait ;
--   * si le lien N'EXISTE PAS → `sans_effet`, avec le motif. C'est le cas
--     interesting : une écriture antérieure au traçage (donnée d'avant la 415)
--     serait sinon un trou MUET, et `sans_effet` est précisément le vocabulaire
--     ajouté par la 315 pour dire « attendu et absent ».
--
-- **CE QUI N'EST PAS CHANGÉ.** Les corps ne sont pas recopiés : ils sont
-- renommés par `ALTER FUNCTION … RENAME TO` (doctrine 412, leçon R-17 de la
-- 220 : « le corps renommé n'est plus exposé »), et les wrappers sont
-- `CREATE OR REPLACE`. Le garde de permission R-17 de `post_payroll_payment`
-- est conservé tel quel, AVANT tout travail. La garde d'inaltérabilité de la
-- 250 n'est pas contournée : elle distingue l'appel direct de l'écriture
-- métier par `current_user`, pas par le nom de la fonction — les wrappers sont
-- `SECURITY DEFINER` comme les corps qu'ils enveloppaient.
--
-- **REJOUABLE.** Le `RENAME` est gardé par un bloc conditionnel, les contrats
-- par `ON CONFLICT`, les wrappers par `CREATE OR REPLACE`.
-- ═══════════════════════════════════════════════════════════════════════════
-- ─────────────────────────────────────────────────────────────
-- 1. LES DEUX CONTRATS D'EFFET — déclarés ici, comme la porte G2 l'exige
--    dans le MÊME fichier que le maillon qui les produit. Sans eux, chaque
--    exécution écrirait `tolere` puis `applique` (mesuré le 30/09 : 1 132
--    `tolere` pour 1 117 `applique`), et le socle, fermé par défaut,
--    refuserait l'entrée.
-- ─────────────────────────────────────────────────────────────
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES
  (NULL, 'pay_runs', 'posted', 'payroll.run.posted',
   true, 'PAIE', false, true, true, false, true,
   'L3/415 : payroll_post_run écrit l''écriture de paie (journal_entries, référence ''PAYROLL-<n>'', journal PAIE) et son registre (payroll_accounting_entries). Le maillon est un POINT DE CONVERGENCE : il est appelé par la porte R-17 (post_payroll_journal), par le versement (payroll_payment_inner) et par un déclencheur au passage du lot à `paid` — les trois chemins sont donc tracés, sans énumérer les appelants. Réversible : la contrepassation de paie (321) porte l''effet miroir `payroll.run.reversed` sur le même lot.'),
  (NULL, 'pay_runs', 'paid', 'payroll.payment.settled',
   true, NULL, false, true, true, false, true,
   'L3/415 : post_payroll_payment (corps payroll_payment_inner) écrit les écritures de versement, références ''PAYPAY-<n>-<scope>'' — jusqu''à quatre : net, social, taxe, acomptes. Effet N:1 : le lien est au niveau du LOT, l''aval de référence est l''écriture de plus petit identifiant, les quatre identifiants, le décompte et les périmètres sont au payload (doctrine 316).')
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
-- 2. payroll_post_run — LE CORPS EST RENOMMÉ, LE WRAPPER TISSE LA CHAÎNE
--    Le corps (validation du lot, une écriture de paie `PAIE` avec une ligne
--    par compte et par sens, le registre `payroll_accounting_entries`, les
--    bulletins marqués comptabilisés) devient `payroll_post_run_inner`. Rien
--    n'est recopié : le corps, ses droits et son `SECURITY DEFINER` survivent
--    au RENAME.
-- ─────────────────────────────────────────────────────────────
DO $bloc$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'payroll_post_run'
                AND pg_get_function_identity_arguments(p.oid) = 'p_run uuid')
      AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'payroll_post_run_inner') THEN
    ALTER FUNCTION public.payroll_post_run(uuid) RENAME TO payroll_post_run_inner;
  END IF;
END $bloc$;

-- Le corps renommé n'est plus une API : seul le wrapper est exposé (leçon
-- R-17, 220). On lui laisse `service_role`, qui l'appelle encore directement.
REVOKE ALL ON FUNCTION public.payroll_post_run_inner(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.payroll_post_run(p_run uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_tid     uuid := current_tenant_id();
  v_debut   timestamptz := clock_timestamp();
  v_r       jsonb;
  v_run     pay_runs%ROWTYPE;
  v_number  text;
  v_entry   uuid;
  v_deja    boolean;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active' USING ERRCODE = '42501';
  END IF;

  -- L'effet métier d'abord, dans la transaction de l'appel.
  v_r := public.payroll_post_run_inner(p_run);

  SELECT * INTO v_run FROM pay_runs WHERE id = p_run AND tenant_id = v_tid;
  IF NOT FOUND THEN
    -- Le corps lève déjà dans ce cas ; on ne peut pas écrire une trace d'un
    -- lot qui n'existe pas.
    RETURN v_r;
  END IF;
  v_number := v_run.number;
  v_deja   := COALESCE((v_r->>'already_posted')::boolean, false);

  IF chain_avant(v_tid, 'pay_runs', 'posted', 'payroll.run.posted',
                 'pay_runs', v_run.id, NULL,
                 format('Lot %s : la comptabilisation n''a pas été tracée (règle payroll.run.posted, module paie).', v_number)) THEN

    IF v_deja THEN
      -- Rejeu : le corps n'a rien produit. On ne réécrit PAS une trace
      -- `applique` — le lien, s'il existe, EST la preuve du fait.
      IF NOT EXISTS (
        SELECT 1 FROM document_links l
        WHERE l.tenant_id = v_tid AND l.amont_type = 'pay_runs'
          AND l.amont_id = v_run.id AND l.effet = 'payroll.run.posted'
          AND l.etat = 'actif') THEN
        PERFORM chain_apres(v_tid, 'payroll.run.posted', 'pay_runs', v_run.id,
                            v_debut, 0, 'sans_effet',
                            format('Lot %s : écrit comme déjà comptabilisé, mais AUCUN lien payroll.run.posted actif — écriture antérieure au traçage.', v_number),
                            NULL, NULL);
      END IF;

    ELSE
      v_entry := (v_r->>'entry_id')::uuid;
      IF v_entry IS NOT NULL THEN
        PERFORM link_documents(v_tid, 'pay_runs', v_run.id, 'journal_entries', v_entry,
                               'payroll.run.posted', 'generated_entry',
                               jsonb_build_object('number', v_number, 'piece', v_run.number,
                                                  'periode', v_run.period_start, 'lien_par_ligne', false));
        PERFORM chain_apres(v_tid, 'payroll.run.posted', 'pay_runs', v_run.id,
                            v_debut, 1, 'applique', NULL, NULL, NULL);
        PERFORM emit_domain_event(v_tid, 'pay_runs.posted', 'pay_runs', v_run.id,
                                  jsonb_build_object('number', v_number, 'entry_id', v_entry), NULL);
      ELSE
        PERFORM chain_apres(v_tid, 'payroll.run.posted', 'pay_runs', v_run.id,
                            v_debut, 0, 'sans_effet',
                            format('Lot %s : le corps a dit avoir comptabilisé, sans rendre d''écriture (règle payroll.run.posted).', v_number),
                            NULL, NULL);
      END IF;
    END IF;
  END IF;

  RETURN v_r;
END $maillon$;

COMMENT ON FUNCTION public.payroll_post_run(uuid) IS
  'L3/415 : la comptabilisation du bulletin, tracée par son chemin d''appel. Le corps est renommé payroll_post_run_inner, intact. Point de convergence : post_payroll_journal (R-17), payroll_payment_inner (versement) et le déclencheur de passage à `paid` passent tous par ici — les trois chemins sont tracés sans énumérer les appelants.';

-- ─────────────────────────────────────────────────────────────
-- 3. post_payroll_payment — LE VERSEMENT, ET SES QUATRE ÉCRITURES
--    Ici le corps a DÉJÀ été renommé par la 224 (`payroll_payment_inner`) et
--    un wrapper R-17 existe. On ne renomme donc rien : on réécrit le wrapper,
--    qui garde sa garde de permission ET son isolement de société, et on y
--    tisse la chaîne.
--
--    L'effet est N:1 — un lot, jusqu'à quatre écritures de versement
--    (`PAYPAY-<n>-net`, `-social`, `-tax`, `-advances`). Doctrine 316 : lien au
--    NIVEAU DU LOT, vers l'aval de référence (plus petit identifiant, donc
--    déterministe pour qu'un rejeu désigne le même), le décompte et les
--    quatre identifiants au `payload`.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.post_payroll_payment(
  p_pay_run_id       uuid,
  p_bank_account_id  uuid  DEFAULT NULL,
  p_date             date  DEFAULT NULL,
  p_scope            text  DEFAULT 'all')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_tid     uuid := current_tenant_id();
  v_debut   timestamptz := clock_timestamp();
  v_r       jsonb;
  v_run     pay_runs%ROWTYPE;
  v_number  text;
  v_n       integer;
  v_aval    uuid;
  v_ids     jsonb;
  v_scopes  jsonb;
BEGIN
  -- R-17 : la porte d'entrée, AVANT tout travail — telle que la 224 l'a écrite.
  IF NOT has_permission('payroll.pay') THEN
    RAISE EXCEPTION 'Permission refusée : payroll.pay' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active' USING ERRCODE = '42501';
  END IF;

  -- L'effet métier d'abord. Il appelle `payroll_post_run`, désormais le
  -- wrapper du §2 : la comptabilisation du bulletin est donc tracée par CE
  -- chemin aussi, sans code supplémentaire ici.
  v_r := public.payroll_payment_inner(p_pay_run_id, p_bank_account_id, p_date, p_scope);

  SELECT * INTO v_run FROM pay_runs WHERE id = p_pay_run_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RETURN v_r;   -- le corps a levé, ou le lot n'est pas à nous
  END IF;
  v_number := v_run.number;

  IF chain_avant(v_tid, 'pay_runs', 'paid', 'payroll.payment.settled',
                 'pay_runs', v_run.id, NULL,
                 format('Lot %s : le versement n''a pas été tracé (règle payroll.payment.settled, module paie).', v_number)) THEN

    -- Les écritures de versement de CE lot. Le préfixe est une clé mesurée
    -- dans le corps (`'PAYPAY-' || v_run.number || '-' || scope`), pas une
    -- convention supposée.
    SELECT count(*),
           COALESCE(jsonb_agg(id ORDER BY id), '[]'::jsonb),
           COALESCE(jsonb_agg(DISTINCT split_part(reference, '-', 3) ORDER BY split_part(reference, '-', 3)), '[]'::jsonb)
      INTO v_n, v_ids, v_scopes
      FROM journal_entries
     WHERE tenant_id = v_tid
       AND reference LIKE 'PAYPAY-' || v_number || '-%';

    -- L'aval de référence : le plus petit identifiant (doctrine 316), pour
    -- qu'un rejeu désigne le même.
    SELECT id INTO v_aval
      FROM journal_entries
     WHERE tenant_id = v_tid
       AND reference LIKE 'PAYPAY-' || v_number || '-%'
     ORDER BY id LIMIT 1;

    IF v_n > 0 THEN
      PERFORM link_documents(v_tid, 'pay_runs', v_run.id, 'journal_entries', v_aval,
                             'payroll.payment.settled', 'paid_by',
                             jsonb_build_object('number', v_number, 'versements', v_n,
                                                'ids', v_ids, 'perimetres', v_scopes,
                                                'date', v_r->'date', 'scope', p_scope,
                                                'lien_par_ligne', false));
      PERFORM chain_apres(v_tid, 'payroll.payment.settled', 'pay_runs', v_run.id,
--   s'appliquera à ces maillons comme aux autres.
                          v_debut, v_n, 'applique', NULL, NULL, NULL);
      PERFORM emit_domain_event(v_tid, 'pay_runs.paid', 'pay_runs', v_run.id,
                                jsonb_build_object('number', v_number, 'versements', v_n,
                                                   'perimetres', v_scopes, 'date', v_r->'date'), NULL);
    ELSIF NOT EXISTS (
      SELECT 1 FROM document_links l
      WHERE l.tenant_id = v_tid AND l.amont_type = 'pay_runs'
        AND l.amont_id = v_run.id AND l.effet = 'payroll.payment.settled'
        AND l.etat = 'actif') THEN
      -- Attendu et absent, ET aucun lien : une écriture antérieure au traçage.
      PERFORM chain_apres(v_tid, 'payroll.payment.settled', 'pay_runs', v_run.id,
                          v_debut, 0, 'sans_effet',
                          format('Lot %s : aucun versement trouvé et aucun lien actif (règle payroll.payment.settled).', v_number),
                          NULL, NULL);
    END IF;
    -- v_n = 0 ET lien actif : rejeu. Le lien EST la preuve ; une seconde
    -- trace `applique` compterait deux fois un fait unique.
  END IF;

  RETURN v_r;
END $maillon$;

COMMENT ON FUNCTION public.post_payroll_payment(uuid, uuid, date, text) IS
  'L3/415 : le versement de la paie, tracé par son chemin d''appel. Effet N:1 (jusqu''à quatre écritures : net, social, taxe, acomptes) — lien au niveau du lot, identifiants et périmètres au payload (doctrine 316). Garde de permission R-17 inchangée.';

REVOKE ALL ON FUNCTION public.payroll_payment_inner(uuid, uuid, date, text) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.payroll_payment_inner(uuid, uuid, date, text) TO service_role;

-- ─────────────────────────────────────────────────────────────
-- 4. DROITS
--    `post_payroll_payment` reste exposée à `authenticated` : c'est l'écran qui
--    paie, et lui retirer ce droit casserait le produit. Sa garde R-17 est
--    dans le corps du wrapper.
--    `payroll_post_run` reste au même régime qu'avant la 415 : `service_role`
--    (mesuré sur la base avant migration — elle n'était PAS exposée à
--    `authenticated`, et le front passe par `post_payroll_journal` ou par le
--    versement). On ne change donc AUCUN droit d'exécution : la 415 ne doit
--    pas élargir la surface d'appel, seulement la tracer.
-- ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.payroll_post_run(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.payroll_post_run(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.post_payroll_payment(uuid, uuid, date, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.post_payroll_payment(uuid, uuid, date, text) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────
-- 5. Ce que cette migration ne fait pas — nommé
-- ─────────────────────────────────────────────────────────────
-- * **Elle ne trace pas le REVERSEMENT.** Il n'existe pas dans le code : le
--   contrat dit `reversible`, ce qui signifie « une contrepassation peut
--   rompre ce lien », pas « un reversement existe ». Le dire ici plutôt que de
--   le laisser croire.
-- * **Elle ne touche pas à `payroll_run.reversed`** : la contrepassation de
--   paie est tracée depuis la 321, par le compagnon `zz_l1_payroll_run_reversal`.
--   Les deux effets sont distincts et cohabitent sur le même lot.
-- * **Elle ne comble pas le trou des écritures antérieures.** Un lot
--   comptabilisé avant le déploiement de la 415 a son écriture mais pas son
--   lien ; le rejouer produit `sans_effet`, ce qui le SIGNALE. Le renseigner
--   est un choix de reprise de données, pas une correction de traçage.
-- * **Elle ne mesure pas la performance.** Le banc D1→D8 (tâches 3.4 → 3.7)
