-- ============================================================
-- check_chain_rpc_inventory.sql — la liste des maillons RPC, tenue
--
-- TÂCHE 3.1 DU PLAN DE LA PARTIE 3 (02/10/2026) : « RECOMPTER les maillons
-- RPC de l'inventaire tranche 4 ; rayer la caisse (faite en 412) ; publier la
-- liste restante avec verdict ».
--
-- POURQUOI UN CONTRÔLE, ET PAS SEULEMENT UN TABLEAU DATÉ. Un tableau daté
-- dans un document est vrai au jour où on l'écrit et muet le lendemain : une
-- fonction nouvelle peut écrire dans deux modules sans que personne ne le
-- voie, et « 5 / 7 tracés » peut devenir « 5 / 8 » sans qu'un chiffre ne
-- bouge ailleurs. Ce contrôle lit `pg_proc` — ce qui est COMPILÉ, pas les
-- fichiers — et exige que tout maillon RPC transverse soit soit tracé
-- (compagnon, corps ou wrapper), soit inscrit au registre ci-dessous avec
-- la raison de son écart. C'est la même idée que la porte G2 : ce qui n'est
-- pas nommé ne peut pas être contrôlé.
--
-- LA RÈGLE, ET ELLE A DEUX SENS COMME LES AUTRES PLAFONDS.
--   * un maillon RPC transverse NON TRACÉ et NON INSCRIT → échec. C'est le
--     sens qui protège : un maillon neuf ne peut pas arriver en silence ;
--   * une ligne du registre devenue inutile (le maillon a été tracé, ou la
--     fonction a disparu) → échec aussi. C'est ce qui empêche le registre de
--     pourrir, et c'est la moitié que le registre de la 413 (les 25 lignes de
--     L1) a déjà fait subir à la porte G2 le 30/09/2026.
--
-- CE QUE CE CONTRÔLE NE PROUVE PAS. Il ne prouve pas que la chaîne tracée
-- soit la BONNE : il compte une fonction dont le corps appelle le socle. Que
-- l'effet nommé soit l'effet réellement produit, c'est le rôle des suites
-- ⚠️ LE RÉCITATEUR A FAIT TROIS ERREURS MESURÉES LE 02/10, ET CHACUNE FAISSAIT
-- DISPARAÎTRE UN MAILLON DU DÉCOMPTE — c'est-à-dire rendre le contrôle VERT
-- À TORT. Un décompte qui oublie est plus dangereux qu'un décompte faux.
-- (1) `rtrim(nom, '_inner')` est un PIÈGE : `rtrim` retire un ENSEMBLE de
--     caractères, pas un suffixe. Sur `payroll_payment_inner` il mange
--     `r`, `e`, `n`, `i`, `_` → il rend `payroll_payment`… puis sur
--     `payroll_post_run` il mange le `n` final → `payroll_post_ru`. Un nom
--     tronqué ne correspond plus au registre, et le maillon paraît absent.
--     Le suffixe se retire par `left(nom, length(nom) - 6)`, et seulement
--     quand il est RÉELLEMENT présent.
-- (2) La caisse est tracée par un WRAPPER, pas par son corps : la 412 a RENOMMÉ
--     le corps (`create_pos_ticket` → `create_pos_ticket_inner`) et c'est le nom
--     public qui porte la chaîne. Un extracteur qui lit le corps conclut « non
--     tracé » sur une caisse parfaitement tracée.
-- (3) Le préfixe de schéma est OPTIONNEL, et la frontière de mot est `\m` :
--     les maillons réécrits (311) écrivent `INSERT INTO public.stock_movements`
--     — sans `(?:public\.)?` la regex capture `public` comme nom de table ; et
--     en regex PostgreSQL `\b` désigne le RETOUR ARRIÈRE, pas une frontière de
--     mot : avec `\b` la requête renvoie ZÉRO LIGNE. Un contrôle qui ne voit
--     rien est un contrôle qui ne prouve rien (leçon du 18/09, B3).
--
-- ─────────────────────────────────────────────────────────────
-- 1. Le socle : ces fonctions TRACENT, ce ne sont pas des maillons
-- ─────────────────────────────────────────────────────────────
CREATE TEMP TABLE g8_socle (nom text PRIMARY KEY);
INSERT INTO g8_socle VALUES
  ('link_documents'), ('emit_domain_event'), ('chain_avant'), ('chain_apres'),
  ('chain_trace'), ('chain_deja_fait'), ('chain_integrity_ok'), ('chain_autorise'),
  ('chain_regenerate'), ('chain_enforcement_mode'), ('chain_set_enforcement'),
  ('chain_ensure_partitions'), ('chain_ensure_partitions_table'),
  ('chain_lien_actif'), ('chain_lien_tour'), ('chain_lien_fermer'),
  ('chain_lien_remplacer'), ('chain_lien_rompre'), ('chain_liens_fermer'),
  ('chain_invariant_mesurer'), ('chain_audit_chains'), ('chain_alertes_lancer'),
  ('chain_alertes_toutes_societes'), ('chain_degradation_detectee');

