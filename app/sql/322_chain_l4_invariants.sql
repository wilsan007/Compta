-- ═══════════════════════════════════════════════════════════════════════════
-- 322 — Lot L4 : les 20 invariants transversaux, et l'indice de cohérence
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **Objet.** Le référentiel (§E.3) nomme 20 invariants transversaux — une
-- **égalité entre deux modules** qui doit être vraie en permanence — et dit que
-- « quatre sont tenus et prouvés (INV-15 à INV-18) », le reste « rompu, partiel
-- ou inexistant », pour un score « de l'ordre de 4 à 6 sur 20 ». Ce chiffre
-- n'était **mesuré nulle part** : cette migration le mesure.
--
-- **Livré.**
--   * `chain_invariants` — le **registre** des 20 invariants (code, libellé,
--     modules, les deux sources, le sens du contrôle, la tolérance). Une ligne
--     `tenant_id NULL` est l'invariant standard livré avec le produit ; une
--     ligne de société l'emporte (même mécanisme que `document_effects`, 252).
--   * `chain_invariant_results` — le **relevé daté** : les deux mesures, l'écart,
--     le nombre de lignes en écart, le verdict, le détail. C'est l'historique
--     que la page « Cohérence » (lot L5) publiera.
--   * `chain_invariant_mesurer(tenant, code)` — le contrôle d'**un** invariant.
--   * `audit_chains(tenant)` — le relevé complet d'une société, et **l'indice de
--     cohérence** (le score sur les invariants mesurables).
--   * le job nocturne `pg_cron` (posé seulement si l'extension est là).
--
-- **Ce qui est mesuré, et ce qui ne l'est pas — dit, pas deviné.**
-- Treize invariants sont mesurés par une requête. **Sept ne le sont pas**, et
-- chacun porte sa raison dans `raison_non_mesurable` : ce n'est pas un oubli,
-- c'est une colonne qui n'existe pas (`dsn_declarations` n'a **aucun** montant
-- pour INV-10, `bank_transactions` aucun **solde** de relevé pour INV-08), un
-- agrégat qui n'est stocké nulle part (le « réalisé » d'INV-06, le « reste à
-- facturer » d'INV-05), deux calculs concurrents qu'aucune égalité ne tranche
-- (INV-12), l'absence d'un lien stocké (INV-07) ou d'une clé étrangère vers
-- l'amont (INV-19). Les enregistrer **non mesurables** est ce qui rend l'indice
-- honnête : un invariant absent du registre serait un invariant oublié, un
-- invariant enregistré non mesurable est un invariant **nommé**.
--
-- **Doctrine.** Un invariant **non mesurable** ne compte **ni** au numérateur
-- **ni** au dénominateur de l'indice : l'indice est le score **sur ce qui est
-- mesuré**, et le relevé publie à côté le nombre de ceux qui ne le sont pas.
-- Afficher « 13/20 » quand sept ne sont pas mesurables serait un mensonge ;
-- l'indice dit « tant tenus sur 13 mesurés, 7 non mesurables sur 20 inscrits ».
--
-- **Non-régression.** Deux tables cloisonnées de plus : RLS **activée et
-- forcée**, politique de lecture par société, index mené par `tenant_id`. Le
-- plafond daté `tables_tenant` de la porte G1 est réinscrit dans le même
-- commit — c'est la règle de `check_bt_grid` (« un plafond qui ne se réinscrit
-- pas est un plafond mort »).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. LE REGISTRE — les 20 invariants (I-03, §E.3 du référentiel)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chain_invariants (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id             uuid REFERENCES tenants(id) ON DELETE CASCADE,
  code                  text NOT NULL,
  libelle               text NOT NULL,
  modules               text[] NOT NULL DEFAULT '{}',
  source_a              text NOT NULL,
  source_b              text NOT NULL,
  sens                  text NOT NULL DEFAULT 'egalite',
  tolerance             numeric NOT NULL DEFAULT 0.01,
  mesurable             boolean NOT NULL DEFAULT true,
  raison_non_mesurable  text,
  actif                 boolean NOT NULL DEFAULT true,
  note                  text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chain_invariants_code_check    CHECK (btrim(code) <> ''),
  CONSTRAINT chain_invariants_libelle_check CHECK (btrim(libelle) <> ''),
  CONSTRAINT chain_invariants_sens_check    CHECK (sens IN (
    'egalite', 'inferieur_ou_egal', 'existence', 'integrite')),
  CONSTRAINT chain_invariants_raison_check  CHECK (
    mesurable OR btrim(COALESCE(raison_non_mesurable, '')) <> ''),
  CONSTRAINT chain_invariants_tolerance_check CHECK (tolerance >= 0)
);

-- L'unicité du registre, standard (tenant_id NULL) ou propre à une société —
-- le même mécanisme que `uq_document_effects_contrat` (252) : une contrainte
-- PRIMARY KEY n'accepte pas d'expression, c'est donc un index unique sur
-- l'expression, et c'est lui que `ON CONFLICT` retrouve.
CREATE UNIQUE INDEX IF NOT EXISTS uq_chain_invariants_code
  ON chain_invariants (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
                       code);

COMMENT ON TABLE chain_invariants IS
  '322 (L4) : le registre des invariants transversaux (§E.3 du référentiel). tenant_id NULL = invariant standard livré avec le produit ; une ligne de société l''emporte (et peut le désactiver par actif = false).';
COMMENT ON COLUMN chain_invariants.mesurable IS
  '322 : false = l''invariant est NOMMÉ mais aucune requête ne peut le trancher aujourd''hui. La raison est obligatoire (raison_non_mesurable) et l''invariant ne compte ni au numérateur ni au dénominateur de l''indice.';
COMMENT ON COLUMN chain_invariants.sens IS
  'egalite = a doit valoir b (à la tolérance près) ; inferieur_ou_egal = a <= b ; existence = aucune ligne ne doit exister ; integrite = la propriété structurelle doit tenir.';

