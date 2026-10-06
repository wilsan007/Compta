-- ═══════════════════════════════════════════════════════════════════════════
-- 750 — L16 · le chaînage interne de la PRODUCTION : le DÉMARRAGE de l'OF cesse
--       d'être muet
-- ═══════════════════════════════════════════════════════════════════════════
-- Numéro pris via migration-numero.mjs (ligne « plan6 A3 L16 (familles
-- restantes) », branche plan6/a3-l16-production). La plage `493` → `499` de la
-- ligne A3 était saturée, d'où la plage dédiée `750` → `759`, inscrite au
-- registre dans le même commit que cette première migration.
--
-- Le référentiel (§B.3) décrit le chaînage interne de la Production — « OF ↔
-- nomenclature ↔ consommation ↔ rebuts ↔ PF ↔ coût ↔ marge par OF » — et nomme
-- le tronçon manquant : « partiel : rebuts corrigés (229), multi-niveaux absent,
-- **`in_progress` muet (`R-044`)** ».
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve, 333 migrations) :
--   * `manufacturing_orders.status` admet bien `in_progress` (CHECK : planned,
--     in_progress, completed, cancelled) — l'état EXISTE ;
--   * **un** maillon existe déjà sur cette table, `zz_l1_manufacturing_order`
--     (401), et il ne traite QUE l'arrivée à `completed` : deux effets
--     (`production.order.generated_entry`, `production.order.stock_in`) et un
--     événement `manufacturing_orders.completed`. Le passage à `in_progress`
--     n'apparaît nulle part : personne n'est prévenu qu'un OF a démarré ;
--   * **aucune** fonction ne lie une réservation de stock à un OF
--     (`stock_reservations.reference_type` existe, mais rien ne l'écrit pour la
--     production) : il n'y a donc **aucun document d'aval** à lier au démarrage.
--     C'est ce qui décide la forme du maillon ci-dessous — et dit franchement
--     ce qu'il n'est pas.
--
-- CE QUE CE FICHIER POSE : le contrat d'effet `production.order.started` et le
-- maillon `chain_l16_production_start` — un déclencheur `AFTER UPDATE`, donc il
-- couvre tous les chemins de démarrage (écran, import, RPC).
--
-- ⚠️ CE MAILLON TRACE ET ANNONCE ; IL NE LIE RIEN, ET LE DIT. Sans aval réel,
-- inventer un lien (l'OF vers lui-même, ou vers une réservation qui n'existe
-- pas) produirait une frise qui MENT. La doctrine du socle est explicite : « la
-- base fait foi ; un maillon qui ne pose pas son lien reste muet ». Ici l'effet
-- est une ANNONCE (`manufacturing_orders.started`), et c'est tout.
--
-- ⚠️ ET L'IDEMPOTENCE EST EXPLICITE, POUR LA MÊME RAISON MESURÉE QUE LA 496 :
-- `chain_deja_fait` du socle détecte le rejeu par `document_links` ; faute de
-- lien, c'est l'ANNONCE qui atteste que l'effet a eu lieu — et le rejeu est DIT
-- (trace « ignore »).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
-- Le type `manufacturing_orders` est DÉJÀ au registre (450) : rien à ajouter.
-- Le contrat, lui, manque — et il dit ce que l'effet EST, y compris qu'il
-- n'écrit aucune comptabilité (le coût se reporte à la CLÔTURE de l'OF, pas à
-- son démarrage : c'est la règle du maillon L1, et on ne la double pas).
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'manufacturing_orders', 'in_progress', 'production.order.started', false, NULL,
       false, false, true, true, true,
       'L16/750 : le DÉMARRAGE d''un ordre de fabrication est TRACÉ et annoncé (événement manufacturing_orders.started). Aucun effet de stock ni d''écriture : les composants ne sont pas réservés par ce maillon (aucune fonction ne le fait aujourd''hui) et le coût se reporte à la clôture (maillon L1 de la 401). Réversible : un OF remis à « planned » puis redémarré ne rejoue pas l''annonce.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'manufacturing_orders' AND evenement = 'in_progress' AND effet = 'production.order.started'
);

