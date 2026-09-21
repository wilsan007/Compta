-- Registre des défauts prouvés et encore ouverts (AUD-A02).
--
-- Tant qu'un identifiant figure ici, son test PEUT échouer sans casser la CI.
-- Dès qu'il passe, `_audit_assert` fait échouer la CI : le commit du correctif
-- doit supprimer la ligne. Un test qui échoue sans figurer ici casse la CI.
-- Une ligne par défaut : on en supprime une sans toucher aux autres.
--
-- Plan : doc/audit/PLAN-CORRECTIF-AUDIT-2026-09-21.md

-- 178 — noyau de saisie (lot C)
-- 179 — clôture et états financiers (lot D)
INSERT INTO _audit_expected VALUES ('D01', 'AUD-D03 clôture écrit dans une période qu''elle exige close');
INSERT INTO _audit_expected VALUES ('D02', 'AUD-D01 résultat = produits + charges');
INSERT INTO _audit_expected VALUES ('D03', 'AUD-D02 classes 6/7 non soldées');
INSERT INTO _audit_expected VALUES ('D04', 'AUD-D04 résultat exclu des à-nouveaux');
INSERT INTO _audit_expected VALUES ('D06', 'AUD-D05/D06 double comptage et clôture à résultat nul');
INSERT INTO _audit_expected VALUES ('D07', 'AUD-D01/D02 écriture de clôture déséquilibrée');
INSERT INTO _audit_expected VALUES ('D08', 'AUD-D05/D08 états après clôture : double comptage des à-nouveaux');
INSERT INTO _audit_expected VALUES ('R04', 'AUD-D08 bilan sans résultat, comptes hors plan écartés');
-- 180 — ventes (lot E)
INSERT INTO _audit_expected VALUES ('E04', 'AUD-E05 facture issue d''un devis sans vat_amount');
INSERT INTO _audit_expected VALUES ('E06', 'AUD-E07 avoir client sans écriture');
INSERT INTO _audit_expected VALUES ('E08', 'AUD-E08 trop-perçu accepté sans avance client');
-- 181 — paie (lot F)
INSERT INTO _audit_expected VALUES ('P01', 'AUD-F02 écriture de paie déséquilibrée (AUD-F01 corrigé par AUD-C10)');
INSERT INTO _audit_expected VALUES ('P02', 'AUD-F02 cotisations salariales absentes, journal NULL');
-- 182 — inscription (lot B)