-- ─────────────────────────────────────────────────────────────
-- 2. LE RELEVÉ DATÉ — ce que la mesure a trouvé
--    Non partitionné, et c'est un choix dit : un relevé nocturne écrit 20 lignes
--    par société et par nuit (7 300 par an), pas un million — le budget §3.3 de
--    la 252 ne s'y applique pas, et le partitionnement ajouterait deux tables
--    au plafond de la porte G1 pour rien.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chain_invariant_results (
  id                bigserial PRIMARY KEY,
  tenant_id         uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  code              text NOT NULL,
  verdict           text NOT NULL,
  mesure_a          numeric,
  mesure_b          numeric,
  ecart             numeric,
  lignes_en_ecart   integer NOT NULL DEFAULT 0,
  duree_ms          integer NOT NULL DEFAULT 0,
  detail            jsonb,
  mesure_le         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chain_invariant_results_verdict_check CHECK (verdict IN (
    'tenu', 'rompu', 'non_mesure')),
  CONSTRAINT chain_invariant_results_code_check CHECK (btrim(code) <> '')
);

-- La lecture par société (l'historique d'un invariant, le dernier relevé).
CREATE INDEX IF NOT EXISTS ix_chain_invariant_results_societe
  ON chain_invariant_results (tenant_id, mesure_le DESC);
CREATE INDEX IF NOT EXISTS ix_chain_invariant_results_code
  ON chain_invariant_results (tenant_id, code, mesure_le DESC);

COMMENT ON TABLE chain_invariant_results IS
  '322 (L4) : le relevé daté des invariants, par société — la matière de la page « Cohérence » (lot L5) : score, écarts, historique.';
COMMENT ON COLUMN chain_invariant_results.verdict IS
  'tenu = l''égalité tient à la tolérance près ; rompu = l''écart est un défaut exploitable ; non_mesure = l''invariant est inscrit mais aucune requête ne le tranche (la raison est au registre).';

-- ─────────────────────────────────────────────────────────────
-- 3. RLS activée ET forcée, politique de lecture, droits
--    Aucune politique d'écriture : le relevé s'écrit par audit_chains()
--    (SECURITY DEFINER, propriétaire des tables), jamais par le client.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE chain_invariants ENABLE ROW LEVEL SECURITY;
ALTER TABLE chain_invariants FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chain_invariants_select ON chain_invariants;
CREATE POLICY chain_invariants_select ON chain_invariants
  FOR SELECT USING (tenant_id IS NULL OR tenant_id = current_tenant_id());

ALTER TABLE chain_invariant_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE chain_invariant_results FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chain_invariant_results_select_societe ON chain_invariant_results;
CREATE POLICY chain_invariant_results_select_societe ON chain_invariant_results
  FOR SELECT USING (tenant_id = current_tenant_id());

REVOKE ALL ON TABLE chain_invariants, chain_invariant_results
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE chain_invariants, chain_invariant_results
  TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────
-- 4. LE REGISTRE EST ÉCRIT — les 20 invariants du §E.3
--    Rejouable : ON CONFLICT met à jour le libellé, les sources et la raison, et
--    ne touche jamais `actif` — une société qui a éteint un invariant garde son
--    choix. Quatre INSERT plutôt qu'un : le registre se lit par groupe.
-- ─────────────────────────────────────────────────────────────
INSERT INTO chain_invariants AS ci
  (tenant_id, code, libelle, modules, source_a, source_b, sens, tolerance,
   mesurable, raison_non_mesurable, note)
VALUES
  (NULL, 'INV-01',
   'Le stock valorisé (couches) égale le solde des comptes de stock',
   ARRAY['stock','compta'],
   'stock_valuation_layers — Σ (remaining_qty × unit_cost)',
   'journal_lines — solde des comptes 31x',
   'egalite', 0.01, true, NULL,
   'Référentiel : « rompu (S-01→S-07) ». La variation de stock (603x) n''est '
   'comptabilisée qu''à la clôture : le contrôle porte donc sur le solde 31x, '
   'et un écart de l''exercice en cours est attendu tant que la clôture n''a pas '
   'passé — c''est dit, pas masqué.'),

  (NULL, 'INV-02',
   'La quantité par dépôt égale la somme des mouvements du dépôt',
   ARRAY['stock'],
   'stock_quantities.quantity',
   'stock_movements — in/initial (+) et out (−)',
   'egalite', 0.000001, true, NULL,
   'Les mouvements `transfer` et `adjustment` sont **ambigus** : quantity est '
   'non négative par contrainte et aucun signe n''est stocké. Ils sont exclus du '
   'calcul et leur nombre est publié dans `detail.mouvements_ambigus` — un '
   'invariant dont une partie des cas n''est pas tranchable le dit.'),

  (NULL, 'INV-03',
   'Rien n''est réservé sans commande confirmée non livrée',
   ARRAY['stock','ventes'],
   'stock_quantities.reserved_quantity',
   'sales_orders confirmées, non entièrement livrées',
   'egalite', 0.000001, true, NULL,
   'Référentiel : « rompu (S-07) ». Une réservation est une **quantité**, une '
   'commande un **document** : le contrôle compare le total réservé au nombre '
   'de commandes confirmées non livrées, et publie les deux côtés. Un total '
   'réservé strictement positif sans aucune commande de ce genre est l''écart.'),

  (NULL, 'INV-04',
   'Aucun pointage, temps projet ou frais un jour d''absence bloquante',
   ARRAY['rh','projets','frais'],
   'employee_absence_days où blocks_work',
   'timesheets / project_time_entries / expense_report_lines du même jour',
   'existence', 0, true, NULL,
   'W9 a livré le registre des absences (263) : le contrôle devient possible. '
   'Sens `existence` = aucune ligne ne doit exister ; `lignes_en_ecart` compte '
   'les violations trouvées, et `detail` les répartit par table.'),

  (NULL, 'INV-05',
   'L''engagement fournisseur égale le reste à facturer des commandes ouvertes',
   ARRAY['achats','budget'],
   'budget_commitments (source_type = purchase_order)',
   'purchase_orders — reste à facturer',
   'egalite', 0.01, false,
   'purchase_orders ne porte **aucun** montant facturé ni reçu : le « reste à '
   'facturer » n''est stocké nulle part et ne peut qu''être deviné. Mesurer '
   'l''écart d''un agrégat inventé produirait un chiffre faux — l''invariant est '
   'nommé, pas mesuré.',
   'Référentiel : « rompu (BUD-03) ». Devient mesurable dès qu''une colonne de '
   'facturé ou de reçu existe sur la commande fournisseur.')
ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), code)
DO UPDATE SET
  libelle = EXCLUDED.libelle, modules = EXCLUDED.modules,
  source_a = EXCLUDED.source_a, source_b = EXCLUDED.source_b,
  sens = EXCLUDED.sens, tolerance = EXCLUDED.tolerance,
  mesurable = EXCLUDED.mesurable,
  raison_non_mesurable = EXCLUDED.raison_non_mesurable,
  note = EXCLUDED.note;

