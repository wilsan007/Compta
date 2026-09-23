-- ============================================================
-- 232_segregation.sql — H06 : la séparation des tâches ne séparait rien
--
-- CONSTAT, mesuré le 24/09 sur base neuve. `check_segregation_of_duties`
-- compare l'auteur d'une écriture (`journal_entries.created_by`) à celui qui la
-- valide. Or **`created_by` n'est jamais renseigné** : aucun défaut de colonne,
-- aucun trigger, et `post_journal_entry` — le seul chemin de saisie de
-- l'application — ne l'écrit pas. La fonction rend donc `true` sans rien
-- comparer : **même avec `enforce_segregation = true`, l'auteur validait sa
-- propre écriture** (T03 rouge). `validated_by` et `validated_at`, colonnes
-- existantes, ne sont écrits par aucune fonction non plus : ni l'auteur ni le
-- valideur d'une écriture n'étaient enregistrés nulle part.
--
-- CORRECTIF
--   1. l'auteur est posé à l'insertion, le valideur et sa date au passage en
--      « comptabilisée » — utile bien au-delà de la séparation (piste d'audit) ;
--   2. la séparation ne porte que sur les écritures **saisies** (D-13). Une
--      écriture produite par un document (facture, achat, paie, caisse, stock)
--      est créée et validée d'un seul mouvement par la fonction du document :
--      lui appliquer la règle rendrait la facturation impossible dès que
--      l'option est cochée (T07). Le document porte sa propre validation.
--   3. saisir et valider d'un seul geste (`post_journal_entry` avec
--      `status = 'posted'`) est refusé quand l'option est active : sans cela la
--      règle se contourne en cochant « comptabilisée » à la saisie (T05).
--
-- COMMENT ON RECONNAÎT UNE ÉCRITURE SAISIE, sans toucher aux 21 fonctions qui
-- en produisent : la pile d'appel. `GET DIAGNOSTICS … PG_CONTEXT` nomme les
-- fonctions traversées. Une écriture est saisie si la pile cite
-- `post_journal_entry`, ou si elle ne cite **aucune** fonction PL/pgSQL (l'insertion
-- vient alors directement du client PostgREST). Toute fonction génératrice —
-- y compris celles qu'on écrira demain — donne donc une écriture automatique,
-- sans rien déclarer : c'est le sens du défaut par défaut.
--
-- LIMITE ASSUMÉE. `is_manual` est calculé, jamais accepté du client : un
-- appelant qui l'enverrait à `false` pour échapper à la règle est ignoré
-- (T08), et il ne peut pas non plus l'éteindre par une mise à jour.
-- ============================================================

ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS is_manual boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN journal_entries.is_manual IS
  'Écriture saisie à la main (par post_journal_entry ou par une insertion directe du client), par opposition à une écriture produite par un document. Calculée par set_journal_entry_authorship ; la valeur envoyée par le client est ignorée.';

CREATE OR REPLACE FUNCTION set_journal_entry_authorship()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_ctx text;
  v_uid uuid := auth.uid();
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_by := COALESCE(NEW.created_by, v_uid);

    GET DIAGNOSTICS v_ctx = PG_CONTEXT;
    -- la première ligne est le cadre de ce trigger : on la retire avant de lire la pile
    v_ctx := regexp_replace(COALESCE(v_ctx, ''), '^[^' || chr(10) || ']*' || chr(10), '');
    NEW.is_manual := (v_ctx ~ 'function post_journal_entry')
                  OR (v_ctx !~ 'PL/pgSQL function [a-zA-Z_][a-zA-Z0-9_]*\(');

    IF NEW.status = 'posted' THEN
      NEW.validated_by := COALESCE(NEW.validated_by, v_uid);
      NEW.validated_at := COALESCE(NEW.validated_at, now());
    END IF;
    RETURN NEW;
  END IF;

  -- Mise à jour : la nature de l'écriture ne se change pas après coup
  NEW.is_manual := OLD.is_manual;
  NEW.created_by := COALESCE(OLD.created_by, NEW.created_by);

  IF NEW.status = 'posted' AND OLD.status IS DISTINCT FROM 'posted' THEN
    NEW.validated_by := COALESCE(v_uid, NEW.validated_by);
    NEW.validated_at := COALESCE(NEW.validated_at, now());
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_journal_entry_authorship ON journal_entries;
-- « a_ » : ce trigger doit poser l'auteur AVANT que enforce_journal_permissions
-- ne le lise (PostgreSQL déclenche les triggers d'un même moment par ordre de nom)
CREATE TRIGGER a_set_journal_entry_authorship
  BEFORE INSERT OR UPDATE ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION set_journal_entry_authorship();

-- La séparation s'applique aux écritures saisies, et le message le dit
CREATE OR REPLACE FUNCTION enforce_journal_entry_permissions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_enforce boolean := false;
BEGIN
  IF NEW.status = 'posted' AND (OLD.status IS NULL OR OLD.status <> 'posted') THEN
    IF NOT has_permission('journal_entry.post') THEN
      RAISE EXCEPTION 'Permission refusée : journal_entry.post';
    END IF;

    SELECT COALESCE(enforce_segregation, false) INTO v_enforce
    FROM company_settings WHERE tenant_id = NEW.tenant_id;

    -- D-13 : seules les écritures saisies sont concernées ; une écriture
    -- produite par un document est validée avec le document.
    IF v_enforce AND COALESCE(NEW.is_manual, false)
       AND NOT check_segregation_of_duties(auth.uid(), 'validate', NEW.id) THEN
      RAISE EXCEPTION 'Séparation des tâches : vous avez saisi cette écriture, sa validation revient à une autre personne';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- check_segregation_of_duties lit created_by : jusqu'ici il était toujours NULL,
-- donc la fonction rendait `true` sans rien comparer. Le corps ne change pas ;
-- ce qui change, c'est que l'auteur existe enfin.

-- La 228 l'a établi : `CREATE FUNCTION` accorde EXECUTE à PUBLIC. Une fonction
-- de trigger n'a rien à faire dans les RPC exposées — elle est appelée par le
-- moteur, pas par un client — et `ci/check_anon_grants.sql` a refusé celle-ci
-- dès sa création. C'est la ligne que toute migration créant une fonction doit
-- désormais écrire.
REVOKE EXECUTE ON FUNCTION set_journal_entry_authorship() FROM PUBLIC, anon;
