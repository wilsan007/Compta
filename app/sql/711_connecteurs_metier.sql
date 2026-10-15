-- 711 — connecteurs_metier
-- Numéro pris le 2026-10-11T08:35:41.322Z par migration-numero.mjs (ligne « plan6 F (plateforme) », branche plan6/f-plateforme).
--
-- ============================================================
-- F.6 / API-03 (partie F du plan du 05/10) : LES CONNECTEURS MÉTIER
--
-- Le constat. La table d'un premier jet (`business_connectors`) a été SUPPRIMÉE
-- le 18/09 par la `164` (« nommée NULLE PART »). F.6 la rétablit : intégrer une
-- société, c'est d'abord DÉCLARER où l'on parle — un webhook, une API REST, un
-- ERP (Odoo, Sage), un prestataire (Stripe) — et le produit ne savait pas le
-- décrire.
--
-- Le modèle, et ce qui le tient :
--   * un CONNECTEUR porte un nom UNIQUE par société, un TYPE contraint
--     (`webhook`, `rest`, `odoo`, `sage`, `stripe`, `generic`), une URL de base,
--     et un MODE D'AUTHENTIFICATION contraint (`none`, `api_key`, `basic`,
--     `oauth2`) ;
--   * **il ne porte JAMAIS le secret** : `auth_ref` est le NOM sous lequel le
--     secret vit ailleurs (un secret d'Edge Function). Une table de connecteurs
--     qui contiendrait le jeton serait une fuite en attente ;
--   * l'URL passe la **garde SSRF du dépôt** — `is_allowed_webhook_url`
--     (migrations `154`/`167`) : HTTPS seulement, et jamais un hôte local ou une
--     IP obfusquée. On ne réécrit pas le contrôle ; on l'appelle. Un connecteur
--     vers `http://` ou `http://127.0.0.1` est refusé par un déclencheur, avec un
--     refus NOMMÉ (`CONNECTOR_URL_REFUSED`).
--
-- ⚠️ LIMITE DITE : HTTPS est une exigence, pas un confort — un connecteur vers un
-- Odoo on‑premise en HTTP **sera refusé**. C'est le prix de la garde SSRF du
-- dépôt, et il est écrit ici pour ne pas être découvert en production.
--
-- RLS FORCÉE, index de société, QUATRE politiques par table.
-- ============================================================

CREATE TABLE IF NOT EXISTS business_connectors (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name           text NOT NULL,
  connector_type text NOT NULL
    CHECK (connector_type IN ('webhook', 'rest', 'odoo', 'sage', 'stripe', 'generic')),
  base_url       text NOT NULL,
  auth_type      text NOT NULL DEFAULT 'none'
    CHECK (auth_type IN ('none', 'api_key', 'basic', 'oauth2')),
  auth_ref       text,                      -- le NOM du secret, jamais le secret
  is_active      boolean NOT NULL DEFAULT true,
  config         jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, name),
  CHECK (auth_type = 'none' OR auth_ref IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_business_connectors_tenant ON business_connectors(tenant_id);

-- ============================================================
-- Le déclencheur : l'URL passe la garde SSRF du dépôt
-- ============================================================
CREATE OR REPLACE FUNCTION validate_business_connector_url()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT is_allowed_webhook_url(NEW.base_url) THEN
    RAISE EXCEPTION 'CONNECTOR_URL_REFUSED : l''URL doit être HTTPS, vers un hôte public (pas d''hôte local ni d''IP obfusquée)';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_validate_business_connector_url ON business_connectors;
CREATE TRIGGER trg_validate_business_connector_url
  BEFORE INSERT OR UPDATE OF base_url ON business_connectors
  FOR EACH ROW EXECUTE FUNCTION validate_business_connector_url();

-- Une fonction de DÉCLENCHEUR n'est pas une fonction de service.
REVOKE ALL ON FUNCTION validate_business_connector_url() FROM PUBLIC, anon;

-- ============================================================
-- RLS : forcée, quatre politiques (une par commande)
-- ============================================================
ALTER TABLE business_connectors ENABLE ROW LEVEL SECURITY;
ALTER TABLE business_connectors FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS business_connectors_select ON business_connectors;
CREATE POLICY business_connectors_select ON business_connectors
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS business_connectors_insert ON business_connectors;
CREATE POLICY business_connectors_insert ON business_connectors
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS business_connectors_update ON business_connectors;
CREATE POLICY business_connectors_update ON business_connectors
  FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS business_connectors_delete ON business_connectors;
CREATE POLICY business_connectors_delete ON business_connectors
  FOR DELETE USING (tenant_id = current_tenant_id());

-- Le visiteur n'écrit rien (défauts du schéma : `ALL` à `anon` sur toute table neuve).
REVOKE ALL ON business_connectors FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON business_connectors TO authenticated;
GRANT ALL ON business_connectors TO service_role;