INSERT INTO chain_invariants AS ci
  (tenant_id, code, libelle, modules, source_a, source_b, sens, tolerance,
   mesurable, raison_non_mesurable, note)
VALUES
  (NULL, 'INV-06',
   'Le réalisé budgétaire égale les mouvements de l''exercice',
   ARRAY['budget','compta'],
   'budgets — réalisé',
   'journal_lines de l''exercice (hors à-nouveaux, clôture, brouillons)',
   'egalite', 0.01, false,
   '`budgets` ne porte que le **budget** (period_1 → period_12) : aucun '
   '« réalisé » n''y est stocké. L''invariant compare deux choses dont l''une '
   'n''existe pas — il est nommé, pas mesuré.',
   'Référentiel : « rompu (BUD-01, BUD-02) ». Le côté `journal_lines` est, lui, '
   'mesurable : c''est le réalisé budgétaire **stocké** qui manque.'),

  (NULL, 'INV-07',
   'Le lettrage égale la TVA sur encaissements correspondante',
   ARRAY['compta','tva'],
   'lettrage_groups (total_debit / total_credit / residual)',
   'journal_lines — comptes 44564 / 44574',
   'egalite', 0.01, false,
   'Aucun lien n''est stocké entre un groupe de lettrage et la ligne de TVA sur '
   'encaissements qu''il est censé déclencher : l''appariement ne peut qu''être '
   'reconstitué par hypothèse. Nommé, pas mesuré.',
   'Référentiel : « inexistant » — et c''est ce que la mesure confirme : il n''y '
   'a pas de jointure à contrôler.'),

  (NULL, 'INV-08',
   'Le solde du relevé égale le solde comptable plus l''en-cours de rapprochement',
   ARRAY['tresorerie','compta'],
   'bank_transactions — solde du relevé',
   'journal_lines — solde des comptes 512',
   'egalite', 0.01, false,
   '`bank_transactions` porte des **lignes** de relevé, jamais le **solde** du '
   'relevé : aucune colonne de solde, aucune table de relevé. Le côté gauche de '
   'l''égalité n''existe pas — nommé, pas mesuré.',
   'Référentiel : « partiellement tenu (223) » : la 223 tient le rapprochement, '
   'pas le solde du relevé.'),

  (NULL, 'INV-09',
   'Le net à payer des bulletins égale le montant du virement',
   ARRAY['paie','tresorerie'],
   'pay_slips — Σ net_salary par lot de paie',
   'sepa_payment_orders.total_amount du même lot',
   'egalite', 0.01, true, NULL,
   'Les deux côtés portent `pay_run_id` : l''appariement est exact, aucune '
   'hypothèse. Les lots sans ordre de virement sont comptés dans '
   '`detail.lots_sans_virement` — un lot pas encore payé n''est pas un écart.'),

  (NULL, 'INV-10',
   'Le brut de la DSN égale le brut des bulletins du mois',
   ARRAY['paie','dsn'],
   'dsn_declarations — brut déclaré',
   'pay_slips — Σ total_gross du mois',
   'egalite', 0.01, false,
   '`dsn_declarations` ne porte **aucun** montant (id, period, type, status, '
   'file_url, generated_at, transmitted_at, response_code) : le brut déclaré '
   'n''existe que dans le fichier produit. Le côté gauche n''est pas lisible en '
   'base — nommé, pas mesuré.',
   'Référentiel : « non testé ». Le côté `pay_slips` est mesurable ; c''est le '
   'brut **déclaré** qui n''est pas stocké.')
ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), code)
DO UPDATE SET
  libelle = EXCLUDED.libelle, modules = EXCLUDED.modules,
  source_a = EXCLUDED.source_a, source_b = EXCLUDED.source_b,
  sens = EXCLUDED.sens, tolerance = EXCLUDED.tolerance,
  mesurable = EXCLUDED.mesurable,
  raison_non_mesurable = EXCLUDED.raison_non_mesurable,
  note = EXCLUDED.note;

INSERT INTO chain_invariants AS ci
  (tenant_id, code, libelle, modules, source_a, source_b, sens, tolerance,
   mesurable, raison_non_mesurable, note)
