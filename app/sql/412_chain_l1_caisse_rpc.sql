-- ============================================================
-- 322_chain_l1_caisse_rpc.sql — L3 (tranche 2) : LA CAISSE, TRACÉE PAR SON
--   CHEMIN D'APPEL — les deux premiers maillons RPC de l'inventaire
--
-- Source : doc/audit/INVENTAIRE-CHAINAGES-L1-TRANCHE4-2026-09-30.md §2 —
--   | #  | Fonction           | Modules écrits        | Verdict             |
--   | 3  | pos_refund_ticket  | commercial, stock, tré| Maillon / RPC — L3  |
--   | 14 | create_pos_ticket  | stock, trésorerie     | Maillon / RPC — L3  |
-- et l'état que la 316 écrivait en toutes lettres : « elle ne traite pas les
-- neuf maillons RPC (caisse, paie versée, relevé manuel) : un compagnon ne
-- peut pas s'accrocher à un appel de fonction — c'est la tranche suivante ».
-- C'est cette tranche. La caisse d'abord : le référentiel la nomme « le plus
-- complet du produit » (§340 : ticket ↔ session ↔ clôture ↔ écart ↔ TVA ↔
-- stock ↔ journal NF-525), et ses deux maillons sont les seuls de la liste à
-- écrire dans le stock ET la trésorerie depuis un APPEL.
--
-- LA DÉCISION D'INGÉNIERIE : LE CORPS EST RENOMMÉ, PAS RECOPIÉ.
--   Un maillon RPC se tracent « par son chemin d'appel » (316) : l'entrée, le
--   lien et la mesure doivent vivre DANS l'appel. Deux voies s'offraient :
--     * recopier le corps pour y insérer les appels — la 310 l'interdit hors
--       correspondance ligne → ligne (319) : « recopier un corps est le chemin
--       le plus court vers une régression silencieuse » ;
--     * RENOMMER le corps (`create_pos_ticket` → `create_pos_ticket_inner`,
--       `ALTER FUNCTION … RENAME TO` — le corps, les droits et SECURITY
--       DEFINER sont préservés, rien n'est recopié) et poser un WRAPPER
--       porteur du nom, qui appelle le corps puis tisse la chaîne.
--   La deuxième voie est celle du dépôt : la 224 l'a déjà empruntée
--   (`payroll.pay` → `payroll_payment_inner`), et le lecteur du front ne
--   change pas (l'écran appelle toujours `.rpc('create_pos_ticket')` —
--   `check-rpc-contract` reste confronté au même nom).
--
-- L'ENTRÉE EST POSÉE APRÈS LE CORPS, ET C'EST ÉQUIVALENT — DIT ET MESURÉ.
--   `chain_avant` décide de produire : dans un déclencheur réécrit (311), il
--   peut être posé AVANT l'effet. Ici le corps est intact, donc l'entrée est
--   posée après lui — et c'est la TRANSACTION DE L'APPEL qui rend la chose
--   équivalente : un appel PostgREST est UNE transaction ; en mode `refuse`,
--   l'entrée LÈVE, et rien ne persiste — ni ticket, ni mouvement, ni paiement,
--   ni lien (suite 322 T06). La limite est celle de la 252 §5, déjà dite : la
--   trace `refuse` elle-même ne survit pas au rollback.
--   Et la garde d'inaltérabilité de la 250 n'est pas contournée : elle
--   distingue l'appel direct de l'écriture métier par `current_user`
--   (SECURITY INVOKER côté déclencheur), PAS par le nom de la fonction — le
--   wrapper est SECURITY DEFINER comme le corps renommé, `current_user` y est
--   le propriétaire (mesuré par la suite 250 rejouée).
--
-- LES EFFETS TRACÉS — et leurs clés, mesurées dans le corps de chacun :
--   * `pos.ticket.stock_out`  — `create_pos_ticket` sort le stock, agrégé PAR
--     PRODUIT (281, M7) : la correspondance ligne → mouvement ne se devine
--     pas (N lignes d'un même produit → UN mouvement). Doctrine de la 316
--     pour les effets N:1 : lien au NIVEAU DU DOCUMENT vers l'aval de plus
--     petit identifiant, les identifiants et le décompte au payload
--     (`lien_par_ligne = false`) ;
--   * `pos.ticket.payment`    — le paiement du ticket (`pos_payments`), lien
--     `paid_by` : la trésorerie entre dans la chaîne (le module que
--     l'inventaire mesure) ;
--   * `pos.ticket.refunded`   — `pos_refund_ticket` écrit un AVOIR COMMERCIAL
--     (`credit_notes`, la 255) : c'est LA pièce, l'aval est unique et propre —
--     lien `adjusted_by` (« un avoir le corrige », dit la 250). L'écriture de
--     l'avoir reste tracée par le compagnon de la 310 (credit_notes) : la
--     chaîne ticket → avoir → écriture existe DEUX étages ;
--   * `pos.ticket.stock_in`   — la rentrée de stock de l'avoir (les
--     mouvements `pos_refund`, qui pointent l'avoir) ;
--   * ET LA DOCTRINE DE LA 320 S'APPLIQUE AU CHEMIN QUI CONTREPASSE :
--     `pos_refund_ticket` rend le stock vendu → le lien `pos.ticket.stock_out`
--     du ticket est ROMPU (motif nominatif). Le lien `pos.ticket.payment`
--     reste ACTIF : la limite de la 255 est écrite — le décaissement de caisse
--     n'est pas écrit par l'avoir, le crédit passe par les écrans de règlement.
--
-- LE CAS ORDINAIRE NE SE TRACE PAS — la retenue de la 316, appliquée.
--   Un ticket de services ne sort AUCUN stock : le maillon l'a DÉCIDÉ, c'est
--   le cas ordinaire, il ne se trace pas (`sans_effet` est réservé à ce qui
--   DEVRAIT exister et n'existe pas — ici : des lignes d'articles de stock
--   sans mouvement, l'anomalie).
--
-- `void_pos_ticket` N'EST PAS UN MAILLON DE L'INVENTAIRE — mais son chemin
--   rend le stock (`pos_ticket_stock_return`, 281). La doctrine de la 320
--   s'applique à lui aussi : il ROMPT le lien `pos.ticket.stock_out` du
--   ticket qu'il annule. Aucun effet neuf n'est tracé (l'inventaire ne l'a pas
--   classé chaînage : ses écritures passent par `pos_ticket_stock_return`),
--   et la fermeture n'écrit aucune `chain_traces` (doctrine 312) : son journal
--   est l'événement `chain.link_broken` et le registre lui-même.
--
-- REJOUABLE : le `RENAME` est gardé par un bloc conditionnel (le dépôt n'a pas
-- d'`ALTER … IF EXISTS`), les contrats par `ON CONFLICT` (clé de la 252), les
-- wrappers par `CREATE OR REPLACE`.
-- ─────────────────────────────────────────────────────────────
-- 1. Les quatre contrats d'effet — déclarés ici, comme la porte G2 l'exige
--    (les drapeaux sont déclaratifs ; seul `actif` est lu par un code — la 313)
-- ─────────────────────────────────────────────────────────────
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES
  (NULL, 'pos_tickets', 'created', 'pos.ticket.stock_out',
   false, NULL, true, false, true, false, true,
   'L3/322 : create_pos_ticket (281, M7) écrit stock_movements — sortie agrégée PAR PRODUIT, au dépôt du terminal. Réversible : void (session ouverte) et l''avoir (session close) rendent le stock. Le lien est au niveau du document (doctrine 316, effets N:1) : l''aval de référence est le mouvement de plus petit identifiant, les identifiants et le décompte sont au payload.'),
  (NULL, 'pos_tickets', 'created', 'pos.ticket.payment',
   false, NULL, false, false, false, false, true,
   'L3/322 : create_pos_ticket (281) écrit pos_payments — le paiement du ticket, lien `paid_by`. Non réversible : l''annulation ne rejette pas l''argent (la 250/255 : un ticket annulé garde ses montants, l''avoir crédite le client, le décaissement passe par les écrans de règlement).'),
  (NULL, 'pos_tickets', 'refunded', 'pos.ticket.refunded',
   false, NULL, false, false, true, false, true,
   'L3/322 : pos_refund_ticket (255) écrit credit_notes + credit_note_lines — l''avoir commercial, aval unique et propre (lien `adjusted_by` : « un avoir le corrige », dit la 250). L''écriture de l''avoir reste tracée par le compagnon de la 310 : la chaîne ticket → avoir → écriture existe sur deux étages.'),
  (NULL, 'pos_tickets', 'refunded', 'pos.ticket.stock_in',
   false, NULL, true, false, true, false, true,
   'L3/322 : pos_refund_ticket (255) écrit les rentrées de stock miroir (stock_movements `pos_refund`, pointées sur l''avoir, au CUMP du dépôt). Réversible : la sortie d''origine a son lien, celui-ci décrit le retour.')
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
-- 2. create_pos_ticket — LE CORPS EST RENOMMÉ, LE WRAPPER TISSE LA CHAÎNE
--    Le corps (281 : session ouverte, totaux calculés par la base, paiements
--    ventilés, sortie de stock agrégée par produit) n'est PAS recopié : il
--    devient `create_pos_ticket_inner`, et le nom que l'écran appelle devient
--    le wrapper ci-dessous.
-- ─────────────────────────────────────────────────────────────
DO $bloc$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'create_pos_ticket'
               AND pg_get_function_identity_arguments(p.oid) = 'p_ticket jsonb, p_lines jsonb, p_payments jsonb')
     AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'create_pos_ticket_inner') THEN
    ALTER FUNCTION public.create_pos_ticket(jsonb, jsonb, jsonb) RENAME TO create_pos_ticket_inner;
  END IF;
END $bloc$;

-- Le corps renommé n'est plus une API : seul le wrapper est exposé (leçon R-17,
-- 220 : « le corps renommé n'est plus exposé »).
REVOKE ALL ON FUNCTION public.create_pos_ticket_inner(jsonb, jsonb, jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_pos_ticket(p_ticket jsonb, p_lines jsonb, p_payments jsonb DEFAULT NULL)
RETURNS public.pos_tickets
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_tid    uuid := current_tenant_id();
  v_tk     public.pos_tickets;
  v_debut  timestamptz := clock_timestamp();
  v_stock  boolean;
  v_n      integer;
  v_aval   uuid;
  v_ids    jsonb;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active' USING ERRCODE = '42501';
  END IF;

  -- LE CHEMIN D'APPEL : l'effet d'abord (le corps métier, intact), puis la
  -- chaîne autour — dans la MÊME transaction que l'appel.
  v_tk := public.create_pos_ticket_inner(p_ticket, p_lines, p_payments);

  -- ── Effet 1 : la sortie de stock (agrégée par produit — doctrine 316) ──
  -- Le cas ordinaire d'abord (la retenue de la 316) : un ticket SANS article
  -- de stock ne sort rien, le maillon l'a décidé, il ne se trace pas.
  SELECT EXISTS (SELECT 1
                   FROM pos_ticket_lines l
                   JOIN products p ON p.id = l.product_id AND p.tenant_id = l.tenant_id
                  WHERE l.ticket_id = v_tk.id AND l.tenant_id = v_tid
                    AND COALESCE(p.type, 'stock') = 'stock')
    INTO v_stock;

  IF v_stock AND chain_avant(v_tid, 'pos_tickets', 'created', 'pos.ticket.stock_out',
                             'pos_tickets', v_tk.id, NULL,
                             format('Ticket %s : la sortie de stock n''a pas été tracée (règle pos.ticket.stock_out, module caisse).', v_tk.number)) THEN
    SELECT count(*), COALESCE(jsonb_agg(id ORDER BY id), '[]'::jsonb)
      INTO v_n, v_ids
      FROM stock_movements
     WHERE tenant_id = v_tid AND reference_type = 'pos_ticket' AND reference_id = v_tk.id;
    -- L'aval de référence : le mouvement de plus petit identifiant — un choix
    -- déterministe, pour qu'un rejeu désigne le même (doctrine 316).
    SELECT id INTO v_aval
      FROM stock_movements
     WHERE tenant_id = v_tid AND reference_type = 'pos_ticket' AND reference_id = v_tk.id
     ORDER BY id LIMIT 1;

    IF v_n > 0 THEN
      PERFORM link_documents(v_tid, 'pos_tickets', v_tk.id, 'stock_movements', v_aval,
                             'pos.ticket.stock_out', 'delivered_by',
                             jsonb_build_object('mouvements', v_n, 'ids', v_ids, 'lien_par_ligne', false,
                                                'number', v_tk.number, 'total', v_tk.total,
                                                'session_id', v_tk.session_id));
      PERFORM chain_apres(v_tid, 'pos.ticket.stock_out', 'pos_tickets', v_tk.id,
                          v_debut, v_n, 'applique', NULL, NULL, NULL);
    ELSE
      -- Des lignes de stock, aucun mouvement : l'effet ATTENDU et ABSENT se dit.
      PERFORM chain_apres(v_tid, 'pos.ticket.stock_out', 'pos_tickets', v_tk.id,
                          v_debut, 0, 'sans_effet',
                          format('Ticket %s : lignes d''articles de stock, aucune sortie trouvée (règle pos.ticket.stock_out).', v_tk.number),
                          NULL, NULL);
    END IF;
  END IF;

  -- ── Effet 2 : le paiement — la trésorerie entre dans la chaîne ──
  IF chain_avant(v_tid, 'pos_tickets', 'created', 'pos.ticket.payment',
                 'pos_tickets', v_tk.id, NULL,
                 format('Ticket %s : le paiement n''a pas été tracé (règle pos.ticket.payment, module caisse).', v_tk.number)) THEN
    SELECT count(*), COALESCE(jsonb_agg(id ORDER BY id), '[]'::jsonb)
      INTO v_n, v_ids
      FROM pos_payments
     WHERE tenant_id = v_tid AND ticket_id = v_tk.id;
    SELECT id INTO v_aval
      FROM pos_payments
     WHERE tenant_id = v_tid AND ticket_id = v_tk.id
     ORDER BY id LIMIT 1;

    IF v_n > 0 THEN
      PERFORM link_documents(v_tid, 'pos_tickets', v_tk.id, 'pos_payments', v_aval,
                             'pos.ticket.payment', 'paid_by',
                             jsonb_build_object('paiements', v_n, 'ids', v_ids,
                                                'number', v_tk.number, 'total', v_tk.total));
      PERFORM chain_apres(v_tid, 'pos.ticket.payment', 'pos_tickets', v_tk.id,
                          v_debut, v_n, 'applique', NULL, NULL, NULL);
    ELSE
      PERFORM chain_apres(v_tid, 'pos.ticket.payment', 'pos_tickets', v_tk.id,
                          v_debut, 0, 'sans_effet',
                          format('Ticket %s : aucun paiement trouvé (règle pos.ticket.payment).', v_tk.number),
                          NULL, NULL);
    END IF;
  END IF;

  -- Un seul événement lisible pour le document : le détail est dans les liens.
  PERFORM emit_domain_event(v_tid, 'pos_tickets.created', 'pos_tickets', v_tk.id,
                            jsonb_build_object('number', v_tk.number, 'total', v_tk.total,
                                               'session_id', v_tk.session_id), NULL);

  RETURN v_tk;
END $maillon$;

COMMENT ON FUNCTION public.create_pos_ticket(jsonb, jsonb, jsonb) IS
  'L3 (322) : l''encaissement atomique de la 281, porté par un wrapper qui tisse la chaîne — sortie de stock (pos.ticket.stock_out, agrégée par produit, lien documentaire) et paiement (pos.ticket.payment, paid_by). Le corps métier est renommé create_pos_ticket_inner, intact.';

REVOKE ALL ON FUNCTION public.create_pos_ticket(jsonb, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pos_ticket(jsonb, jsonb, jsonb) TO authenticated, service_role;
-- ─────────────────────────────────────────────────────────────
-- 3. pos_refund_ticket — L'AVOIR DE CAISSE, SON AVAL PROPRE, ET LA FERMETURE
--    Le corps (255 : l'avoir commercial créé puis validé, le stock rendu au
--    CUMP, la vente marquée refunded, l'événement NF-525) devient
--    `pos_refund_ticket_inner`. Le wrapper tisse DEUX effets et ROMPT le lien
--    de la sortie d'origine — la doctrine de la 320 appliquée à la caisse.
-- ─────────────────────────────────────────────────────────────
DO $bloc$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'pos_refund_ticket'
               AND pg_get_function_identity_arguments(p.oid) = 'p_ticket_id uuid, p_reason text')
     AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'pos_refund_ticket_inner') THEN
    ALTER FUNCTION public.pos_refund_ticket(uuid, text) RENAME TO pos_refund_ticket_inner;
  END IF;
END $bloc$;

REVOKE ALL ON FUNCTION public.pos_refund_ticket_inner(uuid, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.pos_refund_ticket(p_ticket_id uuid, p_reason text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_tid    uuid := current_tenant_id();
  v_av     uuid;
  v_num    text;
  v_debut  timestamptz := clock_timestamp();
  v_n      integer;
  v_aval   uuid;
  v_ids    jsonb;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active : un avoir se fait dans le contexte d''une société.' USING ERRCODE = '42501';
  END IF;

  -- L'effet d'abord : le corps de la 255, intact.
  v_av := public.pos_refund_ticket_inner(p_ticket_id, p_reason);
  SELECT number INTO v_num FROM credit_notes WHERE id = v_av AND tenant_id = v_tid;

  -- ── Effet 1 : l'avoir — LA pièce, aval unique et propre ──
  IF chain_avant(v_tid, 'pos_tickets', 'refunded', 'pos.ticket.refunded',
                 'pos_tickets', p_ticket_id, NULL,
                 format('Ticket %s : l''avoir n''a pas été tracé (règle pos.ticket.refunded, module caisse).',
                        (SELECT number FROM pos_tickets WHERE id = p_ticket_id AND tenant_id = v_tid))) THEN
    PERFORM link_documents(v_tid, 'pos_tickets', p_ticket_id, 'credit_notes', v_av,
                           'pos.ticket.refunded', 'adjusted_by',
                           jsonb_build_object('avoir', v_av, 'numero', v_num,
                                              'reason', p_reason, 'lien_par_ligne', false));
    PERFORM chain_apres(v_tid, 'pos.ticket.refunded', 'pos_tickets', p_ticket_id,
                        v_debut, 1, 'applique', NULL, NULL, NULL);
  END IF;

  -- ── Effet 2 : la rentrée de stock — les mouvements `pos_refund` pointent l'avoir ──
  IF chain_avant(v_tid, 'pos_tickets', 'refunded', 'pos.ticket.stock_in',
                 'pos_tickets', p_ticket_id, NULL,
                 format('Ticket %s : la rentrée de stock de l''avoir n''a pas été tracée (règle pos.ticket.stock_in, module caisse).',
                        (SELECT number FROM pos_tickets WHERE id = p_ticket_id AND tenant_id = v_tid))) THEN
    SELECT count(*), COALESCE(jsonb_agg(id ORDER BY id), '[]'::jsonb)
      INTO v_n, v_ids
      FROM stock_movements
     WHERE tenant_id = v_tid AND reference_type = 'pos_refund' AND reference_id = v_av;
    SELECT id INTO v_aval
      FROM stock_movements
     WHERE tenant_id = v_tid AND reference_type = 'pos_refund' AND reference_id = v_av
     ORDER BY id LIMIT 1;

    IF v_n > 0 THEN
      PERFORM link_documents(v_tid, 'pos_tickets', p_ticket_id, 'stock_movements', v_aval,
                             'pos.ticket.stock_in', 'created_from',
                             jsonb_build_object('mouvements', v_n, 'ids', v_ids, 'lien_par_ligne', false,
                                                'avoir', v_av, 'numero', v_num));
      PERFORM chain_apres(v_tid, 'pos.ticket.stock_in', 'pos_tickets', p_ticket_id,
                          v_debut, v_n, 'applique', NULL, NULL, NULL);
    ELSE
      PERFORM chain_apres(v_tid, 'pos.ticket.stock_in', 'pos_tickets', p_ticket_id,
                          v_debut, 0, 'sans_effet',
                          format('Avoir %s : lignes de stock vendues, aucune rentrée trouvée (règle pos.ticket.stock_in).', v_num),
                          NULL, NULL);
    END IF;
  END IF;

  -- ── LA DOCTRINE DE LA 320 : le chemin qui CONTREPASSE ferme l'effet retiré.
  --    L'avoir rend le stock vendu : le lien de la sortie d'origine est ROMPU.
  --    Le lien du PAIEMENT reste actif — la limite de la 255 est écrite : le
  --    décaissement de caisse n'est pas écrit par l'avoir.
  IF chain_lien_actif(v_tid, 'pos_tickets', p_ticket_id, 'pos.ticket.stock_out') IS NOT NULL THEN
    PERFORM chain_lien_rompre(v_tid, 'pos_tickets', p_ticket_id, 'pos.ticket.stock_out',
      format('Avoir %s : le stock vendu du ticket est rendu (règle pos.ticket.stock_out, module caisse).', v_num));
  END IF;

  PERFORM emit_domain_event(v_tid, 'pos_tickets.refunded', 'pos_tickets', p_ticket_id,
                            jsonb_build_object('avoir', v_av, 'numero', v_num, 'reason', p_reason), NULL);

  RETURN v_av;
END $maillon$;

COMMENT ON FUNCTION public.pos_refund_ticket(uuid, text) IS
  'L3 (322) : l''avoir de caisse de la 255, porté par un wrapper qui tisse la chaîne — le ticket est LIÉ à son avoir (adjusted_by) et à ses rentrées de stock (pos.ticket.stock_in), et le lien de sa sortie d''origine est ROMPU (doctrine 320 : le chemin qui contrepasse ferme l''effet retiré). Le corps métier est renommé pos_refund_ticket_inner, intact.';

REVOKE ALL ON FUNCTION public.pos_refund_ticket(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pos_refund_ticket(uuid, text) TO authenticated;
-- ─────────────────────────────────────────────────────────────
-- 4. void_pos_ticket — PAS UN MAILLON DE L'INVENTAIRE, MAIS UN CHEMIN QUI
--    CONTREPASSE : son annulation (session OUVERTE) rend le stock. La doctrine
--    de la 320 s'applique à lui : le lien `pos.ticket.stock_out` du ticket est
--    ROMPU. Aucun effet neuf, aucune trace — une fermeture n'écrit pas dans
--    `chain_traces` (312) : son journal est l'événement `chain.link_broken`.
-- ─────────────────────────────────────────────────────────────
DO $bloc$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'void_pos_ticket'
               AND pg_get_function_identity_arguments(p.oid) = 'p_ticket_id uuid, p_reason text')
     AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'void_pos_ticket_inner') THEN
    ALTER FUNCTION public.void_pos_ticket(uuid, text) RENAME TO void_pos_ticket_inner;
  END IF;
END $bloc$;

REVOKE ALL ON FUNCTION public.void_pos_ticket_inner(uuid, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.void_pos_ticket(p_ticket_id uuid, p_reason text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_tid uuid := current_tenant_id();
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active : une annulation se fait dans le contexte d''une société.'
      USING ERRCODE = '42501';
  END IF;

  -- L'effet d'abord : le corps de la 250/281, intact.
  PERFORM public.void_pos_ticket_inner(p_ticket_id, p_reason);

  -- Puis la fermeture ciblée : l'annulation d'une session OUVERTE rend le
  -- stock (281, M7) — l'effet `pos.ticket.stock_out` est retiré, son lien le
  -- dit. La ciblée est gardée par la lecture de l'actif : un ticket de
  -- services (aucun lien) s'annule sans lever — c'est le cas ordinaire.
  IF chain_lien_actif(v_tid, 'pos_tickets', p_ticket_id, 'pos.ticket.stock_out') IS NOT NULL THEN
    PERFORM chain_lien_rompre(v_tid, 'pos_tickets', p_ticket_id, 'pos.ticket.stock_out',
      format('Ticket %s annulé (session ouverte) : le stock vendu est rendu (règle pos.ticket.stock_out, module caisse).',
             (SELECT number FROM pos_tickets WHERE id = p_ticket_id AND tenant_id = v_tid)));
  END IF;
END $maillon$;

COMMENT ON FUNCTION public.void_pos_ticket(uuid, text) IS
  '250/281, fermeture ajoutée par L3 (322) : l''annulation d''un ticket sur session ouverte rend le stock — le lien pos.ticket.stock_out du ticket est ROMPU (doctrine 320), sans tracer d''effet neuf : void_pos_ticket n''est pas un maillon de l''inventaire, mais son chemin contrepasse. Le corps métier est renommé void_pos_ticket_inner, intact.';

REVOKE ALL ON FUNCTION public.void_pos_ticket(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.void_pos_ticket(uuid, text) TO authenticated;
-- ============================================================