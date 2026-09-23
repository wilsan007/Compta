-- Registre des défauts prouvés et encore ouverts (AUD-A02).
--
-- Tant qu'un identifiant figure ici, son test PEUT échouer sans casser la CI.
-- Dès qu'il passe, `_audit_assert` fait échouer la CI : le commit du correctif
-- doit supprimer la ligne. Un test qui échoue sans figurer ici casse la CI.
-- Une ligne par défaut : on en supprime une sans toucher aux autres.
--
-- Plan : doc/audit/PLAN-CORRECTIF-AUDIT-2026-09-21.md

-- 178 — noyau de saisie (lot C)
-- 180 — ventes (lot E)
-- 181 — paie (lot F)
-- 182 — inscription (lot B)

-- 231 — temps passés (M-17)
INSERT INTO _audit_expected (test_id, reason) VALUES
  ('M-17-01', 'Les heures facturables n''atteignent aucune facture : create_billable_line_on_timesheet_stop ne crée qu''une notification. Manque de fonction, chiffré 0,5 j à la phase 3 du reste-à-faire.');
