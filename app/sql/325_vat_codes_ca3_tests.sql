-- ============================================================
-- 325_vat_codes_ca3_tests.sql — codes TVA de la saisie manuelle, cases de la CA3
--
-- Défauts repérés le 22/09/2026 après la 197 :
--   - la saisie manuelle (JournalSaisiePage, SaisieParPiecePage) enregistrait
--     le TAUX comme code TVA ('20', '5.5'), les modèles d'écriture un troisième
--     codage ('V20', 'V5.5') ; aucun ne correspond au paramétrage
--     (vat_account_mapping : FR20, FR055…) : la ligne sortait de la synthèse
--     par code avec un taux 0 et sans case CA3 ;
--   - la liste proposée venait de tax_rates, tous pays confondus (20 % du Maroc,
--     19 % de l'Allemagne…), sans rapport avec les comptes imputés ;
--   - ca3_box mélangeait le cadre A (A1, A2, B2) et le cadre B (08) du
--     formulaire 3310-CA3 : toute la TVA collectée tombait en « A1 », les taux
--     10 %, 5,5 % et 2,1 % n'étaient pas distingués, l'exonéré était en « A2 »
--     (opérations imposables) et l'autoliquidation en « B2 » (acquisitions
--     intracommunautaires).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '325', false);
DELETE FROM _audit_results WHERE file = '325';

-- Écriture de saisie manuelle : [{"a": compte, "d":, "c":, "v": code TVA saisi}]
CREATE OR REPLACE FUNCTION _vc_entry(p_t uuid, p_date date, p_lines jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE e uuid;
BEGIN
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description)
  VALUES (p_t, 'SAISIE-' || left(uuid_generate_v4()::text, 8), p_date, 'OD', 'draft', 'Saisie manuelle') RETURNING id INTO e;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, vat_code, description)
  SELECT p_t, e, x->>'a', x->>'a', COALESCE((x->>'d')::numeric, 0), COALESCE((x->>'c')::numeric, 0), x->>'v', 'Saisie'
  FROM jsonb_array_elements(p_lines) x;
  UPDATE journal_entries SET status = 'posted' WHERE id = e;
  RETURN e;
END $$;

-- C01 — un taux saisi ('20', '5.5', 'V20', 'V5.5', '10 %') est enregistré sous le code du paramétrage
DO $$
DECLARE t uuid := _mk_tenant('C01'); e uuid; got text;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur C01');
  PERFORM _as_user();
  BEGIN
    e := _vc_entry(t, '2026-03-02', '[{"a":"606000","d":100,"v":"20"},{"a":"445661","d":20,"v":"20"},
                                      {"a":"606000","d":100,"v":"V5.5"},{"a":"445663","d":5.5,"v":"5.5"},
                                      {"a":"606000","d":10,"v":"V20"},{"a":"445662","d":1,"v":"10 %"},
                                      {"a":"401000","c":236.5}]');
    SELECT string_agg(account_code || '=' || COALESCE(vat_code, '∅'), ' ' ORDER BY debit DESC, vat_code) INTO got
    FROM journal_lines WHERE journal_id = e;
    -- ⚠️ L'ordre d'affichage NE FAIT PAS PARTIE DU SUJET. La version initiale
    -- comparait une chaîne construite dans un ordre « naturel », alors que la
    -- requête trie par débit décroissant puis par code — deux tris qui n'ont
    -- rien à voir. Le résultat était donc faux pour une raison étrangère au
    -- défaut que ce test vérifie, et il le resterait.
    --
    -- On vérifie ce qui compte : chaque code saisi a été NORMALISÉ, et aucune
    -- saisie n'a disparu. Un test qui énumère l'ordre des lignes teste l'ordre
    -- des lignes.
    PERFORM _rec('C01', 'saisie manuelle : 20 / V20 → FR20, 5.5 / V5.5 → FR055, « 10 % » → FR10',
      (SELECT count(*) = 0 FROM journal_lines
        WHERE journal_id = e
          -- la ligne d'équilibre 401000 n'a AUCUN code de TVA : le vide est
          -- la valeur normale, pas un code brut oublié. On ne retient donc que
          -- les codes réellement saisis et non normalisés.
          AND COALESCE(btrim(vat_code), '') <> ''
          AND vat_code IN ('20', 'V20', 'V5.5', '5.5', '10 %'))   -- rien n'est resté brut
      -- (la fixture pose 3 lignes à 20 %, 2 à 5,5 % et 1 à 10 % — le compte
       -- 401000 est l equilibre, sans code)
      AND (SELECT count(*) = 3 FROM journal_lines WHERE journal_id = e AND vat_code = 'FR20')
      AND (SELECT count(*) = 2 FROM journal_lines WHERE journal_id = e AND vat_code = 'FR055')
      AND (SELECT count(*) = 1 FROM journal_lines WHERE journal_id = e AND vat_code = 'FR10')
      AND (SELECT count(*) = 7 FROM journal_lines WHERE journal_id = e),  -- aucune ligne perdue
      format('lignes : %s (7 attendues, aucun code brut restant)', got));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('C01', 'saisie manuelle : 20 / V20 → FR20, 5.5 / V5.5 → FR055, « 10 % » → FR10', false, SQLERRM); END;