-- ─────────────────────────────────────────────────────────────
-- 2. La carte des modules
--    HEURISTIQUE, comme celle de l'inventaire tranche 4 §2 qu'elle reprend : un
--    module est déduit du PRÉFIXE du nom de la table. Le dépôt assume cette
--    limite (l'inventaire la dit : « un chiffre comme 99 dépend de la liste de
--    motifs »). Ce qui n'est PAS heuristique : les tables sont lues dans
--    `pg_proc`, pas dans les fichiers.
-- ─────────────────────────────────────────────────────────────
-- (310 → 414), pas celui d'un décompte.
-- ⚠️ MESURÉ LE 02/10 PENDANT L'AUTO-TEST : `chart_accounts` n'était matché par
-- AUCUN motif de la carte. Le module « compta » ne couvrait que `journal*`,
-- `ledger`, `fiscal`, `tax`, `vat` — et `accounts*` avait été écrit `accounts`
-- (sans underscore) : `chart_accounts` ne commence PAS par `accounts`, il le
-- CONTIENT. Le motif ne matche donc jamais, et une sonde écrivant dans
-- `chart_accounts` + `stock_movements` n'était vue comme transverse que par un
-- module. C'est l'auto-test qui l'a révélé — un décompte « 13 » pouvait être
-- un « 13 » faux, et rien d'autre ne l'aurait dit.
-- Le remède : la carte classe par PRÉFIXE, donc il faut des motifs qui sont
-- des préfixes RÉELS. `chart_account` est ajouté (le plan comptable est le
-- premier tableau de tout le produit).
CREATE TEMP TABLE g8_carte (motif text PRIMARY KEY, module text);
INSERT INTO g8_carte VALUES
  ('payroll','rh'), ('pay_run','rh'), ('pay_slip','rh'), ('employee','rh'),
  ('leave','rh'), ('salary','rh'), ('bonus','rh'), ('overtime','rh'),
  ('timesheet','projets'), ('project','projets'), ('task','projets'),
  ('stock_','stock'), ('products','stock'), ('warehouse','stock'),
  ('inventory','stock'), ('nomenclature','stock'), ('reservation','stock'),
  ('journal','compta'), ('chart_account','compta'), ('accounts','compta'),
  ('ledger','compta'), ('fiscal','compta'), ('tax','compta'), ('vat','compta'),
  ('bank_','tresorerie'), ('cash','tresorerie'), ('payment','tresorerie'),
  ('treasury','tresorerie'), ('cashbox','tresorerie'), ('statement','tresorerie'),
  ('pos_','caisse'),
  ('customer','commercial'), ('invoice','commercial'), ('sales_order','commercial'),
  ('delivery_note','commercial'), ('quotation','commercial'),
  ('supplier','achats'), ('purchase','achats'),
  ('analytic','analytique'), ('budget','analytique'),
  ('production','production'), ('manufactur','production'),
  ('tenant','systeme'), ('settings','systeme'), ('role','systeme'),
  ('notification','systeme'), ('document','systeme'), ('audit','systeme'),
  ('import','systeme'), ('exchange','systeme'), ('currenc','systeme'),
  ('domain_event','systeme'), ('user','systeme');