-- ── 2. Le MAILLON : `chain_l16_production_start` ───────────────────────────
-- Un déclencheur AFTER UPDATE sur la MÊME table que le maillon L1 de la 401,
-- mais sur une AUTRE transition : eux `completed`, lui `in_progress`. Aucun des
-- deux ne recouvre l'autre (vérifié : le L1 ne teste que 'completed').
CREATE OR REPLACE FUNCTION public.chain_l16_production_start()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
BEGIN
  -- 1. Le seul fait qui compte : le statut VIENT de passer à 'in_progress'.
  IF NEW.status <> 'in_progress' OR NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NULL;
  END IF;

  -- 2. IDEMPOTENCE EXPLICITE — même raison MESURÉE que la 496 : `chain_deja_fait`
  --    du socle détecte le rejeu par `document_links`, et ce maillon ne lie rien
  --    (aucun aval réel, cf. l'en-tête). C'est l'ANNONCE qui atteste l'effet, et
  --    le rejeu est DIT (trace « ignore »).
  IF EXISTS (
    SELECT 1 FROM domain_events de
    WHERE de.tenant_id = NEW.tenant_id
      AND de.event_name = 'manufacturing_orders.started'
      AND de.aggregate_id = NEW.id
  ) THEN
    PERFORM chain_trace(NEW.tenant_id, 'production.order.started', 'manufacturing_orders', NEW.id,
                        0, 0, NULL, 'ignore', 'Démarrage déjà annoncé — rejeu sans effet.', NULL);
    RETURN NULL;
  END IF;

  -- 3. ENTRÉE du maillon — rejeu (traité au point 2), puis contrat.
  IF NOT chain_avant(NEW.tenant_id, 'manufacturing_orders', 'in_progress',
                     'production.order.started', 'manufacturing_orders', NEW.id, NULL,
                     format('Ordre de fabrication %s : le démarrage n''a pas été annoncé (règle production.order.started, module production).', NEW.number)) THEN
    RETURN NULL;
  END IF;

  -- 4. L'ÉVÉNEMENT — la pièce que lisent les automatisations et les webhooks
  --    (I-06), et ce qui rend le démarrage visible sans relire l'état.
  PERFORM emit_domain_event(
    NEW.tenant_id, 'manufacturing_orders.started', 'manufacturing_orders', NEW.id,
    jsonb_build_object('number', NEW.number, 'product_id', NEW.product_id,
                       'quantity', NEW.quantity, 'start_date', NEW.start_date),
    NULL);

  -- 5. LA MESURE (§3.4) — un maillon d'annonce, budget ≤ 50 ms.
  PERFORM chain_apres(NEW.tenant_id, 'production.order.started', 'manufacturing_orders', NEW.id,
                      v_debut, 1, 'applique', NULL);
  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l16_production_start() IS
  'L16/750 : maillon du démarrage d''un ordre de fabrication — l''état « in_progress » cesse d''être muet (R-044). Trace (chain_apres « applique ») et annonce (manufacturing_orders.started). Ne lie AUCUN document : aucun aval réel n''existe aujourd''hui (rien ne réserve les composants d''un OF) — inventer un lien ferait mentir la frise.';

DROP TRIGGER IF EXISTS zz_l16_production_start ON manufacturing_orders;
CREATE TRIGGER zz_l16_production_start
  AFTER UPDATE ON manufacturing_orders
  FOR EACH ROW EXECUTE FUNCTION public.chain_l16_production_start();

REVOKE ALL ON FUNCTION public.chain_l16_production_start() FROM PUBLIC, anon, authenticated;
-- Numéro pris le 2026-10-06T06:40:01.547Z par migration-numero.mjs (ligne « plan6 A3 L16 (familles restantes) », branche plan6/a3-l16-production).
