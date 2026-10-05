-- ═══════════════════════════════════════════════════════════════════════════
-- 380 — pack_model : le MODÈLE DE DONNÉES d'un pack de législation
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. LOT 1-A, tâche LOC1-01 du cahier de localisation
-- (doc/localisation/CAHIER-DES-CHARGES-LOCALISATION.md §5). Aujourd'hui
-- `legislation_packs` décrit un pays à PLAT : pas de hiérarchie (un référentiel,
-- un pays et un secteur sont indiscernables), pas de version, pas de statut de
-- publication, une seule notion de décimales, pas de règle d'arrondi. Cette
-- migration pose le MODÈLE : les colonnes de paramétrage, et la hiérarchie
-- « secteur → pays → référentiel » que la résolution héritée (LOC1-03) lira.
--
-- LA HIÉRARCHIE, ET D'OÙ VIENNENT LES PARENTS — DÉCISION ASSUMÉE. La contrainte
-- `legislation_packs_hierarchy_chk` exige qu'un pack de niveau `country` ou
-- `sector` ait un parent, et qu'un `referential` n'en ait pas. Les 17 packs pays
-- existants n'ont AUCUN parent : il faut donc les raccrocher. Le référentiel
-- n'est PAS inventé, il est **lu dans la donnée** : la colonne `accounting_standard`
-- EST déjà la norme comptable (PCG, SYSCOHADA, IFRS, UK_GAAP…). On crée donc
-- **un référentiel par norme** et chaque pack pays se raccroche à la sienne.
-- `SYSCOHADA` est le seul cas particulier : c'est à la fois une norme ET un pack
-- portant `country_code 'CI'` (le doublon). La tâche LOC1-48 le tranche : ce
-- pack DEVIENT le référentiel `SYSCOHADA` (niveau `referential`, `country_code`
-- NULL), et `CI` reste le pack pays. Aucune autre table n'est touchée.
--
-- CE QUI N'EST PAS DANS CETTE MIGRATION. Les tables de données du pack
-- (`pack_sources`, `pack_account_roles`, `pack_holidays`… — LOC1-02), la
-- résolution héritée (`pack_lineage`, `resolve_account` — LOC1-03/05) et le
-- contenu des packs viennent APRÈS. Ici : le moule, pas la farine.
--
-- REJOUABLE. `ADD COLUMN IF NOT EXISTS`, `DROP CONSTRAINT IF EXISTS` + `ADD`,
-- `INSERT … ON CONFLICT DO NOTHING` et un `NOT EXISTS` de garde : un second
-- passage est un no-op (la suite `380` le prouve, T06).
--
-- Numéro pris le 2026-10-05T18:26:32.472Z par migration-numero.mjs
-- (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. Les colonnes du modèle de pack
--    Additives, avec un défaut qui reproduit le comportement d'aujourd'hui :
--    un pack existant reste un pays, version 0.0.0, brouillon, arrondi
--    « au plus proche », semaine du lundi, week-end samedi/dimanche.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE legislation_packs
  ADD COLUMN IF NOT EXISTS level              text    NOT NULL DEFAULT 'country',
  ADD COLUMN IF NOT EXISTS parent_code        text,
  ADD COLUMN IF NOT EXISTS sector             text,
  ADD COLUMN IF NOT EXISTS version            text    NOT NULL DEFAULT '0.0.0',
  ADD COLUMN IF NOT EXISTS status             text    NOT NULL DEFAULT 'draft',
  ADD COLUMN IF NOT EXISTS published_at       timestamptz,
  ADD COLUMN IF NOT EXISTS validated_by       text,
  ADD COLUMN IF NOT EXISTS price_decimals     integer NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS quantity_decimals  integer NOT NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS rounding_mode      text    NOT NULL DEFAULT 'half_up',
  ADD COLUMN IF NOT EXISTS rounding_level     text    NOT NULL DEFAULT 'line',
  ADD COLUMN IF NOT EXISTS number_system      text    NOT NULL DEFAULT 'latn',
  ADD COLUMN IF NOT EXISTS ui_languages       text[]  NOT NULL DEFAULT '{fr}',
  ADD COLUMN IF NOT EXISTS document_languages text[]  NOT NULL DEFAULT '{fr}',
  ADD COLUMN IF NOT EXISTS week_start         integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS weekend_days       integer[] NOT NULL DEFAULT '{6,7}',
  ADD COLUMN IF NOT EXISTS source_ref         text;

COMMENT ON COLUMN legislation_packs.level IS
  '380 (LOT 1-A) : referential (norme comptable, sans country_code) | country (un pays) | sector (variante d''un pays). La hiérarchie secteur → pays → référentiel est bornée par legislation_packs_hierarchy_chk.';
COMMENT ON COLUMN legislation_packs.parent_code IS
  '380 (LOT 1-A) : le parent dans la lignée. NULL pour un référentiel, obligatoire pour un pays ou un secteur. Le référentiel d''un pack pays est sa norme comptable (accounting_standard).';
COMMENT ON COLUMN legislation_packs.status IS
  '380 (LOT 1-A) : cycle de vie du pack — draft → validated → published → archived (LOC1-54 affine les transitions).';

-- Un pack pays porte un code ISO à deux lettres ; un référentiel n''en porte pas.
ALTER TABLE legislation_packs ALTER COLUMN country_code DROP NOT NULL;

-- ─────────────────────────────────────────────────────────────
-- 2. Les référentiels : UN par norme comptable, lu dans la donnée.
--    SYSCOHADA est exclu ici (le pack existe déjà) : il est promu en 3.
--    Les colonnes de format (devise, décimales, locale…) sont recopiées d'un
--    pack pays de la même norme, faute de mieux — elles n'ont de sens qu'au
--    niveau country et le validateur (V03) les contrôlera.
-- ─────────────────────────────────────────────────────────────
WITH normes AS (
  SELECT DISTINCT ON (accounting_standard)
         accounting_standard, currency, currency_decimals, date_format, locale,
         fiscal_year_start, tax_id_label, tax_id_secondary_label, tenant_id
    FROM legislation_packs
   WHERE level = 'country'
     AND accounting_standard IS NOT NULL
     AND accounting_standard <> 'SYSCOHADA'
   ORDER BY accounting_standard, code
)
INSERT INTO legislation_packs
  (code, name, country_code, country_name, accounting_standard,
   currency, currency_decimals, date_format, locale, fiscal_year_start,
   tax_id_label, tax_id_secondary_label, is_default, active, tenant_id,
   level, parent_code)
SELECT n.accounting_standard,
       n.accounting_standard || ' — référentiel comptable',
       NULL,
       n.accounting_standard || ' — référentiel comptable',
       n.accounting_standard,
       n.currency, n.currency_decimals, n.date_format, n.locale, n.fiscal_year_start,
       n.tax_id_label, n.tax_id_secondary_label, false, true, n.tenant_id,
       'referential', NULL
  FROM normes n
 WHERE NOT EXISTS (SELECT 1 FROM legislation_packs r WHERE r.code = n.accounting_standard)
ON CONFLICT (code) DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 3. LOC1-48 — SYSCOHADA était à la fois une norme ET un pays ('CI').
--    Il DEVIENT le référentiel : plus de country_code. 'CI' reste le pays.
-- ─────────────────────────────────────────────────────────────
UPDATE legislation_packs
   SET level = 'referential', country_code = NULL, parent_code = NULL
 WHERE code = 'SYSCOHADA'
   AND (level <> 'referential' OR country_code IS NOT NULL OR parent_code IS NOT NULL);

-- ─────────────────────────────────────────────────────────────
-- 4. Raccrocher chaque pack pays à SON référentiel (sa norme)
-- ─────────────────────────────────────────────────────────────
UPDATE legislation_packs p
   SET parent_code = p.accounting_standard
 WHERE p.level IN ('country', 'sector')
   AND p.parent_code IS NULL
   AND p.accounting_standard IS NOT NULL
   AND EXISTS (SELECT 1 FROM legislation_packs r
                WHERE r.code = p.accounting_standard AND r.level = 'referential');

-- ─────────────────────────────────────────────────────────────
-- 5. Les contraintes du modèle (nommées, rejouables).
--    Ajoutées APRÈS le raccrochage : la contrainte de hiérarchie exige un
--    parent, elle refuserait les 17 packs pays s'ils n'étaient pas raccrochés.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE legislation_packs DROP CONSTRAINT IF EXISTS legislation_packs_level_chk;
ALTER TABLE legislation_packs ADD CONSTRAINT legislation_packs_level_chk
  CHECK (level IN ('referential', 'country', 'sector'));

ALTER TABLE legislation_packs DROP CONSTRAINT IF EXISTS legislation_packs_sector_chk;
ALTER TABLE legislation_packs ADD CONSTRAINT legislation_packs_sector_chk
  CHECK (sector IS NULL OR sector IN ('private', 'public_enterprise', 'public_administrative', 'non_profit'));

ALTER TABLE legislation_packs DROP CONSTRAINT IF EXISTS legislation_packs_status_chk;
ALTER TABLE legislation_packs ADD CONSTRAINT legislation_packs_status_chk
  CHECK (status IN ('draft', 'validated', 'published', 'archived'));

ALTER TABLE legislation_packs DROP CONSTRAINT IF EXISTS legislation_packs_rounding_mode_chk;
ALTER TABLE legislation_packs ADD CONSTRAINT legislation_packs_rounding_mode_chk
  CHECK (rounding_mode IN ('half_up', 'half_even', 'down'));

ALTER TABLE legislation_packs DROP CONSTRAINT IF EXISTS legislation_packs_rounding_level_chk;
ALTER TABLE legislation_packs ADD CONSTRAINT legislation_packs_rounding_level_chk
  CHECK (rounding_level IN ('line', 'document'));

-- Hiérarchie : un référentiel n'a PAS de parent, un pays/secteur en a un.
ALTER TABLE legislation_packs DROP CONSTRAINT IF EXISTS legislation_packs_hierarchy_chk;
ALTER TABLE legislation_packs ADD CONSTRAINT legislation_packs_hierarchy_chk CHECK (
  (level = 'referential' AND parent_code IS NULL) OR
  (level IN ('country', 'sector') AND parent_code IS NOT NULL)
);

-- Un référentiel n'a PAS de code pays ; un pays/secteur en a un (ISO, 2 lettres).
ALTER TABLE legislation_packs DROP CONSTRAINT IF EXISTS legislation_packs_country_chk;
ALTER TABLE legislation_packs ADD CONSTRAINT legislation_packs_country_chk CHECK (
  (level = 'referential' AND country_code IS NULL) OR
  (level IN ('country', 'sector') AND country_code ~ '^[A-Z]{2}$')
);

-- La hiérarchie est une clé étrangère COMPOSITE, pas mono-colonne : la porte
-- ISO-02 (237, `ci/check_composite_fks.sql`) l'exige dès que l'enfant porte
-- `tenant_id` — sinon le pack d'une société pourrait désigner le parent d'une
-- autre. Conséquence assumée : un parent appartient à la MÊME société que l'enfant
-- (les packs globaux vivent tous sous la société technique `…0001`). Même forme
-- que `company_settings_legislation_pack_code_fkey`. Ajoutée APRÈS le
-- raccrochage, pour ne pas être violée par les packs encore sans parent.
ALTER TABLE legislation_packs DROP CONSTRAINT IF EXISTS legislation_packs_parent_code_fkey;
ALTER TABLE legislation_packs ADD CONSTRAINT legislation_packs_parent_code_fkey
  FOREIGN KEY (tenant_id, parent_code) REFERENCES legislation_packs (tenant_id, code);