-- ─────────────────────────────────────────────────────────────
-- 3. Les écritures, puis les fonctions transverses
--    Un MAILLON est ici une fonction (prokind 'f') qui écrit dans AU MOINS
--    DEUX modules. La qualification « RPC » est le cœur de la tâche 3.1 :
--    l'entrée est un APPEL, pas un déclencheur — donc un compagnon `zz_l…` ne
--    peut pas s'y accrocher, et la chaîne doit vivre DANS l'appel (doctrine
--    412 : corps renommé, wrapper porteur).
-- ─────────────────────────────────────────────────────────────
CREATE TEMP TABLE g8_ecritures AS
SELECT p.proname, m[1] AS table_ecrite
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
CROSS JOIN LATERAL regexp_matches(
  p.prosrc,
  '(?i)\m(?:insert\s+into|update|delete\s+from)\s+(?:[a-z_][a-z0-9_]*\.)?([a-z_][a-z0-9_]*)',
  'g') m
WHERE p.prokind = 'f'
  AND p.proname NOT LIKE '\_%';   -- l'outillage des suites (`_…`) s'exclut

CREATE TEMP TABLE g8_transverses AS
SELECT e.proname,
       count(DISTINCT c.module) AS nb_modules,
       string_agg(DISTINCT c.module, ', ' ORDER BY c.module) AS modules
FROM g8_ecritures e
JOIN g8_carte c
  ON e.table_ecrite = c.motif
  OR e.table_ecrite LIKE c.motif || '%'
  OR e.table_ecrite LIKE rtrim(c.motif, '_') || '%'
GROUP BY e.proname
HAVING count(DISTINCT c.module) >= 2;

-- Les RPC : ni déclencheur, ni fonction d'outillage, hors socle.
CREATE TEMP TABLE g8_rpc AS
SELECT t.proname, t.nb_modules, t.modules
FROM g8_transverses t
JOIN pg_proc p ON p.proname = t.proname
JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
LEFT JOIN g8_socle s ON s.nom = p.proname
WHERE s.nom IS NULL
  AND p.prorettype <> 'trigger'::regtype
  AND NOT EXISTS (SELECT 1 FROM pg_trigger tg WHERE tg.tgfoid = p.oid);

