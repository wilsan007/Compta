-- ═══════════════════════════════════════════════════════════════════════════
-- 461 — I-08, l'explicabilité : le DICTIONNAIRE de données
-- ═══════════════════════════════════════════════════════════════════════════
--
-- I-08 du référentiel (D.4) : « sur n'importe quel montant, un bouton
-- qui déroule la chaîne des documents et écritures qui produit ce
-- montant ». Ce que le référentiel exige techniquement, ce n'est pas
-- l'écran : « un indicateur est une requête NOMMÉE et DATÉE, jamais un
-- calcul recopié dans un écran ».
--
-- MESURÉ LE 02/10/2026, avant cette migration : **5 fichiers** de
-- `src/lib/queries/` calculent une marge projet, **8** un suivi
-- budgétaire. Chacun avec SA formule. C'est le défaut « définitions
-- concurrentes » (BUD-01, PROJ-02) : quand l'écran affiche « marge
-- 12 % », rien ne dit QUELLE des cinq formules a produit le 12 %.
--
-- CE QUE FAIT CE FICHIER. Le dictionnaire, et surtout la concurrence
-- rendue IMPOSSIBLE :
--
--   * une définition par (société, code, version), avec une PÉRIODE DE
--     VALIDITÉ (`valide_du` / `valide_au`) ;
--   * deux définitions ne se chevauchent JAMAIS pour la même société et
--     le même code : le déclencheur REFUSE l'insertion. On ne peut donc
--     plus avoir deux réponses au même « quelle est la marge ? » sur la
--     même période — remède STRUCTUREL, pas un commentaire ;
--   * `chain_metric_definition` rend l'unique définition en vigueur.
--
-- L'écran viendra lire ICI au lieu de recalculer. Ce fichier n'est que
-- la condition de possibilité d'I-08 ; il n'exécute aucune définition
-- (stocker du SQL exécutable dans une table que l'écran lit serait, à
-- lui seul, une faille).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.metric_definitions (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- NULL = le STANDARD livré avec le produit. Une société peut définir la
  -- sienne : elle l'emporte, sans jamais casser le standard.
  tenant_id      uuid REFERENCES public.tenants(id) ON DELETE CASCADE,
  code           text NOT NULL CHECK (btrim(code) <> ''),
  version        integer NOT NULL CHECK (version >= 1),
  libelle        text NOT NULL CHECK (btrim(libelle) <> ''),
  unite          text,
  sql_definition text NOT NULL CHECK (btrim(sql_definition) <> ''),
  valide_du      date NOT NULL,
  valide_au      date,
  note           text,
  cree_le        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT metric_definitions_periode_check
    CHECK (valide_au IS NULL OR valide_au >= valide_du)
);

-- `tenant_id` étant NULL pour le standard, une UNIQUE ordinaire n'y verrait
-- pas de doublon (PostgreSQL traite les NULL comme distincts) : on indexe
-- sur la clé « coalescée ».
CREATE UNIQUE INDEX IF NOT EXISTS ux_metric_definitions_portee
  ON public.metric_definitions (coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), code, version);

CREATE INDEX IF NOT EXISTS ix_metric_definitions_vigueur
  ON public.metric_definitions (code, valide_du, valide_au);

COMMENT ON TABLE public.metric_definitions IS
  '461 (I-08) : le dictionnaire de données. Un indicateur est une requête NOMMÉE et DATÉE, écrite une fois. Une définition ne se chevauche jamais avec une autre pour la même société et le même code : deux « définitions concurrentes » (BUD-01, PROJ-02) sont structurellement impossibles. tenant_id NULL = le standard livré.';

-- Lecture seule pour un client connecté : l'écran CONSOMME le dictionnaire,
-- il ne l'écrit pas.
ALTER TABLE public.metric_definitions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS metric_definitions_lecture ON public.metric_definitions;
CREATE POLICY metric_definitions_lecture ON public.metric_definitions
  FOR SELECT TO authenticated USING (tenant_id IS NULL OR tenant_id = current_tenant_id());
REVOKE ALL ON public.metric_definitions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.metric_definitions TO authenticated;
-- ─────────────────────────────────────────────────────────────
-- LE GARDE : deux définitions ne peuvent pas se chevaucher
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_metric_refuser_chevauchement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_autre_version integer;
BEGIN
  -- Une période se chevauche si elle commence avant la fin de l'autre ET
  -- se termine après son début. `coalesce(…, 'infinity')` traite
  -- `valide_au IS NULL` (« en cours ») comme une période ouverte.
  SELECT d.version INTO v_autre_version
    FROM public.metric_definitions d
   WHERE d.id <> NEW.id
     AND d.code = NEW.code
     AND d.tenant_id IS NOT DISTINCT FROM NEW.tenant_id
     AND d.valide_du < coalesce(NEW.valide_au, 'infinity'::date)
     AND coalesce(d.valide_au, 'infinity'::date) >= NEW.valide_du
   LIMIT 1;

  IF v_autre_version IS NOT NULL THEN
    RAISE EXCEPTION
      'METRIC_DEFINITION_CHEVAUCHEMENT : la definition % (version %) couvre deja une periode (% au %). Deux definitions concurrentes du meme indicateur sur la meme periode sont impossibles : c''est le defaut que ce dictionnaire corrige (BUD-01, PROJ-02).',
      NEW.code, NEW.version, NEW.valide_du, coalesce(NEW.valide_au::text, 'sans fin')
      USING ERRCODE = '23505';
  END IF;

  RETURN NEW;
