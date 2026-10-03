-- ============================================================
-- 318_partner_identity_country.sql — lot A (tiers et comptes auxiliaires)
--
-- Recette /qa du 29/09/2026. A4 (ven-001, ach-002) : les fiches client et
-- fournisseur ne permettaient de saisir ni SIRET, ni code postal, ni ville, ni
-- conditions de paiement — et le pays n'était pas une donnée : la colonne
-- `country` portait un défaut figé.
--
--   Mesuré sur la base de recette AVANT : 643 clients et 160 fournisseurs,
--   tous en 'France', aucun SIRET. Un nom de pays n'est pas un code : rien ne
--   pouvait distinguer un client français d'un client belge ou luxembourgeois,
--   et la facture électronique écrivait « France » là où le standard EN 16931
--   attend deux lettres (B3, qui attend cette migration).
--
--   Ce que la 318 change
--   1. `country` devient un code ISO 3166-1 alpha-2, et l'existant est
--      normalisé (T05). C'est le format que le générateur Factur-X
--      (`customer.country`) et `banking.getCompanyCountryCode` lisaient déjà ;
--      `company_settings` garde son `country` (nom) et son `country_code`
--      (code), inchangés.
--   2. Plus de défaut `'France'` (T03) : un tiers dont on ne connaît pas le
--      pays n'en porte pas. Le repli « pays de la société **seulement si**
--      non saisi » est fait par l'écran, à la saisie — pas ici, où un tiers
--      n'a pas accès au pays de sa société.
--   3. `payment_term_id` : les conditions de paiement deviennent une liste
--      (`payment_terms`), pas un texte libre (T04). La colonne texte
--      `payment_terms` reste en place : l'échéance d'une facture née d'un bon
--      de livraison la lit (`misc.ts`), l'écran y écrit donc la valeur du
--      modèle choisi.
--   4. Une garde : un `country` renseigné doit être un code à deux lettres
--      (T01). Posée `NOT VALID` — l'existant non normalisable (un nom hors de
--      la table ci-dessous) n'est pas bloqué à la relecture ; il est compté
--      dans le fichier de tests pour être corrigé à la main. Une fois cet
--      existant corrigé, `VALIDATE CONSTRAINT` fermera la porte.
--
--   Preuves : sql/318_partner_identity_country_tests.sql (T01 à T05, 4 rouges
--   avant), et côté écran `PartnerIdentityForm.test.tsx`.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Les conditions de paiement deviennent une liste (A4)
-- ------------------------------------------------------------
-- Clé étrangère **composite** `(tenant_id, payment_term_id)`, et non simple :
-- la doctrine 237 (migration 237, test 237 T08) refuse qu'une clé mono-colonne
-- relie deux tables cloisonnées — sinon un client de la société A pourrait
-- pointer vers les conditions de paiement d'une société B. `payment_terms` porte
-- bien `UNIQUE (tenant_id, id)` pour recevoir cette référence.
--
-- `ON DELETE SET NULL (payment_term_id)` : seule la référence est détachée,
-- `tenant_id` reste — la 237 a posé cette forme pour la même raison.
ALTER TABLE customers ADD COLUMN IF NOT EXISTS payment_term_id uuid;
ALTER TABLE suppliers  ADD COLUMN IF NOT EXISTS payment_term_id uuid;
ALTER TABLE customers DROP CONSTRAINT IF EXISTS customers_payment_term_id_fkey;
ALTER TABLE suppliers  DROP CONSTRAINT IF EXISTS suppliers_payment_term_id_fkey;