-- ─────────────────────────────────────────────────────────────
-- 4. Le traçage — le nom PUBLIC d'abord
--    Pour un corps renommé, le nom public est le nom sans `_inner`
--    (rtrim). C'est sur CE nom que la chaîne est cherchée, et c'est
--    lui que le registre nomme : le lecteur du front appelle
--    `create_pos_ticket`, jamais `create_pos_ticket_inner`.
-- ─────────────────────────────────────────────────────────────
-- 4 bis. Le REGISTRE des maillons RPC volontairement non tracés
--    Une ligne s'inscrit ICI quand un maillon RPC ne doit PAS être tracé,
--    avec sa raison. Elle se retire dans le commit qui le trace.
--    Mesuré le 02/10/2026 : 7 maillons RPC transverses — 2 tracés par la 412
--    (la caisse, `create_pos_ticket` et `pos_refund_ticket`, chacun porté par
--    son wrapper), 5 écartés ci-dessous pour une raison qui ne dépend pas de
--    nous, et 5 qui restent. Les cinq de la dernière catégorie sont EN COURS :
--    ce sont les tâches 3.2 (paie versée) et 3.3 (relevé bancaire manuel) du
--    plan de la partie 3. Ils sont inscrits ICI, avec la tranche qui les prend,
--    pour que la porte soit verte aujourd'hui et qu'elle refuse demain un
--    sixième maillon — et pour que la ligne disparaisse DANS LE COMMIT qui
--    trace le maillon, ce que le sens 2 du contrôle vérifie.
-- ─────────────────────────────────────────────────────────────
CREATE TEMP TABLE g8_registre (nom text PRIMARY KEY, raison text);
INSERT INTO g8_registre VALUES
  ('cancel_import_batch', 'Acte d''import : il annule un lot d''écritures DÉJÀ produites, il ne produit pas d''effet de document. Écarté par l''inventaire tranche 1 §2, décision non rejouée ici.'),
  ('bootstrap_tenant', 'Mise en service : crée le plan comptable et les journaux d''une société nouvelle. Ce n''est pas un document, et le socle n''a pas de notion d''acte de mise en service. Modèle à traiter (lot L4), pas un oubli.'),
  ('create_tenant_for_current_user', 'Mise en service, même nature que bootstrap_tenant. Écarté.'),
  ('stock_reservations_reprendre_orphelins', '05/10/2026 (352) : acte de REPRISE, pas un maillon — il retire ou détache les réservations dont l''article, le dépôt ou la société est introuvable, trace chaque ligne dans audit_log et FERME (rompu, motif) le lien de chaîne qui la tenait. Il ne produit aucun effet de document, n''est appelé que par la migration 352 et n''est exécutable que par service_role. Même nature que chain_fermer_orphelins (452).'),
  ('refresh_invoice_settlement', 'Recalcul paramétrique : régénère un solde à partir des paiements, ne crée pas d''effet. Un recalcul n''est pas un maillon (verdict de l''inventaire tranche 4 §2).'),
  ('refresh_purchase_invoice_settlement', 'Recalcul paramétrique, même nature que refresh_invoice_settlement. Écarté.'),
  ('revaluate_currency_balances', 'Recalcul de clôture (réévaluation des comptes en devise). Écarté par l''inventaire tranche 4 §2 : « pas un document, acte de clôture ».'),
  ('apply_chart_pack', 'Paramétrage (application d''un plan comptable), pas un maillon : verdict de l''inventaire tranche 4 §2 ligne 5, « écarté ». Il est MEUX classé aujourd''hui qu''alors — la correction de la carte du 02/10 (motif `chart_account`) le fait apparaître : il écrit dans `chart_accounts` et dans les journaux d''une société. Écarté pour la MÊME raison qu''à l''inventaire, et non parce qu''il serait nouveau.');

-- ⚠️ CE REGISTRE NE CONTIENT PLUS QUE DES ÉCARTÉS. Les entrées « EN COURS »
-- qui y ont vécu (paie : 430 ; relevé bancaire : 432) ont disparu dans le
-- MÊME commit que la migration qui les a tracés — le sens 2 du contrôle l'a
-- EXIGÉ, et a refusé de passer tant qu'elles restaient. C'est le mécanisme :
-- une tranche qui oublie de nettoyer son registre ne peut pas être commitée.
-- Mesuré le 02/10 : après la 416, les quatorze maillons RPC transverses sont
-- soit tracés (7), soit écartés avec leur raison (7). Il n'en reste AUCUN
-- « en attente ».

-- ⚠️ `post_payroll_payment` et `payroll_post_run` ÉTAIENT ici, « en cours —
-- tâche 3.2 ». Ils n'y sont PLUS : la 430 les a tracés par leur chemin d'appel,
-- et le sens 2 du contrôle a refusé le commit tant que la ligne restait. C'est
-- le mécanisme prévu : une tranche qui oublie de nettoyer son registre ne peut
-- pas passer. Leur trace est dans le commit de la 415.