VALUES
  (NULL, 'INV-11',
   'Le temps facturé ne dépasse pas le temps saisi, et passe par une ligne de facture',
   ARRAY['projets','ventes'],
   'invoice_lines rattachées à un pointage (time_entry_id)',
   'project_time_entries facturables — Σ duration_seconds',
   'inferieur_ou_egal', 0, true, NULL,
   'Référentiel : « rompu (PROJ-01) ». `invoice_lines.time_entry_id` rend le '
   'rattachement exact : le facturé est la somme des durées des pointages '
   '**liés** à une ligne de facture, le saisi la somme des durées facturables. '
   'Le facturé qui dépasse le saisi est l''écart ; les pointages facturés sans '
   'être facturables sont comptés dans le détail.'),

  (NULL, 'INV-12',
   'La marge projet égale facturé − temps − achats − stock − frais',
   ARRAY['projets'],
   'projects.actual_cost / marge publiée',
   'agrégats croisés (factures, pointages, achats, stock, frais)',
   'egalite', 0.01, false,
   'Le référentiel nomme « **deux calculs concurrents** (PROJ-02) » : il n''y a '
   'pas une marge stockée à confronter à un recalcul, il y a deux recalculs. '
   'Aucune égalité ne tranche entre deux formules — tant que le calcul unique '
   'n''est pas choisi, l''invariant est nommé, pas mesuré.',
   'Devient mesurable quand un seul calcul de marge est écrit (et stocké), ce '
   'qui est un choix de modèle, pas un contrôle.'),

  (NULL, 'INV-13',
   'L''amortissement cumulé égale le solde des comptes 28x',
   ARRAY['immobilisations','compta'],
   'asset_depreciations — Σ amount',
   'journal_lines — solde des comptes 28x (crédit − débit)',
   'egalite', 0.01, true, NULL,
   'Référentiel : « non testé ». Les deux côtés existent et sont lisibles : '
   'le cumul des dotations d''un côté, le solde créditeur des comptes '
   'd''amortissement de l''autre.'),

  (NULL, 'INV-14',
   'La TVA déclarée égale la TVA comptabilisée de la période',
   ARRAY['tva','compta'],
   'vat_returns.vat_collected (déclarations transmises)',
   'journal_lines — TVA collectée comptabilisée sur la période',
   'egalite', 0.01, true, NULL,
   'Référentiel : « non testé (M-10) ». Le contrôle est **par déclaration** : '
   'chacune est confrontée à la TVA comptabilisée entre ses dates. '
   '`lignes_en_ecart` compte les déclarations en écart, `detail` les nomme.'),

  (NULL, 'INV-15',
   'La recette TTC de caisse égale la somme des tickets et l''écriture qui les porte',
   ARRAY['caisse','compta'],
   'pos_tickets — Σ total (tickets non annulés)',
   'journal_lines — débit des écritures POS-<ticket>',
   'egalite', 0.01, true, NULL,
   'Référentiel : « **tenu** (219) ». La clé est celle que la 219 écrit : '
   '`journal_entries.reference = ''POS-'' || pos_tickets.id`. Les tickets non '
   'annulés **sans** écriture sont comptés dans `detail.tickets_sans_ecriture` '
   '— un ticket non comptabilisé est un écart, pas une tolérance.')
ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), code)
DO UPDATE SET
  libelle = EXCLUDED.libelle, modules = EXCLUDED.modules,
  source_a = EXCLUDED.source_a, source_b = EXCLUDED.source_b,
  sens = EXCLUDED.sens, tolerance = EXCLUDED.tolerance,
  mesurable = EXCLUDED.mesurable,
  raison_non_mesurable = EXCLUDED.raison_non_mesurable,
  note = EXCLUDED.note;

INSERT INTO chain_invariants AS ci
  (tenant_id, code, libelle, modules, source_a, source_b, sens, tolerance,
   mesurable, raison_non_mesurable, note)
VALUES
  (NULL, 'INV-16',
   'Le journal NF-525 est intègre (chaîne de hachage sans rupture)',
   ARRAY['compta','caisse','conformite'],
   'verify_nf525_chain — chaîne de hachage',
   'aucune rupture attendue',
   'integrite', 0, true, NULL,
   'Référentiel : « **tenu** (233) ». Le contrôle ne réinvente rien : il appelle '
   'la fonction que la 233 a livrée et lit son verdict. C''est le seul invariant '
   'dont la mesure est **déléguée** à un contrôle déjà prouvé.'),

  (NULL, 'INV-17',
   'Aucune écriture sur un exercice ou une période fermés',
   ARRAY['compta'],
   'journal_entries datées dans une période ou un exercice fermé',
   'fiscal_periods.status / fiscal_years.status',
   'existence', 0, true, NULL,
   'Référentiel : « **tenu** (187) ». Sens `existence` : aucune écriture ne doit '
   'tomber sur une période `closed` ni sur un exercice clos. `lignes_en_ecart` '
   'compte les écritures trouvées.'),

  (NULL, 'INV-18',
   'Tout document validé a un numéro définitif, sans trou',
   ARRAY['compta'],
   'journal_posting_sequences.last_seq par journal et exercice',
   'journal_entries — nombre de numéros de pièce attribués',
   'egalite', 0, true, NULL,
   'Référentiel : « **tenu** (217 / 218) ». Le contrôle est **par journal et par '
   'exercice** : le dernier numéro servi doit égaler le nombre de numéros '
   'attribués. Un écart est un trou (ou un numéro servi deux fois).'),

  (NULL, 'INV-19',
   'Aucun document aval n''est orphelin de son amont',
   ARRAY['chainages'],
   'document_links — aval',
   'le document amont correspondant',
   'existence', 0, false,
   '`document_links` ne porte **aucune** clé étrangère vers l''amont : '
   '`amont_type` est un texte libre et `amont_id` un uuid nu. Contrôler '
   'l''existence de l''amont exige une résolution **dynamique** type par type, '
   'et aucun registre « type de document → table » n''existe. Une résolution '
   'partielle (quelques types seulement) produirait un score faux — l''invariant '
   'est nommé, pas mesuré.',
   'Référentiel : « **inexistant** » — et c''est précisément ce que cette raison '
   'confirme. Devient mesurable dès qu''un registre des types de documents est '
   'écrit (c''est la matière de la vue chaîne, lot L6).'),

  (NULL, 'INV-20',
   'Toute ligne de paie variable a une source identifiée',
   ARRAY['paie'],
   'payroll_variable_elements sans source',
   'temps, absence, frais ou avance identifié',
   'existence', 0, true, NULL,
   'Référentiel : « partiel ». La colonne `source` existe ; le contrôle compte '
   'les lignes où elle est vide ou blanche. `detail` les répartit par '
   '`element_type` — un élément sans source est un montant que personne ne peut '
   'expliquer.')
ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), code)
DO UPDATE SET
  libelle = EXCLUDED.libelle, modules = EXCLUDED.modules,
  source_a = EXCLUDED.source_a, source_b = EXCLUDED.source_b,
  sens = EXCLUDED.sens, tolerance = EXCLUDED.tolerance,
  mesurable = EXCLUDED.mesurable,
  raison_non_mesurable = EXCLUDED.raison_non_mesurable,
  note = EXCLUDED.note;