END $fn$;

COMMENT ON FUNCTION public.chain_metric_refuser_chevauchement() IS
  '461 : garde BEFORE INSERT/UPDATE. REFUSE (23505, METRIC_DEFINITION_CHEVAUCHEMENT) une definition dont la periode recoupe celle d''une autre, pour la meme societe et le meme code. C''est ce qui rend les « definitions concurrentes » structurellement impossibles.';

REVOKE ALL ON FUNCTION public.chain_metric_refuser_chevauchement() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS zz_garde_461_chevauchement ON public.metric_definitions;
CREATE TRIGGER zz_garde_461_chevauchement BEFORE INSERT OR UPDATE ON public.metric_definitions
  FOR EACH ROW EXECUTE FUNCTION public.chain_metric_refuser_chevauchement();

-- ─────────────────────────────────────────────────────────────
-- LA RÉSOLUTION : la définition en vigueur à une date
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_metric_definition(
  p_tenant uuid,
  p_code   text,
  p_date   date
)
RETURNS TABLE (
  code           text,
  version        integer,
  libelle        text,
  unite          text,
  sql_definition text,
  valide_du      date,
  valide_au      date,
  portee         text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_courant uuid := current_tenant_id();
BEGIN
  IF p_code IS NULL OR btrim(p_code) = '' THEN
    RAISE EXCEPTION 'METRIC_DEFINITION_INCONNUE : aucun code d''indicateur n''a été demandé.'
      USING ERRCODE = '23503';
  END IF;

  -- Cloisonnement : un client ne demande que la société active. Le service
  -- (`auth.uid()` nul) garde sa borne explicite.
  IF auth.uid() IS NOT NULL
     AND (v_courant IS NULL OR p_tenant IS DISTINCT FROM v_courant) THEN
    RAISE EXCEPTION 'METRIC_DEFINITION_CLOISONNEMENT : cette société n''est pas la société active.'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT d.code, d.version, d.libelle, d.unite, d.sql_definition, d.valide_du, d.valide_au,
           CASE WHEN d.tenant_id IS NULL THEN 'standard' ELSE 'societe' END
      FROM public.metric_definitions d
     WHERE d.code = p_code
       -- La société d'abord : sa définition prime sur le standard.
       AND (d.tenant_id = p_tenant OR (d.tenant_id IS NULL AND p_tenant IS NOT DISTINCT FROM NULL))
       -- EN VIGUEUR à cette date : et non « la plus récente ».
       AND d.valide_du <= p_date
       AND (d.valide_au IS NULL OR d.valide_au >= p_date)
     ORDER BY (d.tenant_id IS NULL), d.version DESC
     LIMIT 1;

  -- Un indicateur qu'on ne sait pas définir ne se devine pas : « marge »
  -- ne veut rien dire tant qu'aucune définition datée ne le dit.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'METRIC_DEFINITION_INCONNUE : aucun indicateur « % » n''est défini (ni au standard, ni pour cette société) à cette date.', p_code
      USING ERRCODE = '23503';
  END IF;
END $fn$;

COMMENT ON FUNCTION public.chain_metric_definition(uuid, text, date) IS
  '461 (I-08) : rend l''UNIQUE définition d''un indicateur EN VIGUEUR à une date — celle de la société si elle en a une, celle du standard sinon. Un code inconnu est refusé (23503), jamais deviné : c''est ce qui donne un sens au « pourquoi ce chiffre ? ».';

REVOKE ALL ON FUNCTION public.chain_metric_definition(uuid, text, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_metric_definition(uuid, text, date) TO authenticated, service_role;

-- ── Cloisonnement (ex-421) ────────────────────────────────────────────────
-- Ces deux instructions vivaient dans `421_metric_definitions_cloisonnement.sql`.
-- Le runner applique dans l'ordre des NUMÉROS : la 421 passait donc AVANT la
-- création de la table, et toute base neuve s'arrêtait sur « relation
-- "public.metric_definitions" does not exist » (CI rouge du 02/10 au soir au
-- 03/10). Elles sont ici, à la suite de la table qu'elles cloisonnent.
CREATE INDEX IF NOT EXISTS ix_metric_definitions_tenant
  ON public.metric_definitions (tenant_id, code);
ALTER TABLE public.metric_definitions FORCE ROW LEVEL SECURITY;
