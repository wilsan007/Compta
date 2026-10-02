-- ============================================================
-- 416_chain_l4_invariants_mesurables.sql — L4, tranche 3 : le
--   dernier invariant non mesurable, et la preuve des six autres
--
-- TÂCHE 3.8 DU PLAN DE LA PARTIE 3 (02/10/2026) : « rendre MESURABLES
-- les 7 invariants "non mesurables" (ou en retirer avec raison
-- écrite) ». Point de départ mesuré le 02/10 : **13 / 20** mesurables,
-- 7 nommés sans contrôle — `INV-05, 06, 07, 08, 10, 12, 19`.
--
-- ─────────────────────────────────────────────────────────────
-- CE QUE LA MESURE A DONNÉ, ET ELLE A DONNÉ UNE RÉPONSE DIFFÉRENTE
-- DE CELLE ATTENDUE
-- ─────────────────────────────────────────────────────────────
-- On a d'abord **regardé la base** au lieu de relire la raison
-- écrite par la 413. Interrogation sur PostgreSQL 16, conteneur
-- `compta-pg16` (port 5433), base neuve :
--
--   | invariant | ce que la base porte réellement            | suite |
--   |-----------|-----------------------------------------------|-------|
--   | INV-05    | `purchase_orders` : 13 colonnes, **aucune**  | non   |
--   |           | de facturé ni de reçu ; `document_links`     | mes.  |
--   |           | ne contient AUCUN lien commande→facture      |       |
--   | INV-06    | `budgets` : 11 colonnes numériques           | non   |
--   |           | `period_1..12`, **aucun réalisé stocké**      | mes.  |
--   | INV-07    | `lettrage_groups` : aucune clé vers          | non   |
--   |           | `journal_lines` ; `bank_transactions` porte  | mes.  |
--   |           | `reconciled_entry_id`, qui ne relie pas au   |       |
--   |           | groupe de lettrage                           |       |
--   | INV-08    | `bank_transactions` : 33 colonnes, **aucun**  | non   |
--   |           | solde de relevé ; aucune table de relevé     | mes.  |
--   | INV-10    | `dsn_declarations` : 11 colonnes, **zéro     | non   |
--   |           | numérique** — le brut n'existe qu'en fichier  | mes.  |
--   | INV-12    | `projects.actual_cost` existe (3 projets),   | non   |
--   |           | les DEUX recalculs concurrents subsistent    | mes.  |
--   | INV-19    | `amont_type` texte + `amont_id` uuid ; les   | ✅    |
--   |           | types en usage sont `pay_runs` et             | MES.  |
--   |           | `journal_entries`, et **les deux tables       |       |
--   |           | existent** — le résolvable est là            |       |
--
-- LA LECTURE HONNÊTE DE CE TABLEAU. Six des sept n'ont pas une
-- *méthode* de mesure manquante : ils ont une **donnée absente**. On
-- pourrait les rendre « mesurables » en écrivant une requête qui
-- compare un montant à un agrégat **inventé** — le résultat serait un
-- chiffre, il serait faux, et l'indice afficherait une santé que
-- personne n'a. C'est exactement le mensonge que la 413 refuse
-- (« Mesurer l'écart d'un agrégat inventé produirait un chiffre
-- faux — l'invariant est nommé, pas mesuré. ») : cette migration
-- **conserve ce refus** et le rend opposable.
--
-- Ce qu'elle apporte à la place : ces six raisons, qui n'étaient que
-- des affirmations, deviennent des **preuves mesurées** (nombre de
-- colonnes, nom de la colonne manquante). C'est ce que le plan
-- demande en repli — « la raison de chaque exclusion » — et une
-- raison vérifiable vaut mieux qu'un invariant vide.
--
-- LE SEPTIÈME, LUI, EST MESURABLE. INV-19 disait : « Devient
-- mesurable dès qu'un registre des types de documents est écrit
-- (**c'est la matière de la vue chaîne, lot L6**) ». La mesure
-- confirme que les types sont énumérables et que les tables
-- correspondantes existent. Cette migration écrit donc **ce
-- registre** — et le compte est réglé : L6 n'aura plus à l'inventer.
-- ─────────────────────────────────────────────────────────────
-- 1. LE REGISTRE DES TYPES DE DOCUMENTS
--    `chain_document_types` : « le type `pay_runs` est stocké dans
--    la table `pay_runs` ». C'est la pièce qui manquait à INV-19,
--    et celle dont la vue chaîne (L6) a besoin pour résoudre un
--    `amont_type` en table. Elle est **technique**, pas métier :
--    `tenant_id IS NULL` = entrée standard livrée avec le produit,
--    convention identique à `chain_invariants` (413).
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chain_document_types (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid REFERENCES tenants(id) ON DELETE CASCADE,
  type          text NOT NULL,
  table_name    text NOT NULL,
  libelle       text,
  cote          text NOT NULL DEFAULT 'les_deux',
  actif         boolean NOT NULL DEFAULT true,
  mesure_le     timestamptz,
  note          text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chain_document_types_type_check   CHECK (btrim(type) <> ''),
  CONSTRAINT chain_document_types_table_check  CHECK (btrim(table_name) <> ''),
  -- Le nom de table est un identifiant, pas un texte libre : seuls
  -- un identifiant SQL valide passent. C'est ce qui rend le SQL
  -- dynamique de `chain_document_resout` inoffensif.
  CONSTRAINT chain_document_types_ident_check  CHECK (table_name ~ '^[a-z_][a-z0-9_]*$'),
  CONSTRAINT chain_document_types_cote_check   CHECK (cote IN ('amont', 'aval', 'les_deux'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_chain_document_types_type
  ON chain_document_types (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
                           type);

-- L'index MENÉ PAR `tenant_id` : exigé par la porte G1 de toute table
-- cloisonnée. L'index unique ci-dessus porte une expression
-- (`COALESCE`) et ne commence donc pas par `tenant_id`.
CREATE INDEX IF NOT EXISTS ix_chain_document_types_societe
  ON chain_document_types (tenant_id, type);

COMMENT ON TABLE chain_document_types IS
  '416 (L4) : le registre « type de document → table ». Résout l''amont_type / aval_type de document_links, que le socle stocke en texte libre sans clé étrangère. tenant_id NULL = entrée standard ; une société peut la surcharger ou la désactiver.';
COMMENT ON COLUMN chain_document_types.cote IS
  'amont / aval / les_deux : le type n''apparaît que d''un côté de la chaîne.';
COMMENT ON COLUMN chain_document_types.mesure_le IS
  'Date du dernier recalcul par audit_chains() : la couverture du registre est une donnée qui vieillit, elle se date.';

-- ─────────────────────────────────────────────────────────────
-- 1.1 SÉCURITÉ (§3.5) — RLS forcée, UNE politique, lecture seule
--      Le registre est écrit par les migrations et par
--      `audit_chains` (recalcul de couverture). Le client le lit :
--      un `INSERT` direct depuis le navigateur permettrait de déclarer
--      un type résolvable vers une table arbitraire et de **faire
--      verdir INV-19 à volonté** — c'est le seul endroit où une
--      écriture de client dégraderait une garantie.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE chain_document_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE chain_document_types FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chain_document_types_select ON chain_document_types;
CREATE POLICY chain_document_types_select ON chain_document_types
  FOR SELECT TO authenticated
  USING (tenant_id IS NULL OR tenant_id = current_tenant_id());

REVOKE ALL ON TABLE chain_document_types FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE chain_document_types TO authenticated;
--
-- ⚠️ LE SENS DE L'ÉCHEC EST CHOISI, ET C'EST LE POINT IMPORTANT.
-- Un lien dont le `amont_type` n'est pas au registre ne peut pas
-- être prouvé résolu. Le compter comme « tenu » serait le faux vert
-- exact que la 413 refuse. Il compte donc comme **ligne en écart**,
-- à côté des orphelins réels. Les deux nombres sont publiés
-- séparément dans `detail` : un `rompu` dit *pourquoi*. Conséquence
-- utile : **INV-19 se durcit à mesure que le registre grandit**, et
-- il ne peut jamais être vert sans avoir réellement regardé.
-- ─────────────────────────────────────────────────────────────
-- 1.2 LA RÉSOLUTION — « ce type mène-t-il bien à cette ligne ? »
--     Renvoie un MOT, jamais un booléen, parce que « je ne sais pas »
--     et « non » ne sont pas la même chose, et qu'un booléen les
--     confondrait — c'est cette confusion qui produit les faux verts.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_document_resout(
  p_type text,
  p_id   uuid
) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_table text;
  v_ok    boolean;
BEGIN
  IF p_type IS NULL OR btrim(p_type) = '' THEN
    RETURN 'inconnu';
  END IF;
  IF p_id IS NULL THEN
    RETURN 'absent';
  END IF;

  -- L'entrée de la société l'emporte sur l'entrée standard, comme
  -- pour `chain_invariants` (413) et `document_effects` (252).
  SELECT r.table_name INTO v_table
    FROM public.chain_document_types r
   WHERE r.actif
     AND r.type = p_type
     AND (r.tenant_id IS NULL OR r.tenant_id = current_tenant_id())
   ORDER BY (r.tenant_id IS NOT NULL) DESC
   LIMIT 1;

  IF v_table IS NULL THEN
    -- Type inconnu du registre : ni preuve, ni verdict.
    RETURN 'inconnu';
  END IF;

  -- Le nom vient du registre, ET la contrainte
  -- `chain_document_types_ident_check` interdit tout ce qui n'est
  -- pas un identifiant SQL. `%I` quote de toute façon : un nom
  -- piégé ne peut pas s'exécuter.
  EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I d WHERE d.id = $1)',
                 v_table)
     INTO STRICT v_ok
     USING p_id;

  RETURN CASE WHEN v_ok THEN 'trouve' ELSE 'absent' END;
END
$fn$;

COMMENT ON FUNCTION public.chain_document_resout(text, uuid) IS
  '416 : résout un couple (type de document, identifiant) en ''trouve'' / ''absent'' / ''inconnu''. ''inconnu'' signifie que le type n''est pas au registre — ce n''est PAS la même chose que ''absent'', et la 416 compte les deux comme ligne en écart d''INV-19 pour ne jamais produire un vert non vérifié.';

REVOKE ALL ON FUNCTION public.chain_document_resout(text, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chain_document_resout(text, uuid) TO service_role;

-- ─────────────────────────────────────────────────────────────
-- 2. L'AMORÇAGE — les entrées standard, à partir de la MESURE
--    On n'invente pas la liste : on inscrit ce que les chaînages
--    produisent réellement. Le lot L3 continue d'alimenter le
--    registre, et la porte `check_chain_invariants` (plus bas)
--    signale tout type nouveau qui n'y serait pas.
-- ─────────────────────────────────────────────────────────────
INSERT INTO chain_document_types (tenant_id, type, table_name, libelle, cote, note)
VALUES
  (NULL, 'pay_runs',         'pay_runs',         'Lot de paie',       'amont',
   'Mesuré le 02/10 : lien `pay_runs → journal_entries` produit par la 415 (paie versée).'),
  (NULL, 'journal_entries',  'journal_entries',  'Écriture comptable', 'aval',
   'Mesuré le 02/10 : 6 liens de ce type, dont l''amont est un lot de paie.')
ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), type)
DO UPDATE SET
  table_name = EXCLUDED.table_name,
  libelle    = EXCLUDED.libelle,
  cote       = EXCLUDED.cote,
  note       = EXCLUDED.note;

-- ─────────────────────────────────────────────────────────────
-- 3. LA MESURE D'INV-19
--    On ne réécrit pas les 250 lignes de `chain_invariant_mesurer`
--    : une copie de 250 lignes devient une seconde source de vérité
--    qui diverge de la première au premier correctif. On RENOMME la
--    fonction existante et on la rappelle pour les treize codes
--    qu'elle sait déjà mesurer ; cette migration n'apporte que le
--    quatorzième.
-- ─────────────────────────────────────────────────────────────
ALTER FUNCTION public.chain_invariant_mesurer(uuid, text)
  RENAME TO chain_invariant_mesurer_base;

COMMENT ON FUNCTION public.chain_invariant_mesurer_base(uuid, text) IS
  '413 : les treize branches de mesure d''un invariant, telles qu''écrites par la 413. La 416 les a renommées (non dupliquées) et appelle cette fonction pour tout code autre que INV-19. Ne pas la modifier ici : elle se modifie dans son fichier d''origine.';

CREATE OR REPLACE FUNCTION public.chain_invariant_mesurer(
  p_tenant uuid,
  p_code   text,
  OUT mesure_a        numeric,
  OUT mesure_b        numeric,
  OUT ecart           numeric,
  OUT lignes_en_ecart integer,
  OUT detail          jsonb
) RETURNS RECORD
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_orphelins     integer := 0;
  v_inconnus      integer := 0;
  v_liens         integer := 0;
  v_type          text;
  v_n             integer;
  v_hors_registre text[] := ARRAY[]::text[];
BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'chain_invariant_mesurer : p_tenant est obligatoire';
  END IF;

  -- Tout code que la 413 sait déjà mesurer : on lui rend la main.
  IF p_code IS DISTINCT FROM 'INV-19' THEN
    SELECT b.mesure_a, b.mesure_b, b.ecart, b.lignes_en_ecart, b.detail
      INTO mesure_a, mesure_b, ecart, lignes_en_ecart, detail
      FROM public.chain_invariant_mesurer_base(p_tenant, p_code) AS b;
    RETURN;
  END IF;

  SELECT count(*) INTO v_liens
    FROM document_links
   WHERE tenant_id = p_tenant AND etat <> 'rompu';

  -- ⚠️ L'AMONT ET L'AVAL SONT PARCOURUS SÉPARÉMENT, ET C'EST NÉCESSAIRE.
  -- Un lien `pay_runs → journal_entries` porte DEUX types : si une
  -- seule boucle les liste, l'orphelin de l'amont serait compté une
  -- fois au tour « pay_runs » et une seconde fois au tour
  -- « journal_entries » — un lien, deux violations, un compte faux.
  -- Chaque côté est donc mesuré par SON type : un lien ne peut
  -- contribuer qu'une fois par côté.
  --
  -- Et l'on procède par TYPE DISTINCT, pas par lien : une requête par
  -- lien serait un N+1 (interdit par §3.3, moyen technique 1), une
  -- par type distinct ne l'est pas. Et il n'y a pas besoin de SQL
  -- dynamique : la seule résolution dynamique (type → table) vit
  -- dans `chain_document_resout` — ici tout est statique, donc
  -- vérifiable par `check_plpgsql` comme le reste du dépôt.
  FOR v_type IN
    SELECT DISTINCT amont_type FROM document_links
     WHERE tenant_id = p_tenant AND etat <> 'rompu'
  LOOP
    IF NOT EXISTS (SELECT 1 FROM chain_document_types r
                    WHERE r.actif AND r.type = v_type
                      AND (r.tenant_id IS NULL OR r.tenant_id = p_tenant)) THEN
      SELECT count(*) INTO v_n FROM document_links
       WHERE tenant_id = p_tenant AND etat <> 'rompu' AND amont_type = v_type;
      v_inconnus := v_inconnus + v_n;
      v_hors_registre := array_append(v_hors_registre, v_type);
      CONTINUE;
    END IF;

    SELECT count(*) INTO v_n FROM document_links l
     WHERE l.tenant_id = p_tenant AND l.etat <> 'rompu' AND l.amont_type = v_type
       AND public.chain_document_resout(l.amont_type, l.amont_id) = 'absent';
    v_orphelins := v_orphelins + v_n;
  END LOOP;

  FOR v_type IN
    SELECT DISTINCT aval_type FROM document_links
     WHERE tenant_id = p_tenant AND etat <> 'rompu'
  LOOP
    IF NOT EXISTS (SELECT 1 FROM chain_document_types r
                    WHERE r.actif AND r.type = v_type
                      AND (r.tenant_id IS NULL OR r.tenant_id = p_tenant)) THEN
      SELECT count(*) INTO v_n FROM document_links
       WHERE tenant_id = p_tenant AND etat <> 'rompu' AND aval_type = v_type;
      v_inconnus := v_inconnus + v_n;
      IF NOT (v_type = ANY (v_hors_registre)) THEN
        v_hors_registre := array_append(v_hors_registre, v_type);
      END IF;
      CONTINUE;
    END IF;

    SELECT count(*) INTO v_n FROM document_links l
     WHERE l.tenant_id = p_tenant AND l.etat <> 'rompu' AND l.aval_type = v_type
       AND public.chain_document_resout(l.aval_type, l.aval_id) = 'absent';
    v_orphelins := v_orphelins + v_n;
  END LOOP;

  -- ⚠️ LE CHOIX QUI EMPÊCHE LE FAUX VERT. Un lien non résolvable est
  -- compté en écart AU MÊME TITRE qu'un orphelin réel : le relevé ne
  -- peut pas dire « tenu » sur ce qu'il n'a pas su regarder. Les
  -- deux nombres restent distincts dans `detail`, pour que le lecteur
  -- sache lequel des deux il affronte.
  lignes_en_ecart := v_orphelins + v_inconnus;
  detail := jsonb_build_object(
    'liens_examines',     v_liens,
    'orphelins_reels',     v_orphelins,
    'types_non_resolus',   v_inconnus,
    'types_hors_registre', to_jsonb(v_hors_registre),
    'lecture', 'un lien dont le type est hors registre compte en écart : '
               'un invariant ne peut pas être tenu sans avoir été regardé.');

  -- `existence` : le verdict de `audit_chains` se lit sur
  -- `lignes_en_ecart`. Une société sans lien ne peut pas être rompue,
  -- et ne peut pas non plus fournir la preuve d'une bonne santé —
  -- le détail le dit, l'indice reste sur les autres invariants.
  RETURN;
END
$fn$;

COMMENT ON FUNCTION public.chain_invariant_mesurer(uuid, text) IS
  '416 (L4) : mesure UN invariant. INV-19 est mesuré ici (résolution amont/aval par le registre `chain_document_types`) ; les treize autres sont délégués à `chain_invariant_mesurer_base` (413). Lève si un code mesurable n''a aucune branche — un relevé vide ne doit jamais passer pour un invariant tenu.';

REVOKE ALL ON FUNCTION public.chain_invariant_mesurer(uuid, text)
  FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- 4. LE REGISTRE — INV-19 devient mesurable, les six autres
--    passent de l'affirmation à la preuve
--
--    On écrit les raisons au format long, avec la mesure qui les
--    fonde. Une raison vérifiable se contrôle ; une raison
--    invérifiable se recopie, et le contrôle s'arrête à la recopie.
-- ─────────────────────────────────────────────────────────────

-- INV-19 : la raison a été levée parce qu'elle est levée.
UPDATE chain_invariants
   SET mesurable            = true,
       raison_non_mesurable = NULL,
       note = '416 : mesurable. `document_links` ne porte pas de clé '
              'étrangère vers l''amont, mais le registre '
              '`chain_document_types` (écrit par la 416) résout chaque '
              'type vers sa table. Un lien dont le type est hors '
              'registre compte EN ÉCART : l''invariant ne peut pas être '
              'tenu sans avoir été regardé. Matière de la vue chaîne, '
              'lot L6 : le registre est désormais écrit.'
 WHERE tenant_id IS NULL AND code = 'INV-19';

UPDATE chain_invariants
   SET raison_non_mesurable =
       'Mesuré le 02/10/2026 sur base neuve. `purchase_orders` porte 13 '
       'colonnes (id, number, supplier_id, order_date, expected_date, '
       'status, subtotal, vat, total, notes, created_at, updated_at, '
       'tenant_id) : NI montant facturé, NI montant reçu. Et '
       '`document_links` ne porte aucun lien de type `purchase_orders` '
       '(types relevés : `pay_runs`, `journal_entries`). Le reste à '
       'facturer n''a donc ni colonne ni chaîne : le mesurer suppose '
       'd''inventer l''une des deux. Référentiel : « rompu (BUD-03) ». '
       'Mesurable dès que la commande porte son facturé/reçu — décision '
       'de modèle, pas contrôle.'
 WHERE tenant_id IS NULL AND code = 'INV-05';

UPDATE chain_invariants
   SET raison_non_mesurable =
       'Mesuré le 02/10/2026 sur base neuve. `budgets` porte 17 colonnes, '
       'dont les 12 numériques `period_1..12` — qui sont le BUDGET. '
       'Aucun « réalisé » n''y est stocké. Le côté `journal_lines` est '
       'mesurable : c''est le réalisé budgétaire STOCKÉ qui manque, et '
       'l''ajouter (colonne + fonction qui l''écrit + arbitrage de qui '
       'fait foi) est une décision de modèle. Référentiel : « rompu '
       '(BUD-01, BUD-02) ».'
 WHERE tenant_id IS NULL AND code = 'INV-06';

UPDATE chain_invariants
   SET raison_non_mesurable =
       'Mesuré le 02/10/2026 sur base neuve. `lettrage_groups` porte 11 '
       'colonnes et AUCUNE clé vers `journal_lines`. '
       '`bank_transactions.reconciled_entry_id` existe, mais il pointe '
       'vers une écriture, pas vers le groupe de lettrage : il n''y a '
       'donc aucune jointure à contrôler. Référentiel : « inexistant » — '
       'et c''est ce que la mesure confirme.'
 WHERE tenant_id IS NULL AND code = 'INV-07';

UPDATE chain_invariants
   SET raison_non_mesurable =
       'Mesuré le 02/10/2026 sur base neuve. `bank_transactions` porte 33 '
       'colonnes — aucune de solde de relevé — et le schéma ne comporte '
       'AUCUNE table de relevé. Le côté gauche de l''égalité n''existe '
       'pas. Référentiel : « partiellement tenu (223) » : la 223 tient le '
       'rapprochement, pas le solde du relevé.'
 WHERE tenant_id IS NULL AND code = 'INV-08';

UPDATE chain_invariants
   SET raison_non_mesurable =
       'Mesuré le 02/10/2026 sur base neuve. `dsn_declarations` porte 11 '
       'colonnes — id, tenant_id, period, type, status, file_url, '
       'generated_at, transmitted_at, response_code, response_message, '
       'created_at — dont ZÉRO numérique. Le brut déclaré n''existe que '
       'dans le fichier produit : il n''est pas lisible en base. '
       'Référentiel : « non testé ».'
 WHERE tenant_id IS NULL AND code = 'INV-10';

UPDATE chain_invariants
   SET raison_non_mesurable =
       'Mesuré le 02/10/2026 sur base neuve. `projects.actual_cost` '
       || 'existe (3 projets relevés) : le côté gauche est donc lisible. '
       'Mais le référentiel nomme « DEUX calculs concurrents (PROJ-02) » '
       ': tant que le calcul unique de marge n''est pas choisi, '
       'l''égalité n''a pas de terme de droite. Le choisir est une '
       'décision de modèle, pas un contrôle.'
 WHERE tenant_id IS NULL AND code = 'INV-12';

-- ─────────────────────────────────────────────────────────────
-- 5. CE QUE CETTE MIGRATION NE FAIT PAS — nommé
--
-- * **Elle ne rend pas les 20 invariants mesurables.** Elle en rend
--   UN de mesurable (INV-19) et elle transforme les six raisons
--   restantes en preuves mesurées. L'indice passe donc de « 13
--   mesurés sur 20 inscrits » à « 14 mesurés, 6 nommés avec leur
--   preuve ». Le plan autorise ce repli (« ou la raison de chaque
--   exclusion ») ; il n'autorise pas d'écrire un contrôle qui
--  compare un montant à un agrégat inventé.
-- * **Elle ne corrige aucun écart.** Parmi les quatorze mesurés, le
--   référentiel en annonçait plusieurs « rompus » (INV-01, INV-02,
--   INV-03, INV-11). L'indice publié sera bas — et c'est le but.
-- * **Elle ne mesure pas les 8 épreuves.** La page « Robustesse »
--   (L5) lit le banc D1→D8, qui est la tranche 3 du lot L3. Cette
--   migration ne produit que la matière de la page « Cohérence ».
-- * **Elle ne comble pas les données manquantes.** INV-08 (solde de
--   relevé), INV-10 (brut DSN), INV-06 (réalisé budgétaire) :
--   ajouter ces colonnes est un lot de schéma, pas une migration de
--   contrôle. Elles restent nommées jusqu'à ce qu'un lot les porte.
-- ============================================================
REVOKE ALL ON FUNCTION public.chain_invariant_mesurer_base(uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chain_invariant_mesurer(uuid, text) TO service_role;