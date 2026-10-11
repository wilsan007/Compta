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
-- **CE QUE CETTE MIGRATION NE FAIT PAS — ET C'EST LE POINT.**
-- Inscrire le type donne le **libellé** ; il **ne crée aucun lien**. Or la
-- transformation devis → commande (`transformQuoteToSalesOrder`, côté écran)
-- écrit dans `document_transformations` — **pas** dans `document_links`
-- (mesuré le 05/10 : aucun pont en base entre les deux). La frise d'un devis
-- reste donc **« isolée »** tant que le lien **devis → commande n'est pas
-- tracé** : c'est un **maillon NEUF** (L16, « chaînages internes »), donc le
-- territoire de **A3** — pas un enregistrement au registre. **Demande
-- consignée dans `doc/audit/plan6/PARTIE-A1.md` (R3).**
--
-- **Ce que l'inscription débloque DÉJÀ** : dès que le maillon existera, ses
-- nœuds devis porteront leur nom **sans autre changement** ; et l'écran du
-- devis (`QuotesPage`) peut appeler `getChain('quotes', id)` sans libellé de
-- repli forcé.
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

