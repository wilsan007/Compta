-- ═══════════════════════════════════════════════════════════════════════════
-- 460 — I-01, la « Vue Chaîne » : l'ascendance et la descendance
-- ═══════════════════════════════════════════════════════════════════════════
--
-- L'innovation I-01 du référentiel (D.4) : « depuis n'importe quel document
-- (devis, commande, réception, facture, bulletin, ticket de caisse, ordre de
-- fabrication, note de frais), une frise cliquable : ce qui l'a produit, ce
-- qu'il a produit, et les pièces comptables associées ».
--
-- Le référentiel est explicite : « nous avons déjà 62 chaînages identifiés et
-- une fonction par maillon ; il s'agit de les INSTRUMENTER, pas de les
-- réécrire ». C'est ce que fait ce fichier : il n'ajoute AUCUN maillon et ne
-- modifie AUCUN déclencheur. Il ne fait que LIRE `document_links` — que la
-- partie 5 (450) a rendue loyable, type de document par type de document.
--
-- CE QUE FAIT LA FONCTION.
--   chain_document_arborescence(société, type, id, sens, profondeur, fermés)
--     sens       'aval' (ce que ce document a produit, par défaut)
--                'amont' (ce qui l'a produit)
--     profondeur borne la descente (1 à 100, 20 par défaut)
--     fermés     faux (défaut) : seuls les liens ACTIFS portent la chaîne —
--                c'est l'état réel. vrai : l'historique revient aussi, avec son
--                état (rompu / remplace). Rien n'est jamais effacé.
--
-- TROIS GARDES, CHACUNE PAYÉE PAR UNE MESURE.
--
-- 1. **Le cycle.** Un maillon peut se renvoyer la balle : la facture
--    « produit » la commande. Sans borne, `WITH RECURSIVE` ne s'arrête jamais.
--    On borne donc la profondeur, ET on porte un chemin (`type:id`) déjà
--    visité qu'on refuse de réemprunter.
-- 2. **Le renvoi de clé.** `id` et `sens` sont des noms de colonne du CTE ;
--    les variables locales sont donc préfixées `v_`.
-- 3. **Le cloisonnement.** La société vient de `current_tenant_id()` (le
--    contexte, comme PostgREST le pose) ; `p_tenant` sert de borne explicite,
--    et toute divergence est refusée. C'est la suite 460, T06.
--
-- Le libellé vient du REGISTRE (450) : un libellé par type, écrit une fois.
-- L'écran n'a plus à traduire 27 noms de tables.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.chain_document_arborescence(
  p_tenant     uuid,
  p_type       text,
  p_id         uuid,
  p_sens       text    DEFAULT 'aval',
  p_profondeur integer DEFAULT 20,
  p_fermes     boolean DEFAULT false
)
RETURNS TABLE (
  sens       text,
  profondeur integer,
  type       text,
  id         uuid,
  libelle    text,
  effet      text,
  etat       text,
  tour       integer,
  lien_date  timestamptz,
  lien_id    uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_courant    uuid := current_tenant_id();
  v_sens       text;
  v_profondeur integer;
BEGIN
  -- Garde : une chaîne sans société n'est pas une chaîne.
  IF p_tenant IS NULL OR p_type IS NULL OR p_id IS NULL THEN
    RAISE EXCEPTION 'Vue Chaîne : société, type et document sont obligatoires.'
      USING ERRCODE = '23514';
  END IF;

  -- Garde 3 : le cloisonnement. Un client est un utilisateur (`auth.uid()`
  -- non nul) : il ne voit QUE la société active, et il doit y appartenir. On
  -- mesure pourquoi la condition est si entière : une version plus laxiste
  -- (`v_courant IS NOT NULL AND …`) laissait passer TOUTE société dès qu'aucun
  -- contexte ne se résolvait — c'est-à-dire dès que l'appelant n'est membre
  -- de rien, ce qui est précisément le cas à attaquer. Le service (tâche de
  -- nuit, `auth.uid()` nul) garde sa borne explicite `p_tenant`.
  IF auth.uid() IS NOT NULL
     AND (v_courant IS NULL OR p_tenant IS DISTINCT FROM v_courant) THEN
    RAISE EXCEPTION 'Vue Chaîne : cette société n''est pas la société active.'
      USING ERRCODE = '42501';
  END IF;

  v_sens := lower(btrim(coalesce(p_sens, 'aval')));
  IF v_sens NOT IN ('aval', 'amont') THEN
    RAISE EXCEPTION 'Vue Chaîne : sens attendu « aval » ou « amont », reçu « % ».', p_sens
USING ERRCODE = '23514';
  END IF;

  -- Garde 1, première moitié : la profondeur est bornée par l'appelant ET
  -- par nous. 100 niveaux de chaîne n'existent pas ; c'est une sécurité.
  v_profondeur := least(greatest(coalesce(p_profondeur, 20), 1), 100);

RETURN QUERY
  WITH RECURSIVE etape AS (
    -- La RACINE : le document lui-même, profondeur 0.
    SELECT v_sens                                   AS sens,
           0                                       AS profondeur,
           p_type::text                            AS type,
           p_id                                    AS id,
           NULL::text                              AS effet,
           NULL::text                              AS etat,
           NULL::integer                           AS tour,
           NULL::timestamptz                       AS lien_date,
           NULL::uuid                              AS lien_id,
           ARRAY[p_type::text || ':' || p_id::text] AS chemin
    UNION ALL
    -- UNE SEULE branche récursive, qui suit le sens demandé. C'est mesuré :
    -- PostgreSQL n'accepte pas deux références à `etape` dans le même CTE
    -- (« recursive reference to query "etape" must not appear within its
    -- non-recursive term »). Deux branches séparées imposaient de dupliquer
    -- tout ; celle-ci se contente de choisir la colonne.
    SELECT e.sens,
           e.profondeur + 1,
           CASE WHEN e.sens = 'aval' THEN l.aval_type  ELSE l.amont_type END,
           CASE WHEN e.sens = 'aval' THEN l.aval_id    ELSE l.amont_id   END,
           l.effet,
           l.etat,
           l.tour,
           l.created_at,
           l.id,
           e.chemin || (CASE WHEN e.sens = 'aval' THEN l.aval_type  ELSE l.amont_type END
                            || ':' ||
                            CASE WHEN e.sens = 'aval' THEN l.aval_id::text ELSE l.amont_id::text END)
    FROM etape e
    JOIN document_links l
      ON l.tenant_id = p_tenant
     AND ( (e.sens = 'aval'  AND l.amont_type = e.type AND l.amont_id = e.id)
        OR (e.sens = 'amont' AND l.aval_type  = e.type AND l.aval_id  = e.id) )
     AND (p_fermes OR l.etat = 'actif')
    WHERE e.profondeur < v_profondeur
      AND NOT ((CASE WHEN e.sens = 'aval' THEN l.aval_type ELSE l.amont_type END
                   || ':' ||
                   CASE WHEN e.sens = 'aval' THEN l.aval_id::text ELSE l.amont_id::text END)
              = ANY (e.chemin))
  )
  SELECT e.sens,
         e.profondeur,
         e.type,
         e.id,
         d.libelle_fr,
         e.effet,
         coalesce(e.etat, 'racine'),
         e.tour,
         e.lien_date,
         e.lien_id
  FROM etape e
  LEFT JOIN public.chain_document_types d ON d.code = e.type
  ORDER BY e.profondeur, e.type, e.id;
END $fn$;

COMMENT ON FUNCTION public.chain_document_arborescence(uuid, text, uuid, text, integer, boolean) IS
  '460 (I-01) : la Vue Chaîne. Rend la racine et, selon le sens, tout ce que ce document a produit (aval) ou tout ce qui l''a produit (amont), avec profondeur, effet, état du lien et libellé (registre 450). Profondeur bornée et chemin déjà visité : un cycle ne boucle pas. p_fermes = true ajoute l''historique des liens fermés. Aucune écriture, aucun maillon nouveau.';

-- C'est une LECTURE d'écran : `authenticated` l'exécute, `anon` non. Elle est
-- SECURITY DEFINER (le rôle client n'a pas les droits de lecture sur toutes
-- les tables aval) et bornée par `current_tenant_id()` — la porte G4 s'en
-- satisfied par la lecture de ce contexte.
REVOKE ALL ON FUNCTION public.chain_document_arborescence(uuid, text, uuid, text, integer, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_document_arborescence(uuid, text, uuid, text, integer, boolean) TO authenticated;
