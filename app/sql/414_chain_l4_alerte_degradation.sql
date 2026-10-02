-- ═══════════════════════════════════════════════════════════════════════════
-- 414 — Lot L4, tranche 2 : l'ALERTE EN CAS DE DÉGRADATION
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **Objet.** La 413 (L4, tranche 1) mesure et publie l'indice de cohérence.
-- Le plan charge L4 d'un quatrième objet, resté entier : « une **alerte en
-- cas de dégradation** ». Sans elle, la 413 produit un historique que
-- personne ne regarde : le score peut tomber de 13/13 à 12/13 en silence, et
-- l'éditeur découvre le lendemain qu'un maillon s'est cassé. Cette migration
-- **compare le relevé du jour au relevé précédent** et prévient.
--
-- **Livré.**
--   * `chain_invariant_alertes` — l'historique des dégradations, une ligne
--     par (société, code, relevé). C'est la trace de l'alerte, pas seulement
--     son envoi : une alerte jetée est perdue, une ligne datée se relit.
--   * `chain_degradation_detectee(tenant, code)` — la comparaison d'UN
--     invariant entre deux relevés, et le verdict.
--   * `chain_alertes_lancer()` — le passage : relève, compare, alerte.
--   * l'élargissement du job `audit_chains_nocturne` de la 413 pour qu'il
--     enchaîne sur l'alerte.
--
-- **Ce qui déclenche une alerte, et ce qui n'en déclenche pas — dit, pas
-- deviné.** Alerte sur un invariant qui passe de `tenu` à `rompu` (une
-- **perte**), sur un `rompu` dont le nombre de lignes en écart a augmenté
-- (un **agravement**), et sur un `non_mesure` qui redevient mesurable et
-- rompu. Ne déclenche **PAS** d'alerte :
--   * l'amélioration (`rompu` → `tenu`) — elle est écrite au journal et
--     visible dans la page « Cohérence » (lot L5), mais alerter sur une
--     bonne nouvelle est un défaut de conception ;
--   * la bascule `tenu` → `non_mesure` — un invariant qui devient non
--     mesurable n'est pas une dégradation de la DONNÉE mais du CONTRÔLE, et
--     la 413 l'écrit déjà avec sa raison ;
--   * un invariant **déjà** rompu, au même nombre de lignes — on ne répète
--     pas la même alerte chaque nuit : seule la **variation** du nombre de
--     lignes en écart est notifiée.
--
-- **Le canal.** La 413 laissait le canal ouvert (« courriel, webhook — c'est
-- un choix »). On tranche ici par **l'existant** : le produit a déjà
-- `notifications` (dans l'application, là où l'utilisateur est connecté) et
-- `notification_email_queue` (le courriel). L'alerte écrit donc dans
-- `notifications`, et **n'envoie aucun courriel** : l'envoi est un choix qui
-- appartient à `notification_email_queue` et à ses préférences par salarié,
-- pas à cette migration. Rien ici n'empêche de le brancher plus tard.
--
-- **Le garde-fou anti-spam.** Un job nocturne rejoué dix fois, ou une
-- société en boucle, ne doivent pas saturer la table : l'index unique
-- `(tenant_id, code, releve_id)` l'interdit, et il est posé **en base**, pas
-- seulement dans la fonction.
--
-- **Non-régression.** Une table de plus (`chain_invariant_alertes`), RLS
-- activée et forcée, index mené par `tenant_id`. Les plafonds datés de la
-- porte G1 (`tables_tenant`, `moins_de_4_commandes`) et de la porte G7
-- (`tables_forcees`, `muettes`) sont réinscrits dans le même commit, avec la
-- raison — c'est la règle de `check_bt_grid`.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. L'HISTORIQUE DES DÉGRADATIONS
--    Non partitionné : une ligne par dégradation, pas par lecture. La date
--    est celle du RELEVÉ qui l'a produite, pas celle de l'envoi (un job peut
--    tourner le lendemain).
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chain_invariant_alertes (
  id                bigserial PRIMARY KEY,
  tenant_id         uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  code              text NOT NULL,
  mesure_le         timestamptz NOT NULL,
  verdict_avant     text NOT NULL,
  verdict_apres     text NOT NULL,
  mesure_avant      numeric,
  mesure_apres      numeric,
  lignes_avant      integer NOT NULL DEFAULT 0,
  lignes_apres      integer NOT NULL DEFAULT 0,
  delta             numeric,
  motif             text NOT NULL,
  notifiee          boolean NOT NULL DEFAULT false,
  created_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chain_invariant_alertes_motif_check CHECK (btrim(motif) <> ''),
  CONSTRAINT chain_invariant_alertes_code_check   CHECK (btrim(code) <> '')
);

