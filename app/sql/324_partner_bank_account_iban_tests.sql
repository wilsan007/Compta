-- ============================================================
-- 324_partner_bank_account_iban_tests.sql — A5 (ach-003)
--
-- Recette /qa du 29/09/2026. Un IBAN dont la clé de contrôle est fausse
-- s'enregistrait sans résistance : l'écran montrait « IBAN invalide » en rouge
-- et enregistrait quand même, et la base n'avait rien à dire. Le RIB partait
-- alors en virement.
--
-- Mesuré sur la base de recette à la 323, AVANT la 324 : T01 ❌ la fonction
-- `is_valid_iban` n'existe pas, T02/T04 ❌ le compte faux est **accepté**
-- (le déclencheur n'existe pas), T03/T05/T06 non-régressions.
-- Après la 324 : 6/6 verts.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '324', false);
DELETE FROM _audit_results WHERE file = '324';

-- T01 : la clé mod 97-10 (8 cas, dont les faux positifs à éviter)
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM (VALUES
    ('FR7630006000011234567890189',        true),   -- IBAN français
    ('FR76 3000 6000 0112 3456 7890 189',  true),   -- les espaces ne changent rien
    ('fr7630006000011234567890189',        true),   -- ni la casse
    ('BE68539007547034',                   true),   -- belge (IBAN court)
    ('DE89370400440532013000',             true),   -- allemand
    ('FR7630006000011234567890180',        false),  -- clé fausse : dernier chiffre
    ('FR76300060000112345678',             false),  -- trop court
    ('123456789',                          false)   -- pas un IBAN du tout
  ) AS v(valeur, attendu)
  WHERE is_valid_iban(v.valeur) IS DISTINCT FROM v.attendu;

  PERFORM _rec('T01', 'la clé mod 97-10 : 8 IBAN, dont 2 faux et 4 non-IBAN', n = 0,
    format('%s cas discordants (0 attendu)', n));
END $$;

-- T02 : un IBAN faux est refusé, avec un message nommé (le défaut mesuré)
DO $$
DECLARE t uuid; c uuid; refuse boolean := false; message text;
BEGIN
  t := _mk_tenant('T324-refus');
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client T324') RETURNING id INTO c;

  BEGIN
    INSERT INTO partner_bank_accounts (tenant_id, partner_type, partner_id, account_number)
    VALUES (t, 'customer', c, 'FR7630006000011234567890180');
  EXCEPTION WHEN check_violation THEN
    refuse := true; message := SQLERRM;
  END;

  PERFORM _rec('T02', 'un IBAN à clé fausse est refusé à l’écriture, message nommé',
    refuse AND message LIKE 'IBAN invalide%' AND position('IBAN invalide' in message) = 1,
    format('refusé=%s message=%s', refuse, COALESCE(left(message, 60), '—')));
END $$;

-- T03 : un IBAN valide passe (non-régression de ce qui marchait déjà)
DO $$
DECLARE t uuid; c uuid; n int;
BEGIN
  t := _mk_tenant('T324-ok');
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client T324') RETURNING id INTO c;
  INSERT INTO partner_bank_accounts (tenant_id, partner_type, partner_id, account_number, bank_name)
  VALUES (t, 'customer', c, 'FR7630006000011234567890189', 'Banque de France');
  INSERT INTO partner_bank_accounts (tenant_id, partner_type, partner_id, account_number)
  VALUES (t, 'customer', c, 'BE68539007547034');

  SELECT count(*) INTO n FROM partner_bank_accounts
  WHERE tenant_id = t AND account_number IN ('FR7630006000011234567890189', 'BE68539007547034');
  PERFORM _rec('T03', 'un IBAN valide est enregistré, en France comme à l’étranger', n = 2,
    format('%s/2 comptes enregistrés', n));
END $$;

-- T04 : un compte ordinaire n’est PAS un IBAN — il ne doit pas être bloqué
-- (la table n'a pas de colonne qui distingue les deux : bank code / sort code
--  / account key sont les champs d'un compte américain)
DO $$
DECLARE t uuid; s uuid; e uuid; refuse boolean := false; n int;
BEGIN
  t := _mk_tenant('T324-us');
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur T324') RETURNING id INTO s;
  BEGIN
    INSERT INTO partner_bank_accounts (tenant_id, partner_type, partner_id, account_number, bank_code, sort_code, account_key)
    VALUES (t, 'supplier', s, '123456789', '021000021', '011000015', '23');
  EXCEPTION WHEN check_violation THEN
    refuse := true;
  END;
  SELECT count(*) INTO n FROM partner_bank_accounts WHERE tenant_id = t;
  PERFORM _rec('T04', 'un numéro de compte ordinaire (avec bank code) n’est pas bloqué',
    NOT refuse AND n = 1, format('refusé=%s lignes=%s (1 attendue)', refuse, n));
END $$;

-- T05 : la forme décide — un IBAN écrit en bas de casse, avec espaces, passe
DO $$
DECLARE t uuid; c uuid; n int;
BEGIN
  t := _mk_tenant('T324-casse');
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client T324') RETURNING id INTO c;
  INSERT INTO partner_bank_accounts (tenant_id, partner_type, partner_id, account_number)
  VALUES (t, 'customer', c, 'fr76 3000 6000 0112 3456 7890 189');
  SELECT count(*) INTO n FROM partner_bank_accounts WHERE tenant_id = t;
  PERFORM _rec('T05', 'casse et espaces tolérés à l’écriture', n = 1, format('%s/1 (1 attendu)', n));
END $$;

-- T06 : la garde vaut aussi à la modification, pas seulement à la création
DO $$
DECLARE t uuid; c uuid; a uuid; refuse boolean := false; message text; apres text;
BEGIN
  t := _mk_tenant('T324-update');
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client T324') RETURNING id INTO c;
  INSERT INTO partner_bank_accounts (tenant_id, partner_type, partner_id, account_number)
  VALUES (t, 'customer', c, 'FR7630006000011234567890189') RETURNING id INTO a;

  BEGIN
    UPDATE partner_bank_accounts SET account_number = 'FR7630006000011234567890180' WHERE id = a;
  EXCEPTION WHEN check_violation THEN
    refuse := true; message := SQLERRM;
  END;
  SELECT account_number INTO apres FROM partner_bank_accounts WHERE id = a;

  PERFORM _rec('T06', 'modifier un IBAN valide en IBAN faux est refusé, l’ancien reste',
    refuse AND apres = 'FR7630006000011234567890189',
    format('refusé=%s account_number=%s', refuse, COALESCE(apres, '—')));
END $$;

SELECT _audit_assert('324');