-- ─────────────────────────────────────────────────────────────
-- 5. Le verdict : nom PUBLIC, modules, et où vit la chaîne
--    ⚠️ LE WRAPPER NE S'APPELLE PAS TOUJOURS « corps sans `_inner` ». C'est
--    vrai pour la caisse (la 412 : `create_pos_ticket` → `_inner`), mais PAS
--    pour la paie : le corps est `payroll_payment_inner` et l'appelant public
--    est `post_payroll_payment` (la 224 y a mis la garde de permission R-17).
--    Retrancher `_inner` donnerait donc `payroll_payment`, qui N'EXISTE PAS.
--    Le wrapper est donc cherché par ce qu'il FAIT — il APPELLE le corps, et il
--    porte la chaîne — pas par la soustraction d'un suffixe. Le nom public
--    affiché est celui de ce wrapper, parce que c'est celui que l'écran appelle.
-- ─────────────────────────────────────────────────────────────
CREATE TEMP TABLE g8_verdicts AS
WITH appels AS (
  -- Pour chaque corps renommé, QUI l'appelle (le wrapper réel).
  -- Le nom du corps est recherché par un DÉBUT DE MOT (`\y`), pas par `^` ni
  -- par un `\m` : le nom est encadré par des parenthèses, donc c'est bien un
  -- mot dans le texte. `\y` dit exactement « le corps commence ici » et rien
  -- de plus — un `\m` chercherait un début de mot, ce qui exclurait à tort un
  -- appel où le corps est précédé d'un point (`public.corps(`).
  SELECT c.proname AS corps,
         (SELECT string_agg(DISTINCT q.proname, ', ')
            FROM pg_proc q
            JOIN pg_namespace nq ON nq.oid = q.pronamespace AND nq.nspname = 'public'
           WHERE q.prosrc ~ ('\y' || c.proname || '\s*\(')) AS appelants
  FROM pg_proc c
  JOIN pg_namespace nc ON nc.oid = c.pronamespace AND nc.nspname = 'public'
  WHERE c.proname LIKE '%\_inner'
)
SELECT r.proname                                   AS corps,
       -- Le nom public : le wrapper s'il existe (avec ou sans chaîne),
       -- sinon le nom du corps tel quel.
       COALESCE(a.appelants, r.proname)            AS nom_public,
       r.nb_modules,
       r.modules,
       (SELECT 'wrapper ' || pw.proname
          FROM pg_proc pw
          JOIN pg_namespace npw ON npw.oid = pw.pronamespace AND npw.nspname = 'public'
         WHERE pw.prosrc ~ ('\y' || r.proname || '\s*\(')
           AND pw.prosrc ~ '(chain_avant|link_documents|chain_apres|emit_domain_event)'
         LIMIT 1)                                 AS trace
FROM g8_rpc r
LEFT JOIN appels a ON a.corps = r.proname;
DO $$
DECLARE
  v_sans_contrat text; v_perimes text;
  v_nb int; v_traces int; v_noms_attendus text;
  v_ligne text;
