-- ============================================================
-- 324_partner_bank_account_iban.sql — A5 (ach-003)
--
-- L'écran affichait « IBAN invalide » en rouge… et laissait enregistrer. Le
-- signal n'était qu'un avertissement : un IBAN dont la clé de contrôle est
-- fausse partait en base, et de là dans les virements (SEPA, ordres de
-- paiement). Le correctif d'écran est dans `src/lib/iban.ts` ; cette migration
-- pose la **défense en profondeur** : la base refuse aussi, donc un appel
-- direct à l'API, un import ou un script ne peuvent pas écrire un faux IBAN.
--
-- Deux règles, et non une :
--   - la **forme** (`^[A-Z]{2}[0-9]{2}`) décide de ce qui est un IBAN : deux
--     lettres de pays puis deux chiffres ;
--   - la **clé** (mod 97-10, ISO 13616) décide de sa justesse.
-- Un numéro de compte ordinaire — les champs bank code / sort code / account
-- key d'un compte américain ne sont pas des IBAN, et la table n'a aucune colonne
-- qui les distingue — n'est pas un IBAN faux : il passe.
-- ============================================================

-- La clé mod 97-10 : les quatre premiers caractères passent à la fin, chaque
-- lettre devient son numéro (A = 10 … Z = 35), et le reste doit valoir 1
-- modulo 97. IMMUTABLE pour être utilisable dans une contrainte comme dans un
-- déclencheur ; la boucle chiffre par chiffre évite tout débordement numérique.
CREATE OR REPLACE FUNCTION public.is_valid_iban(p_value text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
STRICT
AS $function$
DECLARE
  v_clean text;
  v_block text;
  v_num   text := '';
  v_rest  numeric := 0;
  i       int;
BEGIN
  v_clean := upper(regexp_replace(p_value, '[^0-9A-Za-z]', '', 'g'));
  IF v_clean !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{1,30}$' THEN
    RETURN false;
  END IF;
  v_block := substr(v_clean, 5) || substr(v_clean, 1, 4);
  FOR i IN 1 .. length(v_block) LOOP
    IF substr(v_block, i, 1) ~ '[A-Z]' THEN
      v_num := v_num || (ascii(substr(v_block, i, 1)) - 55)::text;
    ELSE
      v_num := v_num || substr(v_block, i, 1);
    END IF;
  END LOOP;
  FOR i IN 1 .. length(v_num) LOOP
    v_rest := mod(v_rest * 10 + substr(v_num, i, 1)::numeric, 97);
  END LOOP;
  RETURN v_rest = 1;
END $function$;

COMMENT ON FUNCTION public.is_valid_iban(text) IS
  'Clé de contrôle mod 97-10 d''un IBAN (ISO 13616) : vrai si les chiffres de contrôle correspondent. IMMUTABLE.';

CREATE OR REPLACE FUNCTION public.partner_bank_account_iban_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
  v_clean text;
BEGIN
  v_clean := upper(regexp_replace(NEW.account_number, '[^0-9A-Za-z]', '', 'g'));
  IF v_clean ~ '^[A-Z]{2}[0-9]{2}' AND NOT public.is_valid_iban(NEW.account_number) THEN
    RAISE EXCEPTION 'IBAN invalide : la clé de contrôle de « % » ne correspond pas. Ce compte bancaire n''a pas été enregistré.', NEW.account_number
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS ta_partner_bank_account_iban ON public.partner_bank_accounts;
CREATE TRIGGER ta_partner_bank_account_iban
  BEFORE INSERT OR UPDATE OF account_number ON public.partner_bank_accounts
  FOR EACH ROW EXECUTE FUNCTION public.partner_bank_account_iban_guard();

COMMENT ON FUNCTION public.partner_bank_account_iban_guard() IS
  'A5 (ach-003) : refuse d''enregistrer un IBAN dont la clé de contrôle est fausse. Ne touche pas les numéros de compte qui ne sont pas des IBAN.';
