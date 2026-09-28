-- ============================================================
-- 279_functional_currency_not_exposed.sql — garde de la 306 (W7)
--
-- `check_tenant_guard` (règle 1) a refusé `functional_currency(p_tenant uuid)`,
-- posée par la 306 : SECURITY DEFINER, exécutable par `authenticated`, elle rend
-- la devise de N'IMPORTE QUELLE société dont on passe l'identifiant, sans vérifier
-- que l'appelant en est membre. Elle ne sert qu'aux déclencheurs de la 306 (aucun
-- appel du front) : comme les fonctions internes de la 256 et de la 260, elle
-- n'est plus exposée ; les déclencheurs (SECURITY DEFINER) l'appellent toujours.
--
-- Pourquoi la fonction est DÉCLARÉE ici, avec le corps exact de la 306 : les
-- migrations s'exécutent dans l'ordre des numéros, et 279 passe avant 306 sur une
-- base neuve. `CREATE OR REPLACE FUNCTION` conserve les droits existants : quand la
-- 306 la redéclare, la révocation posée ici tient. Sur une base où la 306 est déjà
-- passée, la redéclaration est sans effet et la révocation s'applique.
-- ============================================================
CREATE OR REPLACE FUNCTION public.functional_currency(p_tenant uuid)
RETURNS text
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT COALESCE(NULLIF(cs.currency, ''), 'EUR')
  FROM public.company_settings cs
  WHERE cs.tenant_id = p_tenant
  LIMIT 1
$$;

REVOKE EXECUTE ON FUNCTION public.functional_currency(uuid) FROM PUBLIC, anon, authenticated;
