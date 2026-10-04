"""Partie 5, tâche 5.8 — adapte le banc G6 (sql/ci/check_chain_performance.sql) au registre (450)
et au contrôle d'existence (451).

Usage : python3 adapt_g6.py <chemin de check_chain_performance.sql>
  1. 'zz_doc' et 'zz_aval' (types inventés) -> 'sales_orders' (type inscrit au registre) ;
  2. à chaque tour, une VRAIE commande en brouillon porte l'identifiant v_amont — créée AVANT
     le chronomètre (v_t0), donc hors de la mesure : le banc mesure toujours les quatre appels
     du socle, contrôle d'existence de 451 compris.
"""
import sys

p = sys.argv[1]
s = open(p, encoding='utf-8').read()
if 'P5-PERF-' in s:
    print('déjà adapté')
    sys.exit(0)
n = s.count("'zz_doc'") + s.count("'zz_aval'")
s = s.replace("'zz_doc'", "'sales_orders'").replace("'zz_aval'", "'sales_orders'")
s = s.replace("'zz_doc.confirme'", "'sales_orders.perf'")
avant = "    v_amont := gen_random_uuid();          -- un document DISTINCT par tour\n    v_t0 := clock_timestamp();\n"
apres = ("    v_amont := gen_random_uuid();          -- un document DISTINCT par tour\n"
         "    -- Partie 5 (451) : link_documents exige un document RÉEL. Créé hors chronomètre.\n"
         "    INSERT INTO sales_orders (id, tenant_id, number, status)\n"
         "    VALUES (v_amont, v_tenant, 'P5-PERF-' || v_i, 'draft');\n"
         "    v_t0 := clock_timestamp();\n")
assert avant in s, 'ancre de la boucle introuvable'
s = s.replace(avant, apres, 1)
open(p, 'w', encoding='utf-8').write(s)
print(f'{n} types inventés remplacés ; commande réelle créée à chaque tour')
