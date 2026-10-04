-- ============================================================
-- 250_pos_nf525_immutability.sql — POS-01, POS-02, POS-03, POS-04
--
-- Audit des modules hors comptabilité (23/09), § Caisse, mesuré le 24/09 en
-- rejouant `doc/audit/scenarios/POS_inalterabilite_nf525.sql` sur base neuve :
--
--   B1 ⚠️ ticket ramené de 120 € à 12 € SANS REFUS ; hachage inchangé = t
--   B2 ⚠️ 1 ligne de ticket supprimée sans refus
--   B3 journal NF525 : 3 événement(s) — aucun ne mentionne la modification
--
--   POS-01  `prevent_pos_ticket_deletion` (119) garde la suppression et
--           `assign_pos_ticket_number_and_hash` (119) signe à l'insertion,
--           mais AUCUN déclencheur ne veille en modification : le montant d'un
--           ticket signé se réécrit, l'empreinte n'est pas recalculée, et la
--           chaîne « valide » le ticket falsifié. C'est la dissimulation de
--           recettes que la NF-525 existe pour empêcher.
--   POS-02  `pos_ticket_lines` n'a que `set_tenant_id` : ses lignes se
--           suppriment et se modifient librement.
--   POS-03  Aucun index unique sur (société, caisse, numéro), et le numéro est
--           calculé par `MAX(…)+1` SANS VERROU : deux encaissements simultanés
--           sur le même terminal prennent le même numéro. Mesuré : le verrou
--           advisory n'est jamais pris (0 dans `pg_locks`).
--   POS-04  `created_at`, fourni par le client, entre dans le hachage : un
--           ticket antidaté produit une empreinte cohérente — et mesuré ici,
--           un ticket dont le client a omis `tenant_id` reçoit un hachage
--           calculé sur NULL, donc une empreinte que `verify_pos_ticket_chain`
--           déclare invalide (0 ticket valide sur 1).
--   POS-01, la cause silencieuse : aucune contrainte `CHECK` sur le statut. Un
--           ticket dont le statut n'est pas exactement 'completed' sort de
--           l'écriture de clôture sans que rien ne le dise.
--
-- CORRECTIFS
--   1. Le statut est contraint à ('completed','cancelled','refunded') ; les
--      statuts nuls sont repris en 'completed' (une vente NULL ne compte dans
--      aucune clôture : du chiffre d'affaires perdu). Un statut inconnu fait
--      échouer la migration en le NOMMANT : la reprise est une décision
--      d'exploitation, pas un effacement silencieux.
--   2. `created_at` est un fait serveur (posé par le déclencheur) et la société
--      vient du contexte quand le client l'omet : sans elle, ni numérotation ni
--      chaîne d'empreintes ne veulent dire quelque chose.
--   3. La numérotation se fait sous `pg_advisory_xact_lock` par terminal, et
--      l'unicité (société, caisse, numéro) est tenue par la base. Les doublons
--      déjà en base sont RÉPARÉS et leur empreinte recalculée (une migration
--      qui échoue sur les données réelles ne se déploie pas).
--   4. Un ticket encaissé ne se réécrit plus : les montants, la date, le numéro
--      et l'empreinte sont immuables, pour tout le monde — y compris le
--      propriétaire de la table. La seule modification permise est le passage à
--      'cancelled' par `void_pos_ticket()`, avant la clôture de la session.
--   5. Les lignes d'un ticket ne se modifient ni ne se suppriment ; on n'en
--      ajoute que tant que la session est ouverte et le ticket valide.
--   6. `void_pos_ticket()` est la sortie honnête : elle refuse après clôture
--      (l'avoir est alors le seul chemin), trace le motif, et écrit un
--      événement NF-525 — le journal dit désormais qu'un ticket a changé.
--
-- LIMITES DITES

-- ─────────────────────────────────────────────────────────────
-- 0. Reprises — le statut d'abord (POS-01, la cause silencieuse)
-- ─────────────────────────────────────────────────────────────
-- Un statut NULL n'est pas un statut : le ticket ne compte dans aucune
-- clôture. C'est une vente qui a eu lieu (elle a un ticket, un encaissement),
-- donc elle est reprise en 'completed' — et le nombre repris est publié.
DO $$
DECLARE v_null int; v_inconnus text;
BEGIN
  SELECT count(*) INTO v_null FROM pos_tickets WHERE status IS NULL OR btrim(status) = '';
  IF v_null > 0 THEN
    UPDATE pos_tickets SET status = 'completed' WHERE status IS NULL OR btrim(status) = '';
    RAISE NOTICE '250 : % ticket(s) sans statut repris en ''completed'' (ils ne comptaient dans aucune clôture)', v_null;
  END IF;

  SELECT string_agg(DISTINCT quote_literal(status), ', ' ORDER BY quote_literal(status))
  INTO v_inconnus
  FROM pos_tickets
  WHERE status NOT IN ('completed', 'cancelled', 'refunded');

  IF v_inconnus IS NOT NULL THEN
    RAISE EXCEPTION '250 : pos_tickets porte des statuts hors (completed, cancelled, refunded) : %. Trancher leur sort avant de contraindre la colonne (un statut inconnu sort de la clôture en silence) : UPDATE pos_tickets SET status = ''completed'' WHERE status IN (…);', v_inconnus;
  END IF;
END $$;

ALTER TABLE pos_tickets DROP CONSTRAINT IF EXISTS pos_tickets_status_check;
ALTER TABLE pos_tickets ADD CONSTRAINT pos_tickets_status_check
  CHECK (status IN ('completed', 'cancelled', 'refunded'));
ALTER TABLE pos_tickets ALTER COLUMN status SET DEFAULT 'completed';

-- La trace de l'annulation (POS-01) : quand, et pourquoi.
ALTER TABLE pos_tickets ADD COLUMN IF NOT EXISTS voided_at timestamptz;
ALTER TABLE pos_tickets ADD COLUMN IF NOT EXISTS void_reason text;
COMMENT ON COLUMN pos_tickets.voided_at IS
  '250 : horodatage de l''annulation posée par void_pos_ticket(). Un ticket annulé reste lisible, avec ses montants d''origine.';
COMMENT ON COLUMN pos_tickets.void_reason IS
  '250 : motif de l''annulation, tel que saisi par le caissier.';
-- ─────────────────────────────────────────────────────────────
-- 1. La numérotation : un numéro par (société, caisse), sous verrou (POS-03)
-- ─────────────────────────────────────────────────────────────
-- Reprise AVANT la contrainte : une base qui porte déjà des doublons (le
-- `MAX+1` sans verrou en produit dès deux encaissements simultanés) verrait la
-- migration échouer. Les lignes sont renumérotées dans leur ordre de création
-- ET leur empreinte recalculée — l'empreinte porte le numéro, la laisser
-- fausser ferait dire à `verify_pos_ticket_chain` qu'une base saine est
-- altérée.
CREATE OR REPLACE FUNCTION public.pos_tickets_renumber_duplicates()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_term record; v_row record;
  v_seq int; v_prev text; v_hash text; v_touched int := 0;
BEGIN
  -- Réparation réservée au propriétaire : le déclencheur d'immutabilité
  -- n'ouvre cette porte qu'à lui, et seulement pendant ces lignes.
  PERFORM set_config('app.pos_repair', 'on', true);

  FOR v_term IN
    SELECT tenant_id, terminal_id
    FROM pos_tickets
    GROUP BY tenant_id, terminal_id
    HAVING count(*) <> count(DISTINCT sequential_number)
  LOOP
    v_seq := 0;
    v_prev := NULL;
    FOR v_row IN
      SELECT id, total, created_at
      FROM pos_tickets
      WHERE tenant_id = v_term.tenant_id AND terminal_id = v_term.terminal_id
      ORDER BY created_at NULLS LAST, id
    LOOP
      v_seq := v_seq + 1;
      v_hash := encode(digest(
        v_term.tenant_id::text || '|' || v_term.terminal_id::text || '|' || v_seq || '|' ||
        v_row.total || '|' || COALESCE(v_prev, '') || '|' || v_row.created_at, 'sha256'), 'hex');
      UPDATE pos_tickets
      SET sequential_number = v_seq, previous_hash = v_prev, ticket_hash = v_hash
      WHERE id = v_row.id
        AND (sequential_number IS DISTINCT FROM v_seq
             OR ticket_hash IS DISTINCT FROM v_hash
             OR previous_hash IS DISTINCT FROM v_prev);
      IF FOUND THEN
        v_touched := v_touched + 1;
      END IF;
      v_prev := v_hash;
    END LOOP;
  END LOOP;

  PERFORM set_config('app.pos_repair', 'off', true);
  RETURN v_touched;
END $$;

COMMENT ON FUNCTION public.pos_tickets_renumber_duplicates() IS
  '250 : renumérote les tickets d''une caisse dans leur ordre de création et recalcule leur empreinte chaînée. Appelée par la migration 250 avant de poser l''unicité, et par le test T11 sur un état hostile fabriqué.';

SELECT public.pos_tickets_renumber_duplicates();

ALTER TABLE pos_tickets DROP CONSTRAINT IF EXISTS pos_tickets_terminal_seq_unique;
ALTER TABLE pos_tickets ADD CONSTRAINT pos_tickets_terminal_seq_unique
  UNIQUE (tenant_id, terminal_id, sequential_number);

-- ─────────────────────────────────────────────────────────────
-- 2. La signature du ticket : société, date serveur, numéro sous verrou
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION assign_pos_ticket_number_and_hash()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_last_number int := 0;
  v_last_hash text;
  v_hash_input text;
  v_grand_daily numeric := 0;
  v_grand_monthly numeric := 0;
  v_grand_yearly numeric := 0;
  v_grand_lifetime numeric := 0;
BEGIN
  -- POS-04 : la société d'abord. Sans elle, le numéro se calcule sur une
  -- colonne NULL (chaque ticket prend le numéro 1) et le hachage porte NULL :
  -- la chaîne d'empreintes ne vérifie plus rien.
  NEW.tenant_id := COALESCE(NEW.tenant_id, current_tenant_id());
  IF NEW.tenant_id IS NULL THEN
    RAISE EXCEPTION 'Ticket de caisse sans société : aucun contexte actif. Un ticket sans société ne compte dans aucune clôture.'
      USING ERRCODE = 'not_null_violation';
  END IF;

  IF NEW.terminal_id IS NULL THEN
    RAISE EXCEPTION 'Ticket de caisse sans caisse : la numérotation et la chaîne d''empreintes sont par terminal.'
      USING ERRCODE = 'not_null_violation';
  END IF;

  -- POS-04 : created_at est l'ancre du hachage, et c'est le serveur qui la pose.
  -- La date métier (`date`) reste celle de l'appelant : un terminal hors ligne
  -- peut enregistrer une vente en différé.
  NEW.created_at := now();

  -- POS-03 : un numéro par (société, caisse), attribué sous verrou
  -- transactionnel — deux encaissements simultanés ne peuvent plus prendre le
  -- même numéro, et la chaîne ne fourche plus.
  PERFORM pg_advisory_xact_lock(hashtext('pos_ticket:' || NEW.tenant_id::text || ':' || NEW.terminal_id::text));

  SELECT COALESCE(MAX(sequential_number), 0) INTO v_last_number
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id;

  NEW.sequential_number := v_last_number + 1;

  -- Récupérer le hash précédent
  SELECT ticket_hash INTO v_last_hash
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id
  ORDER BY sequential_number DESC
  LIMIT 1;

  NEW.previous_hash := v_last_hash;

  -- POS-01 : la même formule que `pos_tickets_renumber_duplicates()` et que
  -- `verify_pos_ticket_chain()` — une seule vérité pour l'empreinte.
  v_hash_input := NEW.tenant_id || '|' || NEW.terminal_id || '|' ||
    NEW.sequential_number || '|' || NEW.total || '|' ||
    COALESCE(v_last_hash, '') || '|' || NEW.created_at;

  NEW.ticket_hash := encode(digest(v_hash_input, 'sha256'), 'hex');

  -- Cumuls perpétuels (jamais remis à zéro)
  SELECT COALESCE(SUM(total), 0) INTO v_grand_daily
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id
    AND DATE(created_at) = DATE(NEW.created_at);

  SELECT COALESCE(SUM(total), 0) INTO v_grand_monthly
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id
    AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', NEW.created_at);

  SELECT COALESCE(SUM(total), 0) INTO v_grand_yearly
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id
    AND DATE_TRUNC('year', created_at) = DATE_TRUNC('year', NEW.created_at);

  SELECT COALESCE(SUM(total), 0) INTO v_grand_lifetime
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id;

  NEW.grand_total_daily := v_grand_daily + NEW.total;
  NEW.grand_total_monthly := v_grand_monthly + NEW.total;
  NEW.grand_total_yearly := v_grand_yearly + NEW.total;
  NEW.grand_total_lifetime := v_grand_lifetime + NEW.total;

  -- Journaliser dans nf525_event_log via la fonction certifiée avec hash-chaining
  PERFORM log_nf525_event(
    'pos_ticket_created',
    'pos_ticket',
    NEW.id,
    jsonb_build_object(
      'terminal_id', NEW.terminal_id,
      'sequential_number', NEW.sequential_number,
      'total', NEW.total,
      'hash', NEW.ticket_hash,
      'previous_hash', NEW.previous_hash
    ),
    NULL,
    to_char(now(), 'YYYY-MM')
  );

  RETURN NEW;
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- 3. L'inaltérabilité (POS-01)
-- ─────────────────────────────────────────────────────────────
-- Le déclencheur est SECURITY INVOKER (volontairement) : `current_user` y est
-- l'appelant réel. C'est ce qui distingue un appel direct à PostgREST
-- (authenticated) d'une écriture faite par `void_pos_ticket()`, qui est
-- SECURITY DEFINER — aucune variable de session ne peut être falsifiée pour
-- franchir la garde.
CREATE OR REPLACE FUNCTION public.prevent_pos_ticket_modification()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_owner name;
  v_intact boolean;
BEGIN
  -- Montants, date, numéro, empreinte : ce que la NF-525 appelle le ticket.
  v_intact := NEW.total IS NOT DISTINCT FROM OLD.total
    AND NEW.subtotal IS NOT DISTINCT FROM OLD.subtotal
    AND NEW.vat_total IS NOT DISTINCT FROM OLD.vat_total
    AND NEW.amount_paid IS NOT DISTINCT FROM OLD.amount_paid
    AND NEW.change_given IS NOT DISTINCT FROM OLD.change_given
    AND NEW.number IS NOT DISTINCT FROM OLD.number
    AND NEW.date IS NOT DISTINCT FROM OLD.date
    AND NEW.created_at IS NOT DISTINCT FROM OLD.created_at
    AND NEW.sequential_number IS NOT DISTINCT FROM OLD.sequential_number
    AND NEW.ticket_hash IS NOT DISTINCT FROM OLD.ticket_hash
    AND NEW.previous_hash IS NOT DISTINCT FROM OLD.previous_hash
    AND NEW.terminal_id IS NOT DISTINCT FROM OLD.terminal_id
    AND NEW.session_id IS NOT DISTINCT FROM OLD.session_id
    AND NEW.customer_id IS NOT DISTINCT FROM OLD.customer_id;

  SELECT pg_get_userbyid(c.relowner) INTO v_owner
  FROM pg_class c WHERE c.oid = 'public.pos_tickets'::regclass;

  IF current_user IS NOT DISTINCT FROM v_owner
     OR pg_has_role(current_user, 'service_role', 'MEMBER')
     OR (v_owner IS NOT NULL AND pg_has_role(current_user, v_owner, 'MEMBER'))
  THEN
    -- Réparation de numérotation (POS-03), ouverte au seul propriétaire, le
    -- temps de `pos_tickets_renumber_duplicates()`.
    IF current_setting('app.pos_repair', true) = 'on' THEN
      RETURN NEW;
    END IF;

    IF NOT v_intact THEN
      RAISE EXCEPTION 'Ticket de caisse % : les montants, la date, le numéro et l''empreinte sont immuables (NF-525). Un ticket ne se corrige pas : un avoir le corrige.', OLD.number
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  -- Appel direct (l'écran, l'API) : le rattachement d'une facture est la seule
  -- écriture qui ne réécrit rien de la vente.
  IF v_intact
     AND NEW.status IS NOT DISTINCT FROM OLD.status
     AND NEW.tenant_id IS NOT DISTINCT FROM OLD.tenant_id
     AND NEW.is_voided IS NOT DISTINCT FROM OLD.is_voided
  THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Ticket de caisse % : modification interdite (NF-525). Une vente encaissée ne se réécrit pas : l''annuler avant la clôture de la caisse (void_pos_ticket), ou émettre un avoir après.', OLD.number
    USING ERRCODE = '42501';
END $$;

COMMENT ON FUNCTION public.prevent_pos_ticket_modification() IS
  '250 (POS-01) : refuse toute réécriture d''un ticket encaissé — montants, date, numéro, empreinte — pour l''appel direct comme pour le propriétaire. Seule exception ouverte : le passage à ''cancelled'' par void_pos_ticket(), et le rattachement d''une facture.';

DROP TRIGGER IF EXISTS prevent_pos_ticket_modification_trg ON pos_tickets;
CREATE TRIGGER prevent_pos_ticket_modification_trg
  BEFORE UPDATE ON pos_tickets
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_pos_ticket_modification();

-- ------------------------------------------------------------
-- La suppression d'un ticket (POS-01) : le même refus, avec son code
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prevent_pos_ticket_deletion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'Ticket de caisse % : suppression interdite (NF-525). Un ticket ne disparaît pas : l''annuler avant la clôture (void_pos_ticket), ou émettre un avoir après.', OLD.number
    USING ERRCODE = '42501';
END;
$$;

COMMENT ON FUNCTION public.prevent_pos_ticket_deletion() IS
  '250 (POS-01) : la suppression d''un ticket reste impossible, désormais avec le message et le code (42501) qui disent quoi faire.';
-- ------------------------------------------------------------
-- Les lignes d'un ticket (POS-02)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prevent_pos_ticket_line_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid;
  v_ticket uuid;
  v_status text;
  v_number text;
  v_session text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Ligne de ticket : une ligne de ticket encaissé ne se supprime pas (NF-525). Elle ne disparaît pas, le ticket s''annule.'
      USING ERRCODE = '42501';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'Ligne de ticket : une ligne de ticket encaissé ne se modifie pas (NF-525). Un avoir corrige la vente, pas une réécriture.'
      USING ERRCODE = '42501';
  END IF;

  v_tid := NEW.tenant_id;
  v_ticket := NEW.ticket_id;

  SELECT tk.status, tk.number, ps.status
  INTO v_status, v_number, v_session
  FROM pos_tickets tk
  LEFT JOIN pos_sessions ps ON ps.id = tk.session_id AND ps.tenant_id = tk.tenant_id
  WHERE tk.id = v_ticket
    AND tk.tenant_id = COALESCE(v_tid, current_tenant_id());

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Ligne de ticket rattachée à aucun ticket de la société courante : le ticket doit exister avant ses lignes.'
      USING ERRCODE = '42501';
  END IF;

  IF v_status <> 'completed' THEN
    RAISE EXCEPTION 'Ticket % annulé : on n''y ajoute plus de ligne. Le ticket annulé est une pièce, pas un brouillon.', v_number
      USING ERRCODE = '42501';
  END IF;

  IF v_session IS DISTINCT FROM 'open' THEN
    RAISE EXCEPTION 'Session de caisse clôturée : le ticket % est figé. Émettre un avoir pour le corriger.', v_number
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.prevent_pos_ticket_line_change() IS
  '250 (POS-02) : les lignes d''un ticket ne se modifient ni ne se suppriment ; on n''en ajoute que dans une session ouverte et sur un ticket valide.';

DROP TRIGGER IF EXISTS prevent_pos_ticket_line_change_trg ON pos_ticket_lines;
CREATE TRIGGER prevent_pos_ticket_line_change_trg
  BEFORE INSERT OR UPDATE OR DELETE ON pos_ticket_lines
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_pos_ticket_line_change();


-- ─────────────────────────────────────────────────────────────
-- 4. La sortie honnête : annuler un ticket (POS-01)
-- ─────────────────────────────────────────────────────────────
-- Sans cette fonction, la garde serait contournée par le produit : l'écran
-- avait besoin d'annuler un ticket (`cancelPosTicket` écrivait `status`).
-- La sortie est tracée, unique, et refusée après la clôture de la session —
-- là, la vente est comptabilisée et seul un avoir la corrige.
CREATE OR REPLACE FUNCTION public.void_pos_ticket(p_ticket_id uuid, p_reason text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_tk record;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active : une annulation se fait dans le contexte d''une société.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT can_perform('pos_tickets', 'update') THEN
    RAISE EXCEPTION 'Le rôle courant n''a pas le droit d''annuler un ticket de caisse.'
      USING ERRCODE = '42501';
  END IF;

  SELECT tk.*, ps.status AS session_status
  INTO v_tk
  FROM pos_tickets tk
  JOIN pos_sessions ps ON ps.id = tk.session_id AND ps.tenant_id = tk.tenant_id
  WHERE tk.id = p_ticket_id AND tk.tenant_id = v_tid
  FOR UPDATE OF tk;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ticket % : introuvable dans la société courante.', p_ticket_id
      USING ERRCODE = '42501';
  END IF;

  IF v_tk.status <> 'completed' OR COALESCE(v_tk.is_voided, false) THEN
    RAISE EXCEPTION 'Ticket % : déjà annulé (statut « % »). Une annulation ne s''écrit qu''une fois.', v_tk.number, v_tk.status
      USING ERRCODE = '42501';
  END IF;

  IF v_tk.session_status = 'closed' THEN
    RAISE EXCEPTION 'Session de caisse clôturée : la vente % est comptabilisée. Émettre un ticket d''annulation (avoir) au lieu de réécrire celui-ci.', v_tk.number
      USING ERRCODE = '42501';
  END IF;

  UPDATE pos_tickets
  SET status = 'cancelled',
      is_voided = true,
      voided_at = now(),
      void_reason = NULLIF(btrim(COALESCE(p_reason, '')), '')
  WHERE id = p_ticket_id AND tenant_id = v_tid;

  -- Le journal NF-525 dit désormais qu'un ticket a changé (avant la 250, trois
  -- événements d'insertion et rien sur la réécriture).
  PERFORM log_nf525_event(
    'pos_ticket_voided',
    'pos_ticket',
    p_ticket_id,
    jsonb_build_object(
      'number', v_tk.number,
      'total', v_tk.total,
      'hash', v_tk.ticket_hash,
      'reason', p_reason,
      'terminal_id', v_tk.terminal_id,
      'sequential_number', v_tk.sequential_number
    ),
    NULL,
    to_char(now(), 'YYYY-MM')
  );
END $$;

COMMENT ON FUNCTION public.void_pos_ticket(uuid, text) IS
  '250 (POS-01) : annule un ticket encaissé d''une session ouverte — le seul chemin de correction avant clôture. Trace le motif, écrit un événement NF-525, et refuse une seconde annulation comme une annulation après clôture.';

-- ─────────────────────────────────────────────────────────────
-- 5. Droits — un déclencheur n'est pas une RPC (leçon de la 228)
-- ─────────────────────────────────────────────────────────────
-- `CREATE FUNCTION` accorde EXECUTE à PUBLIC : sans ces révocations, les cinq
-- fonctions seraient appelables par `anon` et la CI le refuserait
-- (`ci/check_anon_grants.sql`, suite 228).
REVOKE ALL ON FUNCTION public.prevent_pos_ticket_modification() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.prevent_pos_ticket_deletion() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.prevent_pos_ticket_line_change() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION assign_pos_ticket_number_and_hash() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pos_tickets_renumber_duplicates() FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.void_pos_ticket(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.void_pos_ticket(uuid, text) TO authenticated;

-- La reprise : une base saine n'a aucun doublon de numéro, la fonction ne
-- touche alors rien. Elle est laissée en place pour l'exploitation (et pour le
-- test T11, qui fabrique l'état hostile).

-- ============================================================