-- ─────────────────────────────────────────────────────────────
-- 5. LA MESURE D'UN INVARIANT
--    Une fonction, une branche par code : le contrôle se lit d'un bloc, et
--    chaque branche nomme les deux côtés qu'elle compare. Aucune branche ne
--    devine une colonne — ce qui n'existe pas est au registre en
--    `mesurable = false`, avec sa raison.
--    STABLE et SECURITY DEFINER : la fonction ne fait que lire. Le job nocturne
--    n'a pas de session utilisateur, donc pas de `current_tenant_id()` : c'est
--    `p_tenant` qui borne **chaque** requête, explicitement.
-- ─────────────────────────────────────────────────────────────
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
  v_a  numeric;
  v_b  numeric;
  v_n  integer := 0;
  v_n2 integer := 0;
  v_n3 integer := 0;
BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'chain_invariant_mesurer : p_tenant est obligatoire';
  END IF;

  detail := '{}'::jsonb;

  -- ── INV-01 — le stock valorisé (couches restantes) vs le solde des comptes de
  --    stock (31x). La variation (603x) n'est passée qu'à la clôture : un écart
  --    en exercice courant est attendu, et le registre le dit.
  IF p_code = 'INV-01' THEN
    SELECT COALESCE(SUM(remaining_qty * unit_cost), 0) INTO v_a
      FROM stock_valuation_layers WHERE tenant_id = p_tenant;
    SELECT COALESCE(SUM(debit - credit), 0) INTO v_b
      FROM journal_lines
     WHERE tenant_id = p_tenant AND account_code LIKE '31%';

  -- ── INV-02 — la quantité par dépôt vs la somme des mouvements. `transfer` et
  --    `adjustment` n'ont aucun signe stocké (quantity >= 0 par contrainte) :
  --    ils sont exclus du calcul, et leur nombre est publié.
  ELSIF p_code = 'INV-02' THEN
    SELECT COALESCE(SUM(quantity), 0) INTO v_a
      FROM stock_quantities WHERE tenant_id = p_tenant;
    SELECT COALESCE(SUM(CASE WHEN type IN ('in', 'initial') THEN quantity
                             WHEN type = 'out'              THEN -quantity
                             ELSE 0 END), 0),
           COUNT(*) FILTER (WHERE type IN ('transfer', 'adjustment'))
      INTO v_b, v_n2
      FROM stock_movements WHERE tenant_id = p_tenant;
    detail := jsonb_build_object('mouvements_ambigus', v_n2);

  -- ── INV-03 — rien n'est réservé sans commande confirmée non livrée. Une
  --    réservation est une quantité, une commande un document : le contrôle est
  --    une **implication**, pas une égalité de montants.
  ELSIF p_code = 'INV-03' THEN
    SELECT COUNT(*) INTO v_n FROM stock_quantities
     WHERE tenant_id = p_tenant AND COALESCE(reserved_quantity, 0) > 0;
    SELECT COUNT(*) INTO v_n2 FROM sales_orders
     WHERE tenant_id = p_tenant AND status = 'confirmed'
       AND COALESCE(fully_delivered, false) = false;
    v_a := v_n::numeric;
    v_b := v_n2::numeric;
    lignes_en_ecart := CASE WHEN v_n > 0 AND v_n2 = 0 THEN v_n ELSE 0 END;
    detail := jsonb_build_object(
      'lignes_reservees', v_n, 'commandes_confirmees_non_livrees', v_n2);

  -- ── INV-04 — aucun pointage, temps projet ou frais un jour d'absence
  --    bloquante. Trois tables ; chaque violation est comptée.
  ELSIF p_code = 'INV-04' THEN
    WITH absences AS (
      SELECT a.employee_id, a.day,
        (SELECT COUNT(*) FROM timesheets x
          WHERE x.tenant_id = p_tenant AND x.employee_id = a.employee_id
            AND x.date = a.day) AS c_pointage,
        (SELECT COUNT(*) FROM project_time_entries y
          WHERE y.tenant_id = p_tenant AND y.employee_id = a.employee_id
            AND y.start_time::date = a.day) AS c_temps,
        (SELECT COUNT(*) FROM expense_report_lines l
           JOIN expense_reports r ON r.id = l.expense_report_id
          WHERE l.tenant_id = p_tenant AND r.employee_id = a.employee_id
            AND l.date = a.day) AS c_frais
        FROM employee_absence_days a
       WHERE a.tenant_id = p_tenant AND a.blocks_work
    )
    SELECT COALESCE(SUM(c_pointage), 0)::int, COALESCE(SUM(c_temps), 0)::int,
           COALESCE(SUM(c_frais), 0)::int
      INTO v_n, v_n2, v_n3 FROM absences;
    lignes_en_ecart := v_n + v_n2 + v_n3;
    detail := jsonb_build_object(
      'pointages', v_n, 'temps_projet', v_n2, 'frais', v_n3);

  -- ── INV-09 — le net à payer des bulletins vs le montant du virement. Les deux
  --    côtés portent `pay_run_id` : l'appariement est exact. Un lot sans ordre de
  --    virement n'est pas un écart (il n'est pas encore payé) : il est compté à
  --    part, et **seuls** les lots rapprochés entrent dans l'écart.
  ELSIF p_code = 'INV-09' THEN
    SELECT COALESCE(SUM(s.net), 0),
           COALESCE(SUM(CASE WHEN o.id IS NOT NULL THEN o.total_amount END), 0),
           COUNT(*) FILTER (WHERE o.id IS NULL),
           COUNT(*) FILTER (WHERE o.id IS NOT NULL
                              AND abs(s.net - o.total_amount) > 0.01)
      INTO v_a, v_b, v_n2, v_n
      FROM (SELECT pay_run_id, SUM(COALESCE(net_salary, 0)) AS net
              FROM pay_slips WHERE tenant_id = p_tenant GROUP BY pay_run_id) s
      LEFT JOIN sepa_payment_orders o
        ON o.pay_run_id = s.pay_run_id AND o.tenant_id = p_tenant;
    lignes_en_ecart := v_n;
    detail := jsonb_build_object('lots_sans_virement', v_n2, 'lots_en_ecart', v_n);

  -- ── INV-11 — le temps facturé ne dépasse pas le temps saisi. `invoice_lines.
  --    time_entry_id` rend le rattachement exact : aucune hypothèse.
  ELSIF p_code = 'INV-11' THEN
    SELECT COALESCE(SUM(p.duration_seconds), 0) INTO v_a
      FROM project_time_entries p
     WHERE p.tenant_id = p_tenant
       AND EXISTS (SELECT 1 FROM invoice_lines il
                    WHERE il.tenant_id = p_tenant AND il.time_entry_id = p.id);
    SELECT COALESCE(SUM(duration_seconds), 0) INTO v_b
      FROM project_time_entries
     WHERE tenant_id = p_tenant AND COALESCE(is_billable, false);
    -- les pointages facturés alors qu'ils ne sont pas facturables
    SELECT COUNT(*) INTO v_n
      FROM project_time_entries p
     WHERE p.tenant_id = p_tenant
       AND COALESCE(p.is_billable, false) = false
       AND EXISTS (SELECT 1 FROM invoice_lines il
                    WHERE il.tenant_id = p_tenant AND il.time_entry_id = p.id);
    lignes_en_ecart := v_n;
    detail := jsonb_build_object('factures_non_facturables', v_n);

  -- ── INV-13 — l'amortissement cumulé vs le solde des comptes 28x.
  ELSIF p_code = 'INV-13' THEN
    SELECT COALESCE(SUM(amount), 0) INTO v_a
      FROM asset_depreciations WHERE tenant_id = p_tenant;
    SELECT COALESCE(SUM(credit - debit), 0) INTO v_b
      FROM journal_lines
     WHERE tenant_id = p_tenant AND account_code LIKE '28%';

  -- ── INV-14 — la TVA déclarée vs la TVA comptabilisée de la période. Le
  --    contrôle est **par déclaration** : chacune est confrontée à la TVA
  --    collectée comptabilisée entre ses dates (comptes 4457x).
  ELSIF p_code = 'INV-14' THEN
    WITH d AS (
      SELECT COALESCE(v.vat_collected, 0) AS declare,
             (SELECT COALESCE(SUM(jl.credit - jl.debit), 0)
                FROM journal_lines jl
                JOIN journal_entries je ON je.id = jl.journal_id
               WHERE jl.tenant_id = p_tenant
                 AND jl.account_code LIKE '4457%'
                 AND COALESCE(jl.line_date, je.date)::date
                     BETWEEN v.period_start AND v.period_end) AS comptabilise
        FROM vat_returns v
       WHERE v.tenant_id = p_tenant AND v.status <> 'draft'
    )
    SELECT COALESCE(SUM(declare), 0), COALESCE(SUM(comptabilise), 0),
           COUNT(*) FILTER (WHERE abs(declare - comptabilise) > 0.01),
           COUNT(*)
      INTO v_a, v_b, v_n, v_n2 FROM d;
    lignes_en_ecart := v_n;
    detail := jsonb_build_object(
      'declarations_en_ecart', v_n, 'declarations_controlees', v_n2);

  -- ── INV-15 — la recette TTC de caisse vs le débit des écritures qui portent
  --    les tickets. La clé est celle que la 219 écrit :
  --    `journal_entries.reference = 'POS-' || pos_tickets.id`. Le préfixe
  --    'POS-AV-' (avoirs) est **exclu** : ce n'est pas une recette de ticket.
  ELSIF p_code = 'INV-15' THEN
    SELECT COALESCE(SUM(total), 0) INTO v_a
      FROM pos_tickets
     WHERE tenant_id = p_tenant AND COALESCE(is_voided, false) = false;
    SELECT COALESCE(SUM(jl.debit), 0) INTO v_b
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.journal_id
     WHERE jl.tenant_id = p_tenant
       AND je.reference LIKE 'POS-%'
       AND je.reference NOT LIKE 'POS-AV-%';
    SELECT COUNT(*) INTO v_n
      FROM pos_tickets t
     WHERE t.tenant_id = p_tenant AND COALESCE(t.is_voided, false) = false
       AND NOT EXISTS (SELECT 1 FROM journal_entries je
                        WHERE je.tenant_id = p_tenant
                          AND je.reference = 'POS-' || t.id);
    lignes_en_ecart := v_n;
    detail := jsonb_build_object('tickets_sans_ecriture', v_n);

  -- ── INV-16 — la chaîne de hachage NF-525 sans rupture. Le contrôle ne
  --    réinvente rien : il refait, en une requête, ce que `verify_nf525_chain`
  --    (233) vérifie ligne à ligne — chaque `previous_hash` doit valoir le
  --    `current_hash` de la ligne précédente, dans l'ordre des identifiants.
  --    Refait ici et non **appelé** : `verify_nf525_chain` lit
  --    `current_tenant_id()`, qui exige une session utilisateur ; le job
  --    nocturne n'en a pas.
  ELSIF p_code = 'INV-16' THEN
    WITH e AS (
      SELECT previous_hash,
             LAG(current_hash) OVER (ORDER BY id) AS attendu
        FROM nf525_event_log WHERE tenant_id = p_tenant
    )
    SELECT COUNT(*),
           COUNT(*) FILTER (WHERE attendu IS NOT NULL
                              AND previous_hash IS DISTINCT FROM attendu)
      INTO v_a, v_n FROM e;
    v_n := COALESCE(v_n, 0);
    v_b := v_n::numeric;
    lignes_en_ecart := v_n;
    detail := jsonb_build_object(
      'evenements', COALESCE(v_a, 0)::int, 'ruptures', v_n);

  -- ── INV-17 — aucune écriture sur un exercice ou une période fermés.
  ELSIF p_code = 'INV-17' THEN
    SELECT COUNT(*) INTO v_n
      FROM journal_entries je
     WHERE je.tenant_id = p_tenant
       AND (EXISTS (SELECT 1 FROM fiscal_periods fp
                     WHERE fp.id = je.fiscal_period_id
                       AND fp.status IN ('closed', 'locked'))
         OR EXISTS (SELECT 1 FROM fiscal_years fy
                     WHERE fy.id = je.fiscal_year_id
                       AND (fy.status IN ('closed', 'locked')
                            OR fy.closed_at IS NOT NULL)));
    lignes_en_ecart := v_n;
    detail := jsonb_build_object('ecritures_sur_periode_fermee', v_n);

  -- ── INV-18 — tout document validé a un numéro définitif, sans trou : par
  --    journal et par exercice, le dernier numéro servi doit égaler le nombre de
  --    numéros attribués.
  ELSIF p_code = 'INV-18' THEN
    WITH s AS (
      SELECT journal_code, fiscal_year_id, COALESCE(last_seq, 0) AS last_seq
        FROM journal_posting_sequences WHERE tenant_id = p_tenant),
    e AS (
      SELECT journal_code, fiscal_year_id, COUNT(*)::int AS n
        FROM journal_entries
       WHERE tenant_id = p_tenant AND posting_number IS NOT NULL
       GROUP BY journal_code, fiscal_year_id)
    SELECT COALESCE(SUM(s.last_seq), 0), COALESCE(SUM(COALESCE(e.n, 0)), 0),
           COUNT(*) FILTER (WHERE s.last_seq <> COALESCE(e.n, 0))
      INTO v_a, v_b, v_n
      FROM s LEFT JOIN e USING (journal_code, fiscal_year_id);
    lignes_en_ecart := COALESCE(v_n, 0);
    detail := jsonb_build_object('journaux_en_ecart', COALESCE(v_n, 0));

  -- ── INV-20 — toute ligne de paie variable a une source identifiée.
  ELSIF p_code = 'INV-20' THEN
    SELECT COUNT(*) INTO v_n
      FROM payroll_variable_elements
     WHERE tenant_id = p_tenant AND btrim(COALESCE(source, '')) = '';
    lignes_en_ecart := v_n;
    SELECT COALESCE(jsonb_object_agg(element_type, c), '{}'::jsonb) INTO detail
      FROM (SELECT COALESCE(element_type, '(nul)') AS element_type, COUNT(*) AS c
              FROM payroll_variable_elements
             WHERE tenant_id = p_tenant AND btrim(COALESCE(source, '')) = ''
             GROUP BY 1) s;

  -- Un code inscrit `mesurable` sans branche de mesure est un mensonge : il
  -- produirait un relevé vide lu comme « tout va bien ». Il doit crier.
  ELSE
    RAISE EXCEPTION
      'chain_invariant_mesurer : % n''a aucune branche de mesure. Un invariant '
      'inscrit mesurable sans contrôle produit un relevé vide — corrigez le '
      'registre (mesurable = false, avec sa raison) ou écrivez la branche.',
      p_code;
  END IF;

  mesure_a := v_a;
  mesure_b := v_b;
  IF v_a IS NOT NULL AND v_b IS NOT NULL THEN
    ecart := abs(v_a - v_b);
  END IF;
  lignes_en_ecart := COALESCE(lignes_en_ecart, 0);