-- La clé du garde-fou est (société, code, releve_id) — l'IDENTIFIANT du
-- relevé, pas son horodatage. C'est une correction MESURÉE, pas une
-- préférence : `audit_chains` écrit ses lignes avec le `now()` de la
-- transaction, donc deux passages dans la MÊME transaction partagent le même
-- `mesure_le`. Sur une clé horodatée, le second passage était silencieusement
-- absorbé par `ON CONFLICT DO NOTHING`, et l'aggravation d'un écart déjà
-- signalé n'était jamais notifiée (mesuré : motif `agravement` rendu, 0
-- alerte écrite). L'identifiant, lui, distingue deux relevés même quand ils
-- sont de la même seconde — c'est exactement ce qu'il faut dédupliquer.
--
-- La colonne est ajoutée APRÈS le CREATE TABLE puis la contrainte est reposée :
-- PostgreSQL n'a pas d'ALTER CONSTRAINT sur une UNIQUE, et on ne peut pas
-- déclarer une clé sur une colonne qui n'existe pas encore.

-- `releve_id` désigne la ligne de `chain_invariant_results` comparée : c'est
-- elle qui dit « quel relevé, de quelle seconde ». `ON DELETE CASCADE` : le
-- relevé disparaît, l'alerte qu'il a fondée n'a plus d'objet.
--
-- ⚠️ LA CLÉ ÉTAIT MONO-COLONNE, ET C'ÉTAIT UNE FAUTE (mesuré le 02/10).
--   `REFERENCES chain_invariant_results(id)` ne compare que l'identifiant :
--   une alerte de la société B pouvait donc désigner le relevé de la société A.
--   MESURÉ : l'insertion d'une alerte de SEPT avec un `releve_id` pris chez SIX
--   est ACCEPTÉE, et `alertes_croisees` (tenant_id de l'alerte <> tenant_id du
--   relevé visé) vaut 1. C'est la porte ISO-02 qui l'a dit
--   (`chain_invariant_alertes.releve_id → chain_invariant_results.id`).
--   La clé devient COMPOSITE `(tenant_id, releve_id)` : le lien ne peut plus
--   traverser une société. La cible porte l'UNIQUE `(tenant_id, id)` que la
--   clé composite exige (même forme que `301_project_time_billing.sql`).
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'chain_invariant_results_tenant_id_id_key'
                   AND conrelid = 'public.chain_invariant_results'::regclass) THEN
    ALTER TABLE public.chain_invariant_results
      ADD CONSTRAINT chain_invariant_results_tenant_id_id_key
      UNIQUE (tenant_id, id);
  END IF;
END $$;

ALTER TABLE chain_invariant_alertes
  ADD COLUMN IF NOT EXISTS releve_id bigint;

-- Idempotent : la contrainte mono-colonne tombe d'abord, puis la composite se
-- pose. Un rejeu ne doit jamais laisser les deux.
ALTER TABLE chain_invariant_alertes
  DROP CONSTRAINT IF EXISTS chain_invariant_alertes_releve_id_fkey;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'chain_invariant_alertes_releve_fkey'
                   AND conrelid = 'public.chain_invariant_alertes'::regclass) THEN
    ALTER TABLE public.chain_invariant_alertes
      ADD CONSTRAINT chain_invariant_alertes_releve_fkey
      FOREIGN KEY (tenant_id, releve_id)
      REFERENCES public.chain_invariant_results (tenant_id, id)
      ON DELETE CASCADE;
  END IF;
END $$;

