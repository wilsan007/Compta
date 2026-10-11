-- ============================================================
-- 475_chain_document_types_quotes_tests.sql — le devis est au registre
--
--   T01  le devis y est : code `quotes`, table `quotes`, lignes `quote_lines`,
--        et un libellé non vide ;
--   T02  les deux tables NOMMÉES existent réellement (le registre ne doit pas
--        désigner une table absente).
--
-- Ce que cette suite NE prouve PAS : que la frise d'un devis montre une
-- chaîne. Le **lien** devis → commande n'est pas tracé (mesuré : la
-- transformation écrit dans `document_transformations`, aucun pont vers
-- `document_links`) — c'est un maillon NEUF, du ressort de A3/L16. La suite le
-- dit en T03 plutôt que de le laisser croire.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '475', false);
DELETE FROM _audit_results WHERE file = '475';

DO $t01$
DECLARE r record; n_tables int; n_liens int;
BEGIN
  SELECT code, table_name, ligne_table, libelle_fr INTO r
    FROM chain_document_types WHERE code = 'quotes';

  PERFORM _rec('T01', 'le devis est au registre (code quotes, table quotes, lignes quote_lines, libellé non vide)',
    r.code = 'quotes' AND r.table_name = 'quotes' AND r.ligne_table = 'quote_lines'
    AND btrim(COALESCE(r.libelle_fr, '')) <> '',
    format('code=%s table=%s lignes=%s libellé=%s',
           COALESCE(r.code, '(absent)'), COALESCE(r.table_name, '(absent)'),
           COALESCE(r.ligne_table, '(absent)'), COALESCE(r.libelle_fr, '(vide)')));

  -- Le registre ne doit pas nommer une table qui n'existe pas.
  SELECT count(*) INTO n_tables FROM pg_class c
   WHERE c.relname IN ('quotes', 'quote_lines') AND c.relkind IN ('r', 'p');
  PERFORM _rec('T02', 'les deux tables nommées existent réellement en base',
    n_tables = 2, format('tables_trouvées=%s/2', n_tables));

  -- ⚠️ T03 DIT CE QUI MANQUE, IL NE LE TAIT PAS. Aucun lien de chaîne ne porte
  -- aujourd'hui `amont_type = 'quotes'` : la frise d'un devis est donc vide de
  -- tout amont/aval. On inscrit le constat pour qu'il ne soit pas confondu avec
  -- un défaut d'écran — c'est le maillon devis → commande (A3/L16) qui manque.
  SELECT count(*) INTO n_liens FROM document_links WHERE amont_type = 'quotes' OR aval_type = 'quotes';
  PERFORM _rec('T03', 'constat (à porter par A3/L16) : aucun lien de chaîne ne porte encore le type quotes',
    n_liens = 0,
    format('liens_quotes=%s — 0 attendu tant que le maillon devis → commande n''est pas tracé', n_liens));
END $t01$;

SELECT _audit_assert('475');