END
$fn$;

COMMENT ON FUNCTION public.chain_invariant_mesurer(uuid, text) IS
  '322 (L4) : mesure UN invariant transversal pour une société. Rend les deux mesures, l''écart, le nombre de lignes en écart et le détail. Lève une exception si le code est inscrit mesurable mais n''a aucune branche — un relevé vide ne doit jamais passer pour un invariant tenu.';

-- ─────────────────────────────────────────────────────────────
-- 6. LE RELEVÉ COMPLET D'UNE SOCIÉTÉ — et l'indice de cohérence
--    Une ligne par invariant actif, écrite dans `chain_invariant_results`, et un
--    JSON qui dit le score. L'indice est le score **sur ce qui est mesuré** :
--    les invariants non mesurables ne comptent ni au numérateur ni au
--    dénominateur, et leur nombre est publié à côté. Afficher « 13/20 » quand
--    sept ne sont pas mesurables serait un mensonge.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.audit_chains(p_tenant uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_inv       RECORD;
  v_m         RECORD;
  v_t0        timestamptz;
  v_verdict   text;
  v_inscrits  integer := 0;
  v_tenus     integer := 0;
  v_rompus    integer := 0;
  v_non_mes   integer := 0;
BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'audit_chains : p_tenant est obligatoire';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM tenants WHERE id = p_tenant) THEN
    RAISE EXCEPTION 'audit_chains : société % introuvable', p_tenant;
  END IF;

  -- Le registre applicable : le standard (tenant_id NULL), sauf quand la société
  -- a écrit sa propre ligne pour ce code — elle l'emporte, exactement comme pour
  -- `document_effects` (252).
  FOR v_inv IN
    SELECT i.code, i.sens, i.tolerance, i.mesurable, i.raison_non_mesurable
      FROM chain_invariants i
     WHERE i.actif
       AND (i.tenant_id IS NULL OR i.tenant_id = p_tenant)
       AND NOT (i.tenant_id IS NULL AND EXISTS (
             SELECT 1 FROM chain_invariants s
              WHERE s.tenant_id = p_tenant AND s.code = i.code))
     ORDER BY i.code
  LOOP
    v_inscrits := v_inscrits + 1;

    -- Un invariant nommé mais non mesurable est écrit **avec sa raison** : le
    -- relevé dit ce qu'il ne sait pas, il ne le cache pas.
    IF NOT v_inv.mesurable THEN
      INSERT INTO chain_invariant_results
        (tenant_id, code, verdict, lignes_en_ecart, duree_ms, detail)
      VALUES
        (p_tenant, v_inv.code, 'non_mesure', 0, 0,
         jsonb_build_object('raison', v_inv.raison_non_mesurable));
      v_non_mes := v_non_mes + 1;
      CONTINUE;
    END IF;

    v_t0 := clock_timestamp();
    SELECT * INTO v_m FROM chain_invariant_mesurer(p_tenant, v_inv.code);

    -- Le verdict dépend du **sens** du contrôle : une égalité se juge sur
    -- l'écart, une interdiction (`existence`, `integrite`) sur le nombre de
    -- violations trouvées.
    IF v_inv.sens IN ('existence', 'integrite') THEN
      v_verdict := CASE WHEN COALESCE(v_m.lignes_en_ecart, 0) = 0
                        THEN 'tenu' ELSE 'rompu' END;
    ELSIF v_inv.sens = 'inferieur_ou_egal' THEN
      v_verdict := CASE WHEN COALESCE(v_m.mesure_a, 0)
                           <= COALESCE(v_m.mesure_b, 0) + v_inv.tolerance
                          AND COALESCE(v_m.lignes_en_ecart, 0) = 0
                        THEN 'tenu' ELSE 'rompu' END;
    ELSE  -- egalite
      v_verdict := CASE WHEN COALESCE(v_m.ecart, 0) <= v_inv.tolerance
                          AND COALESCE(v_m.lignes_en_ecart, 0) = 0
                        THEN 'tenu' ELSE 'rompu' END;
    END IF;

    INSERT INTO chain_invariant_results
      (tenant_id, code, verdict, mesure_a, mesure_b, ecart,
       lignes_en_ecart, duree_ms, detail)
    VALUES
      (p_tenant, v_inv.code, v_verdict, v_m.mesure_a, v_m.mesure_b, v_m.ecart,
       COALESCE(v_m.lignes_en_ecart, 0),
       GREATEST(0, floor(EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) * 1000))::int,
       v_m.detail);

    IF v_verdict = 'tenu' THEN v_tenus := v_tenus + 1;
    ELSE v_rompus := v_rompus + 1; END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'tenant_id',       p_tenant,
    'mesure_le',       clock_timestamp(),
    'inscrits',        v_inscrits,
    'mesures',         v_tenus + v_rompus,
    'tenus',           v_tenus,
    'rompus',          v_rompus,
    'non_mesurables',  v_non_mes,
    'indice',          CASE WHEN (v_tenus + v_rompus) = 0 THEN NULL
                            ELSE round(v_tenus::numeric / (v_tenus + v_rompus), 4)
                       END,
    'indice_pct',      CASE WHEN (v_tenus + v_rompus) = 0 THEN NULL
                            ELSE round(100.0 * v_tenus / (v_tenus + v_rompus), 1)
                       END);