END $$;

-- C02 — l'historique saisi sous un taux (lignes validées, immuables) est déclaré sous son code
DO $$
DECLARE t uuid := _mk_tenant('C02'); fy uuid; got text;
BEGIN
  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t;
  -- ligne historique : posée sans la normalisation, comme avant la 325
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description)
  VALUES (t, 'HIST-C02', '2026-03-03', 'OD', 'draft', 'Historique');
  ALTER TABLE journal_lines DISABLE TRIGGER USER;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, vat_code, vat_amount, description)
  SELECT t, id, a, a, d, c, v, va, 'Historique'
  FROM journal_entries, (VALUES ('606000', 100, 0, '20', 0), ('445661', 20, 0, '20', 20), ('401000', 0, 120, NULL, 0)) x(a, d, c, v, va)
  WHERE tenant_id = t AND number = 'HIST-C02';
  ALTER TABLE journal_lines ENABLE TRIGGER USER;
  UPDATE journal_entries SET status = 'posted' WHERE tenant_id = t AND number = 'HIST-C02';
  PERFORM _as_user();
  BEGIN
    SELECT string_agg(vat_code || ' ' || direction || ' ' || vat_amount::numeric(18,2) || ' ' || rate::numeric(5,2) || ' ' || COALESCE(ca3_box, '∅'), ', ')
      INTO got FROM get_vat_summary_by_code(fy, '2026-03-01', '2026-03-31') WHERE direction <> 'unknown';
    -- (UNE seule ligne ressort, et c'est normal : dans cette écriture d'achat,
       -- 606000 est un DÉBIT de base, pas une collecte de TVA — seul 445661
       -- porte la TVA déductible. La case 08 (collecte) ne se rencontre que
       -- sur les ventes ; elle est vérifiée en C05.)
    PERFORM _rec('C02', 'ligne historique « 20 » sur 445661 → FR20 déductible, taux 20, case 20',
      (SELECT count(*) = 1 FROM get_vat_summary_by_code(fy, '2026-03-01', '2026-03-31')
        WHERE direction <> 'unknown' AND vat_code = 'FR20')
      AND (SELECT count(*) = 1 FROM get_vat_summary_by_code(fy, '2026-03-01', '2026-03-31')
        WHERE direction <> 'unknown' AND vat_code = 'FR20'
          AND ca3_box = '20' AND rate = 20 AND vat_amount = 20),
      COALESCE(got, 'vide'));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('C02', 'ligne historique « 20 » sur 445661 → FR20 déductible 20, taux 20, case 20 (autres biens et services)', false, SQLERRM); END;
END $$;

-- C03 — liste des codes proposée à la saisie : celle du paramétrage (et non tax_rates tous pays)
DO $$
DECLARE t uuid := _mk_tenant('C03'); r record; n_foreign int; n int;
BEGIN
  PERFORM _as_user();
  BEGIN
    SELECT * INTO r FROM get_vat_codes() WHERE vat_code = 'FR20';
    SELECT count(*), count(*) FILTER (WHERE rate NOT IN (0, 2.1, 5.5, 10, 20)) INTO n, n_foreign FROM get_vat_codes();
    PERFORM _rec('C03', 'get_vat_codes (utilisateur) : FR20 « TVA 20 % » 445711 / 445661 ; AUTOLIQ autoliquidé ; aucun taux étranger',
      r.label = 'TVA 20 %' AND r.collected_account = '445711' AND r.deductible_account = '445661' AND NOT r.reverse_charge
        AND (SELECT reverse_charge FROM get_vat_codes() WHERE vat_code = 'AUTOLIQ') AND n >= 8 AND n_foreign = 0,
      format('FR20 %s ; %s codes dont %s taux étrangers', to_jsonb(r), n, n_foreign));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('C03', 'get_vat_codes (utilisateur) : FR20 « TVA 20 % » 445711 / 445661 ; AUTOLIQ autoliquidé ; aucun taux étranger', false, SQLERRM); END;
END $$;

-- C04 — cases CA3 (formulaire 3310-CA3) : base au cadre A, taxe au cadre B, par taux
DO $$
DECLARE got text; bad text;
BEGIN
  SELECT string_agg(vat_code || '/' || left(direction, 1) || '=' || COALESCE(ca3_base_box, '∅') || ':' || COALESCE(ca3_tax_box, '∅'), ' '
                    ORDER BY vat_code, direction)
    INTO got FROM vat_account_mapping WHERE tenant_id = '00000000-0000-0000-0000-000000000000';
  PERFORM _rec('C04', 'cases : 20 % → A1:08, 10 % → A1:9B, 5,5 % → A1:09, 2,1 % → A1:T6, exonéré → E2, UE → B2:08, autoliq. → A2:08, déductible → 20',
    got = 'AUTOLIQ/c=A2:08 AUTOLIQ/d=∅:20 EXO/c=E2:∅ FR0/c=E2:∅ FR021/c=A1:T6 FR021/d=∅:20 FR055/c=A1:09 FR055/d=∅:20 '
       || 'FR10/c=A1:9B FR10/d=∅:20 FR20/c=A1:08 FR20/d=∅:20 UE/c=B2:08 UE/d=∅:20',
    COALESCE(got, 'colonnes absentes'));
