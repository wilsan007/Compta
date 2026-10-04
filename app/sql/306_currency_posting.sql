-- ============================================================
-- 306_currency_posting.sql — W7 (M-01) : le taux de change est appliqué
--
-- Deux défauts prouvés par `306_currency_posting_tests.sql`, vus **rouges avant** :
--
--   M01-01 🔴 Une facture en devise était comptabilisée **au montant en devise**
--             (1 000 USD au taux 0,90 → écriture de 1 000 EUR ; achat de 500 USD
--             → charge de 500 EUR au lieu de 450). `invoices.exchange_rate`
--             n'était lu par personne, sinon par les gardes qui interdisent de
--             le modifier après validation.
--   M01-02 🔴 `journal_lines` n'avait **aucune** colonne de devise, de montant
--             en devise ni de taux : la ligne ne pouvait pas conserver le
--             montant d'origine, et le FEC (`Montantdevise` / `Idevise`) ne
--             pouvait pas être rempli.
--
-- CE QUI EST POSÉ.
--   1. `journal_lines` reçoit `currency_code`, `currency_amount` (montant en
--      devise, **signé** : positif au débit, négatif au crédit) et
--      `exchange_rate`.
--   2. **Un seul moteur** convertit : `apply_currency_on_journal_line`, un
--      déclencheur `BEFORE INSERT` sur `journal_lines`. Il retrouve le document
--      par `journal_entries.invoice_ref` (facture de vente, facture d'achat,
--      avoir), pose la devise et le taux sur l'écriture, garde le montant
--      d'origine sur la ligne, et convertit `debit`/`credit` dans la devise de
--      tenue. Toutes les écritures engendrées en bénéficient — ventes, achats,
--      avoirs — sans toucher aux fonctions de comptabilisation.
--   3. Une devise **sans taux** est **refusée** : le défaut venait du taux par
--      défaut à 1, qui transformait 1 000 USD en 1 000 EUR en silence.
--   4. L'arrondi de conversion est **absorbé** (`aa_currency_rounding`) : trois
--      lignes de 100,00 USD au taux 0,333333 donnent 33,33 chacune, soit un
--      centime de moins que la contrepartie (100,00) — l'écriture serait refusée
--      par le noyau. Le centime est porté par la ligne la plus forte, du côté du
--      résidu, à la validation de l'écriture.
--
-- LES LIMITES, DITES.
--   • L'**écart de change au règlement** (666/766) et la **réévaluation de
--     clôture** (`currency_revaluations`) restent à faire : c'est le troisième
--     défaut de M01, `M01-03`, traité séparément. Cette migration pose ce sans
--     quoi il ne peut pas exister : le montant en devise sur chaque ligne.
--   • L'écran de facture n'offre pas encore le choix de la devise : le modèle,
--     l'écriture, le FEC et l'API le portent (`currency_code` + `exchange_rate`) ;
--     un lot d'interface reste à faire.
--   • La conversion s'applique aux documents rattachés par `invoice_ref` ; une
--     écriture saisie à la main dans une devise pose sa devise elle-même
--     (`post_journal_entry` accepte déjà les lignes avec leur devise).
-- ============================================================

ALTER TABLE public.journal_lines ADD COLUMN IF NOT EXISTS currency_code text;
ALTER TABLE public.journal_lines ADD COLUMN IF NOT EXISTS currency_amount numeric(14,2);
ALTER TABLE public.journal_lines ADD COLUMN IF NOT EXISTS exchange_rate numeric(12,6);

COMMENT ON COLUMN public.journal_lines.currency_amount IS
  'Montant de la ligne dans la devise du document, signé (positif au débit, négatif au crédit). 306 (W7).';
COMMENT ON COLUMN public.journal_lines.exchange_rate IS
  'Taux appliqué pour convertir la ligne dans la devise de tenue (1 quand la devise est celle de la société). 306 (W7).';

-- Devise de tenue d'une société
CREATE OR REPLACE FUNCTION public.functional_currency(p_tenant uuid)
RETURNS text
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT COALESCE(NULLIF(cs.currency, ''), 'EUR')
  FROM public.company_settings cs
  WHERE cs.tenant_id = p_tenant
  LIMIT 1
$$;

REVOKE EXECUTE ON FUNCTION public.functional_currency(uuid) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- 2. Une seule conversion : la ligne d'écriture d'un document en devise
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_currency_on_journal_line()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_ref text;
  v_reference text;
  v_fonc text;
  v_dev text;
  v_taux numeric;