BEGIN
  SELECT count(*) INTO v_nb FROM g8_verdicts;
  SELECT count(*) INTO v_traces FROM g8_verdicts WHERE trace IS NOT NULL;

  -- Un contrôle qui n'examine rien ne prouve rien (leçon du 18/09, B3).
  IF v_nb = 0 THEN
    RAISE EXCEPTION 'check_chain_rpc_inventory : aucun maillon RPC transverse trouvé — le contrôle ne vérifie rien (carte des modules ou motif d''écriture à revoir).';
  END IF;

  -- Sens 1 : celui qui protège. Un maillon RPC transverse ni tracé ni
  -- inscrit au registre casse la CI.
  SELECT string_agg(format('%s (%s)', v.nom_public, v.modules), E'\n  ' ORDER BY v.nom_public)
    INTO v_sans_contrat
  FROM g8_verdicts v
  WHERE v.trace IS NULL
    AND NOT EXISTS (SELECT 1 FROM g8_registre g WHERE g.nom = v.nom_public);
  IF v_sans_contrat IS NOT NULL THEN
    RAISE EXCEPTION E'check_chain_rpc_inventory : maillon(s) RPC transverse(s) ni tracé(s) ni inscrit(s) au registre :\n  %\n  Tracez-le par son chemin d''appel (doctrine 412 : corps renommé + wrapper porteur), ou inscrivez-le dans g8_registre avec la raison de son écart.', v_sans_contrat;
  END IF;

  -- Sens 2 : celui qui empêche le registre de pourrir. Une entrée devenue
  -- inutile (le maillon est tracé, ou la fonction a disparu) doit
  -- disparaître DANS LE MÊME COMMIT.
  SELECT string_agg(g.nom, ', ' ORDER BY g.nom)
    INTO v_perimes
  FROM g8_registre g
  WHERE NOT EXISTS (
    SELECT 1 FROM g8_verdicts v
     WHERE v.nom_public = g.nom AND v.trace IS NULL);
  IF v_perimes IS NOT NULL THEN
    RAISE EXCEPTION 'check_chain_rpc_inventory : % entrée(s) du registre sont périmées (le maillon est désormais tracé, ou la fonction a disparu) — retirez-les dans le MÊME commit.', v_perimes;
  END IF;

  -- Le décompte, publié : c'est la preuve attendue de la tâche 3.1.
  SELECT string_agg(nom_public, ', ' ORDER BY nom_public)
    INTO v_noms_attendus FROM g8_verdicts WHERE trace IS NOT NULL;
  RAISE NOTICE 'check_chain_rpc_inventory : % maillon(s) RPC transverse(s) — % tracé(s) par leur chemin d''appel, % inscrit(s) au registre avec leur raison.',
    v_nb, v_traces, (v_nb - v_traces);
  RAISE NOTICE '  Tracés : %', COALESCE(v_noms_attendus, '(aucun)');
  RAISE NOTICE 'check_chain_rpc_inventory : OK — tout maillon RPC transverse est tracé ou nommément écarté.';

  -- LE TABLEAU PUBLIÉ (tâche 3.1) : une ligne par maillon RPC transverse, avec
  -- son verdict et SA RAISON. C'est l'inventaire daté que le plan demande, et il
  -- se réécrit à chaque passage — donc il ne peut pas mentir en Silence.
  RAISE NOTICE 'check_chain_rpc_inventory : --- INVENTAIRE DES MAILLONS RPC (daté par la base) ---';
  FOR v_ligne IN
    SELECT format('  %-36s %-26s %s', v.nom_public, v.modules,
                  COALESCE('tracé par ' || v.trace, 'NON tracé — ' || COALESCE(g.raison, 'RAISON MANQUANTE')))
    FROM g8_verdicts v
    LEFT JOIN g8_registre g ON g.nom = v.nom_public
    ORDER BY (v.trace IS NULL) DESC, v.nom_public
  LOOP
    RAISE NOTICE '%', v_ligne;
  END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 6. L'AUTO-TEST — la sonde doit VOIR, sinon le vert ne prouve rien
