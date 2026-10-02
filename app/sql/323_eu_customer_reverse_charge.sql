-- ============================================================
-- 323_eu_customer_reverse_charge.sql — B3 (ven-009)
--
-- Recette /qa du 29/09/2026. Une facture à un client UE assujetti était une
-- facture française ordinaire : le formulaire proposait 20 %, l'écriture portait
-- 411000 D 250 / 707000 C 250 **sans aucun `vat_code`**, et Factur-X écrivait
-- `CategoryCode>Z` sans motif d'exonération. Mesuré :
--   `select l.account_code, l.debit, l.credit, l.vat_code from journal_lines l
--    join journal_entries e on e.id = l.journal_id
--    where e.invoice_ref = 'FAC-2026-000003'` → `411000|250|0|`, `707000|0|250|`
--   (dernière colonne vide : ni la CA3, ni la DEB/DES, ni Factur-X ne pouvaient
--   ranger l'opération).
--
-- CE QUE LA 323 ÉTABLIT
--
--   1. Le client a une **position fiscale** — `customers.fiscal_position_id`,
--      colonne qui existait déjà (FK vers `fiscal_positions`, table que l'écran
--      « Positions fiscales » remplissait **à la main**, 0 ligne sur la base de
--      recette). La 323 pose un `regime` sur cette table et **sème les trois
--      positions standard** d'une société : France, UE assujetti, hors UE.
--
--   2. Le régime se **déduit** du pays (`country`, code ISO-2 depuis la 318) et
--      du n° de TVA : FR → `fr` ; pays de l'UE **avec** n° de TVA → `eu_vat` ;
--      autre pays → `non_eu` ; pays inconnu (NULL) → **aucun régime**, on ne
--      devine pas. Un `fiscal_position_id` **déjà posé n'est jamais écrasé** :
--      la déduction est un défaut, pas une décision.
--
--   3. Une ligne de vente à un client UE assujetti porte le **code TVA `UE`**
--      (opération intracommunautaire non taxée en France) et **zéro TVA** ; à un
--      client hors UE, le code `EXO` (exonération d'export, art. 262-I CGI).
--      C'est la base qui le pose, pas l'écran : `invoice_line_compute` (197)
--      annule déjà la TVA d'un code autoliquidé, et la 323 lui donne le code
--      **avant** (`ta_fiscal_position` < `tg_line_compute`, ordre alphabétique
--      des déclencheurs `BEFORE`).
--
--   4. Conséquence comptable, vérifiée en T06 : l'écriture reste
--      411 D / 70x C, **sans ligne 4457x**, le CA est dans la classe 70 (donc
--      dans le `total_sales` de la CA3, règle 300) et `vat_collected` reste 0.
--
-- Preuves : sql/323_eu_customer_reverse_charge_tests.sql (T01 à T07, rouges
-- avant) et, côté écran, `facturX.test.ts` (category `AE`/`K` + motif) et le
-- formulaire de facture (0 % proposé, mention affichée).
-- ============================================================

-- ------------------------------------------------------------
-- 1. La position fiscale reçoit un régime
-- ------------------------------------------------------------
ALTER TABLE fiscal_positions ADD COLUMN IF NOT EXISTS regime text;
COMMENT ON COLUMN fiscal_positions.regime IS
  'B3 (323) — régime fiscal d''une position standard : fr, eu_vat, non_eu. NULL pour une position composée à la main.';

CREATE UNIQUE INDEX IF NOT EXISTS fiscal_positions_tenant_regime_key
  ON fiscal_positions (tenant_id, regime) WHERE regime IS NOT NULL;

-- ------------------------------------------------------------
-- 2. Le partenaire peut porter sa position fiscale
-- ------------------------------------------------------------
-- `invoices` et `purchase_invoices` la portaient déjà ; le **tiers** non — or
-- c'est lui qui détermine le régime d'une vente. Clé étrangère **composite**
-- `(tenant_id, fiscal_position_id)`, doctrine 237 : une position d'une autre
-- société ne doit pas pouvoir être référencée.
ALTER TABLE customers ADD COLUMN IF NOT EXISTS fiscal_position_id uuid;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS fiscal_position_id uuid;

DO $$ BEGIN
  ALTER TABLE customers ADD CONSTRAINT customers_fiscal_position_tenant_fkey
    FOREIGN KEY (tenant_id, fiscal_position_id) REFERENCES fiscal_positions (tenant_id, id)
    ON DELETE SET NULL (fiscal_position_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE suppliers ADD CONSTRAINT suppliers_fiscal_position_tenant_fkey
    FOREIGN KEY (tenant_id, fiscal_position_id) REFERENCES fiscal_positions (tenant_id, id)
    ON DELETE SET NULL (fiscal_position_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMENT ON COLUMN customers.fiscal_position_id IS
  'B3 (323) — régime fiscal du client (France, UE assujetti, hors UE). Déduit du pays et du n° de TVA s''il est laissé vide.';
COMMENT ON COLUMN suppliers.fiscal_position_id IS
  'B3 (323) — régime fiscal du fournisseur. Déduit du pays et du n° de TVA s''il est laissé vide.';

-- ------------------------------------------------------------
-- 3. L'Union européenne, en codes ISO-2 (27 États membres)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_eu_country(p_code text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT upper(btrim(COALESCE(p_code, ''))) IN (
    'AT','BE','BG','HR','CY','CZ','DK','EE','FI','FR','DE','GR','HU','IE','IT',
    'LV','LT','LU','MT','NL','PL','PT','RO','SK','SI','ES','SE'
  )
$$;
COMMENT ON FUNCTION is_eu_country(text) IS
  'B3 (323) — pays de l''Union européenne, codes ISO 3166-1 alpha-2 (27 États membres).';

-- B3 — cette fonction n'a AUCUN droit d'écran. Elle sert à déduire un régime
-- fiscal à l'intérieur d'un déclencheur ou d'une autre fonction, et elle
-- était livrée à `PUBLIC` : PostgreSQL accorde EXECUTE à PUBLIC sur toute
-- fonction créée, si rien ne le reprend. Un visiteur non connecté pouvait donc
-- appeler `is_eu_country` — mesure du 02/10 (`check_anon_grants`, porte 1.5a).
-- Elle est révoquée pour PUBLIC, `anon` et `authenticated` : seul le code SQL
-- qui l'appelle (déclencheurs, SECURITY DEFINER) l'exécute encore.
REVOKE ALL ON FUNCTION is_eu_country(text) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- 4. Le régime se déduit du pays et du n° de TVA
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION resolve_fiscal_regime(p_country text, p_vat_number text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    -- Un pays inconnu ne se devine pas : aucun régime, donc aucune décision.
    WHEN p_country IS NULL OR btrim(p_country) = '' THEN NULL
    WHEN upper(btrim(p_country)) = 'FR' THEN 'fr'
    WHEN is_eu_country(p_country) AND COALESCE(btrim(p_vat_number), '') <> '' THEN 'eu_vat'
    WHEN is_eu_country(p_country) THEN 'non_eu'   -- UE sans n° de TVA : pas d'assujetti, pas d'autoliquidation
    ELSE 'non_eu'
  END
$$;
COMMENT ON FUNCTION resolve_fiscal_regime(text, text) IS
  'B3 (323) — fr | eu_vat | non_eu, d''après le pays (ISO-2) et le n° de TVA. NULL si le pays est inconnu.';

-- Même raison que `is_eu_country` : un droit d'écran, ce n'est pas ce que c'est.
-- Elle est appelée par le déclencheur et par le rattrapage, pas par le client.
REVOKE ALL ON FUNCTION resolve_fiscal_regime(text, text) FROM PUBLIC, anon, authenticated;
-- ------------------------------------------------------------
-- 5. Les trois positions standard d une societe
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION ensure_standard_fiscal_position(p_tenant uuid, p_regime text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_id uuid;
BEGIN
  IF p_tenant IS NULL OR p_regime IS NULL OR p_regime NOT IN ('fr', 'eu_vat', 'non_eu') THEN
    RETURN NULL;
  END IF;

  SELECT id INTO v_id FROM fiscal_positions
  WHERE tenant_id = p_tenant AND regime = p_regime LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  INSERT INTO fiscal_positions (tenant_id, name, regime, country_code, auto_apply, active)
  VALUES (p_tenant,
          CASE p_regime WHEN 'fr' THEN 'France'
                        WHEN 'eu_vat' THEN 'UE assujetti'
                        ELSE 'Hors UE' END,
          p_regime,
          CASE p_regime WHEN 'fr' THEN 'FR' ELSE NULL END,
          p_regime <> 'fr',
          true)
  ON CONFLICT (tenant_id, regime) WHERE regime IS NOT NULL DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM fiscal_positions
    WHERE tenant_id = p_tenant AND regime = p_regime LIMIT 1;
  END IF;
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION ensure_standard_fiscal_position(uuid, text) FROM PUBLIC, anon, authenticated;

-- Rattrapage : les sociétés existantes reçoivent leurs trois positions.
DO $$
DECLARE t uuid;
BEGIN
  FOR t IN SELECT id FROM tenants LOOP
    PERFORM ensure_standard_fiscal_position(t, 'fr');
    PERFORM ensure_standard_fiscal_position(t, 'eu_vat');
    PERFORM ensure_standard_fiscal_position(t, 'non_eu');
  END LOOP;
END $$;

-- ------------------------------------------------------------
-- 6. La fiche du tiers recoit sa position fiscale (defaut, jamais impose)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION partner_apply_fiscal_position()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_regime text;
BEGIN
  -- Un choix explicite n'est jamais écrasé : c'est un défaut, pas une décision.
  IF NEW.fiscal_position_id IS NOT NULL THEN RETURN NEW; END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NEW; END IF;

  v_regime := resolve_fiscal_regime(NEW.country, NEW.vat_number);
  IF v_regime IS NULL OR v_regime = 'fr' THEN RETURN NEW; END IF;

  NEW.fiscal_position_id := ensure_standard_fiscal_position(NEW.tenant_id, v_regime);
  RETURN NEW;
END $$;

-- Un déclencheur n'a pas à être exécutable par un visiteur : il est attaché à
-- sa table et appelé par elle. `PUBLIC` pouvait l'appeler directement.
REVOKE ALL ON FUNCTION partner_apply_fiscal_position() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS ta_partner_fiscal_position ON customers;
CREATE TRIGGER ta_partner_fiscal_position
  BEFORE INSERT OR UPDATE OF country, vat_number, fiscal_position_id ON customers
  FOR EACH ROW EXECUTE FUNCTION partner_apply_fiscal_position();

DROP TRIGGER IF EXISTS ta_partner_fiscal_position ON suppliers;
CREATE TRIGGER ta_partner_fiscal_position
  BEFORE INSERT OR UPDATE OF country, vat_number, fiscal_position_id ON suppliers
  FOR EACH ROW EXECUTE FUNCTION partner_apply_fiscal_position();

-- Rattrapage : les tiers dont le pays et la TVA disent déjà le régime.
UPDATE customers SET fiscal_position_id = ensure_standard_fiscal_position(tenant_id, resolve_fiscal_regime(country, vat_number))
WHERE fiscal_position_id IS NULL AND resolve_fiscal_regime(country, vat_number) IN ('eu_vat', 'non_eu');
UPDATE suppliers SET fiscal_position_id = ensure_standard_fiscal_position(tenant_id, resolve_fiscal_regime(country, vat_number))
WHERE fiscal_position_id IS NULL AND resolve_fiscal_regime(country, vat_number) IN ('eu_vat', 'non_eu');

-- ------------------------------------------------------------
-- 7. Une ligne de vente suit la position fiscale du client
-- ------------------------------------------------------------
-- L'ordre alphabétique des déclencheurs `BEFORE` fait passer ce qui suit avant
-- `tg_line_compute` : `set_tenant_id_invoice_lines` (s) → `ta_fiscal_position`
-- (ta) → `tg_line_compute` (tg). Le code est donc posé **avant** que
-- `invoice_line_compute` n'annule la TVA d'un code autoliquidé (197).
--
-- ⚠️ UNE FONCTION PAR TABLE, et non une fonction partagée — décision de la
-- 280, appliquée ici pour la même raison et avec le même argument.
--
-- La fonction initiale était PARTAGÉE par `invoice_lines` et
-- `credit_note_lines`, deux tables dont les colonnes diffèrent : elle
-- nommait `NEW.invoice_id` dans une branche et `NEW.credit_note_id` dans
-- l'autre. Or `NEW` est un `record` : `plpgsql_check` valide les DEUX branches
-- contre le type `record`, qui n'a aucun de ces champs. Le refus est donc
-- statique (5 erreurs, mesurées le 02/10) — et il annonce l'erreur
-- d'exécution qui se produirait sur la table où le champ manque.
--
-- Le correctif n'est pas de faire taire le contrôle, mais de nommer des
-- colonnes qui existent : deux fonctions, chacune attachée à sa seule table,
-- chacune ne nommant que ses colonnes. Le test statique peut alors les
-- valider, et l'exécution ne peut pas tomber sur un champ absent.
CREATE OR REPLACE FUNCTION invoice_line_apply_customer_fiscal_position()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_customer uuid;
  v_regime text;
BEGIN
  SELECT i.customer_id INTO v_customer FROM invoices i
  WHERE i.id = NEW.invoice_id AND i.tenant_id = NEW.tenant_id;
  IF v_customer IS NULL THEN RETURN NEW; END IF;

  SELECT fp.regime INTO v_regime
  FROM customers cu
  JOIN fiscal_positions fp ON fp.id = cu.fiscal_position_id AND fp.tenant_id = cu.tenant_id
  WHERE cu.id = v_customer AND cu.tenant_id = NEW.tenant_id;
  IF v_regime IS NULL OR v_regime = 'fr' THEN RETURN NEW; END IF;

  -- L'opération n'est pas taxée en France : le code le dit et le taux est nul.
  NEW.vat_code := CASE v_regime WHEN 'eu_vat' THEN 'UE' ELSE 'EXO' END;
  NEW.vat_rate := 0;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION invoice_line_apply_customer_fiscal_position() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION credit_note_line_apply_customer_fiscal_position()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_customer uuid;
  v_regime text;
BEGIN
  SELECT c.customer_id INTO v_customer FROM credit_notes c
  WHERE c.id = NEW.credit_note_id AND c.tenant_id = NEW.tenant_id;
  IF v_customer IS NULL THEN RETURN NEW; END IF;

  SELECT fp.regime INTO v_regime
  FROM customers cu
  JOIN fiscal_positions fp ON fp.id = cu.fiscal_position_id AND fp.tenant_id = cu.tenant_id
  WHERE cu.id = v_customer AND cu.tenant_id = NEW.tenant_id;
  IF v_regime IS NULL OR v_regime = 'fr' THEN RETURN NEW; END IF;

  NEW.vat_code := CASE v_regime WHEN 'eu_vat' THEN 'UE' ELSE 'EXO' END;
  NEW.vat_rate := 0;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION credit_note_line_apply_customer_fiscal_position() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS ta_fiscal_position ON invoice_lines;
CREATE TRIGGER ta_fiscal_position
  BEFORE INSERT OR UPDATE ON invoice_lines
  FOR EACH ROW EXECUTE FUNCTION invoice_line_apply_customer_fiscal_position();

DROP TRIGGER IF EXISTS ta_fiscal_position ON credit_note_lines;
CREATE TRIGGER ta_fiscal_position
  BEFORE INSERT OR UPDATE ON credit_note_lines
  FOR EACH ROW EXECUTE FUNCTION credit_note_line_apply_customer_fiscal_position();

-- L'ancienne fonction partagée n'est plus appelée par personne. Elle est
-- supprimée : la laisser en place laisserait un corps que `plpgsql_check`
-- refuserait toujours, et que le jour où un nom serait réutilisé, on
-- réintroduirait le défaut qu'on vient de corriger.
DROP FUNCTION IF EXISTS line_apply_customer_fiscal_position();