BEGIN
  -- Une ligne qui porte déjà sa devise (saisie manuelle, import) est respectée.
  IF NEW.currency_code IS NOT NULL THEN RETURN NEW; END IF;

  SELECT e.invoice_ref, e.reference, e.functional_currency
    INTO v_ref, v_reference, v_fonc
  FROM public.journal_entries e
  WHERE e.id = NEW.journal_id AND e.tenant_id = NEW.tenant_id;

  -- Sans document d'origine, il n'y a rien à convertir.
  IF COALESCE(v_ref, v_reference) IS NULL THEN RETURN NEW; END IF;

  -- Devise et taux de la pièce : vente, puis achat, puis avoir.
  SELECT i.currency_code, i.exchange_rate INTO v_dev, v_taux
  FROM public.invoices i
  WHERE i.tenant_id = NEW.tenant_id AND i.number IN (v_ref, v_reference)
  LIMIT 1;

  IF v_dev IS NULL THEN
    SELECT pi.currency_code, pi.exchange_rate INTO v_dev, v_taux
    FROM public.purchase_invoices pi
    WHERE pi.tenant_id = NEW.tenant_id AND pi.number IN (v_ref, v_reference)
    LIMIT 1;
  END IF;

  IF v_dev IS NULL THEN
    SELECT cn.currency_code, 1 INTO v_dev, v_taux
    FROM public.credit_notes cn
    WHERE cn.tenant_id = NEW.tenant_id AND cn.number IN (v_ref, v_reference)
    LIMIT 1;
  END IF;

  IF v_dev IS NULL THEN RETURN NEW; END IF;

  v_fonc := COALESCE(v_fonc, public.functional_currency(NEW.tenant_id));
  v_taux := COALESCE(v_taux, 1);

  -- L'écriture porte sa devise et son taux — **la pièce fait foi** (le défaut de
  -- `currency_code` par défaut, posé par une autre migration à la devise de la
  -- société, ne doit pas cacher une facture en devise). C'est ce que lit le FEC
  -- pour `Montantdevise` / `Idevise`.
  UPDATE public.journal_entries
  SET currency_code = v_dev,
      functional_currency = COALESCE(functional_currency, v_fonc),
      exchange_rate = v_taux
  WHERE id = NEW.journal_id AND tenant_id = NEW.tenant_id;

  NEW.currency_code := v_dev;
  NEW.exchange_rate := v_taux;

  IF v_dev <> v_fonc THEN
    -- Un taux absent n'est pas un taux de 1 : on refuse plutôt que de fausser
    -- le chiffre d'affaires, le client et la TVA de tout l'écart de change.
    IF COALESCE(v_taux, 0) <= 0 THEN
      RAISE EXCEPTION 'Pièce en % sans taux de change : renseignez le taux avant de comptabiliser', v_dev
        USING ERRCODE = '22023';
    END IF;
    -- Montant d'origine conservé (signé), montant de tenue converti.
    NEW.currency_amount := CASE WHEN NEW.debit <> 0 THEN NEW.debit ELSE -NEW.credit END;
    NEW.debit  := round(NEW.debit * v_taux, 2);
    NEW.credit := round(NEW.credit * v_taux, 2);
  ELSE
    NEW.currency_amount := CASE WHEN NEW.debit <> 0 THEN NEW.debit ELSE -NEW.credit END;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.apply_currency_on_journal_line() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS apply_currency_on_journal_line ON public.journal_lines;
CREATE TRIGGER apply_currency_on_journal_line
  BEFORE INSERT
  ON public.journal_lines
  FOR EACH ROW
  EXECUTE FUNCTION public.apply_currency_on_journal_line();


-- ------------------------------------------------------------
-- 3. L'arrondi de conversion n'est pas une écriture déséquilibrée
--    (`aa_` : tiré avant le contrôle d'équilibre du noyau,
--     `check_journal_entry_balance_on_post`)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.absorb_currency_rounding()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_res numeric;
  v_id uuid;
BEGIN
  IF NOT (NEW.status = 'posted' AND OLD.status IS DISTINCT FROM 'posted') THEN RETURN NEW; END IF;
  IF NEW.currency_code IS NULL
     OR NEW.currency_code = COALESCE(NEW.functional_currency, NEW.currency_code) THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(sum(debit), 0) - COALESCE(sum(credit), 0) INTO v_res
  FROM public.journal_lines
  WHERE journal_id = NEW.id AND tenant_id = NEW.tenant_id;

  -- Un vrai déséquilibre n'est pas un arrondi : le noyau le refusera, et il a raison.
  IF v_res = 0 OR abs(v_res) > 0.05 THEN RETURN NEW; END IF;

  -- Le centime est porté par la ligne la plus forte, **du côté du résidu** :
  -- chaque ligne reste un débit ou un crédit pur, le montant en devise est intact.
  SELECT id INTO v_id FROM public.journal_lines
  WHERE journal_id = NEW.id AND tenant_id = NEW.tenant_id
    AND (CASE WHEN v_res > 0 THEN debit ELSE credit END) > 0
  ORDER BY (CASE WHEN v_res > 0 THEN debit ELSE credit END) DESC, line_order, id
  LIMIT 1;

  IF v_id IS NULL THEN RETURN NEW; END IF;

  IF v_res > 0 THEN
    UPDATE public.journal_lines SET debit = debit - v_res WHERE id = v_id AND tenant_id = NEW.tenant_id;
  ELSE
    UPDATE public.journal_lines SET credit = credit + v_res WHERE id = v_id AND tenant_id = NEW.tenant_id;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.absorb_currency_rounding() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS aa_currency_rounding ON public.journal_entries;
CREATE TRIGGER aa_currency_rounding
  BEFORE UPDATE OF status
  ON public.journal_entries
  FOR EACH ROW
  EXECUTE FUNCTION public.absorb_currency_rounding();

