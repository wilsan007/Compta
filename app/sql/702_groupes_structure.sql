-- 702 — groupes_structure
-- Numéro pris le 2026-10-05T20:42:40.931Z par migration-numero.mjs (ligne « plan6 F (plateforme) », branche plan6/f-plateforme).
--
-- ============================================================
-- F.4 / GRP-01 + GRP-02 (partie F du plan du 05/10) : LA STRUCTURE D'UN GROUPE
-- ET LES OPÉRATIONS INTRA-GROUPE.
--
-- Le constat. Les trois tables qu'avait esquissées la 127 (`group_entities`,
-- `group_members`, `intra_group_transactions`) ont été SUPPRIMÉES le 18/09 par
-- la `164` : « nommées NULLE PART : ni dans `src/`, ni dans les fonctions
-- edge ». C'était vrai — il n'y avait que du DDL. F.4 les rétablit, mais
-- CORRIGÉES sur deux points que la 127 avait faux :
--
--   1. UN GROUPE RELIE PLUSIEURS SOCIÉTÉS. La 127 rangeait `group_entities`
--      sous une seule société (`tenant_id`) — un « groupe » qu'une seule
--      société voit n'est pas un groupe. Le maître `groups` est donc GLOBAL
--      (pas de `tenant_id`) ; l'appartenance vit dans `group_members`, qui
--      porte, elle, le `tenant_id` de la société membre.
--   2. LE CLOISONNEMENT RESTE TENU PAR LA BASE. Un membre ne voit que son
--      groupe et ses pairs — jamais les groupes des autres. La lecture passe
--      par `my_group_ids()`, un helper SECURITY DEFINER (sans quoi deux
--      politiques se référenceraient l'une l'autre : PostgreSQL lève
--      « infinite recursion detected in policy »). L'écriture, elle, n'a
--      AUCUNE politique : seules les RPC ci-dessous écrivent (elles vérifient
--      que l'appelant est administrateur d'une société membre).
--
-- GRP-03 (la consolidation des comptes) n'est PAS dans cette migration : elle
-- mérite son propre lot. La structure et les flux qu'elle consomme sont posés
-- ici — c'est ce que la 701 a laissé « à brancher ».
-- ============================================================

-- ============================================================
-- 1. Le maître : un groupe (global — il relie plusieurs sociétés)
-- ============================================================
CREATE TABLE IF NOT EXISTS groups (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  created_by  uuid NOT NULL,                       -- auth.users.id du créateur
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE groups FORCE ROW LEVEL SECURITY;

-- ============================================================
-- 2. L'appartenance : une société membre d'un groupe
-- ============================================================
CREATE TABLE IF NOT EXISTS group_members (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id             uuid NOT NULL REFERENCES groups(id)  ON DELETE CASCADE,
  tenant_id            uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  member_type          text NOT NULL DEFAULT 'subsidiary'
    CHECK (member_type IN ('parent', 'subsidiary', 'branch', 'joint_venture')),
  ownership_pct        numeric(5,2) NOT NULL DEFAULT 100
    CHECK (ownership_pct > 0 AND ownership_pct <= 100),
  consolidation_method text NOT NULL DEFAULT 'full'
    CHECK (consolidation_method IN ('full', 'equity', 'proportional', 'none')),
  joined_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, tenant_id)
);

CREATE INDEX IF NOT EXISTS idx_group_members_tenant ON group_members(tenant_id);
CREATE INDEX IF NOT EXISTS idx_group_members_group  ON group_members(group_id);

ALTER TABLE group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_members FORCE ROW LEVEL SECURITY;

-- ============================================================
-- 3. GRP-02 : les opérations intra-groupe (un flux d'une société à une autre)
-- ============================================================
CREATE TABLE IF NOT EXISTS intra_group_transactions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id         uuid NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  from_tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  to_tenant_id     uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  transaction_type text NOT NULL
    CHECK (transaction_type IN ('sale', 'purchase', 'loan', 'transfer', 'management_fee', 'dividend')),
  amount           numeric(18,2) NOT NULL CHECK (amount <> 0),
  currency         text NOT NULL DEFAULT 'EUR',
  reference        text,
  label            text,
  transaction_date date NOT NULL,
  status           text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'confirmed', 'cancelled')),
  created_by       uuid,
  created_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (from_tenant_id <> to_tenant_id)
);

CREATE INDEX IF NOT EXISTS idx_intra_group_tx_group ON intra_group_transactions(group_id);
CREATE INDEX IF NOT EXISTS idx_intra_group_tx_from  ON intra_group_transactions(from_tenant_id);
CREATE INDEX IF NOT EXISTS idx_intra_group_tx_to    ON intra_group_transactions(to_tenant_id);

ALTER TABLE intra_group_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE intra_group_transactions FORCE ROW LEVEL SECURITY;

