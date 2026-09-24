-- Registre des défauts prouvés et encore ouverts (AUD-A02).
--
-- Tant qu'un couple (fichier, identifiant) figure ici, son test PEUT échouer sans
-- casser la CI. Dès qu'il passe, `_audit_assert` fait échouer la CI : le commit du
-- correctif doit supprimer la ligne. Un test qui échoue sans figurer ici casse la CI.
-- Une ligne par défaut : on en supprime une sans toucher aux autres.
--
-- AUD-X01 : la clé est le couple (file, test_id), jamais le seul test_id. Treize
-- fichiers emploient les identifiants `T01`…`T07` ; indexer sur `test_id` seul
-- blanchirait le `T01` de tous les autres fichiers.
--
-- Plan : doc/audit/PLAN-CORRECTIF-AUDIT-2026-09-21.md

-- 178 — noyau de saisie (lot C)
-- 180 — ventes (lot E)
-- 181 — paie (lot F)
-- 182 — inscription (lot B)

-- 231 — temps passés (M-17)
INSERT INTO _audit_expected (file, test_id, reason) VALUES
  ('231', 'M-17-01', 'Les heures facturables n''atteignent aucune facture : create_billable_line_on_timesheet_stop ne crée qu''une notification. Manque de fonction, chiffré 0,5 j à la phase 3 du reste-à-faire.');

-- 245 — déclaration de TVA (M-10)
-- La base hors taxe de la CA3 est reconstituée depuis la TVA (montant ÷ taux).
-- Un chiffre d'affaires non taxé — exonéré, export, livraison
-- intracommunautaire — ne porte aucune TVA et n'entre donc dans aucune base.
INSERT INTO _audit_expected (file, test_id, reason) VALUES
  ('245', 'T08', 'Le chiffre d''affaires non taxé (exonéré, export, livraison intracommunautaire) n''entre pas dans le CA déclaré : la base est reconstituée depuis la TVA, et ces ventes n''en portent pas. Cases A2, E1 et E2 de la CA3. Correctif : tirer la base des comptes de produits par code de TVA — chantier à part, chiffré à la phase 3.');