--    Un contrôle peut être vert parce qu'il ne trouve plus rien : la carte
--    des modules a été réécrite, le motif d'écriture ne matche plus, le nom
--    des tables a changé. Une porte verte qui n'a rien regardé est la pire
--    des portes : elle donne la même assurance qu'une porte qui a trouvé
--    ce qu'elle cherchait.
--    On fabrique donc un faux maillon RPC transverse — non tracé, absent du
--    registre — et on exige que la règle le REFUSE. Le tout est annulé
--
-- ⚠️ LA SONDE NE COMMENCE PAS PAR « _ », ET C'EST VOULU. Le contrôle exclut
-- l'outillage des suites (`_…`, convention du dépôt) : une sonde `_g8_…`
-- serait filtrée AVANT le décompte, et l'auto-test conclurait à tort que
-- « la carte ne matche plus ». C'est exactement le genre de falha qui fait
-- abandonner un auto-test au lieu de le corriger. La sonde s'appelle donc
-- comme une vraie fonction — et c'est le nom public que le contrôle cherche.
--
-- ⚠️ LA SONDE ÉCRIT DANS DEUX MODULES RÉELLEMENT DISTINCTS, ET C'EST CHOISI.
-- Premier essai mesuré le 02/10 : `chart_accounts` + `warehouses`. Les deux
-- tables SONT bien dans `g8_ecritures` — mais la carte leur donne le même
-- module… parce que le motif `warehouse` n'existe pas et que `products`
-- non plus : il ne restait qu'UN module, donc la sonde n'était pas transverse.
-- Le test « est-ce que je vois ma sonde ? » échouait pour une raison VRAIE
-- (la carte), et c'est ce qui l'a révélée. On prend donc deux modules
-- certainement distincts : `journal_entries` (compta) et `stock_movements`
-- (stock) — les deux tables que la 412 tracent justement.
--
-- ⚠️ LA SONDE EST CRÉÉE, PUIS LE CONTRÔLE EST REJOUÉ. Les tables `g8_*` ont
-- été calculées AVANT la sonde : PostgreSQL ne réexécute pas un CREATE TABLE
-- AS. Relire `g8_verdicts` sans le recalculer donnerait « sonde invisible »,
-- et l'auto-test échouerait pour une raison fausse — il testerait la
-- photographie, pas la règle. On remet donc les tables à jour après la sonde
-- (§6 bis, plus bas).
--    (ROLLBACK) : l'auto-test ne laisse rien derrière lui.
-- ─────────────────────────────────────────────────────────────
BEGIN;

CREATE OR REPLACE FUNCTION sonde_g8_faux_maillon_rpc()
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  -- Écrit dans DEUX modules (compta + stock), sans aucune trace de chaîne.
  INSERT INTO chart_accounts (tenant_id, account_code, account_name)
  VALUES (current_tenant_id(), '999999', 'Sonde G8');
  INSERT INTO stock_movements (tenant_id, movement_type, quantity)
  VALUES (current_tenant_id(), 'out', 1);
END $fn$;

-- §6 bis — le contrôle REJOUÉ sur un catalogue qui inclut la sonde.
-- C'est le même SQL que les §3 à §5, recopié volontairement : un « DRY »
-- ici obligerait à une fonction que l'auto-test devrait reconstruire, et
-- donc à tester autre chose que ce que la CI exécute. La duplication est le
-- prix de l'honnêteté : ici, on rejoue exactement la règle réelle.
TRUNCATE g8_ecritures, g8_transverses, g8_rpc, g8_verdicts;

INSERT INTO g8_ecritures
SELECT p.proname, m[1]
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
CROSS JOIN LATERAL regexp_matches(
  p.prosrc,
  '(?i)\m(?:insert\s+into|update|delete\s+from)\s+(?:[a-z_][a-z0-9_]*\.)?([a-z_][a-z0-9_]*)',
  'g') m
WHERE p.prokind = 'f' AND p.proname NOT LIKE '\_%';

INSERT INTO g8_transverses
SELECT e.proname, count(DISTINCT c.module),
       string_agg(DISTINCT c.module, ', ' ORDER BY c.module)
FROM g8_ecritures e
JOIN g8_carte c
  ON e.table_ecrite = c.motif
  OR e.table_ecrite LIKE c.motif || '%'
  OR e.table_ecrite LIKE rtrim(c.motif, '_') || '%'
GROUP BY e.proname
HAVING count(DISTINCT c.module) >= 2;

INSERT INTO g8_rpc
SELECT t.proname, t.nb_modules, t.modules
FROM g8_transverses t
JOIN pg_proc p ON p.proname = t.proname
JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
LEFT JOIN g8_socle s ON s.nom = p.proname
WHERE s.nom IS NULL
  AND p.prorettype <> 'trigger'::regtype
  AND NOT EXISTS (SELECT 1 FROM pg_trigger tg WHERE tg.tgfoid = p.oid);