-- `releve_avant_id` suit la même portée : il désigne le relevé PRÉCÉDENT, donc
-- il doit appartenir à la société de l'alerte. Même clé composite.
ALTER TABLE chain_invariant_alertes
  ADD COLUMN IF NOT EXISTS releve_avant_id bigint;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'chain_invariant_alertes_releve_avant_fkey'
                   AND conrelid = 'public.chain_invariant_alertes'::regclass) THEN
    ALTER TABLE public.chain_invariant_alertes
      ADD CONSTRAINT chain_invariant_alertes_releve_avant_fkey
      FOREIGN KEY (tenant_id, releve_avant_id)
      REFERENCES public.chain_invariant_results (tenant_id, id)
      ON DELETE SET NULL;
  END IF;
END $$;

-- Idempotent : sur une base neuve, ou après un rejeu, la contrainte tombe
-- puis se repose sur la même définition.
ALTER TABLE chain_invariant_alertes
  DROP CONSTRAINT IF EXISTS chain_invariant_alertes_releve_uniq;
ALTER TABLE chain_invariant_alertes
  ADD CONSTRAINT chain_invariant_alertes_releve_uniq
  UNIQUE (tenant_id, code, releve_id);

CREATE INDEX IF NOT EXISTS ix_chain_invariant_alertes_societe
  ON chain_invariant_alertes (tenant_id, mesure_le DESC);
CREATE INDEX IF NOT EXISTS ix_chain_invariant_alertes_code
  ON chain_invariant_alertes (tenant_id, code, mesure_le DESC);
CREATE INDEX IF NOT EXISTS ix_chain_invariant_alertes_en_attente
  ON chain_invariant_alertes (created_at) WHERE notifiee = false;

COMMENT ON TABLE chain_invariant_alertes IS
  '414 (L4, tr. 2) : l''historique des dégradations de cohérence — une ligne par invariant perdu ou aggravé, datée par le relevé qui l''a produit. notifiee = false signifie « l''écart est dans le journal, personne n''a encore été prévenu ».';

-- ─────────────────────────────────────────────────────────────
-- 2. RLS activée ET forcée, politique de lecture
--    Le journal se LIT (page « Cohérence »), il ne s'écrit que par la
--    fonction — comme `chain_invariant_results`.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE chain_invariant_alertes ENABLE ROW LEVEL SECURITY;
ALTER TABLE chain_invariant_alertes FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chain_invariant_alertes_select ON chain_invariant_alertes;
CREATE POLICY chain_invariant_alertes_select ON chain_invariant_alertes
  FOR SELECT USING (tenant_id = current_tenant_id());