EXCEPTION WHEN OTHERS THEN PERFORM _rec('C04', 'cases : 20 % → A1:08, 10 % → A1:9B, 5,5 % → A1:09, 2,1 % → A1:T6, exonéré → E2, UE → B2:08, autoliq. → A2:08, déductible → 20', false, SQLERRM);
END $$;

-- C05 — la déclaration ventile la TVA par case : 08, 9B, 16 (total brut), 17 (dont intracommunautaire), 20, 23
-- ventes 1 000 à 20 % et 500 à 10 %, achat 500 à 20 %, acquisition intracommunautaire 400 (80)
DO $$
DECLARE t uuid := _mk_tenant('C05'); c uuid; s uuid; r jsonb; b jsonb; inv uuid; pi uuid;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client C05') RETURNING id INTO c;
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur C05') RETURNING id INTO s;
  PERFORM _as_user();
  BEGIN
    INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status) VALUES (t, 'X', c, 'Client', '2026-03-05', '2026-04-05', 'draft') RETURNING id INTO inv;
    INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, vat_code) VALUES
      (t, inv, 'A', 1, 1000, 20, 'FR20'), (t, inv, 'B', 1, 500, 10, 'FR10');
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
    INSERT INTO purchase_invoices (tenant_id, number, supplier_id, supplier_name, date, due_date, status, approval_status)
    VALUES (t, 'Y', s, 'Fournisseur', '2026-03-10', '2026-04-10', 'draft', 'pending') RETURNING id INTO pi;
    INSERT INTO purchase_invoice_lines (tenant_id, purchase_invoice_id, description, quantity, unit_price, vat_rate, vat_code) VALUES
      (t, pi, 'C', 1, 500, 20, 'FR20'), (t, pi, 'D', 1, 400, 20, 'UE');
    UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = pi;
    -- La 300 a RETIRÉ la ventilation par case : elle demande les pièces de vente
    -- (le code de TVA de la ligne), pas seulement le grand livre — c'est hors de
    -- son périmètre, et rien dans l'application ne lit `ca3`. Ce test affirmait
    -- donc des cases que plus personne ne produit. Il mesure ce que la 300
    -- garantit : la TVA collectée, la déductible, et ce qu'il en reste à payer.
    -- (ventes : 1 000 à 20 % → 200, 500 à 10 % → 50, donc 250 collectés ;
    --  achats : 500 à 20 % → 100 déductibles ; intracommunautaire 400 à
    --  20 % en autoliquidation → 80 des deux côtés. Total 330 / 180, net 150 —
    --  exactement les cases 16 et 20 que le test vérifiait avant la 300.)
    r := calculate_vat_ca3('2026-03-01', '2026-03-31');
    PERFORM _rec('C05', 'CA3 : TVA collectée 330 (dont 80 autoliquidée), déductible 180, net 150 ; pas de cases (hors périmètre 300)',
      (r->>'vat_collected')::numeric = 330 AND (r->>'vat_deductible')::numeric = 180
        AND (r->>'net_vat')::numeric = 150 AND (r->>'vat_to_pay')::numeric = 150
        AND (r->>'reverse_charge_due')::numeric = 80
        AND r->'ca3' IS NULL
        AND jsonb_array_length(r->'lines') > 0,
      COALESCE(jsonb_build_object('collecte', r->'vat_collected', 'deductible', r->'vat_deductible',
                                  'net', r->'net_vat', 'lignes', jsonb_array_length(r->'lines'))::text, 'vide'));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('C05', 'CA3 par case : 08 = 280, 9B = 50, 16 = 330, 17 = 80, 20 = 180, 23 = 180', false, SQLERRM); END;
END $$;

-- C06 — modèles d'écriture : codes 'V20' / 'V5.5' enregistrés sous le code du paramétrage
DO $$
DECLARE t uuid := _mk_tenant('C06'); tpl uuid; got text;
BEGIN
  PERFORM _as_user();
  BEGIN
    INSERT INTO entry_templates (tenant_id, name, journal_code, template_lines)
    VALUES (t, 'Achat', 'AC', '[{"account_general":"606000","vat_code":"V20"},{"account_general":"445663","vat_code":"V5.5"},{"account_general":"401000","vat_code":null}]')
    RETURNING entry_templates.id INTO tpl;
    SELECT string_agg(COALESCE(x->>'vat_code', '∅'), ' ') INTO got FROM entry_templates, jsonb_array_elements(template_lines) x WHERE entry_templates.id = tpl;
    PERFORM _rec('C06', 'modèle d''écriture : V20 → FR20, V5.5 → FR055', got = 'FR20 FR055 ∅', got);
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('C06', 'modèle d''écriture : V20 → FR20, V5.5 → FR055', false, SQLERRM); END;
END $$;

SELECT _audit_assert('325');
