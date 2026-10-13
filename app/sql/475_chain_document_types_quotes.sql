-- ═══════════════════════════════════════════════════════════════════════════
-- 475 — Le DEVIS entre au registre des types de documents (I-01, Vue Chaîne)
-- Numéro pris le 2026-10-11T05:55:58.483Z par migration-numero.mjs (ligne « plan6 A1 (preuve et indice) », branche plan6/a-chainages).
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **Objet.** La Vue Chaîne (`460`) rend, pour un document, sa chaîne amont/aval.
-- Le nœud **racine** porte son libellé par l'appelant ; les nœuds
-- **intermédiaires** le lisent au registre `chain_document_types` (`450`) :
-- `chain_document_arborescence` fait `LEFT JOIN chain_document_types d ON
-- d.code = e.type` et rend `d.libelle_fr`. Un type **absent** du registre
-- traverse donc la chaîne **sans nom** — le nœud apparaît, mais muet.
--
-- **Le devis manquait.** Les 27 types de la `450` couvrent la facture, la
-- commande, la livraison, la réception… **pas le devis** — or c'est l'**entrée**
-- de la chaîne commerciale (« devis en amont », dit le commentaire de la
-- commande de vente dans `SalesOrdersPage`).
--
-- **CE QUE CETTE MIGRATION NE FAIT PAS.** Inscrire le type donne le **libellé** ;
-- il **ne crée aucun lien**. Le lien devis → commande est un **maillon** — et
-- **A3 l'a posé** (`493_chain_l16_devis_commande`, effet `sale.quote.to_order`,
-- maillon `convert_quote_to_order`). Cette migration-ci ne pose **que** le
-- registre.
--
-- **DOUBLON CONNU, SANS CONFLIT.** La `493` (A3) inscrit `quotes` avec **les
-- mêmes valeurs** — c'est un préalable de son maillon. Deux upserts identiques :
-- le second ne change rien. Les deux numéros sont licites (`475` plage A1,
-- `493` plage A3) ; **l'intégration tranchera** s'il faut en retirer un.
--
-- **Ce que l'inscription débloque** : les nœuds devis de la Vue Chaîne portent
-- leur nom (`chain_document_arborescence` lit `d.libelle_fr`), et l'écran du
-- devis (`QuotesPage`) peut appeler `getChain('quotes', id)`.
--
-- **Doctrine reprise de la `450`** : la ligne est posée en
-- `ON CONFLICT (code) DO UPDATE`, donc **rejouable** ; le registre reste la
-- seule vérité des libellés.
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO public.chain_document_types (code, table_name, ligne_table, libelle_fr) VALUES
  ('quotes', 'quotes', 'quote_lines', 'Devis')
ON CONFLICT (code) DO UPDATE SET
  table_name  = EXCLUDED.table_name,
  ligne_table = EXCLUDED.ligne_table,
  libelle_fr  = EXCLUDED.libelle_fr;

