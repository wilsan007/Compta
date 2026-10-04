-- ============================================================
-- 351_chart_account_labels_accents_tests.sql — tâche 2.12 (F5, suite)
--
--   T01  le plan livré à une société neuve ne porte plus ni « a » isolé, ni
--        élision manquante (« d immobilisations »), ni mot sans son accent
--   T02  dix libellés relus sont exactement ceux de la liste validée, dont les
--        cas qui dépassent l'accent (« Hypothèques », « groupe A », « prêts »)
--   T03  le plan n'a perdu aucun compte et aucun libellé n'est vide
--   T04  plus aucun compte de la base ne porte un ancien libellé livré
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '351', false);
DELETE FROM _audit_results WHERE file = '351';

DO $$
DECLARE
  t uuid := _mk_tenant('P2F5L01', false);
  n_a int; n_elision int; n_mots int; v_ex text; v jsonb; n_total int; n_vides int; n_anciens int;
BEGIN
  SELECT count(*) FILTER (WHERE name ~ ' a '),
         count(*) FILTER (WHERE name ~ '(^| )[dl] [[:alpha:]]'),
         count(*) FILTER (WHERE name ~* '\m(accordees|accordes|activites|affectes|anterieurs|anticipes|appele|assimilees|assimiles|associes|aupres|benefice|benefices|cedes|clientele|collectee|collectivites|comites|conges|constatees|constates|copropriete|creances|credit|crediteur|crediteurs|credits|debiteur|debiteurs|dedommagements|deductible|deduire|deplacements|depots|depreciation|depreciations|detache|donnes|ecarts|echantillons|echus|electricite|elements|emis|encaisses|energie|equilibrage|equipements|etablir|etablissement|etablissements|etat|etranger|etrangeres|etudes|exterieur|exterieurs|financieres|generale|immobilisee|immobilises|impots|imprimes|integre|interet|interets|intermediaires|irrecouvrables|legale|liberalites|liees|marches|materiel|materiels|matieres|medecine|mobilieres|negociation|numeraire|operations|particulieres|payes|penales|penalites|periodique|premieres|presence|prevoyance|prevoyances|procedes|propriete|publicite|rattachees|rattaches|reception|receptions|recues|recuperables|recus|regies|reglementees|regularisation|regulariser|remuneration|remunerations|reparations|reparties|repartition|reserve|reserves|residuels|resultat|resultats|reunion|salaries|securite|siege|societe|societes|stockee|stockes|telecommunications|tres|tresor|tresorerie|verses)\M')
    INTO n_a, n_elision, n_mots
    FROM chart_accounts WHERE tenant_id = t;
  SELECT string_agg(code || ' ' || name, ' | ' ORDER BY code) INTO v_ex FROM (
    SELECT code, name FROM chart_accounts
     WHERE tenant_id = t AND (name ~ ' a ' OR name ~ '(^| )[dl] [[:alpha:]]' OR name ~* '\m(accordees|accordes|activites|affectes|anterieurs|anticipes|appele|assimilees|assimiles|associes|aupres|benefice|benefices|cedes|clientele|collectee|collectivites|comites|conges|constatees|constates|copropriete|creances|credit|crediteur|crediteurs|credits|debiteur|debiteurs|dedommagements|deductible|deduire|deplacements|depots|depreciation|depreciations|detache|donnes|ecarts|echantillons|echus|electricite|elements|emis|encaisses|energie|equilibrage|equipements|etablir|etablissement|etablissements|etat|etranger|etrangeres|etudes|exterieur|exterieurs|financieres|generale|immobilisee|immobilises|impots|imprimes|integre|interet|interets|intermediaires|irrecouvrables|legale|liberalites|liees|marches|materiel|materiels|matieres|medecine|mobilieres|negociation|numeraire|operations|particulieres|payes|penales|penalites|periodique|premieres|presence|prevoyance|prevoyances|procedes|propriete|publicite|rattachees|rattaches|reception|receptions|recues|recuperables|recus|regies|reglementees|regularisation|regulariser|remuneration|remunerations|reparations|reparties|repartition|reserve|reserves|residuels|resultat|resultats|reunion|salaries|securite|siege|societe|societes|stockee|stockes|telecommunications|tres|tresor|tresorerie|verses)\M')
     ORDER BY code LIMIT 3) s;
  PERFORM _rec('T01', 'le plan livré à une société neuve porte ses accents et ses apostrophes : aucun « a » isolé, aucune élision manquante, aucun mot sans accent',
    n_a = 0 AND n_elision = 0 AND n_mots = 0,
    format('« a » isolé=%s, élision manquante=%s, mot sans accent=%s%s', n_a, n_elision, n_mots,
      COALESCE(' — ' || left(v_ex, 150), '')));

  SELECT jsonb_object_agg(code, name) INTO v FROM chart_accounts
   WHERE tenant_id = t AND code IN ('601000', '404000', '518000', '110000', '440000', '606120', '801700', '355000', '762600', '445560');
  PERFORM _rec('T02', 'dix libellés relus sont ceux de la liste validée (accents, apostrophes, « à », majuscule accentuée, fautes de frappe, « groupe »)',
    v->>'601000' = 'Achats de matières premières' AND v->>'404000' = 'Fournisseurs d''immobilisations'
      AND v->>'518000' = 'Intérêts courus à payer' AND v->>'110000' = 'Report à nouveau (solde créditeur)'
      AND v->>'440000' = 'État et autres collectivités publiques' AND v->>'606120' = 'Énergie (gaz, électricité)'
      AND v->>'801700' = 'Hypothèques' AND v->>'355000' = 'Produits finis (groupe A)'
      AND v->>'762600' = 'Revenus des prêts' AND v->>'445560' = 'TVA déductible (autres biens et services)',
    format('601000=%s | 404000=%s | 518000=%s | 801700=%s | 355000=%s', v->>'601000', v->>'404000', v->>'518000', v->>'801700', v->>'355000'));

  SELECT count(*), count(*) FILTER (WHERE btrim(COALESCE(name, '')) = '') INTO n_total, n_vides
    FROM chart_accounts WHERE tenant_id = t;
  PERFORM _rec('T03', 'le plan livré n''a perdu aucun compte (701 de la fonction, plus les comptes de TVA) et aucun libellé n''est vide',
    n_total >= 701 AND n_vides = 0, format('comptes=%s, libellés vides=%s', n_total, n_vides));

  SELECT count(*) INTO n_anciens FROM chart_accounts
   WHERE (code, name) IN (('601000', 'Achats de matieres premieres'), ('404000', 'Fournisseurs d immobilisations'),
     ('518000', 'Interets courus a payer'), ('110000', 'Report a nouveau (solde crediteur)'),
     ('440000', 'Etat et autres collectivites publiques'), ('606120', 'Energie (gaz, electricite)'),
     ('801700', 'Hypotèques'), ('355000', 'Produits finis (group A)'), ('762600', 'Revenus des pretes'),
     ('445560', 'TVA a dedeductible (autres biens et services)'), ('108000', 'Compte de l exploitant'),
     ('681000', 'Dotations aux amortissements et aux provisions - charges d exploitation'));
  PERFORM _rec('T04', 'plus aucun compte de la base ne porte un ancien libellé livré (douze témoins)',
    n_anciens = 0, format('comptes encore à l''ancien libellé=%s', n_anciens));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'T01 à T04 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

SELECT _audit_assert('351');