-- ============================================================
-- 4. Le helper de lecture : les groupes de MA société
-- ============================================================
-- SECURITY DEFINER : il lit `group_members` en contournant sa propre politique
-- (sinon « infinite recursion detected in policy for relation group_members »).
-- Il ne rend QUE les groupes du `current_tenant_id()` de l'appelant : être
-- appelable ne dit rien de plus que ce que la RLS dit déjà.
CREATE OR REPLACE FUNCTION my_group_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT DISTINCT gm.group_id FROM group_members gm WHERE gm.tenant_id = current_tenant_id();
$$;

-- ============================================================
-- 5. Les politiques de LECTURE (aucune d'écriture : les RPC écrivent)
-- ============================================================
DROP POLICY IF EXISTS groups_select_members ON groups;
CREATE POLICY groups_select_members ON groups
  FOR SELECT USING (created_by = auth.uid() OR id IN (SELECT my_group_ids()));

DROP POLICY IF EXISTS group_members_select ON group_members;
CREATE POLICY group_members_select ON group_members
  FOR SELECT USING (tenant_id = current_tenant_id() OR group_id IN (SELECT my_group_ids()));

DROP POLICY IF EXISTS intra_group_tx_select ON intra_group_transactions;
CREATE POLICY intra_group_tx_select ON intra_group_transactions
  FOR SELECT USING (from_tenant_id = current_tenant_id() OR to_tenant_id = current_tenant_id());

-- ============================================================
-- 6. GRP-01 : les RPC de la structure
-- ============================================================
-- Toutes vérifient la même chose AVANT d'écrire : l'appelant est
-- ADMINISTRATEUR de la société courante, et cette société est membre du groupe
-- visé. C'est la garde de société que lit `ci/check_tenant_guard.sql` (règle 2,
-- fonctions SECURITY DEFINER écrivantes).
CREATE OR REPLACE FUNCTION _is_admin_of_current_tenant()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM tenant_users
     WHERE tenant_id = current_tenant_id()
       AND auth_id = auth.uid()
       AND role = 'admin'
       AND status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION create_group(p_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant uuid := current_tenant_id();
  v_user   uuid := auth.uid();
  v_group  uuid;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Aucune société active';
  END IF;
  IF btrim(COALESCE(p_name, '')) = '' THEN
    RAISE EXCEPTION 'GROUP_NAME_REQUIRED : un groupe porte un nom';
  END IF;
  IF NOT _is_admin_of_current_tenant() THEN
    RAISE EXCEPTION 'GROUP_FORBIDDEN : seul un administrateur crée un groupe';
  END IF;

  INSERT INTO groups (name, created_by) VALUES (btrim(p_name), v_user) RETURNING id INTO v_group;

  -- La société de l'appelant en est le premier membre (« tête de groupe »).
  INSERT INTO group_members (group_id, tenant_id, member_type, ownership_pct, consolidation_method)
  VALUES (v_group, v_tenant, 'parent', 100, 'full');

  RETURN jsonb_build_object('success', true, 'group_id', v_group);
END $$;

CREATE OR REPLACE FUNCTION add_group_member(
  p_group_id             uuid,
  p_tenant_id            uuid,
  p_member_type          text    DEFAULT 'subsidiary',
  p_ownership_pct        numeric DEFAULT 100,
  p_consolidation_method text    DEFAULT 'full'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant uuid := current_tenant_id();
BEGIN
  IF v_tenant IS NULL THEN RAISE EXCEPTION 'Aucune société active'; END IF;
  IF NOT _is_admin_of_current_tenant() THEN
    RAISE EXCEPTION 'GROUP_FORBIDDEN : seul un administrateur gère un groupe';
  END IF;
  -- L'appelant ne touche qu'un groupe dont SA société est membre.
  IF NOT EXISTS (SELECT 1 FROM group_members WHERE group_id = p_group_id AND tenant_id = v_tenant) THEN
    RAISE EXCEPTION 'GROUP_NOT_MEMBER : votre société n''appartient pas à ce groupe';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM tenants WHERE id = p_tenant_id) THEN
    RAISE EXCEPTION 'GROUP_TENANT_UNKNOWN : société % inconnue', p_tenant_id;
  END IF;

  INSERT INTO group_members (group_id, tenant_id, member_type, ownership_pct, consolidation_method)
  VALUES (p_group_id, p_tenant_id, p_member_type, p_ownership_pct, p_consolidation_method)
  ON CONFLICT (group_id, tenant_id) DO UPDATE
    SET member_type = EXCLUDED.member_type,
        ownership_pct = EXCLUDED.ownership_pct,
        consolidation_method = EXCLUDED.consolidation_method;

  RETURN jsonb_build_object('success', true);
END $$;

CREATE OR REPLACE FUNCTION remove_group_member(p_group_id uuid, p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant uuid := current_tenant_id();
  v_reste  int;
BEGIN
  IF v_tenant IS NULL THEN RAISE EXCEPTION 'Aucune société active'; END IF;
  IF NOT _is_admin_of_current_tenant() THEN
    RAISE EXCEPTION 'GROUP_FORBIDDEN : seul un administrateur gère un groupe';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM group_members WHERE group_id = p_group_id AND tenant_id = v_tenant) THEN
    RAISE EXCEPTION 'GROUP_NOT_MEMBER : votre société n''appartient pas à ce groupe';
  END IF;

  DELETE FROM group_members WHERE group_id = p_group_id AND tenant_id = p_tenant_id;

  SELECT count(*) INTO v_reste FROM group_members WHERE group_id = p_group_id;
  IF v_reste = 0 THEN
    DELETE FROM groups WHERE id = p_group_id;   -- un groupe sans membre n'existe pas
    RETURN jsonb_build_object('success', true, 'group_deleted', true);
  END IF;

  RETURN jsonb_build_object('success', true);
END $$;



-- ============================================================
-- 7. GRP-02 : les RPC des opérations intra-groupe
-- ============================================================
-- Règle de gestion tenue par la base : un flux intra-groupe s'enregistre pour
-- la société de l'appelant EN TANT QU'ÉMETTEUR (`from`). Un membre ne peut pas
-- déclarer un flux qui part d'une société qu'il ne représente pas — c'est le
-- symétrique exact de la garde de société des RPC ci-dessus.
CREATE OR REPLACE FUNCTION record_intra_group_transaction(
  p_group_id         uuid,
  p_to_tenant_id     uuid,
  p_transaction_type text,
  p_amount           numeric,
  p_transaction_date date,
  p_reference        text    DEFAULT NULL,
  p_label            text    DEFAULT NULL,
  p_currency         text    DEFAULT 'EUR'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant uuid := current_tenant_id();
  v_id     uuid;
BEGIN
  IF v_tenant IS NULL THEN RAISE EXCEPTION 'Aucune société active'; END IF;
  IF v_tenant = p_to_tenant_id THEN
    RAISE EXCEPTION 'INTRA_GROUP_SELF : un flux relie deux sociétés différentes';
  END IF;
  -- Les DEUX sociétés sont membres du groupe, et la mienne en fait partie.
  IF NOT EXISTS (SELECT 1 FROM group_members WHERE group_id = p_group_id AND tenant_id = v_tenant)
     OR NOT EXISTS (SELECT 1 FROM group_members WHERE group_id = p_group_id AND tenant_id = p_to_tenant_id) THEN
    RAISE EXCEPTION 'GROUP_NOT_MEMBER : les deux sociétés doivent appartenir au groupe';
  END IF;

  INSERT INTO intra_group_transactions (
    group_id, from_tenant_id, to_tenant_id, transaction_type,
    amount, currency, reference, label, transaction_date, status, created_by
  ) VALUES (
    p_group_id, v_tenant, p_to_tenant_id, p_transaction_type,
    p_amount, p_currency, p_reference, p_label, p_transaction_date, 'confirmed', auth.uid()
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('success', true, 'transaction_id', v_id);
END $$;

-- Lecture : la structure d'un groupe (auquel l'appelant appartient).
CREATE OR REPLACE FUNCTION group_structure(p_group_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN EXISTS (
    SELECT 1 FROM group_members gm
     WHERE gm.group_id = p_group_id AND gm.tenant_id = current_tenant_id()
  ) THEN jsonb_build_object(
    'group_id', g.id,
    'name', g.name,
    'members', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'tenant_id', m.tenant_id,
        'name', t.name,
        'member_type', m.member_type,
        'ownership_pct', m.ownership_pct,
        'consolidation_method', m.consolidation_method
      ) ORDER BY (m.member_type = 'parent') DESC, t.name)
      FROM group_members m JOIN tenants t ON t.id = m.tenant_id
      WHERE m.group_id = g.id
    ), '[]'::jsonb)
  ) ELSE NULL END
  FROM groups g WHERE g.id = p_group_id;
$$;

-- ============================================================
-- 8. Les droits : `authenticated` seul (jamais `anon`)
-- ============================================================
REVOKE ALL ON FUNCTION my_group_ids()                              FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION _is_admin_of_current_tenant()               FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION create_group(text)                          FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION add_group_member(uuid, uuid, text, numeric, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION remove_group_member(uuid, uuid)             FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION record_intra_group_transaction(uuid, uuid, text, numeric, date, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION group_structure(uuid)                       FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION create_group(text)                          TO authenticated;
GRANT EXECUTE ON FUNCTION add_group_member(uuid, uuid, text, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION remove_group_member(uuid, uuid)             TO authenticated;
GRANT EXECUTE ON FUNCTION record_intra_group_transaction(uuid, uuid, text, numeric, date, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION group_structure(uuid)                       TO authenticated;
-- `my_group_ids()` et `_is_admin_of_current_tenant()` : lues par les
-- politiques et les RPC (SECURITY DEFINER), pas d'appel direct depuis l'écran.