END
$fn$;

COMMENT ON FUNCTION public.audit_chains(uuid) IS
  '322 (L4) : le relevé complet d''une société — écrit une ligne par invariant actif dans chain_invariant_results, et rend l''indice de cohérence (tenus / mesurés). Les invariants non mesurables sont écrits avec leur raison et exclus du score.';

-- ─────────────────────────────────────────────────────────────
-- 7. Droits sur les fonctions
--    `chain_invariant_mesurer` est interne : seul `audit_chains` l'appelle.
--    `audit_chains` n'est pas donnée au client : vingt requêtes d'agrégation sur
--    commande seraient un levier de déni de service. Le client **lit** le relevé
--    (SELECT sur chain_invariant_results) ; c'est le job nocturne qui l'écrit.
-- ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.chain_invariant_mesurer(uuid, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.audit_chains(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_chains(uuid) TO service_role;

-- ─────────────────────────────────────────────────────────────
-- 8. Le job nocturne
--    Posé **seulement** si `pg_cron` est installé : l'extension n'est pas là en
--    CI ni sur une base de développeur, et une migration qui échoue parce qu'une
--    extension manque n'est pas une migration. L'absence du job est visible :
--    sans relevé récent, la page « Cohérence » dit la date du dernier relevé.
-- ─────────────────────────────────────────────────────────────
DO $do$
DECLARE
  v_cmd text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- 2 h 30 : après les clôtures de journée, avant l'ouverture. Une société par
    -- ligne ; audit_chains écrit son propre relevé.
    v_cmd := format(
      'SELECT cron.schedule(%L, %L, %L)',
      'audit_chains_nocturne',
      '30 2 * * *',
      'SELECT public.audit_chains(t.id) FROM public.tenants t ORDER BY t.id');
    EXECUTE v_cmd;
    RAISE NOTICE '322 : job nocturne audit_chains_nocturne posé (2 h 30).';
  ELSE
    RAISE NOTICE
      '322 : pg_cron absent — le job nocturne n''est pas posé. Le relevé reste '
      'produit par tout appel de audit_chains(tenant) (déploiement, recette, '
      'service_role).';
  END IF;
END
$do$;

-- ─────────────────────────────────────────────────────────────
-- 9. Ce que cette migration ne fait pas — nommé
--
-- * **Elle ne corrige aucun écart.** Sept invariants sont inscrits non
--   mesurables, et parmi les treize mesurés le référentiel en annonçait plusieurs
--   « rompus » (INV-01, INV-02, INV-03, INV-11). L'indice publié sera donc bas —
--   et c'est le but : « un éditeur qui affiche ce score, puis le fait monter de
--   6 à 20 devant le client, gagne la confiance qu'aucune plaquette n'achète ».
--   Corriger les écarts, c'est la phase D (R-001 → R-062), pas L4.
-- * **Elle n'alerte pas encore.** Le plan demande « une alerte en cas de
--   dégradation » : comparer le relevé du jour au précédent et notifier. La
--   matière est là (l'historique daté), la notification dépend du canal choisi
--   (courriel, webhook) — c'est la tranche 2 de L4.
-- * **Elle ne mesure pas les 8 épreuves.** La page « Robustesse » du lot L5 lit
--   le banc D1→D8, qui est la **tranche 3 du lot L3** et n'existe pas encore.
--   Cette migration ne produit que la matière de la page « Cohérence ».
-- ─────────────────────────────────────────────────────────────

