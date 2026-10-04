-- ============================================================
-- 415_chain_l23_evenements.sql — L23 (tranche 1) : LE JOURNAL
--   D'ÉVÉNEMENTS UNIFIÉ — un pont, un vocabulaire, une file
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md
-- §5 Phase F, lot **L23** — « journal unique + automatisations + webhooks
-- branchés sur les MÊMES événements » (I-06). Dépendances du lot : **L0**
-- (socle ✅, 252) et **L2** (portes CI ✅) — c'est le premier lot de
-- l'horizon L16 → L24 dont les dépendances sont livrées, et c'est un
-- prérequis de L22 (moteur de règles) et L24 (explicabilité, assistant).
--
-- LE DÉFAUT, MESURÉ SUR BASE NEUVE (272 migrations, 0 erreur), et c'est
-- lui qui justifie cette migration — pas une intuition :
--
--   1. **Aucun événement n'atteint jamais la file de livraison.** Le socle
--      écrit 27 événements dans `domain_events` (252, puis les maillons
--      400 → 412) ; l'Edge Function `outgoing-webhooks` consomme
--      `webhook_delivery_queue` par `claim_webhook_batch()` (234). Entre
--      les deux : **rien**. Mesuré : 0 fonction n'insère dans
--      `webhook_delivery_queue` depuis `domain_events`.
--
--   2. **Les deux seules sources historiques écrivent dans le journal des
--      envois, pas dans la file.** `notify_webhook_invoice_created` et
--      `notify_webhook_invoice_paid` insèrent dans
--      `webhook_delivery_logs` — la table où l'Edge Function consigne ce
--      qu'elle a ENVOYÉ, après coup, avec `endpoint_id = NULL`. Un client
--      abonné à `invoice.created` ne recevait rien : sa promesse était
--      journalisée comme si elle avait été tenue.
--
--   3. **Deux vocabulaires disjoints.** Le catalogue
--      `webhook_event_catalog` promettait 15 événements dont **13 sans
--      aucun producteur** — dont `manufacturing_order.completed`, dont le
--      nom réellement produit est `manufacturing_orders.completed` (le
--      singulier n'existe nulle part). Et les 27 producteurs réels
--      étaient tous invisibles du client.
--
-- CE QUE CETTE MIGRATION POSE (la doctrine du plan §3.2 : écrire une
-- fois, utiliser partout) :
--
--   * `chain_l23_enfiler(event_id)` — LE PONT. Il lit l'événement dans le
--     journal, et pour chaque point de livraison actif de **la société de
--     l'événement** abonné (liste explicite, `*`, ou vide), enfile UNE
--     livraison. Idempotence STRUCTURELLE : un index unique
--     `(tenant, point, source)` — rejouer rend 0, jamais un `IF` recopié.
--   * `zz_l23_webhook_fanout` — déclencheur `AFTER INSERT` sur
--     `domain_events`. Le pont ne peut pas être contourné par un maillon
--     qui émettrait « à la main » : tant que l'événement passe par le
--     journal, la livraison part.
--   * Les **deux déclencheurs historiques parlent désormais le même
--     langage** : ils émettent `invoice.created` / `invoice.paid` par
--     `emit_domain_event` (l'API du socle), donc ils passent par le pont
--     comme tout le monde. Leurs noms sont conservés — une intégration
--     existante ne change rien à son abonnement.
--   * Le **catalogue devient vrai** : les 29 événements réellement
--     produits sont déclarés actifs (27 du socle + les 2 historiques), et
--     les 13 promesses mortes sont éteintes — pas supprimées : éteintes,
--     avec leur raison écrite, pour que l'écran qui les liste ne mente
--     plus. Réactivables le jour où un producteur existera.
--   * Un **abonnement à un événement inexistant est refusé** (garde
--     `BEFORE INSERT OR UPDATE` sur `webhook_endpoints`) : c'est la
--     règle d'urbanisme §E.5, appliquée aux événements — la faute de
--     configuration invisible devient un refus nommé.
--   * `webhook_delivery_queue` passe sous **FORCE ROW LEVEL SECURITY**
--     (mesuré : elle était la seule table de la chaîne des webhooks sans
--     le FORCÉ, §3.5 l'exige).
--
-- POURQUOI LE PONT EST UN DÉCLENCHEUR ET PAS UN APPEL DANS
-- `emit_domain_event`. Trois raisons, mesurables :
--   * il attrape TOUT producteur, y compris ceux qui écriraient demain
--     directement dans le journal (le déclencheur est le seul point que
--     personne ne peut oublier d'appeler) ;
--   * il ne change pas la signature ni le contrat d'`emit_domain_event`
--     (25 maillons l'appellent déjà) ;
--   * une erreur du pont ne peut pas faire échouer l'émission de
--     l'événement métier : le déclencheur est dans la même transaction,
--     donc il PEUT — et c'est voulu : une livraison qui ne part pas alors
--     qu'elle est promise est un défaut qui doit se voir (§4.1 point 6).
--
-- REJOUABLE : contrats par `ON CONFLICT` (clé de la 252), fonctions par
-- `CREATE OR REPLACE`, index `IF NOT EXISTS`, déclencheurs `DROP IF
-- EXISTS` avant `CREATE`. Le catalogue est **convergent** : un `ON
-- CONFLICT DO UPDATE` par événement.
--
-- ⚠️ NON-RÉGRESSION : les deux déclencheurs historiques ne touchent plus
-- `webhook_delivery_logs` ; cette table reste le journal des envois
-- (écrite par l'Edge Function, W6), et les suites 234/236/257/270 qui la
-- lisent ne changent pas. La suite **234 T01** insère elle-même dans la
-- file avec `event = 'invoice.created'` et `payload` sans source : la clé
-- unique du pont est PARTIELLE par nature (l'expression est NULL pour ces
-- lignes), elle ne les voit pas.
-- ============================================================
-- ─────────────────────────────────────────────────────────────
-- 1. LE CONTRAT D'EFFET — déclaré ici, comme la porte G2 l'exige.
--    Le pont n'est pas un maillon métier (il ne produit ni écriture, ni
--    stock, ni paie), mais il a un effet aval réel : la livraison promise.
--    Sa NON-réversibilité est DÉCLARÉE avec son motif (§4.1, point 4) :
--    une livraison enfilée ne se « défile » pas.
-- ─────────────────────────────────────────────────────────────
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'domain_events', 'created', 'event.webhook.enqueued',
        false, NULL, false, false,
        false, false, true,
        'L23/415 : le pont domain_events → webhook_delivery_queue. NON RÉVERSIBLE, motif : une livraison enfilée n''a pas d''effet inverse — la retirer de la file reviendrait à faire disparaître un envoi promis, et le destinataire ne saurait jamais qu''on le lui a retiré. Le refus d''envoi, lui, reste TRACÉ par le statut « blocked » de la file (garde SSRF) : rien ne disparaît en silence. Le point 4 de §4.1 exige que cette absence d''inverse soit dite, pas subie.')
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 2. LA CLÉ D'IDEMPOTENCE — structurelle, pas un `IF` recopié.
--    `(société, point, source)` : le même événement vers le même point ne
--    peut exister qu'une fois. L'expression est NULL pour les lignes
--    écrites par l'Edge Function (pas de source) : elles ne se voient pas
--    entre elles, c'est le comportement actuel, préservé.
-- ─────────────────────────────────────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS uq_webhook_queue_source_event
  ON webhook_delivery_queue (tenant_id, endpoint_id, (payload ->> 'source_event_id'));

-- ─────────────────────────────────────────────────────────────
-- 3. LE PONT — une fonction, un seul chemin, écrit une fois.
--    L'isolation (§4.1 point 7) : le `tenant_id` vient de L'ÉVÉNEMENT,
--    jamais de la session — c'est ce que la suite 415 T04 prouve, en
--    posant le contexte sur B et en émettant pour A.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION chain_l23_enfiler(p_event_id bigint)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_event record;
  v_ins   integer;
BEGIN
  -- Un identifiant inconnu n'enfile rien : ce n'est pas une erreur, c'est
  -- le cas ordinaire d'un journal vidé par la rétention (24 mois, §3.3).
  SELECT * INTO v_event FROM domain_events WHERE id = p_event_id;
  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  -- Cloisonnement fermé : un événement sans société n'entre pas dans la
  -- chaîne (même garde que emit_domain_event, 252).
  IF v_event.tenant_id IS NULL THEN
    RETURN 0;
  END IF;

  -- LE FANOUT. Un seul INSERT…SELECT (§3.3 : zéro N+1), pour chaque point
  -- actif de la société DE L'ÉVÉNEMENT abonné à l'événement — ou à tout,
  -- ou sans filtre (NULL et vide = tout, ce que fait déjà l'Edge Function
  -- outgoing-webhooks ligne 417 : « activeEvents.length > 0 &&… »).
  INSERT INTO webhook_delivery_queue
    (tenant_id, endpoint_id, url, event, event_name, payload, secret,
     status, attempts, next_attempt_at)
  SELECT
    v_event.tenant_id,
    e.id,
    e.url,
    v_event.event_name,
    v_event.event_name,
    jsonb_build_object(
      'source_event_id', p_event_id,
      'event',           v_event.event_name,
      'entity_type',     v_event.aggregate_type,
      'entity_id',       v_event.aggregate_id,
      'occurred_at',     v_event.created_at,
      'data',            v_event.payload),
    COALESCE(e.secret, ''),
    'pending',
    0,
    now()
  FROM webhook_endpoints e
  WHERE e.tenant_id = v_event.tenant_id   -- l'isolation : la société de l'ÉVÉNEMENT
    AND COALESCE(e.active, false)
    AND (e.active_events IS NULL
         OR jsonb_array_length(e.active_events) = 0
         OR e.active_events ? '*'
         OR e.active_events ? v_event.event_name)
  ON CONFLICT (tenant_id, endpoint_id, (payload ->> 'source_event_id')) DO NOTHING;

  GET DIAGNOSTICS v_ins = ROW_COUNT;
  RETURN v_ins;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 4. LE DÉCLENCHEUR — le pont ne peut pas être contourné. Tout ce qui
--    entre dans le journal est fanouté, quel que soit l'appelant. La
--    fonction du déclencheur ne fait QUE déléguer : la logique vit dans
--    `chain_l23_enfiler`, appelable aussi pour un rejeu explicite (T02).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION chain_l23_fanout()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM chain_l23_enfiler(NEW.id);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS zz_l23_webhook_fanout ON domain_events;
CREATE TRIGGER zz_l23_webhook_fanout
  AFTER INSERT ON domain_events
  FOR EACH ROW EXECUTE FUNCTION chain_l23_fanout();
-- ─────────────────────────────────────────────────────────────
-- 5. LES DEUX DÉCLENCHEURS HISTORIQUES PARLENT LE MÊME LANGAGE.
--    Avant : ils écrivaient dans `webhook_delivery_logs` (le journal des
--    envois, écrit APRÈS coup par l'Edge Function) avec `endpoint_id =
--    NULL` — la promesse était consignée, l'envoi ne partait jamais.
--    Maintenant : ils émettent par `emit_domain_event`, l'API du socle,
--    et le pont les enfile comme tout le monde. Les NOMS d'événements
--    sont conservés — une intégration existante ne change rien.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION notify_webhook_invoice_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- L23/415 : la facture naît. Un seul chemin désormais — l'événement
  -- domaine, fanouté vers les points abonnés (chain_l23_enfiler). La table
  -- `webhook_delivery_logs` reste le JOURNAL des envois : c'est l'Edge
  -- Function qui l'écrit, après avoir livré, et ce n'est pas une file.
  IF NEW.tenant_id IS NULL THEN
    RETURN NEW;
  END IF;
  PERFORM emit_domain_event(NEW.tenant_id, 'invoice.created', 'invoices', NEW.id,
    jsonb_build_object('number', NEW.number, 'total', NEW.total,
                       'customer_id', NEW.customer_id,
                       'payment_state', NEW.payment_state), NULL);
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION notify_webhook_invoice_paid()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.tenant_id IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.payment_state = 'paid' AND OLD.payment_state IS DISTINCT FROM 'paid' THEN
    PERFORM emit_domain_event(NEW.tenant_id, 'invoice.paid', 'invoices', NEW.id,
      jsonb_build_object('number', NEW.number, 'total', NEW.total,
                         'customer_id', NEW.customer_id), NULL);
  END IF;
  RETURN NEW;
END $$;
-- ─────────────────────────────────────────────────────────────
-- 6. LE CATALOGUE DEVIENT VRAI — les 29 événements réellement produits
--    sont déclarés ACTIFS. Chaque description dit ce que l'événement
--    signifie et ce que porte le payload, parce qu'un catalogue sans
--    description est une liste, pas une promesse vérifiable.
--    Le `ON CONFLICT DO UPDATE` rend la migration rejouable ET
--    convergente : rejouer ne double pas, il réaffirme.
-- ─────────────────────────────────────────────────────────────
INSERT INTO webhook_event_catalog (event_name, description, category, is_active)
VALUES
  -- ── ventes ──
  ('invoices.validated', 'Une facture de vente passe du brouillon à l''état validé : son écriture comptable (journal VT) est née. Payload : entry_id, total.', 'sales', true),
  ('credit_notes.validated', 'Un avoir client est validé : il corrige la facture d''origine, sa sortie du CA et son écriture sont nées. Payload : entry_id, total.', 'sales', true),
  ('sales_orders.confirmed', 'Une commande client est confirmée : ses réservations de stock sont posées, par ligne. Payload : reservations, lines.', 'sales', true),
  ('delivery_notes.shipped', 'Un bon de livraison est expédié : sortie de stock par ligne et dépôt, réservations consommées. Payload : lines, warehouse_id.', 'sales', true),
  ('invoice.created', 'Une facture de vente est créée (nom historique conservé pour les intégrations existantes). Payload : number, total, customer_id.', 'sales', true),
  ('invoice.paid', 'Une facture de vente passe à l''état payé (nom historique conservé pour les intégrations existantes). Payload : number, total.', 'sales', true),
  ('project_time_entries.billed', 'Un temps projet est facturé : sa ligne de facture est née (unicité société/temps). Payload : invoice_id, line_id, hours, amount.', 'projects', true),
  -- ── achats ──
  ('purchase_invoices.approved', 'Une facture d''achat est approuvée : sa charge et sa TVA entrent au journal (AC) et son élément de paie éventuel est posé. Payload : entry_id, payroll_element_id.', 'purchases', true),
  ('goods_receipts.received', 'Une réception de marchandise est reçue : entrée en stock à son coût, par ligne, dépôt d''origine. Payload : mouvements, warehouse_id, purchase_order_id.', 'purchases', true),
  -- ── trésorerie ──
  ('customer_payments.recorded', 'Un encaissement client est enregistré : son écriture de règlement est née et le lettrage l''a rattaché à sa facture. Payload : entry_id, invoice_ids.', 'banking', true),
  ('customer_payments.exchange_gain_loss_posted', 'Un règlement en devise produit un écart de change constaté au jour du règlement. Payload : gain_loss_amount, currency.', 'banking', true),
  ('supplier_payments.recorded', 'Un décaissement fournisseur est enregistré : son écriture est née et la dette est apurée. Payload : entry_id, invoice_ids.', 'banking', true),
  ('bank_transactions.matched', 'Une ligne de relevé bancaire est appariée à son règlement. Payload : payment_id, amount.', 'banking', true),
  ('bank_transactions.reconciled', 'Une ligne de relevé crédit est rapprochée : l''encaissement correspondant est né. Payload : payment_id, amount, reference.', 'banking', true),
  ('bank_accounts.ledger_attached', 'Un compte bancaire est rattaché à son compte comptable 512x et son journal. Payload : journal_code, account_code.', 'banking', true),
  -- ── paie / RH ──
  ('pay_runs.reversed', 'Un lot de paie comptabilisé est annulé : sa contrepassation est née (PAYROLL-REV-<numéro>). Payload : reversal_entry_id.', 'hr', true),
  ('pay_runs.pay_recalls_integrated', 'Les rappels de paie d''un lot sont intégrés : leurs éléments de paie et écritures sont nés, par document. Payload : rappels, elements.', 'hr', true),
  ('pay_runs.salary_advances_deducted', 'Les acomptes d''un lot sont déduits : leurs retenues sont posées. Payload : acomptes, elements.', 'hr', true),
  ('expense_reports.approved', 'Une note de frais est approuvée : son écriture OD (charge + TVA + compte fournisseur) ET son élément de paie sont nés. Payload : entry_id, payroll_element_id.', 'hr', true),
  -- ── production ──
  ('manufacturing_orders.completed', 'Un ordre de fabrication est terminé : ses entrées de produit fini, son coût et son écriture de stock sont nés. Payload : entry_id, movements, cost_variance.', 'production', true),
  ('st_shipments.shipped', 'Un envoi de sous-traitance part : ses composants sortent du stock, par ligne. Payload : lines, movements.', 'production', true),
  ('st_receipts.received', 'Une réception de sous-traitance est reçue : son produit fini entre au coût matière + façon. Payload : movements, total_cost.', 'production', true),
  -- ── caisse ──
  ('pos_tickets.created', 'Un ticket de caisse est créé : sa sortie de stock et ses paiements sont nés. Payload : movements, payments.', 'pos', true),
  ('pos_tickets.refunded', 'Un ticket de caisse est remboursé : son avoir commercial et la rentrée de stock sont nés. Payload : credit_note_id, movements.', 'pos', true),
  ('pos_sessions.closed', 'Une session de caisse est clôturée : son écriture de clôture (recette par mode de paiement) est née. Payload : entry_id, mouvements_stock.', 'pos', true),
  -- ── chaîne (socle) ──
  ('chain.enforcement_changed', 'Le mode d''application des chaînages d''une société change (observe, avertit, refuse). Payload : mode.', 'chain', true),
  ('chain.regenerated', 'Un effet de chaîne a été régénéré (cause : taux, compte, prix de revient, diviseur…). Payload : effet, cause, regeneration_id.', 'chain', true),
  ('chain.link_broken', 'Un lien de chaîne est rompu : l''effet aval a été retiré ou contre-passé. Payload : effet, motif.', 'chain', true),
  ('chain.link_superseded', 'Un lien de chaîne est remplacé par un nouveau tour : l''ancien reste lisible pour l''historique. Payload : effet, tour.', 'chain', true)
ON CONFLICT (event_name) DO UPDATE
SET description = EXCLUDED.description,
    category    = EXCLUDED.category,
    is_active   = true;
-- ─────────────────────────────────────────────────────────────
-- 7. LES PROMESSES MORTES SONT ÉTEINTES — pas supprimées.
--    13 événements du catalogue n'avaient AUCUN producteur : un client
--    qui s'y abonnait ne recevait rien, pour toujours, sans un signe.
--    Ils restent listés (une intégration peut les référencer), mais
--    `is_active = false` et la RAISON est écrite — l'écran qui liste le
--    catalogue ne peut plus mentir. Réactivables le jour où un
--    producteur existera : il suffira de repasser la ligne active dans
--    le même commit que le producteur (la suite 415 T05 l'exige).
-- ─────────────────────────────────────────────────────────────
UPDATE webhook_event_catalog
SET is_active = false,
    description = CASE event_name
      WHEN 'manufacturing_order.completed'
        THEN 'Éteint le 02/10/2026 (415) : AUCUN producteur ne l''émettait — le nom réellement produit est « manufacturing_orders.completed » (pluriel). Un abonnement ici ne recevait rien. Abonnez-vous au nom pluriel.'
      ELSE 'Éteint le 02/10/2026 (415) : AUCUN producteur ne l''émettait — un abonnement ici ne recevait rien, sans un signe. La ligne reste pour mémoire (une intégration peut la référencer) et sera réactivée le jour où un producteur existera.'
    END
WHERE event_name IN (
        'customer.created', 'customer.updated', 'dsn.transmitted',
        'invoice.overdue', 'journal_entry.posted',
        'manufacturing_order.completed', 'payment.received',
        'payslip.created', 'payslip.validated',
        'purchase_order.confirmed', 'stock.low',
        'supplier.created', 'vat_return.submitted')
  AND COALESCE(is_active, true);

-- ─────────────────────────────────────────────────────────────
-- 8. LA GARDE D'ABONNEMENT — la règle d'urbanisme §E.5, appliquée.
--    S'abonner à un événement qui n'existe pas est une faute de
--    configuration INVISIBLE : le client croirait attendre une facture
--    et ne recevrait rien, pour toujours. La base refuse, et le message
--    NOMME l'événement et la règle (§4.1 point 6).
--    `NULL` et `[]` passent : sans filtre, l'Edge Function livrait déjà
--    tout — on garde ce comportement, on ne le durcit pas en silence.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION webhook_guard_abonnement()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_inconnu text;
BEGIN
  IF NEW.active_events IS NULL OR jsonb_typeof(NEW.active_events) <> 'array' THEN
    RETURN NEW;
  END IF;

  SELECT string_agg(e, ', ' ORDER BY e) INTO v_inconnu
  FROM jsonb_array_elements_text(NEW.active_events) AS e
  WHERE e <> '*'
    AND NOT EXISTS (SELECT 1 FROM webhook_event_catalog c
                     WHERE c.event_name = e
                       AND COALESCE(c.is_active, true));

  IF v_inconnu IS NOT NULL THEN
    RAISE EXCEPTION 'Abonnement webhook refusé : l''événement « % » n''existe pas au catalogue des événements du module webhook (règle d''urbanisme du socle des chaînages : un point de livraison ne peut s''abonner qu''à un événement réellement produit). Choisissez un événement actif du catalogue.', v_inconnu
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS webhook_guard_abonnement ON webhook_endpoints;
CREATE TRIGGER webhook_guard_abonnement
  BEFORE INSERT OR UPDATE OF active_events ON webhook_endpoints
  FOR EACH ROW EXECUTE FUNCTION webhook_guard_abonnement();

-- ─────────────────────────────────────────────────────────────
-- 9. LA FILE PASSE SOUS FORCE ROW LEVEL SECURITY — §3.5.
--    Mesuré avant : `webhook_delivery_queue` était RLS activée mais NON
--    forcée, seule table de la chaîne des webhooks dans ce cas (les points
--    et le journal sont forcés). Le plafond daté de la porte G1
--    (`rls_sans_force`, 55) est réinscrit dans le même commit : il
--    descend à 54, c'est une amélioration, et elle s'inscrit.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE webhook_delivery_queue FORCE ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────────────────────
-- 10. LES TROIS FONCTIONS NE SONT EXPOSÉES À PERSONNE.
--     Défaut vu par la porte `check_anon_grants` : une fonction créée l'est
--     avec EXECUTE pour PUBLIC — un visiteur NON connecté pouvait appeler
--     `chain_l23_enfiler`. Ces fonctions sont internes au socle : le pont
--     vit dans le déclencheur (propriétaire de la table), la garde dans le
--     BEFORE de `webhook_endpoints`. Même convention que la 410
--     (`chain_l3_*_cancel_liens`) : REVOKE total, le propriétaire suffit.
--     La porte l'avait mesuré AVANT le commit — c'est son rôle.
-- ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.chain_l23_enfiler(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.chain_l23_fanout() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.webhook_guard_abonnement() FROM PUBLIC, anon, authenticated;
