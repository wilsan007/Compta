-- ============================================================
-- 219_pos_vat_cash.sql — R-13 : la TVA de la caisse se ventile par TAUX, et
-- l'écart de caisse se comptabilise
--
-- Deux défauts mesurés dans post_pos_session_on_close_multi :
--
-- 1. TVA mono-compte. La clôture créditait UNE ligne dure « 445710 » avec
--    SUM(pos_tickets.vat_total), alors que pos_ticket_lines.vat_rate porte le
--    taux de chaque ligne : une session mêlant 20 % et 10 % déclarait tout en
--    20 %, et la CA3 était fausse. Le correctif ventile par taux par
--    vat_account_mapping (direction « collected », ligne de la société puis
--    ligne partagée 00000000-…), avec repli 445710. Aucun compte nouveau n'est
--    écrit en dur : 445710 est déjà exigé du plan (chart_required_accounts,
--    201), et c'est la seule façon de rester neutre pour les packs pays (LOC1).
--    Le total crédité reste Σ(pos_tickets.vat_total) — le ticket fait foi ;
--    l'écart d'arrondi de la ventilation est absorbé par le taux le plus élevé.
--
-- 2. Écart de caisse jamais comptabilisé. Les colonnes opening_amount,
--    closing_amount, expected_amount et difference existent depuis la 54, mais
--    elles étaient remplies par l'écran et rien n'en passait en comptabilité.
--    Pire, l'attendu de l'écran additionnait TOUS les tickets sans regarder le
--    moyen de paiement (posAdvanced.ts:70-74) : dès qu'un ticket était réglé par
--    carte, l'attendu était faux. Ici le serveur recalcule l'attendu sur les
--    ESPÈCES seules — le reste dû par carte ne se compte pas dans le tiroir —,
--    l'écrit sur la session, et comptabilise l'écart : manquant D 658000 /
--    C compte de caisse, excédent D compte de caisse / C 758000. Les deux
--    comptes (658000, 758000) appartiennent au plan semé à l'inscription, ce que
--    vérifie déjà G10 (192).
--
-- Le reste de la fonction est repris tel quel de la 194 (sorties de stock par
-- dépôt de la caisse, une seule décrémentation) : cette migration ne touche ni
-- au stock, ni à la chaîne NF525, ni aux moyens de paiement.
--
-- Le trigger passe de AFTER à BEFORE UPDATE : l'attendu et l'écart de caisse
-- sont ainsi écrits dans la ligne avant son enregistrement, et l'appelant (l'écran
-- de clôture) lit l'écart du serveur, pas celui qu'il avait proposé.
--
-- Preuve : sql/219_pos_vat_cash_tests.sql (G13a à G13d), vu rouge avant.
-- ============================================================

-- Compte de TVA collectée d'un taux de caisse.
--
-- Trois niveaux, dans cet ordre :
--   1. la correspondance canonique du taux (vat_code_for_rate) — société puis
--      ligne partagée : 20 % → FR20 → 445711, 10 % → FR10 → 445712… ;
--   2. à défaut, n'importe quelle ligne de ce taux, les codes de régime
--      particulier (AUTOLIQ, UE, EXO — sortis des comptes de taux par la 197)
--      passant en dernier : une vente au comptoir n'est pas une autoliquidation,
--      même si elle porte le même taux de 20 % ;
--   3. à défaut, le repli 445710, compte toujours présent au plan
--      (chart_required_accounts, 201).
--
-- L'appariement par le seul code TVA est volontairement écarté : vat_code_for_rate
-- retombe sur « FR20 » pour un taux non répertorié, ce qui enverrait une TVA à
-- 7,7 % sur le compte de 20 %. Un taux inconnu n'a pas de compte dédié : il va
-- au repli, où il reste visible et corrigeable.
CREATE OR REPLACE FUNCTION pos_vat_account(p_tenant uuid, p_rate numeric)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    -- 1. la correspondance canonique du taux
    (SELECT m.account_code FROM vat_account_mapping m
      WHERE m.tenant_id IN (p_tenant, '00000000-0000-0000-0000-000000000000')
        AND m.direction = 'collected'
        AND m.rate = p_rate AND m.vat_code = vat_code_for_rate(p_rate)
      ORDER BY (m.tenant_id <> '00000000-0000-0000-0000-000000000000') DESC
      LIMIT 1),
    -- 2. un autre code du même taux, les régimes particuliers en dernier
    (SELECT m.account_code FROM vat_account_mapping m
      WHERE m.tenant_id IN (p_tenant, '00000000-0000-0000-0000-000000000000')
        AND m.direction = 'collected'
        AND m.rate = p_rate
      ORDER BY (m.tenant_id <> '00000000-0000-0000-0000-000000000000') DESC,
               (m.vat_code IN ('AUTOLIQ', 'UE', 'EXO')) ASC,
               m.vat_code
      LIMIT 1),
    -- 3. le repli
    '445710')
$$;
REVOKE ALL ON FUNCTION pos_vat_account(uuid, numeric) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION pos_vat_account(uuid, numeric) IS
  'Compte de TVA collectée d''un taux de caisse : correspondance canonique du taux, '
  'puis autre code du même taux (régimes particuliers en dernier), puis repli 445710 '
  '(R-13, 219).';

