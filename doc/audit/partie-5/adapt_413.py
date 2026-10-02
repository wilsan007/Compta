"""Partie 5, tâche 5.9 — la suite 413 suit le passage d'INV-19 à « mesurable » (migration 455).

Usage : python3 adapt_413.py <chemin de 413_chain_l4_invariants_tests.sql>
Le comportement a changé (14 invariants mesurables au lieu de 13) : les assertions changent de
nombre, PAS de nature. Doctrine du dépôt : le changement est daté et l'ancien verdict est conservé
en commentaire.
"""
import sys

p = sys.argv[1]
s = open(p, encoding='utf-8').read()
if 'Partie 5, 455' in s:
    print('déjà adapté')
    sys.exit(0)

REMPLACEMENTS = [
    # T01
    ("    n_total = 20 AND n_mes = 13 AND n_non = 7 AND n_sans_raison = 0 AND n_doublon = 0,",
     "    -- 02/10/2026 (Partie 5, 455) : INV-19 devient mesurable par le registre 450.\n"
     "    -- Verdict précédent : n_mes = 13 AND n_non = 7.\n"
     "    n_total = 20 AND n_mes = 14 AND n_non = 6 AND n_sans_raison = 0 AND n_doublon = 0,"),
    ("mesurables=%s (13) non mesurables=%s (7)", "mesurables=%s (14) non mesurables=%s (6)"),
    ("20 invariants standard, tous distincts, 13 mesurables et 7 non mesurables — chacun des 7 porte une raison non vide",
     "20 invariants standard, tous distincts, 14 mesurables et 6 non mesurables — chacun des 6 porte une raison non vide"),
    # T02
    ("        AND (res->>'mesures')::int = 13\n        AND (res->>'tenus')::int = 13",
     "        -- 02/10/2026 (Partie 5, 455) : 13 → 14 (INV-19 mesuré). Verdict précédent : mesures = 13, tenus = 13.\n"
     "        AND (res->>'mesures')::int = 14\n        AND (res->>'tenus')::int = 14"),
    ("        AND (res->>'non_mesurables')::int = 7", "        AND (res->>'non_mesurables')::int = 6"),
    ("        AND n_lignes = 20 AND n_non_mesure = 7,", "        AND n_lignes = 20 AND n_non_mesure = 6,"),
    ("non_mesure AVEC raison=%s/7", "non_mesure AVEC raison=%s/6"),
    ("société neuve = 13/13 tenus, indice 1.0000, et les 7 non mesurables",
     "société neuve = 14/14 tenus, indice 1.0000, et les 6 non mesurables"),
    # T03
    ("        AND (res->>'tenus')::int = 12\n        AND (res->>'mesures')::int = 13",
     "        -- 02/10/2026 (Partie 5, 455) : verdict précédent tenus = 12, mesures = 13.\n"
     "        AND (res->>'tenus')::int = 13\n        AND (res->>'mesures')::int = 14"),
    # T05
    ("        AND (res_a->>'mesures')::int = 12",
     "        -- 02/10/2026 (Partie 5, 455) : verdict précédent mesures = 12.\n"
     "        AND (res_a->>'mesures')::int = 13"),
]

for avant, apres in REMPLACEMENTS:
    n = s.count(avant)
    assert n >= 1, f'introuvable : {avant[:70]!r}'
    s = s.replace(avant, apres)
open(p, 'w', encoding='utf-8').write(s)
print(f'{len(REMPLACEMENTS)} remplacements appliqués')
