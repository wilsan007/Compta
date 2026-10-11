-- ============================================================
-- 475_chain_document_types_quotes_tests.sql — le devis est au registre
--
--   T01  le devis y est : code `quotes`, table `quotes`, lignes `quote_lines`,
--        et un libellé non vide ;
--   T02  les deux tables NOMMÉES existent réellement (le registre ne doit pas
--        désigner une table absente).
--
-- Ce que cette suite NE prouve PAS : que la frise d'un devis montre une chaîne.
-- Le **lien** devis → commande est bâti par A3 (`493_chain_l16_devis_commande`,
-- maillon `convert_quote_to_order`) : c'est **lui** qui crée les liens, pas ce
-- registre. On l'écrit ici pour que le vert de `475` ne soit pas pris pour un
-- « la frise du devis marche ».
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '475', false);
DELETE FROM _audit_results WHERE file = '475';

DO $t01$
DECLARE r record; n_tables int;
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

  -- ⚠️ ON N'ASSERTE RIEN SUR LES LIENS, ET C'EST DÉLIBÉRÉ. « Aucun lien de type
  -- `quotes` » n'est **pas** un invariant : dès que le maillon devis → commande
  -- (A3, `493`) a tourné, des liens existent — et une suite qui l'exigerait à
  -- zéro deviendrait rouge selon l'**ordre** des suites en CI. Un constat se dit
  -- dans le fichier de suivi, **jamais** dans une assertion.
END $t01$;

SELECT _audit_assert('475');
