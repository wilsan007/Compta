-- ═══════════════════════════════════════════════════════════════════════════
-- 433 — Lot L3, tranche 5 : LE MOTEUR DU BANC D'UNS D'ÉPREUVES, ET SON
--   RAPPORT PAR MAILLON (tâche 3.4 du plan de la partie 3)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **Objet.** Le plan des chaînages demande « une description du maillon → les
-- 8 épreuves », et un « rapport par maillon : un chaînage déclaré = 8 verdicts
-- datés ». C'est la transformation qui manquait : jusqu'ici, le traçage
-- prouvait qu'un maillon PRODUIT un effet, jamais qu'il le produit BIEN.
-- Un maillon qui double au rejeu, qui laisse un effet orphelin à l'annulation,
-- ou qui fuit vers la société voisine reste « tracé » tant que rien ne
-- l'éprouve.
--
-- **UNE DESCRIPTION, HUIT ÉPREUVES.** On ne redemande pas huit fois la
-- description d'un maillon : `chain_banc_maillons` en porte UNE (code, effet,
-- document, amont, et la FONCTION qui produit l'effet avec ses arguments), et
-- `chain_banc_lancer` en dérive les huit. C'est ce qui rend le banc TENABLE :
-- ajouter un maillon coûte une ligne, pas huit scénarios.
--
-- **LES HUIT ÉPREUVES, ET CE QUE CHACUNE PROUVE RÉELLEMENT** (la définition
-- est dans le plan des chaînages §3, elle est reprise ici pour qu'on n'ait pas
-- à l'ouvrir) :
--
--   D1 rejeu        l'effet n'est pas doublé          → 0 effet de plus au 2ᵉ appel
--   D2 concurrence  deux appels simultanés           → verrous tenus, 0 doublement
--   D3 tout ou rien une panne partielle ne laisse rien→ 0 effet orphelin
--   D4 annulation   le lien se ferme, l'effet part   → 0 lien actif
--   D5 réouverture  un nouveau tour naît             → 2 tours, 1 lien actif
--   D6 retour arrière la transaction recule          → état initial restauré
--   D7 volume       le p95 reste dans le budget G6   → p95 ≤ 50 ms (§3.3)
--   D8 isolation    la société voisine ne voit rien  → 0 fuite entre sociétés
--
-- **ET SI UNE ÉPREUVE NE PEUT PAS ÊTRE JOUÉE, ELLE LE DIT.** C'est le point
-- de méthode. Un banc qui rend « vert » une épreuve qu'il n'a pas jouée est
-- le pire des instruments : il donne l'assurance d'une preuve sans la preuve.
-- Une épreuve non jouée est enregistrée comme telle, AVEC SA RAISON, et le
-- rapport la compte séparément. Le plan dit « 62/62 éprouvés, OU LA LISTE DES
-- EXCLUS AVEC LEUR RAISON » : cette seconde branche n'existe que si le banc
-- sait dire ce qu'il n'a pas fait.
--
-- **LE RAPPORT EST DANS LA BASE, PAS DANS UN DOCUMENT.** `chain_banc_resultats`
-- conserve chaque exécution (datée, avec la mesure et l'attendu), et la vue
-- `chain_banc_rapport` donne le DERNIER verdict par (maillon, épreuve). C'est ce
-- que lira la page « Robustesse » (lot L5, partie 4). Un rapport écrit dans un
-- document serait vrai au jour où on l'écrit — même objection que pour la
-- tâche 3.1.
--
-- **CE QUE CE MOTEUR NE FAIT PAS.** Il n'exécute pas les épreuves : il les
-- décrit, les enregistre et les publie. Les épreuves elles-mêmes sont les
-- tranches 3.5 à 3.7 ; ce fichier pose le cadre dans lequel elles s'écrivent,
-- pour que chacune d'elles n'ait pas à réinventer le rapport.
-- ═══════════════════════════════════════════════════════════════════════════
-- ─────────────────────────────────────────────────────────────
-- 1. LE CATALOGUE DES MAILLONS ÉPROUVÉS
--    UNE ligne de description par maillon. C'est cette table qui rend le banc
--    tenable : les huit épreuves en sont dérivées, on ne les décrit pas huit
--    fois.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chain_banc_maillons (
  code           text PRIMARY KEY,
  libelle        text NOT NULL,
  -- L'effet que le maillon produit : c'est la clé du registre des traces.
  effet          text NOT NULL,
  document_type  text NOT NULL,
  evenement      text NOT NULL,
  amont_type     text NOT NULL,
  -- La FONCTION qui produit l'effet, et ses arguments. Le banc les appelle ;
  -- il ne connaît rien du métier.
  fonction       text NOT NULL,
  arguments      jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- ⚠️ LE SENS EST CE QUI PERMET À DEUX MAILLONS DE PARTAGER UN EFFET.
  -- `releve.delettrage` ne PRODUIT PAS `treasury.statement_line.posted` : il
  -- le RETIRE, il rompt son lien (doctrine 320). Sans cette colonne, l'index
  -- unique sur `effet` l'interdisait — et il l'interdit à raison : il
  -- obligerait à inventer un nom d'effet pour un maillon qui n'en crée aucun.
  -- Un vocabulaire qui ne sait pas dire « celui-ci ne fait que fermer »
  -- oblige à mentir. C'est le même défaut que celui de la 416 sur les
  -- `link_type`, et la même correction : on ajoute le mot qui manque.
  sens           text NOT NULL DEFAULT 'produit',
  actif          boolean NOT NULL DEFAULT true,
  note           text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chain_banc_maillons_code_check    CHECK (code ~ '^[a-z0-9_.]+$'),
  CONSTRAINT chain_banc_maillons_libelle_check CHECK (btrim(libelle) <> ''),
  CONSTRAINT chain_banc_maillons_args_check    CHECK (jsonb_typeof(arguments) = 'object'),
  CONSTRAINT chain_banc_maillons_sens_check     CHECK (sens = ANY (ARRAY['produit','ferme']))
);

COMMENT ON TABLE chain_banc_maillons IS
  '433 (L3, tr. 5) : UNE description par maillon éprouvé. Le banc en tire les huit épreuves — c''est ce qui remplace huit scénarios par maillon. `sens` = ''produit'' (le maillon crée un effet) ou ''ferme'' (il retire un effet existant, doctrine 320) : deux maillons peuvent partager un effet s''ils n''en ont pas le même sens.';

-- REJOUEABLE : la table existe peut-être déjà si la 433 a été appliquée sans la
-- colonne `sens` (correction ultérieure). `CREATE TABLE IF NOT EXISTS` ne
-- l'ajouterait pas — il ne fait rien du tout si la table existe.
ALTER TABLE chain_banc_maillons ADD COLUMN IF NOT EXISTS sens text NOT NULL DEFAULT 'produit';
DROP INDEX IF EXISTS ux_chain_banc_maillons_effet;

-- L'unicité porte sur (effet, SENS) : deux maillons peuvent viser le même
-- effet s'ils n'en ont pas le même sens (l'un le produit, l'autre le ferme).
CREATE UNIQUE INDEX IF NOT EXISTS ux_chain_banc_maillons_effet
  ON chain_banc_maillons (effet, sens);

-- ─────────────────────────────────────────────────────────────
-- 2. LE RAPPORT — une ligne par (maillon, épreuve, exécution)
--    On CONSERVE chaque exécution, pas seulement la dernière : un rapport
--    qui ne garde que le dernier verdict ne dit pas si le défaut est nouveau
--    ou ancien.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chain_banc_resultats (
  id            bigserial PRIMARY KEY,
  code          text NOT NULL REFERENCES chain_banc_maillons(code) ON DELETE CASCADE,
  epreuve       text NOT NULL,          -- 'D1' … 'D8'
  tenant_id     uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  joue_le       timestamptz NOT NULL DEFAULT now(),
  verdict       text NOT NULL,          -- 'tenu' | 'rompu' | 'non_joue'
  mesure        numeric,                -- la valeur relevée (p95, nombre d'effets…)
  attendu       text,                   -- ce que l'épreuve exige (lisible)
  obtenu        text,                   -- ce qui a été constaté (lisible)
  duree_ms      integer,
  -- La raison d'un `non_joue` est OBLIGATOIRE : une épreuve non jouée sans
  -- raison est un trou muet, exactement ce que ce banc combat.
  raison        text,
  CONSTRAINT chain_banc_resultats_epreuve_check
    -- Liste explicite (et non un motif) : la suite 105 sait alimenter une
    -- colonne bornée par une liste, pas par une expression régulière.
    CHECK (epreuve IN ('D1','D2','D3','D4','D5','D6','D7','D8')),
  CONSTRAINT chain_banc_resultats_verdict_check
    CHECK (verdict = ANY (ARRAY['tenu','rompu','non_joue'])),
  CONSTRAINT chain_banc_resultats_raison_check
    CHECK (verdict <> 'non_joue' OR btrim(COALESCE(raison, '')) <> '')
);

COMMENT ON TABLE chain_banc_resultats IS
  '433 : le rapport du banc, une ligne par exécution d''épreuve. Chaque passage est conservé — un rapport qui ne garde que le dernier verdict ne dit pas si un défaut est nouveau ou ancien. Un `non_joue` DOIT porter sa raison.';

-- Une seule exécution par (maillon, épreuve, société, seconde) : rejouer le
-- banc dix fois ne doit pas saturer l'historique. La contrainte est en BASE,
-- pas seulement dans la fonction — le garde-fou de la 414, même raison.
-- ─────────────────────────────────────────────────────────────
-- 3. LE RAPPORT PAR MAILLON — la vue que lira l'écran (lot L5)
--    Une ligne par (maillon, épreuve) : le DERNIER verdict, et l'historique
--    en `n_tours` / `n_tenus` / `n_rompus` pour qu'une page puisse montrer
--    « tenu depuis 40 nuits » ou « rompu depuis hier ».
--    Une épreuve jamais jouée reste VISIBLE comme telle : l'absence est
--    publiée, donc elle ne peut pas être prise pour un succès.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW chain_banc_rapport AS
SELECT m.code,
       m.libelle,
       m.effet,
       m.actif,
       e.epreuve,
       (r.verdict IS NOT NULL)                        AS epreuve_jouee,
       COALESCE(r.verdict, 'non_joue')                AS verdict,
       r.mesure,
       r.attendu,
       r.obtenu,
       r.raison,
       r.joue_le                                     AS dernier_passage,
       r.duree_ms,
       COALESCE(h.n_tours, 0)                        AS n_tours,
       COALESCE(h.n_tenus, 0)                         AS n_tenus,
       COALESCE(h.n_rompus, 0)                        AS n_rompus
FROM chain_banc_maillons m
CROSS JOIN (VALUES ('D1'),('D2'),('D3'),('D4'),
                   ('D5'),('D6'),('D7'),('D8')) AS e(epreuve)
LEFT JOIN LATERAL (
  SELECT * FROM chain_banc_resultats x
   WHERE x.code = m.code AND x.epreuve = e.epreuve
   ORDER BY x.joue_le DESC LIMIT 1
) r ON true
LEFT JOIN LATERAL (
  SELECT count(*) AS n_tours,
         count(*) FILTER (WHERE verdict = 'tenu')  AS n_tenus,
         count(*) FILTER (WHERE verdict = 'rompu') AS n_rompus
  FROM chain_banc_resultats y
   WHERE y.code = m.code AND y.epreuve = e.epreuve
) h ON true;

COMMENT ON VIEW chain_banc_rapport IS
  '433 : le rapport par maillon — huit lignes par maillon, une par épreuve. `verdict` vaut tenu, rompu ou non_joue ; une épreuve jamais jouée reste VISIBLE comme telle, donc elle ne peut pas être prise pour un succès.';

-- ─────────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────
-- 3 bis. LE CATALOGUE DES MAILLONS DÉJÀ TRACÉS
--    Sept maillons, sept LIGNES. C'est la démonstration que le moteur est
--    tenable : ce que la 412, la 415 et la 416 ont produit se décrit en sept
--    lignes, et le banc en tire 56 verdicts.
--    `arguments` reste `{}` : les identifiants (lot de paie, ligne de relevé)
--    sont propres à chaque société, ils sont fournis à l'exécution, pas
--    stockés dans un catalogue qui serait faux pour tout le monde.
-- ─────────────────────────────────────────────────────────────
INSERT INTO chain_banc_maillons (code, libelle, effet, document_type, evenement, amont_type, fonction, sens)
VALUES
  ('caisse.ticket',      'Ticket de caisse (encaissement atomique)', 'pos.ticket.stock_out',
   'pos_tickets', 'created', 'pos_tickets', 'create_pos_ticket', 'produit'),
  ('caisse.avoir',       'Avoir de caisse (avec retour de stock)',    'pos.ticket.stock_in',
   'pos_tickets', 'refunded', 'pos_tickets', 'pos_refund_ticket', 'produit'),
  ('paie.comptabilisee', 'Comptabilisation du bulletin de paie',      'payroll.run.posted',
   'pay_runs', 'posted', 'pay_runs', 'payroll_post_run', 'produit'),
  ('paie.versement',     'Versement de la paie (net, social, taxe, acomptes)', 'payroll.payment.settled',
   'pay_runs', 'paid', 'pay_runs', 'post_payroll_payment', 'produit'),
  ('releve.comptabilise', 'Comptabilisation d''une ligne de relevé',   'treasury.statement_line.posted',
   'bank_transactions', 'posted', 'bank_transactions', 'post_bank_statement_line', 'produit'),
  ('releve.pointage',    'Pointage manuel d''une ligne de relevé',     'treasury.statement_line.manually_reconciled',
   'bank_transactions', 'reconciled', 'bank_transactions', 'reconcile_bank_statement_line', 'produit'),
  ('releve.delettrage',  'Dé-lettrage d''une ligne de relevé (FERME le lien, ne produit rien)',
   'treasury.statement_line.posted',
   'bank_transactions', 'posted', 'bank_transactions', 'unreconcile_bank_statement_line', 'ferme')
ON CONFLICT (code) DO UPDATE SET
  libelle = EXCLUDED.libelle, effet = EXCLUDED.effet,
  document_type = EXCLUDED.document_type, evenement = EXCLUDED.evenement,
  amont_type = EXCLUDED.amont_type, fonction = EXCLUDED.fonction,
  sens = EXCLUDED.sens;

-- ─────────────────────────────────────────────────────────────
-- 4. LE MOTEUR : UNE DESCRIPTION → LES HUIT ÉPREUVES
-- 4. LE MOTEUR : UNE DESCRIPTION → LES HUIT ÉPREUVES
--    `chain_banc_lancer` parcourt le catalogue et enregistre un verdict par
--    (maillon, épreuve). Il n'exécute PAS encore les épreuves de fond : il
--    pose le cadre, et les écrit `non_joue` AVEC SA RAISON pour celles qui ne
--    sont pas implémentées — ce qui est le contraire d'un « vert par défaut ».
--    Les tranches 3.5 à 3.7 remplacent chaque `non_joue` par sa mesure.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION chain_banc_lancer(p_tenant uuid, p_code text DEFAULT NULL)
RETURNS TABLE (v_code text, v_epreuves int, v_tenues int, v_rompus int, v_non_jouees int)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $moteur$
DECLARE
  v_tid   uuid := COALESCE(p_tenant, current_tenant_id());
  m       record;
  v_epreuve text;
  v_total int; v_tenu int; v_rompu int; v_nonjoue int;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Banc de chaînage : aucune société active' USING ERRCODE = '42501';
  END IF;

  FOR m IN
    SELECT * FROM chain_banc_maillons b
     WHERE b.actif AND (p_code IS NULL OR b.code = p_code)
  LOOP
    FOR v_epreuve IN SELECT unnest(ARRAY['D1','D2','D3','D4','D5','D6','D7','D8'])
    LOOP
      -- Tant que l'épreuve n'est pas implémentée, elle est ENREGISTRÉE comme
      -- non jouée, avec sa raison. Jamais « verte par défaut » : c'est la règle
      -- que ce banc s'impose, et elle est vérifiée par la suite 433.
      INSERT INTO chain_banc_resultats
        (code, epreuve, tenant_id, verdict, attendu, obtenu, raison)
      VALUES
        (m.code, v_epreuve, v_tid, 'non_joue',
         'l''épreuve doit être implémentée (tranches 3.5 à 3.7)',
         NULL,
         format('Non jouée au %s : le moteur (433) existe, l''épreuve %s n''est pas encore implémentée.',
                to_char(now(), 'DD/MM/YYYY'), v_epreuve))
      ON CONFLICT (code, epreuve, tenant_id, joue_le) DO NOTHING;
    END LOOP;

    SELECT count(*),
           count(*) FILTER (WHERE verdict = 'tenu'),
           count(*) FILTER (WHERE verdict = 'rompu'),
           count(*) FILTER (WHERE verdict = 'non_joue')
      INTO v_total, v_tenu, v_rompu, v_nonjoue
      FROM chain_banc_resultats r
     WHERE r.code = m.code AND r.tenant_id = v_tid
       AND r.joue_le = (SELECT max(r2.joue_le) FROM chain_banc_resultats r2
                         WHERE r2.code = m.code AND r2.tenant_id = v_tid);

    v_code     := m.code;
    v_epreuves  := v_total;
    v_tenues    := v_tenu;
    v_rompus    := v_rompu;
    v_non_jouees := v_nonjoue;
    RETURN NEXT;
  END LOOP;
END $moteur$;

COMMENT ON FUNCTION chain_banc_lancer(uuid, text) IS
  '433 : le moteur du banc. Parcourt le catalogue et enregistre un verdict par (maillon, épreuve). Tant que les épreuves des tranches 3.5 à 3.7 ne sont pas écrites, elles sont ENREGISTRÉES comme non jouées avec leur raison — jamais vertes par défaut.';

REVOKE ALL ON FUNCTION chain_banc_lancer(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION chain_banc_lancer(uuid, text) TO service_role;
CREATE UNIQUE INDEX IF NOT EXISTS ux_chain_banc_resultats_tour
  ON chain_banc_resultats (code, epreuve, tenant_id, joue_le);

CREATE INDEX IF NOT EXISTS ix_chain_banc_resultats_tenant
  ON chain_banc_resultats (tenant_id, code, joue_le DESC);
CREATE INDEX IF NOT EXISTS ix_chain_banc_resultats_non_joue
  ON chain_banc_resultats (joue_le) WHERE verdict = 'non_joue';

-- ─────────────────────────────────────────────────────────────
-- 2 bis. LA RLS, ET L'INDEX DE SOCIÉTÉ — la porte G1 l'a refusé, et elle a
--     raison. Mesuré : sans ce bloc, la 433 fait monter `tables_tenant`,
--     `moins_de_4_commandes`, `sans_politique` et `sans_rls`, et la grille BT
--     casse. La consigne du contrôle est explicite — « corrigez la table
--     fautive, ne relevez pas le plafond » — et c'est la bonne : un relevé de
--     robustesse sans cloisonnement laisserait fuiter les chiffres d'une
--     société vers l'écran d'une autre.
--     `chain_banc_maillons` ne porte PAS `tenant_id` : c'est un catalogue de
--     MÉTHODE, pas une donnée de société — il est donc hors de la grille
--     (qui ne compte que les tables cloisonnées), et sa lecture est ouverte à
--     `service_role` comme à `authenticated` pour que l'écran puisse nommer
--     les maillons qu'il n'a pas encore éprouvés.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE chain_banc_resultats ENABLE ROW LEVEL SECURITY;
ALTER TABLE chain_banc_resultats FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chain_banc_resultats_select_societe ON chain_banc_resultats;
CREATE POLICY chain_banc_resultats_select_societe ON chain_banc_resultats
  FOR SELECT USING (tenant_id = current_tenant_id());

-- Index de société : sans lui, une lecture du rapport par société scanne la
-- table (défaut BUD-04 à l'échelle du schéma).
CREATE INDEX IF NOT EXISTS ix_chain_banc_resultats_societe
  ON chain_banc_resultats (tenant_id, code, epreuve, joue_le DESC);

ALTER TABLE chain_banc_maillons ENABLE ROW LEVEL SECURITY;
ALTER TABLE chain_banc_maillons FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chain_banc_maillons_select ON chain_banc_maillons;
CREATE POLICY chain_banc_maillons_select ON chain_banc_maillons
  FOR SELECT USING (true);

REVOKE ALL ON TABLE chain_banc_maillons, chain_banc_resultats
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE chain_banc_maillons, chain_banc_resultats
  TO authenticated, service_role;
-- L'ÉCRITURE reste au seul `service_role` : le banc est un instrument de
-- mesure, pas une surface d'écriture du client.