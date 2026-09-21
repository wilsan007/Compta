-- ============================================================
-- ci/ledger_fixture.sql — société de test comptablement utilisable
--
-- Depuis la 187 (lot C du plan correctif), une écriture exige un journal
-- existant, un exercice couvrant sa date et des comptes présents au plan de
-- la société. Une société réelle reçoit tout cela à l'inscription
-- (bootstrap_tenant) ; les suites qui créent leur société à la main
-- appellent _ledger_fixture juste après l'avoir créée.
--
-- L'exercice va du 01/01/2026 à la fin de l'année courante : plusieurs
-- scénarios datent leurs pièces de CURRENT_DATE.
-- ============================================================
CREATE OR REPLACE FUNCTION _ledger_fixture(p_tenant uuid, p_extra_accounts text[] DEFAULT '{}')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM seed_standard_chart_unchecked(p_tenant);
  PERFORM ensure_standard_journals(p_tenant);
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status)
  VALUES (p_tenant, 'TEST', DATE '2026-01-01',
          make_date(GREATEST(2026, extract(year FROM CURRENT_DATE)::int), 12, 31), 'open');
  -- Comptes propres au scénario (sous-comptes clients, etc.)
  INSERT INTO chart_accounts (tenant_id, code, name, type)
  SELECT p_tenant, c, 'Compte de test ' || c,
         CASE WHEN c ~ '^6' THEN 'expense' WHEN c ~ '^7' THEN 'income' WHEN c ~ '^1' THEN 'equity'
              WHEN c ~ '^40' THEN 'liability' ELSE 'asset' END
  FROM unnest(p_extra_accounts) c
  ON CONFLICT (tenant_id, code) DO NOTHING;
END $$;