DO $$ BEGIN
  ALTER TABLE customers ADD CONSTRAINT customers_payment_term_tenant_fkey
    FOREIGN KEY (tenant_id, payment_term_id) REFERENCES payment_terms (tenant_id, id)
    ON DELETE SET NULL (payment_term_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE suppliers ADD CONSTRAINT suppliers_payment_term_tenant_fkey
    FOREIGN KEY (tenant_id, payment_term_id) REFERENCES payment_terms (tenant_id, id)
    ON DELETE SET NULL (payment_term_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMENT ON COLUMN customers.payment_term_id IS
  'A4 (318) — conditions de paiement choisies dans la liste (payment_terms), sous la contrainte composite (doctrine 237). Le texte `payment_terms` reste tenu : l''échéance d''une facture née d''un bon de livraison le lit.';
COMMENT ON COLUMN suppliers.payment_term_id IS
  'A4 (318) — conditions de paiement choisies dans la liste (payment_terms), sous la contrainte composite (doctrine 237).';

-- ------------------------------------------------------------
-- 2. Le pays devient un code ISO 3166-1 alpha-2
-- ------------------------------------------------------------
-- Les noms que l'application a pu écrire (la colonne portait 'France' par
-- défaut ; `countries.ts` porte une liste de noms en français). Les 27 pays de
-- l'Union et les pays voisins que l'application connaît déjà
-- (`COUNTRY_CODE_MAP`).
-- Pas de `ON COMMIT DROP` : ce fichier se rejoue aussi par `psql -f`, où
-- chaque instruction est sa propre transaction — la table temporaire y serait
-- supprimée avant l'UPDATE. Elle est lâchée à la fin du fichier.
DROP TABLE IF EXISTS _pays_iso_318;
CREATE TEMP TABLE _pays_iso_318 (nom text PRIMARY KEY, code text NOT NULL);
INSERT INTO _pays_iso_318 (nom, code) VALUES
  -- Union européenne
  ('france','FR'), ('france métropolitaine','FR'), ('république française','FR'),
  ('allemagne','DE'), ('germany','DE'),
  ('belgique','BE'), ('belgium','BE'),
  ('luxembourg','LU'),
  ('espagne','ES'), ('spain','ES'),
  ('italie','IT'), ('italy','IT'),
  ('pays-bas','NL'), ('netherlands','NL'),
  ('portugal','PT'),
  ('autriche','AT'), ('austria','AT'),
  ('irlande','IE'), ('ireland','IE'),
  ('royaume-uni','GB'), ('united kingdom','GB'),
  ('danemark','DK'), ('denmark','DK'),
  ('suède','SE'), ('sweden','SE'),
  ('norvège','NO'), ('norway','NO'),
  ('finlande','FI'), ('finland','FI'),
  ('pologne','PL'), ('poland','PL'),
  ('république tchèque','CZ'), ('czech republic','CZ'),
  ('slovaquie','SK'), ('slovakia','SK'),
  ('slovénie','SI'), ('slovenia','SI'),
  ('croatie','HR'), ('croatia','HR'),
  ('grèce','GR'), ('greece','GR'),
  ('hongrie','HU'), ('hungary','HU'),
  ('roumanie','RO'), ('romania','RO'),
  ('bulgarie','BG'), ('bulgaria','BG'),
  ('estonie','EE'), ('estonia','EE'),
  ('lettonie','LV'), ('latvia','LV'),
  ('lituanie','LT'), ('lithuania','LT'),
  ('chypre','CY'), ('cyprus','CY'),
  ('malte','MT'), ('malta','MT'),
  -- Voisins et pays déjà connus de l'application
  ('suisse','CH'), ('switzerland','CH'),
  ('maroc','MA'), ('morocco','MA'),
  ('tunisie','TN'), ('tunisia','TN'),
  ('algérie','DZ'), ('algeria','DZ'),
  ('sénégal','SN'), ('senegal','SN'),
  ('côte d''ivoire','CI'),
  ('cameroun','CM'), ('cameroon','CM'),
  ('burkina faso','BF'),
  ('mali','ML'),
  ('niger','NE'),
  ('guinée','GN'),
  ('mozambique','MZ'),
  ('angola','AO'),
  ('djibouti','DJ');

-- 1. Les conditions de paiement deviennent une liste (A4)
-- ------------------------------------------------------------
ALTER TABLE customers ADD COLUMN IF NOT EXISTS payment_term_id uuid REFERENCES payment_terms(id) ON DELETE SET NULL;
ALTER TABLE suppliers  ADD COLUMN IF NOT EXISTS payment_term_id uuid REFERENCES payment_terms(id) ON DELETE SET NULL;

COMMENT ON COLUMN customers.payment_term_id IS
  'A4 (318) — conditions de paiement choisies dans la liste (payment_terms). Le texte `payment_terms` reste tenu : l''échéance d''une facture née d''un bon de livraison le lit.';
COMMENT ON COLUMN suppliers.payment_term_id IS
  'A4 (318) — conditions de paiement choisies dans la liste (payment_terms).';


UPDATE customers c SET country = m.code
  FROM _pays_iso_318 m WHERE lower(btrim(c.country)) = m.nom;
UPDATE suppliers  s SET country = m.code
  FROM _pays_iso_318 m WHERE lower(btrim(s.country)) = m.nom;

-- Un pays vide reste vide : on ne devine pas.
UPDATE customers SET country = NULL WHERE country IS NOT NULL AND length(btrim(country)) = 0;
UPDATE suppliers  SET country = NULL WHERE country IS NOT NULL AND length(btrim(country)) = 0;

COMMENT ON COLUMN customers.country IS
  'A4 (318) — code ISO 3166-1 alpha-2 (FR, BE, …). Un nom de pays n''est plus accepté ; aucun pays n''est supposé.';
COMMENT ON COLUMN suppliers.country IS
  'A4 (318) — code ISO 3166-1 alpha-2 (FR, BE, …).';

-- ------------------------------------------------------------
-- 3. Le défaut « France » disparaît (A4)
-- ------------------------------------------------------------
ALTER TABLE customers ALTER COLUMN country DROP DEFAULT;
ALTER TABLE suppliers  ALTER COLUMN country DROP DEFAULT;

-- ------------------------------------------------------------
-- 4. La garde : un pays renseigné est un code à deux lettres
-- ------------------------------------------------------------
DO $$ BEGIN
  ALTER TABLE customers ADD CONSTRAINT customers_country_iso_ck
    CHECK (country IS NULL OR country ~ '^[A-Z]{2}$') NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE suppliers ADD CONSTRAINT suppliers_country_iso_ck
    CHECK (country IS NULL OR country ~ '^[A-Z]{2}$') NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Reste à corriger à la main, puis `VALIDATE CONSTRAINT` : un nom de pays hors
-- table. Compté par le fichier de tests (T05) — sur la base de recette après
-- normalisation : 0 client et 0 fournisseur.
DROP TABLE IF EXISTS _pays_iso_318;
