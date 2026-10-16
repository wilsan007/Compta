-- 709 — crm_sequences_relance
-- Numéro pris le 2026-10-11T06:25:39.439Z par migration-numero.mjs (ligne « plan6 F (plateforme) », branche plan6/f-plateforme).
--
-- ============================================================
-- F.5 / CRM-01 (partie F du plan du 05/10) : LES SÉQUENCES DE RELANCE
--
-- Le constat. Les tables d'un premier jet (`crm_sequences`,
-- `crm_sequence_steps`) ont été SUPPRIMÉES le 18/09 par la `164` (« nommées NULLE
-- PART »). F.5 les rétablit : relancer un prospect, c'est une CADENCE — un
-- premier e-mail, puis un appel trois jours après, puis une tâche… — et le
-- produit ne savait pas la décrire.
--
-- Le modèle, et ce qui le tient :
--   * une SÉQUENCE porte un nom, une description et un état (active ou non) ;
--     son nom est UNIQUE par société (deux « Relance devis » dans la même société
--     seraient un doublon, pas une variante) ;
--   * une ÉTAPE appartient à une séquence par une clé COMPOSITE
--     `(tenant_id, sequence_id)` : supprimer une séquence emporte ses étapes, et
--     une étape ne peut pas viser la séquence d'une autre société (ISO-02) ;
--   * le RANG (`step_order`) est UNIQUE dans la séquence (`(société, séquence,
--     rang)`) et strictement positif : deux étapes ne se disputent pas la même
--     place ;
--   * le DÉLAI (jours après l'étape précédente) est positif ou nul, et le
--     CANAL est contraint (`email`, `call`, `task`, `sms`) — la base refuse un
--     canal hors vocabulaire, pas l'écran.
--
-- RLS FORCÉE, index de société, QUATRE politiques par table (une par commande).
--
-- ⚠️ CE QUE CE LOT N'EST PAS. Il pose le CATALOGUE des séquences (la cadence
-- décrite). Il n'enrôle personne et ne PLANIFIE rien : « qui entre dans quelle
-- séquence, et quand part la prochaine étape » suppose une horloge et un
-- rattachement aux prospects — c'est un lot, pas un oubli.
-- ============================================================

CREATE TABLE IF NOT EXISTS crm_sequences (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name        text NOT NULL,
  description text,
  is_active   boolean NOT NULL DEFAULT true,
  created_by  uuid,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, name),
  UNIQUE (tenant_id, id)
);

CREATE INDEX IF NOT EXISTS idx_crm_sequences_tenant ON crm_sequences(tenant_id);

CREATE TABLE IF NOT EXISTS crm_sequence_steps (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  sequence_id uuid NOT NULL,
  step_order  int NOT NULL CHECK (step_order > 0),
  delay_days  int NOT NULL DEFAULT 0 CHECK (delay_days >= 0),
  channel     text NOT NULL CHECK (channel IN ('email', 'call', 'task', 'sms')),
  subject     text,
  body        text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, sequence_id, step_order),
  FOREIGN KEY (tenant_id, sequence_id) REFERENCES crm_sequences (tenant_id, id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_crm_sequence_steps_tenant   ON crm_sequence_steps(tenant_id);
CREATE INDEX IF NOT EXISTS idx_crm_sequence_steps_sequence ON crm_sequence_steps(sequence_id);

-- ============================================================
-- RLS : forcée, quatre politiques par table
-- ============================================================
ALTER TABLE crm_sequences ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_sequences FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS crm_sequences_select ON crm_sequences;
CREATE POLICY crm_sequences_select ON crm_sequences
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS crm_sequences_insert ON crm_sequences;
CREATE POLICY crm_sequences_insert ON crm_sequences
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS crm_sequences_update ON crm_sequences;
CREATE POLICY crm_sequences_update ON crm_sequences
  FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS crm_sequences_delete ON crm_sequences;
CREATE POLICY crm_sequences_delete ON crm_sequences
  FOR DELETE USING (tenant_id = current_tenant_id());

ALTER TABLE crm_sequence_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_sequence_steps FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS crm_sequence_steps_select ON crm_sequence_steps;
CREATE POLICY crm_sequence_steps_select ON crm_sequence_steps
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS crm_sequence_steps_insert ON crm_sequence_steps;
CREATE POLICY crm_sequence_steps_insert ON crm_sequence_steps
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS crm_sequence_steps_update ON crm_sequence_steps;
CREATE POLICY crm_sequence_steps_update ON crm_sequence_steps
  FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS crm_sequence_steps_delete ON crm_sequence_steps;
CREATE POLICY crm_sequence_steps_delete ON crm_sequence_steps
  FOR DELETE USING (tenant_id = current_tenant_id());

-- Le visiteur n'écrit rien (défauts du schéma : `ALL` à `anon` sur toute table neuve).
REVOKE ALL ON crm_sequences, crm_sequence_steps FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON crm_sequences, crm_sequence_steps TO authenticated;
GRANT ALL ON crm_sequences, crm_sequence_steps TO service_role;

