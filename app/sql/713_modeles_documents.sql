-- ============================================================
-- 713 — F.6 / ADM-04 : LES MODÈLES DE DOCUMENTS, TENUS PAR LA BASE
-- Numéro pris le 2026-10-11T09:28:57.413Z par migration-numero.mjs
-- (ligne « plan6 F (plateforme) », branche plan6/f-plateforme).
--
--   CE QUI A ÉTÉ MESURÉ, sur base neuve (`pg_p5/fbase`) :
--   · `document_templates` EXISTE (depuis la 68) et porte ce qui fait l'IDENTITÉ
--     d'un document : le logo, les deux couleurs, `template_config`. Zéro ligne,
--     RLS **forcée**, index de société — l'intention y est, et l'écran l'écrit
--     déjà (`DocumentTemplatesPage`, `src/pages/Phase2Pages.tsx:314`) ;
--   · mais elle porte CINQ politiques, dont une `FOR ALL`
--     (`document_templates_tenant`). En RLS **permissive** les politiques
--     s'AJOUTENT : la `FOR ALL` est plus large que les quatre autres, donc c'est
--     elle qui décide — les quatre gardes par commande ne gardent RIEN. C'est le
--     défaut ISO-03 que la 238 a fermé sur 506 politiques, pas refermé ici (le
--     contrôle `check_policy_duplicates` ne voit pas cette forme : il compare des
--     couples (table, commande), et `ALL` n'en est pas un) ;
--   · RIEN ne tient « UN SEUL modèle par défaut par type » : `is_default` est un
--     booléen libre — deux modèles « par défaut » pour les factures cohabitent ;
--   · RIEN ne valide l'identité : `primary_color` accepte `bleu`, `#12345` ou
--     `rgb(1,2,3)` ; `logo_url` accepte `javascript:` ou `http://127.0.0.1` ;
--     `template_config` accepte un TABLEAU là où le rendu lit un OBJET ; `name`
--     accepte la chaîne vide ;
--   · l'écriture est ouverte à qui peut LIRE : un `viewer` crée, modifie et
--     supprime un modèle (PERM-01 / décision D-6 : c'est un réglage de société).
--
--   LE LOT : le modèle est VALIDÉ (nom, couleurs, logo, config), le DÉFAUT est
--   UNIQUE par (société, type), le rôle est OPPOSABLE, et UNE politique décide
--   par commande. Deux mécanismes, un chacun : l'index unique partiel tient la
--   règle (déclaratif, non contournable), et `set_default_document_template` est
--   l'ACTE de bascule (démarquer puis marquer, dans la même transaction).
--
--   ⚠️ CE QUE CE LOT NE FAIT PAS, et il faut le dire : il ne GÉNÈRE rien. La
--   production du document (le logo est TÉLÉCHARGÉ, puis converti en PDF) est
--   D-4 — convertisseur, `GOTENBERG_URL`, un appelant —, et `is_default` n'est
--   encore LU par personne aujourd'hui (mesuré : le flag est écrit, décoratif).
--   Ce lot rend la donnée VRAIE ; il ne la rend pas encore utile.
-- ============================================================

-- ------------------------------------------------------------
-- 1) LA RÈGLE : un seul modèle par défaut par (société, type)
--    Les doublons DÉJÀ écrits sont repris en gardant le plus récent —
--    jamais supprimés : on démarque, on n'efface pas (doctrine 450/453).
-- ------------------------------------------------------------
UPDATE document_templates d
   SET is_default = false
 WHERE d.is_default
   AND EXISTS (
     SELECT 1 FROM document_templates x
      WHERE x.tenant_id = d.tenant_id
        AND x.document_type = d.document_type
        AND x.is_default
        AND (COALESCE(x.created_at, 'epoch'::timestamptz), x.id)
          > (COALESCE(d.created_at, 'epoch'::timestamptz), d.id)
   );

CREATE UNIQUE INDEX IF NOT EXISTS uniq_document_templates_defaut
  ON document_templates (tenant_id, document_type)
  WHERE is_default;

-- ------------------------------------------------------------
-- 2) L'ACTE : faire d'un modèle LE modèle par défaut de son type
--    UNE transaction — démarquer l'ancien, marquer le nouveau. Un client
--    ne peut pas le faire en deux appels : entre les deux, il y aurait
--    deux « par défaut » (état que l'index refuse désormais), donc le
--    geste deviendrait impossible à moitié — c'est précisément ce qui
--    justifie une fonction plutôt qu'un enchaînement d'écritures.
--    Bornée à la SOCIÉTÉ ACTIVE, et gardée par le RÔLE (doctrine
--    271/274 : un lecteur ne change pas un réglage de société). La
--    portée du geste est le TYPE du modèle visé, jamais la société
--    entière — un défaut par type, pas un seul en tout.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_default_document_template(p_template_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_tenant uuid := current_tenant_id();
  v_type   text;
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT document_type INTO v_type
    FROM document_templates
   WHERE id = p_template_id AND tenant_id = v_tenant;

  IF v_type IS NULL THEN
    RAISE EXCEPTION 'DOCUMENT_TEMPLATE_INTROUVABLE : aucun modèle % dans cette société', p_template_id
      USING ERRCODE = '42501';
  END IF;

  IF auth.uid() IS NOT NULL AND NOT can_perform('document_templates', 'update') THEN
    RAISE EXCEPTION 'DOCUMENT_TEMPLATE_ROLE_REFUSE : votre rôle ne modifie pas les modèles de documents'
      USING ERRCODE = '42501';
  END IF;

  UPDATE document_templates
     SET is_default = false
   WHERE tenant_id = v_tenant
     AND document_type = v_type
     AND is_default
     AND id <> p_template_id;

  UPDATE document_templates
     SET is_default = true
   WHERE id = p_template_id;
END $$;

REVOKE ALL ON FUNCTION set_default_document_template(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_default_document_template(uuid) TO authenticated;

-- ------------------------------------------------------------
-- 3) UNE politique décide par commande — et le rôle est OPPOSABLE
--    La `FOR ALL` (`document_templates_tenant`) est RETIRÉE : en RLS
--    permissive elle s'AJOUTE aux quatre autres et les annule — c'est
--    elle, la plus large, qui décidait (ISO-03). Puis les trois
--    commandes d'ÉCRITURE passent sous `can_perform` (PERM-01,
--    décision D-6 : c'est un réglage de société) : lecture à quiconque
--    voit la société, écriture à qui en a le droit.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS document_templates_tenant ON document_templates;

DROP POLICY IF EXISTS tenant_select_document_templates ON document_templates;
CREATE POLICY tenant_select_document_templates ON document_templates FOR SELECT
  USING (tenant_id = current_tenant_id());

DROP POLICY IF EXISTS tenant_insert_document_templates ON document_templates;
CREATE POLICY tenant_insert_document_templates ON document_templates FOR INSERT
  WITH CHECK (tenant_id = current_tenant_id()
              AND can_perform('document_templates', 'insert'));

DROP POLICY IF EXISTS tenant_update_document_templates ON document_templates;
CREATE POLICY tenant_update_document_templates ON document_templates FOR UPDATE
  USING (tenant_id = current_tenant_id()
         AND can_perform('document_templates', 'update'))
  WITH CHECK (tenant_id = current_tenant_id()
              AND can_perform('document_templates', 'update'));

DROP POLICY IF EXISTS tenant_delete_document_templates ON document_templates;
CREATE POLICY tenant_delete_document_templates ON document_templates FOR DELETE
  USING (tenant_id = current_tenant_id()
         AND can_perform('document_templates', 'delete'));

-- ------------------------------------------------------------
-- 4) L'IDENTITÉ EST VALIDÉE — mesuré : elle ne l'était pas
--    Une couleur est un HEX (`bleu`, `#12345`, `rgb(1,2,3)` passaient),
--    le nom n'est pas vide, et `template_config` est un OBJET (le rendu
--    lit des clés ; un TABLEAU y passait sans bruit). `NULL` reste
--    permis : c'est « je n'ai rien choisi », pas une valeur fausse.
-- ------------------------------------------------------------
-- 4 a) LA REPRISE — RÉPARER AVANT DE DÉCLARER. Une migration qui refuse de
--      démarrer sur des lignes sales bloque la montée en production : on ne
--      peut pas poser un CHECK sur une table que la production a déjà remplie
--      avec autre chose (mesuré : la première version échouait sur
--      « check constraint is violated by some row »). Chaque réparation est
--      nommée, et aucune ne SUPPRIME une donnée :
--        · nom vide      → « Sans nom (<type>) » : un libellé utilisable —
--          la colonne est NOT NULL, on ne peut pas la remettre à NULL ;
--        · couleur fausse → NULL : c'est « je n'ai rien choisi », l'état que
--          le CHECK accepte et que l'écran comprend (son défaut est un HEX) ;
--        · config qui n'est pas un OBJET → CONSERVÉE, rangée sous la clé
--          `_config_initiale` : on ne jette pas la donnée, on la place là où
--          le rendu (qui lit des clés d'objet) ne la confondra pas.
-- ------------------------------------------------------------
UPDATE document_templates
   SET name = 'Sans nom (' || document_type || ')'
 WHERE btrim(name) = '';

UPDATE document_templates
   SET primary_color = NULL
 WHERE primary_color IS NOT NULL AND primary_color !~ '^#[0-9a-fA-F]{6}$';

UPDATE document_templates
   SET secondary_color = NULL
 WHERE secondary_color IS NOT NULL AND secondary_color !~ '^#[0-9a-fA-F]{6}$';

UPDATE document_templates
   SET template_config = jsonb_build_object('_config_initiale', template_config)
 WHERE template_config IS NOT NULL AND jsonb_typeof(template_config) <> 'object';

-- ------------------------------------------------------------
-- 4 b) PUIS LES RÈGLES
-- ------------------------------------------------------------
ALTER TABLE document_templates DROP CONSTRAINT IF EXISTS document_templates_name_check;
ALTER TABLE document_templates ADD CONSTRAINT document_templates_name_check
  CHECK (length(btrim(name)) > 0);

