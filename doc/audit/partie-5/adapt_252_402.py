"""Partie 5, tâche 5.7 — adapte les suites 252 et 402 au registre (450) et au contrôle d'existence (451).

Usage : python3 adapt_252_402.py <dossier app/sql>
Ce que fait le script (et ce qu'un développeur peut faire à la main, à l'identique) :
  1. remplace les types inventés 'commande' -> 'sales_orders' et 'livraison' -> 'delivery_notes'
     (littéraux SQL entre apostrophes UNIQUEMENT), et le motif LIKE '%commande%' de 402 C06 ;
  2. ajoute l'aide `_p5_doc(société, type, id, ligne)` juste avant l'aide de lien du fichier ;
  3. fait appeler `_p5_doc` par l'aide de lien (`_lien252` / `_l312_lien`) AVANT link_documents.
"""
import re
import sys

SQL = sys.argv[1]

AIDE = """-- Partie 5 (450/451) : link_documents exige désormais que l'amont, l'aval et la
-- ligne amont EXISTENT. Les scénarios tirent leurs identifiants au hasard : cette
-- aide crée le vrai document (commande en brouillon, bon de livraison en attente,
-- ligne de commande) qui porte cet identifiant, s'il n'existe pas encore.
-- Société NULL ou identifiant NULL : rien n'est créé (le scénario teste justement
-- le refus de link_documents sur ces valeurs).
DROP FUNCTION IF EXISTS _p5_doc(uuid, text, uuid, uuid);
CREATE OR REPLACE FUNCTION _p5_doc(p_t uuid, p_type text, p_id uuid, p_ligne uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $p5$
BEGIN
  IF p_t IS NULL OR p_id IS NULL THEN
    RETURN;
  END IF;
  IF p_type = 'sales_orders' THEN
    INSERT INTO sales_orders (id, tenant_id, number, status)
    VALUES (p_id, p_t, 'P5-' || p_id::text, 'draft')
    ON CONFLICT (id) DO NOTHING;
    IF p_ligne IS NOT NULL THEN
      INSERT INTO sales_order_lines (id, tenant_id, sales_order_id, description, quantity, unit_price)
      VALUES (p_ligne, p_t, p_id, 'Ligne P5', 1, 0)
      ON CONFLICT (id) DO NOTHING;
    END IF;
  ELSIF p_type = 'delivery_notes' THEN
    INSERT INTO delivery_notes (id, tenant_id, number, status)
    VALUES (p_id, p_t, 'P5-' || p_id::text, 'pending')
    ON CONFLICT (id) DO NOTHING;
  END IF;
END $p5$;

"""

CIBLES = {
    '252_chain_socle_tests.sql': ('_lien252', 'CREATE OR REPLACE FUNCTION _lien252('),
    '402_chain_lien_cycle_tests.sql': ('_l312_lien', 'DROP FUNCTION IF EXISTS _l312_lien('),
}

for fichier, (aide, ancre) in CIBLES.items():
    chemin = f'{SQL}/{fichier}'
    s = open(chemin, encoding='utf-8').read()
    if '_p5_doc' in s:
        print(f'{fichier} : déjà adapté, rien à faire')
        continue
    n1 = s.count("'commande'")
    n2 = s.count("'livraison'")
    s = s.replace("'commande'", "'sales_orders'").replace("'livraison'", "'delivery_notes'")
    # 402 C06 vérifie que le message de refus NOMME le type : il le nomme désormais « sales_orders ».
    s = s.replace("LIKE '%commande%'", "LIKE '%sales_orders%'")
    assert ancre in s, f'{fichier} : ancre introuvable ({ancre})'
    s = s.replace(ancre, AIDE + ancre, 1)
    # Dans le corps de l'aide de lien : créer les documents avant link_documents.
    motif = re.compile(r"(CREATE OR REPLACE FUNCTION " + re.escape(aide) + r"\(.*?\nBEGIN\n)(\s*RETURN link_documents\()", re.S)
    assert motif.search(s), f'{fichier} : corps de {aide} introuvable'
    s = motif.sub(r"\1  PERFORM _p5_doc(p_t, 'sales_orders', p_amont, p_ligne);\n"
                  r"  PERFORM _p5_doc(p_t, 'delivery_notes', p_aval);\n\2", s, count=1)
    open(chemin, 'w', encoding='utf-8').write(s)
    print(f"{fichier} : {n1} 'commande' et {n2} 'livraison' remplacés, _p5_doc ajoutée et appelée par {aide}")