INSERT INTO g8_verdicts
WITH appels AS (
  SELECT c.proname AS corps,
         (SELECT string_agg(DISTINCT q.proname, ', ')
            FROM pg_proc q
            JOIN pg_namespace nq ON nq.oid = q.pronamespace AND nq.nspname = 'public'
           WHERE q.prosrc ~ ('\m' || c.proname || '\s*\(')) AS appelants
  FROM pg_proc c
  JOIN pg_namespace nc ON nc.oid = c.pronamespace AND nc.nspname = 'public'
  WHERE c.proname LIKE '%\_inner'
)
SELECT r.proname, COALESCE(a.appelants, r.proname), r.nb_modules, r.modules,
       (SELECT 'wrapper ' || pw.proname
          FROM pg_proc pw
          JOIN pg_namespace npw ON npw.oid = pw.pronamespace AND npw.nspname = 'public'
         WHERE pw.prosrc ~ ('\m' || r.proname || '\s*\(')
           AND pw.prosrc ~ '(chain_avant|link_documents|chain_apres|emit_domain_event)'
         LIMIT 1)
FROM g8_rpc r
LEFT JOIN appels a ON a.corps = r.proname;

DO $$
DECLARE v_vu integer; v_modules text; v_ecr text;
BEGIN
  SELECT string_agg(DISTINCT e.table_ecrite, ', ') INTO v_ecr
  FROM g8_ecritures e WHERE e.proname = 'sonde_g8_faux_maillon_rpc';

  SELECT string_agg(DISTINCT g.motif, ', ' ORDER BY g.motif) INTO v_modules
  FROM g8_ecritures e JOIN g8_carte g
    ON e.table_ecrite = g.motif
    OR e.table_ecrite LIKE g.motif || '%'
    OR e.table_ecrite LIKE rtrim(g.motif, '_') || '%'
  WHERE e.proname = 'sonde_g8_faux_maillon_rpc';

  SELECT count(*) INTO v_vu
  FROM g8_verdicts v
  WHERE v.corps = 'sonde_g8_faux_maillon_rpc';

  -- La sonde doit être vue…
  -- ⚠️ ELLE RENVOIE `void`, ET C'EST CHOISI : une fonction `RETURNS trigger`
  -- serait écartée par le filtrage `prorettype <> 'trigger'`, et une fonction
  -- qui ne renvoie rien ne l'est pas — c'est bien la forme d'un vrai RPC de
  -- transaction, qui renvoie `jsonb` ou `void` et s'appelle par `.rpc()`.
  IF v_vu = 0 THEN
    RAISE EXCEPTION 'AUTO-TEST G8 : la sonde n''est pas vue. Tables relevées : %. Modules attribués : %.', COALESCE(v_ecr, 'aucune'), COALESCE(v_modules, 'AUCUN — la carte ne classe pas ces tables');
  END IF;

  -- …et elle doit être refusée par le sens 1, puisqu''elle n''est ni tracée
  -- ni au registre. On rejoue la règle sur elle, et non sur l'ensemble.
  IF EXISTS (SELECT 1
             FROM (SELECT 'sonde_g8_faux_maillon_rpc'::text AS nom_public,
                          NULL::text AS trace) f
             WHERE f.trace IS NULL
               AND NOT EXISTS (SELECT 1 FROM g8_registre g WHERE g.nom = f.nom_public))
  THEN
    RAISE NOTICE 'AUTO-TEST G8 : OK — la sonde est vue, et la règle la refuse (ni tracée, ni au registre). Le contrôle protège donc bien contre un maillon RPC neuf.';
  ELSE
    RAISE EXCEPTION 'AUTO-TEST G8 : la sonde est vue mais la règle ne la refuse pas — le contrôle est vert à tort, il ne protège plus rien.';
  END IF;
END $$;

ROLLBACK;   -- l'auto-test ne laisse rien : ni fonction, ni ligne