REVOKE ALL ON TABLE chain_invariant_alertes FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE chain_invariant_alertes TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────
-- 3. LA COMPARAISON D'UN INVARIANT ENTRE DEUX RELEVÉS
--    Le cœur de la tranche. Le « précédent » est le relevé **immédiatement
--    antérieur du même code** — jamais « le dernier mesuré il y a un mois » :
--    une dégradation d'hier est une dégradation d'aujourd'hui.
--
--    Renvoyer une ligne (et non un booléen) parce que la page « Cohérence »
--    doit pouvoir afficher le motif, pas seulement dire « dégradé ».
--
--    STABLE + SECURITY DEFINER : la fonction ne fait que lire, et le job
--    nocturne n'a pas de session utilisateur — donc pas de
--    `current_tenant_id()` : c'est `p_tenant` qui borne la requête.
-- ─────────────────────────────────────────────────────────────
-- Le `DROP` est nécessaire et se dit : la fonction rend désormais deux
-- colonnes de plus (`releve_id`, `releve_avant_id`), et PostgreSQL ne sait pas
-- changer le type de retour d'une fonction existante (`cannot change return
-- type of existing function`). C'est la seule fonction que la 414 remplace
-- ainsi — les deux autres sont créées pour la première fois.
DROP FUNCTION IF EXISTS public.chain_degradation_detectee(uuid, text);
CREATE OR REPLACE FUNCTION public.chain_degradation_detectee(
  p_tenant uuid,
  p_code   text
)
RETURNS TABLE(
  degrade            boolean,
  motif              text,
  verdict_avant      text,
  verdict_apres      text,
  lignes_avant       integer,
  lignes_apres       integer,
  mesure_avant       numeric,
  mesure_apres       numeric,
  mesure_le          timestamptz,
  releve_id          bigint,
  releve_avant_id    bigint
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_avant  record;
  v_apres  record;
  v_motif  text;
  v_role   text := current_user;
BEGIN
  IF p_tenant IS NULL OR btrim(COALESCE(p_code, '')) = '' THEN
    RAISE EXCEPTION 'chain_degradation_detectee : (société, code) sont obligatoires';
  END IF;

  -- ⚠️ GARDE DE SOCIÉTÉ — elle manquait, et la porte `check_tenant_guard`
  --    l'avait dit (mesuré le 02/10 : « chain_degradation_detectee(p_tenant
  --    uuid, p_code text) agissent au nom d'une société sans vérifier que
  --    l'appelant en est membre »).
  --    La fonction est `SECURITY DEFINER` : elle lit
  --    `chain_invariant_results` avec les droits du propriétaire, donc
  --    SANS que la RLS du lecteur ne puisse s'y opposer. Son `p_tenant`
  --    est libre, et la fonction est donnée à `authenticated` (les droits
  --    ci-dessous). Un client pouvait donc passer l'identifiant d'une
  --    AUTRE société et lire son relevé d'invariants.
  --    MESURÉ avant le correctif : le contexte `authenticated` de la
  --    société SEPT appelait `chain_degradation_detectee(<SIX>, 'INV-20')`
  --    et obtenait `degrade = true`, `lignes_apres = 1`, `releve_id = 3015`
  --    — le relevé de SIX. Après : refus.
  --    `service_role` passe : c'est lui qui porte le job nocturne, qui
  --    relève TOUTES les sociétés et doit donc pouvoir les comparer toutes
  --    (cf. `chain_alertes_toutes_societes`).
  IF v_role <> 'service_role' AND p_tenant IS DISTINCT FROM current_tenant_id() THEN
    RAISE EXCEPTION 'chain_degradation_detectee : société % refusée — elle n''est pas celle du contexte', p_tenant
      USING ERRCODE = '42501';
  END IF;

  -- Le relevé à juger : le plus récent pour ce code.
  SELECT * INTO v_apres
    FROM chain_invariant_results r
   WHERE r.tenant_id = p_tenant AND r.code = p_code
   ORDER BY r.mesure_le DESC, r.id DESC
   LIMIT 1;

  -- Pas de relevé : il n'y a rien à dégrader. C'est le cas NORMAL d'une
  -- société neuve, pas une anomalie.
  IF v_apres IS NULL THEN
    RETURN QUERY SELECT false, 'aucun_releve'::text, NULL::text, NULL::text,
                        0, 0, NULL::numeric, NULL::numeric, NULL::timestamptz,
                        NULL::bigint, NULL::bigint;
    RETURN;
  END IF;

  -- Le précédent : même code, strictement avant le relevé à juger.
  SELECT * INTO v_avant
    FROM chain_invariant_results r
   WHERE r.tenant_id = p_tenant AND r.code = p_code
     AND (r.mesure_le, r.id) < (v_apres.mesure_le, v_apres.id)
   ORDER BY r.mesure_le DESC, r.id DESC
   LIMIT 1;

  -- Premier relevé de cet invariant : rien à comparer. Alerter ici enverrait
  -- une notification à CHAQUE société la première nuit où elle est relevée.
  IF v_avant IS NULL THEN
    RETURN QUERY SELECT false, 'premier_releve'::text,
                        NULL::text, v_apres.verdict, 0,
                        v_apres.lignes_en_ecart, NULL::numeric,
                        v_apres.mesure_a, v_apres.mesure_le,
                        v_apres.id, NULL::bigint;
    RETURN;
  END IF;

  -- ── Les trois motifs d'alerte ──────────────────────────────────
  -- 1. `perte` : il était tenu, il ne l'est plus. La dégradation
  --    principale, et la seule qui soit par définition une perte de garantie.
  IF v_avant.verdict = 'tenu' AND v_apres.verdict = 'rompu' THEN
    RETURN QUERY SELECT
      true, 'perte'::text, v_avant.verdict, v_apres.verdict,
      v_avant.lignes_en_ecart, v_apres.lignes_en_ecart,
      v_avant.mesure_a, v_apres.mesure_a, v_apres.mesure_le,
      v_apres.id, v_avant.id;
    RETURN;
  END IF;

  -- 2. `retour_non_mesure` : un invariant non mesurable redevient mesuré ET
  --    rompu. Sans ce motif, un contrôle qui « revient » en se retrouvant
  --    rompu passerait inaperçu — c'est le cas même qu'un non-mesurable
  --    censurait.
  IF v_avant.verdict = 'non_mesure' AND v_apres.verdict = 'rompu' THEN
    RETURN QUERY SELECT
      true, 'retour_non_mesure'::text, v_avant.verdict, v_apres.verdict,
      v_avant.lignes_en_ecart, v_apres.lignes_en_ecart,
      v_avant.mesure_a, v_apres.mesure_a, v_apres.mesure_le,
      v_apres.id, v_avant.id;
    RETURN;
  END IF;

  -- 3. `agravement` : déjà rompu, mais davantage. Un défaut qui s'aggrave
  --    se signale ; un défaut stationnaire, non.
  IF v_apres.verdict = 'rompu' AND v_avant.verdict = 'rompu'
     AND v_apres.lignes_en_ecart > v_avant.lignes_en_ecart THEN
    RETURN QUERY SELECT
      true, 'agravement'::text, v_avant.verdict, v_apres.verdict,
      v_avant.lignes_en_ecart, v_apres.lignes_en_ecart,
      v_avant.mesure_a, v_apres.mesure_a, v_apres.mesure_le,
      v_apres.id, v_avant.id;
    RETURN;
  END IF;

  -- Les cas sans alerte sont NOMMÉS, pas silencieux : une fonction qui
  -- renvoie `false` sans dire pourquoi oblige à la deviner au débogage.
  v_motif := CASE
    WHEN v_avant.verdict = 'rompu' AND v_apres.verdict = 'tenu'
      THEN 'amelioration'          -- le défaut est réparé : on n'alerte pas
    WHEN v_avant.verdict = 'rompu' AND v_apres.verdict = 'rompu'
      THEN 'deja_rompu'            -- stationnaire : on ne répète pas
    WHEN v_avant.verdict = 'tenu' AND v_apres.verdict = 'non_mesure'
      THEN 'devenu_non_mesure'     -- le CONTRÔLE a disparu, pas la garantie
    WHEN v_avant.verdict = 'non_mesure' AND v_apres.verdict = 'non_mesure'
      THEN 'toujours_non_mesure'
    WHEN v_avant.verdict = 'non_mesure'
      THEN 'redevient_mesure'      -- mesurable à nouveau, mais tenu
    ELSE 'stable'
  END;

  RETURN QUERY SELECT
    false, v_motif, v_avant.verdict, v_apres.verdict,
    v_avant.lignes_en_ecart, v_apres.lignes_en_ecart,
    v_avant.mesure_a, v_apres.mesure_a, v_apres.mesure_le,
    v_apres.id, v_avant.id;
END
$fn$;

COMMENT ON FUNCTION public.chain_degradation_detectee(uuid, text) IS
  '414 (L4, tr. 2) : compare le dernier relevé d''un invariant au relevé immédiatement précédent et rend le verdict. degrade = true pour perte / retour_non_mesure / aggravation ; sinon le motif nomme le cas (amelioration, deja_rompu, devenu_non_mesure, premier_releve, aucun_releve, stable…).';

-- ─────────────────────────────────────────────────────────────
-- 4. LE PASSAGE : relever, comparer, alerter
--    L'ordre est imposé par la logique, et il est écrit ici pour que
--    personne ne l'inverse : on relève d'abord, on compare ENSUITE. Comparer
--    avant de relever comparerait le relevé d'aujourd'hui à celui d'hier, et
--    l'écart de la nuit ne serait jamais vu.
--
--    Sur une société : `audit_chains`, puis un `chain_degradation_detectee`
--    par invariant. Une seule écriture par (société, relevé, code) —
--    l'index unique la garantit, `ON CONFLICT DO NOTHING` la rend silencieuse
--    plutôt que fatale : un job rejoué doit être sans effet, pas en erreur.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_alertes_lancer(p_tenant uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_code    text;
  v_d       record;
  v_nb      integer := 0;

BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'chain_alertes_lancer : p_tenant est obligatoire';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM tenants WHERE id = p_tenant) THEN
    RAISE EXCEPTION 'chain_alertes_lancer : société % introuvable', p_tenant;
  END IF;

  -- 1. LE RELEVÉ D'ABORD : ce sont ses lignes que la comparaison va
  --    confronter à celles de la veille.
  PERFORM public.audit_chains(p_tenant);

  -- 2. Puis la comparaison, invariant par invariant.
  FOR v_code IN
    SELECT DISTINCT r.code FROM chain_invariant_results r
     WHERE r.tenant_id = p_tenant ORDER BY 1
  LOOP
    SELECT * INTO v_d
      FROM public.chain_degradation_detectee(p_tenant, v_code) d;

    IF NOT COALESCE(v_d.degrade, false) THEN
      CONTINUE;                      -- rien ne s'est dégradé : pas de ligne
    END IF;

    INSERT INTO chain_invariant_alertes
      (tenant_id, code, mesure_le, verdict_avant, verdict_apres,
       mesure_avant, mesure_apres, lignes_avant, lignes_apres, delta, motif,
       releve_id, releve_avant_id)
    VALUES
      (p_tenant, v_code, v_d.mesure_le, v_d.verdict_avant, v_d.verdict_apres,
       v_d.mesure_avant, v_d.mesure_apres,
       COALESCE(v_d.lignes_avant, 0), COALESCE(v_d.lignes_apres, 0),
       COALESCE(v_d.lignes_apres, 0) - COALESCE(v_d.lignes_avant, 0),
       v_d.motif, v_d.releve_id, v_d.releve_avant_id)
    ON CONFLICT (tenant_id, code, releve_id) DO NOTHING;

    -- `FOUND` est le seul témoin fiable : sous `ON CONFLICT DO NOTHING`,
    -- le `RETURNING` ne rend rien et `GET DIAGNOSTICS` mentirait au lecteur.
    IF FOUND THEN
      v_nb := v_nb + 1;

      -- La notification part APRÈS l'écriture : si elle échoue, l'alerte est
      -- déjà dans le journal, donc l'écart n'est jamais perdu.
      INSERT INTO notifications
        (tenant_id, user_id, category, severity, title, message, link, metadata)
      SELECT p_tenant, tu.auth_id, 'chain_coherence',
             CASE WHEN v_d.motif = 'perte' THEN 'warning' ELSE 'info' END,
             -- Le libellé du registre est une PHRASE (« Toute ligne de paie
             -- variable a une source identifiée ») : le mettre tel quel devant
             -- « ne tient plus » produirait une phrase sans verbe
             -- conjugué. On garde le code, qui est court et non ambigu.
             'Cohérence dégradée — ' || v_code
               || CASE v_d.motif
                    WHEN 'perte' THEN ' : un invariant qui tenait ne tient plus'
                    WHEN 'agravement' THEN ' : l''écart signalé s''est agrandi'
                    ELSE ' : un contrôle redevenu mesurable est rompu'
                  END,
             CASE v_d.motif
               WHEN 'perte' THEN 'Un invariant qui était tenu ne l''est plus.'
               WHEN 'agravement' THEN 'Un écart déjà signalé s''est agrandi.'
               ELSE 'Un contrôle redevenu mesurable est rompu.'
             END,
             '/chain/coherence',
             jsonb_build_object(
               'code', v_code, 'motif', v_d.motif,
               'lignes_avant', COALESCE(v_d.lignes_avant, 0),
               'lignes_apres', COALESCE(v_d.lignes_apres, 0),
               'mesure_avant', v_d.mesure_avant,
               'mesure_apres', v_d.mesure_apres,
               'mesure_le', v_d.mesure_le)
        FROM tenant_users tu
       WHERE tu.tenant_id = p_tenant AND tu.status = 'active'
         AND tu.role IN ('admin', 'owner', 'manager');
    END IF;
  END LOOP;

  RETURN v_nb;
END
$fn$;

COMMENT ON FUNCTION public.chain_alertes_lancer(uuid) IS
  '414 (L4, tr. 2) : le passage d''une société — relève (audit_chains), compare chaque invariant au relevé précédent, écrit une ligne par dégradation et notifie les rôles admin/owner/manager. Rend le nombre d''alertes NOUVELLES : un rejeu rend 0 (index unique (société, code, relevé_id)).';

-- ─────────────────────────────────────────────────────────────
-- 5. Le passage sur TOUTES les sociétés — celui du job nocturne
--    Le job n'a pas de session utilisateur, donc pas de
--    `current_tenant_id()` : chaque société est traitée par son `id`. Une
--    société en erreur n'interrompt pas les autres — une société corrompue ne
--    doit pas priver les autres de leur relevé du matin.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_alertes_toutes_societes()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  t         record;
  v_nb      integer := 0;
  v_erreurs integer := 0;
BEGIN
  FOR t IN SELECT id FROM tenants ORDER BY id LOOP
    BEGIN
      v_nb := v_nb + public.chain_alertes_lancer(t.id);
    EXCEPTION WHEN OTHERS THEN
      v_erreurs := v_erreurs + 1;
      RAISE WARNING 'chain_alertes_lancer : société % en échec — %',
        t.id, left(SQLERRM, 200);
    END;
  END LOOP;

  RAISE NOTICE '414 : alerte de cohérence — % alerte(s) sur % société(s), % en échec.',
    v_nb, (SELECT count(*) FROM tenants), v_erreurs;
  RETURN v_nb;
END
$fn$;

COMMENT ON FUNCTION public.chain_alertes_toutes_societes() IS
  '414 (L4, tr. 2) : le passage sur toutes les sociétés — celui que pose le job nocturne. Une société en échec est comptée et journalisée, elle n''interrompt pas les autres.';

-- ─────────────────────────────────────────────────────────────
-- 6. Droits
--    `chain_alertes_lancer` est donnée au `service_role` comme
--    `audit_chains` : c'est le rôle qui l'exploite (job nocturne, recette).
--    Elle n'est PAS donnée à `authenticated` : déclencher un relevé ET une
--    notification depuis le client serait un levier de déni de service et une
--    source de spam. La COMPARAISON, elle, reste lisible : c'est une lecture
--    du relevé, elle prend les droits d'`authenticated`.
-- ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.chain_degradation_detectee(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_degradation_detectee(uuid, text)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.chain_alertes_lancer(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chain_alertes_lancer(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.chain_alertes_toutes_societes()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chain_alertes_toutes_societes() TO service_role;

-- ─────────────────────────────────────────────────────────────
-- 7. Le job nocturne — élargi, pas dupliqué
--    La 413 pose `audit_chains_nocturne` à 2 h 30. Cette migration
--    AJOUTE `chain_alertes_nocturne` à 5 h 10 — après le relevé, et assez
--    tard pour que la nuit soit terminée. Deux jobs distincts plutôt qu'un
--    seul enchaîné : le relevé doit continuer à tourner même si l'alerte
--    échoue, sinon une notification ratée empêcherait le relevé du matin.
-- ─────────────────────────────────────────────────────────────
DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'chain_alertes_nocturne') THEN
      PERFORM cron.unschedule('chain_alertes_nocturne');
    END IF;
    PERFORM cron.schedule(
      'chain_alertes_nocturne',
      '10 5 * * *',
      $cron$ SELECT public.chain_alertes_toutes_societes() $cron$);
    RAISE NOTICE '414 : job chain_alertes_nocturne posé (5 h 10, après le relevé de 2 h 30).';
  ELSE
    RAISE NOTICE
      '414 : pg_cron absent — le job n''est pas posé. Le relevé ET l''alerte restent produits par tout appel de chain_alertes_lancer(tenant) ou chain_alertes_toutes_societes() (déploiement, recette, service_role).';
  END IF;
END
$do$;

-- ─────────────────────────────────────────────────────────────
-- 8. Ce que cette migration ne fait pas — nommé
--
-- * **Elle n'envoie pas de courriel.** L'alerte écrit dans `notifications`,
--   l'application. Brancher le courriel tient en une ligne dans
--   `notification_email_queue` et un type dans `email_types` — c'est un
--   choix de produit, pas un oubli technique.
-- * **Elle ne corrige aucun écart.** Elle les SIGNALE. La correction est la
--   phase D (R-001 → R-062), comme le disait déjà la 413.
-- * **Elle ne répète pas un écart déjà rompu et stationnaire.** Le motif
--   `deja_rompu` est écrit, sans notification : répéter la même alerte chaque
--   nuit serait du bruit, et un bruit s'éteint.
-- * **Elle n'atteint pas la page « Cohérence »** (lot L5) : cette migration
--   n'apporte que la matière, l'historique des alertes.
-- ═══════════════════════════════════════════════════════════════════════════
