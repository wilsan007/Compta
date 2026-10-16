-- 705 — recrutement
-- Numéro pris le 2026-10-11T05:17:59.288Z par migration-numero.mjs (ligne « plan6 F (plateforme) », branche plan6/f-plateforme).
--
-- ============================================================
-- F.7 / RH-03 (partie F du plan du 05/10) : LE RECRUTEMENT
--
-- Le constat. Les tables d'un premier jet (`job_postings`, `job_applications`)
-- ont été SUPPRIMÉES le 18/09 par la `164` (« nommées NULLE PART : ni dans
-- `src/`, ni dans les fonctions edge »). C'était vrai. F.7 les rétablit sur un
-- modèle STANDARD, faute d'arbitrage produit : un POSTE (offre) porte ses
-- informations et un statut de cycle de vie ; une CANDIDATURE appartient à un
-- poste et avance dans un pipeline nommé.
--
-- Ce que le modèle tient, et qui n'est pas décoratif :
--   * la candidature référence le poste par une clé COMPOSITE
--     `(tenant_id, posting_id)` — supprimer un poste emporte ses candidatures,
--     et une candidature ne peut pas viser le poste d'une autre société (le
--     défaut ISO-02 que `ci/check_composite_fks.sql` refuse) ;
--   * les deux statuts sont CONTRAINTS (un poste : draft → open → closed/filled ;
--     une candidature : received → screening → interview → offer → hired/rejected) :
--     un statut hors vocabulaire est refusé par la base, pas par l'écran ;
--   * RLS FORCÉE, index de société, et QUATRE politiques par table (une par
--     commande) — la grille BT du dépôt s'applique.
--
-- Le vocabulaire de statut est un CHOIX, écrit ici pour être discuté : il couvre
-- le recrutement courant ; une société qui en veut un autre le changera par une
-- migration, pas en base à la main.
-- ============================================================

CREATE TABLE IF NOT EXISTS job_postings (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  reference      text,
  title          text NOT NULL,
  description    text,
  department     text,
  contract_type  text NOT NULL DEFAULT 'cdi'
    CHECK (contract_type IN ('cdi', 'cdd', 'stage', 'alternance', 'interim', 'freelance')),
  location       text,
  openings       int NOT NULL DEFAULT 1 CHECK (openings > 0),
  status         text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'open', 'closed', 'filled')),
  published_at   timestamptz,
  closing_at     date,
  created_by     uuid,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id)
);

CREATE INDEX IF NOT EXISTS idx_job_postings_tenant ON job_postings(tenant_id);

ALTER TABLE job_postings ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_postings FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS job_postings_select ON job_postings;
CREATE POLICY job_postings_select ON job_postings
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS job_postings_insert ON job_postings;
CREATE POLICY job_postings_insert ON job_postings
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS job_postings_update ON job_postings;
CREATE POLICY job_postings_update ON job_postings
  FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS job_postings_delete ON job_postings;
CREATE POLICY job_postings_delete ON job_postings
  FOR DELETE USING (tenant_id = current_tenant_id());


CREATE TABLE IF NOT EXISTS job_applications (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  posting_id      uuid NOT NULL,
  candidate_name  text NOT NULL,
  candidate_email text,
  candidate_phone text,
  source          text,
  status          text NOT NULL DEFAULT 'received'
    CHECK (status IN ('received', 'screening', 'interview', 'offer', 'hired', 'rejected')),
  applied_at      date NOT NULL DEFAULT CURRENT_DATE,
  notes           text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  -- Clé COMPOSITE : une candidature ne peut viser que le poste de SA société,
  -- et supprimer un poste emporte ses candidatures (ISO-02).
  FOREIGN KEY (tenant_id, posting_id) REFERENCES job_postings (tenant_id, id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_job_applications_tenant  ON job_applications(tenant_id);
CREATE INDEX IF NOT EXISTS idx_job_applications_posting ON job_applications(posting_id);

ALTER TABLE job_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_applications FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS job_applications_select ON job_applications;
CREATE POLICY job_applications_select ON job_applications
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS job_applications_insert ON job_applications;
CREATE POLICY job_applications_insert ON job_applications
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS job_applications_update ON job_applications;
CREATE POLICY job_applications_update ON job_applications
  FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS job_applications_delete ON job_applications;
CREATE POLICY job_applications_delete ON job_applications
  FOR DELETE USING (tenant_id = current_tenant_id());

-- Le visiteur n'écrit rien (les défauts du schéma donnent `ALL` à `anon` sur
-- toute table neuve — on le retire ici, comme le fait `78_revoke_anon_...`).
REVOKE ALL ON job_postings, job_applications FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON job_postings, job_applications TO authenticated;
GRANT ALL ON job_postings, job_applications TO service_role;