CREATE OR REPLACE FUNCTION public.post_pos_session_on_close_multi()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := NEW.tenant_id;
  v_je_id uuid;
  v_line_num int := 1;
  v_total_sales numeric := 0;
  v_total_vat numeric := 0;
  v_ticket record;
  v_payment record;
  v_method_amount numeric;
  v_product record;
  v_je_number text;
  v_session_ref text;
  v_close_date date := COALESCE(NEW.closed_at, NOW())::date;
  -- 219 : ventilation de la TVA par taux, et écart de caisse
  v_rate record;
  v_line_vat numeric;
  v_rest numeric;
  v_acc text;
  v_cash_expected numeric := 0;
  v_cash_account text;
  v_diff numeric := 0;
BEGIN
  IF NEW.status <> 'closed' OR OLD.status = 'closed' THEN
    RETURN NEW;
  END IF;

  -- LOT2-13 : utiliser NEW.id::text comme fallback
  v_session_ref := COALESCE(NEW.session_number, NEW.id::text);

  -- Calculer le total des ventes et TVA
  SELECT COALESCE(SUM(subtotal), 0), COALESCE(SUM(vat_total), 0)
  INTO v_total_sales, v_total_vat
  FROM pos_tickets
  WHERE session_id = NEW.id AND tenant_id = v_tid AND status = 'completed';

  IF v_total_sales = 0 THEN
    RETURN NEW;
  END IF;

  v_je_number := 'POS-' || NEW.id;

  -- LOT2-12 : utiliser v_close_date au lieu de CURRENT_DATE
  INSERT INTO journal_entries (
    tenant_id, journal_code, number, date, description, status, created_at
  ) VALUES (
    v_tid, 'POS', v_je_number, v_close_date,
    'Clôture caisse session ' || v_session_ref, 'draft', now()
  )
  RETURNING id INTO v_je_id;

  -- Une ligne de débit par moyen de paiement
  FOR v_payment IN
    SELECT ppm.account_code, SUM(pp.amount) AS total
    FROM pos_payments pp
    JOIN pos_payment_methods ppm ON ppm.id = pp.payment_method_id AND ppm.tenant_id = v_tid
    JOIN pos_tickets pt ON pt.id = pp.ticket_id AND pt.tenant_id = v_tid
    WHERE pt.session_id = NEW.id AND pt.status = 'completed' AND pp.tenant_id = v_tid
    GROUP BY ppm.account_code
  LOOP
    INSERT INTO journal_lines (
      tenant_id, journal_id, line_order, account_code,
      debit, credit, created_at
    ) VALUES (
      v_tid, v_je_id, v_line_num, v_payment.account_code,
      v_payment.total, 0, now()
    );
    v_line_num := v_line_num + 1;
  END LOOP;

  -- Crédit des ventes (707000)
  INSERT INTO journal_lines (
    tenant_id, journal_id, line_order, account_code,
    debit, credit, created_at
  ) VALUES (
    v_tid, v_je_id, v_line_num, '707000', 0, v_total_sales, now()
  );
  v_line_num := v_line_num + 1;

  -- R-13 : la TVA se ventile par TAUX (un compte par taux du plan), au lieu
  -- d'une seule ligne 445710 pour toute la session.
  IF v_total_vat > 0 THEN
    v_rest := v_total_vat;
    FOR v_rate IN
      SELECT l.vat_rate AS rate,
             round(sum(l.line_total * l.vat_rate / 100), 2) AS tva
      FROM pos_ticket_lines l
      JOIN pos_tickets pt ON pt.id = l.ticket_id AND pt.tenant_id = l.tenant_id
      WHERE pt.session_id = NEW.id AND pt.status = 'completed' AND pt.tenant_id = v_tid
        AND COALESCE(l.vat_rate, 0) > 0
      GROUP BY 1
      ORDER BY 1 DESC   -- le taux le plus élevé absorbe l'écart d'arrondi
    LOOP
      -- Le ticket fait foi : la ventilation ne peut pas dépasser son total
      v_line_vat := LEAST(COALESCE(v_rate.tva, 0), v_rest);
      IF v_line_vat > 0 THEN
        v_acc := pos_vat_account(v_tid, v_rate.rate);
        INSERT INTO journal_lines (
          tenant_id, journal_id, line_order, account_code, debit, credit, created_at, description
        ) VALUES (
          v_tid, v_je_id, v_line_num, v_acc, 0, v_line_vat, now(),
          'TVA collectée ' || v_rate.rate || ' % — ' || v_session_ref
        );
        v_line_num := v_line_num + 1;
        v_rest := v_rest - v_line_vat;
      END IF;
    END LOOP;

    -- Lignes sans taux exploitable : le reste va au compte de repli, qui
    -- appartient au plan exigé (chart_required_accounts, 201).
    IF v_rest > 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, line_order, account_code, debit, credit, created_at, description
      ) VALUES (
        v_tid, v_je_id, v_line_num, '445710', 0, v_rest, now(),
        'TVA collectée — ' || v_session_ref
      );
      v_line_num := v_line_num + 1;
    END IF;
  END IF;

  -- R-13 : l'écart de caisse. Le comptage porte sur les ESPÈCES — le reste dû
  -- par carte ou chèque ne se compte pas dans le tiroir. L'attendu est recalculé
  -- ici, sur les paiements espèces seuls, puis écrit sur la session : le serveur
  -- fait foi, l'écran ne le calcule plus.
  SELECT COALESCE(sum(pp.amount), 0), min(ppm.account_code)
    INTO v_cash_expected, v_cash_account
  FROM pos_payments pp
  JOIN pos_payment_methods ppm ON ppm.id = pp.payment_method_id AND ppm.tenant_id = v_tid
  JOIN pos_tickets pt ON pt.id = pp.ticket_id AND pt.tenant_id = v_tid
  WHERE pt.session_id = NEW.id AND pt.status = 'completed' AND pp.tenant_id = v_tid
    AND ppm.type = 'cash';

  v_diff := COALESCE(NEW.closing_amount, 0)
            - (COALESCE(NEW.opening_amount, 0) + v_cash_expected);

  -- Le serveur fait foi : l'attendu et l'écart sont écrits sur la ligne AVANT
  -- qu'elle ne soit enregistrée (trigger BEFORE), pour que l'appelant — l'écran —
  -- lise l'écart calculé par le serveur et non celui qu'il a proposé.
  NEW.expected_amount := COALESCE(NEW.opening_amount, 0) + v_cash_expected;
  NEW.difference := v_diff;

  -- Manquant : la caisse a moins que l'attendu → charge 658. Excédent : produit
  -- 758. Le compte de caisse est celui du moyen de paiement espèces (jamais un
  -- compte en dur) ; si la session en utilise plusieurs, l'écart va au premier
  -- par ordre de compte — un tiroir physique, un compte.
  IF v_diff <> 0 AND v_cash_account IS NOT NULL THEN
    IF v_diff < 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, line_order, account_code, debit, credit, created_at, description
      ) VALUES
        (v_tid, v_je_id, v_line_num, '658000', -v_diff, 0, now(),
         'Écart de caisse — manquant ' || v_session_ref),
        (v_tid, v_je_id, v_line_num + 1, v_cash_account, 0, -v_diff, now(),
         'Écart de caisse — manquant ' || v_session_ref);
    ELSE
      INSERT INTO journal_lines (
        tenant_id, journal_id, line_order, account_code, debit, credit, created_at, description
      ) VALUES
        (v_tid, v_je_id, v_line_num, v_cash_account, v_diff, 0, now(),
         'Écart de caisse — excédent ' || v_session_ref),
        (v_tid, v_je_id, v_line_num + 1, '758000', 0, v_diff, now(),
         'Écart de caisse — excédent ' || v_session_ref);
    END IF;
    v_line_num := v_line_num + 2;
  END IF;

  -- Poster l'écriture
  UPDATE journal_entries SET status = 'posted' WHERE id = v_je_id;

  -- Sorties de stock : un mouvement par article et par dépôt de la caisse.
  -- update_stock_on_movement décrémente le stock de CE dépôt et valorise la sortie
  -- (couches FIFO, écriture ST) : aucune autre décrémentation ici.
  FOR v_product IN
    SELECT ptl.product_id, SUM(ptl.quantity) AS total_qty, pt2.warehouse_id
    FROM pos_ticket_lines ptl
    JOIN pos_tickets pt ON pt.id = ptl.ticket_id AND pt.tenant_id = ptl.tenant_id
    JOIN pos_sessions ps ON ps.id = pt.session_id AND ps.tenant_id = pt.tenant_id
    JOIN pos_terminals pt2 ON pt2.id = ps.terminal_id AND pt2.tenant_id = ps.tenant_id
    WHERE pt.session_id = NEW.id AND pt.status = 'completed' AND ptl.tenant_id = v_tid
      AND ptl.product_id IS NOT NULL
    GROUP BY ptl.product_id, pt2.warehouse_id
  LOOP
    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type, type,
      quantity, reference, reference_type, reference_id,
      date, movement_date, created_at
    ) VALUES (
      v_tid, v_product.product_id, v_product.warehouse_id, 'out', 'out',
      v_product.total_qty,
      'POS-' || v_session_ref, 'pos_session', NEW.id,
      v_close_date, v_close_date, now()
    );
  END LOOP;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS post_pos_session_on_close_multi_trigger ON pos_sessions;
CREATE TRIGGER post_pos_session_on_close_multi_trigger
  BEFORE UPDATE ON pos_sessions
  FOR EACH ROW
  EXECUTE FUNCTION post_pos_session_on_close_multi();

COMMENT ON FUNCTION public.post_pos_session_on_close_multi() IS
  'Clôture d''une session de caisse : D de chaque moyen de paiement, C ventes, '
  'C TVA ventilée par taux (R-13, 219), écart de caisse en 658/758 contre le '
  'compte du moyen de paiement espèces, sorties de stock par dépôt.';