ALTER TABLE document_templates DROP CONSTRAINT IF EXISTS document_templates_primary_color_check;
ALTER TABLE document_templates ADD CONSTRAINT document_templates_primary_color_check
  CHECK (primary_color IS NULL OR primary_color ~ '^#[0-9a-fA-F]{6}$');

ALTER TABLE document_templates DROP CONSTRAINT IF EXISTS document_templates_secondary_color_check;
ALTER TABLE document_templates ADD CONSTRAINT document_templates_secondary_color_check
  CHECK (secondary_color IS NULL OR secondary_color ~ '^#[0-9a-fA-F]{6}$');

ALTER TABLE document_templates DROP CONSTRAINT IF EXISTS document_templates_config_check;
ALTER TABLE document_templates ADD CONSTRAINT document_templates_config_check
  CHECK (template_config IS NULL OR jsonb_typeof(template_config) = 'object');

-- ------------------------------------------------------------
-- 5) LE LOGO : une URL publique, ou rien
--    La chaîne VIDE n'est pas une valeur, c'est « rien » : le
--    formulaire de l'écran envoie `logo_url: ''` quand aucun logo n'est
--    choisi — sans normalisation, le CHECK refuserait un état légitime
--    (doctrine M2, X1/272 : « e-mail vide → NULL »).
--    Puis l'URL est validée par la GARDE SSRF DU DÉPÔT : le logo est
--    TÉLÉCHARGÉ par le convertisseur au moment de produire le document
--    (D-4), donc une URL interne ou une IP obfusquée est un SSRF en
--    attente. On ne réécrit pas le contrôle, on l'APPELLE (doctrine 711).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION validate_document_template() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.logo_url IS NOT NULL AND btrim(NEW.logo_url) = '' THEN NEW.logo_url := NULL; END IF;
  IF NEW.primary_color IS NOT NULL AND btrim(NEW.primary_color) = '' THEN NEW.primary_color := NULL; END IF;
  IF NEW.secondary_color IS NOT NULL AND btrim(NEW.secondary_color) = '' THEN NEW.secondary_color := NULL; END IF;

  IF NEW.logo_url IS NOT NULL AND NOT is_allowed_webhook_url(NEW.logo_url) THEN
    RAISE EXCEPTION 'DOCUMENT_TEMPLATE_LOGO_URL_REFUSED : le logo doit être en HTTPS, vers un hôte public (pas d''hôte local ni d''IP obfusquée)';
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_validate_document_template ON document_templates;
CREATE TRIGGER trg_validate_document_template
  BEFORE INSERT OR UPDATE ON document_templates
  FOR EACH ROW EXECUTE FUNCTION validate_document_template();

-- Une fonction de DÉCLENCHEUR n'est pas une fonction de service.
REVOKE ALL ON FUNCTION validate_document_template() FROM PUBLIC, anon;

-- ------------------------------------------------------------
-- 6) Les droits : rien pour le visiteur, et rien de plus pour le rôle
--    Mesuré avant : `anon` n'avait rien (bien), mais `authenticated`
--    portait `REFERENCES` et `TRIGGER` sur cette table — deux droits
--    qu'aucun écran n'utilise et qui laissent un rôle poser un
--    déclencheur ou une clé étrangère sur un réglage de société. Retirés.
--    `SELECT/INSERT/UPDATE/DELETE` restent : c'est le CRUD de l'écran, et
--    il est passé sous `can_perform` (section 3).
-- ------------------------------------------------------------
REVOKE ALL ON TABLE document_templates FROM anon;
REVOKE REFERENCES, TRIGGER ON TABLE document_templates FROM authenticated;
