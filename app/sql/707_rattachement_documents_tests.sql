-- ============================================================
-- 707_rattachement_documents_tests.sql — F.6 / GED-01 :
--   UN DOCUMENT SE RATTACHE À UNE PIÈCE QUI EXISTE — ET DE SA SOCIÉTÉ
--
--   T01  un document SANS rattachement reste valide (le cas ordinaire)
--   T02  rattachement VALIDE : à une pièce réelle de la même société (contre-épreuve)
--   T03  refus : une pièce INEXISTANTE (DOCUMENT_LINK_MISSING)
--   T04  refus : une pièce d'une AUTRE société (DOCUMENT_LINK_MISSING)
--   T05  refus : un type inconnu du REGISTRE (DOCUMENT_LINK_TYPE)
--   T06  refus : une moitié seulement — id sans type (DOCUMENT_LINK_INCOMPLETE)
--   T07  le registre `chain_document_types` couvre bien les 27 pièces (dont `journals`)
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '707', false);
DELETE FROM _audit_results WHERE file = '707';

-- Insère un document de module rattaché (ou non) à une pièce.
CREATE OR REPLACE FUNCTION _l707_doc(p_tenant uuid, p_type text, p_id uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE u uuid;
BEGIN
  SELECT id INTO u FROM tenant_users WHERE tenant_id = p_tenant AND role = 'admin' LIMIT 1;
  INSERT INTO module_documents
    (tenant_id, module, document_type, title, file_url, file_name, uploaded_by, entity_type, entity_id)
  VALUES
    (p_tenant, 'general', 'other', 'Document de test', 'tmp/x.pdf', 'x.pdf', u, p_type, p_id);
END $$;

-- T07 — le registre (décor commun : on y vérifie les 27 codes)
DO $$
DECLARE n int; ok_j boolean;
BEGIN
  SELECT count(*) INTO n FROM chain_document_types;
  SELECT EXISTS (SELECT 1 FROM chain_document_types WHERE code = 'journals') INTO ok_j;
  PERFORM _rec('T07', 'le registre `chain_document_types` couvre les 27 pièces (dont `journals`)',
    -- 13/10/2026 (fusion plan6) : `n = 27` est devenu faux — le registre a
    -- GROSSI (37+ types : devis, projets, commandes, certificat… portés par les
    -- lots A1/A3/B) et c'est une amélioration, pas une régression. L'intention
    -- de la 707 est la COUVERTURE (les 27 pièces d'origine, dont `journals`),
    -- pas l'effectif exact : `>= 27` + le repère `journals`.
    n >= 27 AND ok_j, format('codes = %s (27 au minimum) ; `journals` présent = %s', n, ok_j));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T07', 'couverture du registre', false, SQLERRM);
END $$;

-- T01 → T06 : le rattachement, mesuré
DO $$
DECLARE
  ta uuid; tb uuid; j uuid; jb uuid; u uuid; n int; ok boolean;
BEGIN
  ta := _mk_tenant('F707A');
  SELECT id INTO j  FROM journals WHERE tenant_id = ta LIMIT 1;
  tb := _mk_tenant('F707B');
  SELECT id INTO jb FROM journals WHERE tenant_id = tb LIMIT 1;
  SELECT id INTO u  FROM tenant_users WHERE tenant_id = ta AND role = 'admin' LIMIT 1;

  -- T01 — sans rattachement : valide
  PERFORM _l707_doc(ta, NULL, NULL);
  SELECT count(*) INTO n FROM module_documents WHERE tenant_id = ta;
  PERFORM _rec('T01', 'un document SANS rattachement reste valide (le cas ordinaire)',
    n = 1, format('documents insérés = %s (attendu 1)', n));

  -- T02 — rattachement valide à une pièce de la MÊME société
  PERFORM _l707_doc(ta, 'journals', j);
  SELECT count(*) INTO n FROM module_documents
   WHERE tenant_id = ta AND entity_type = 'journals' AND entity_id = j;
  PERFORM _rec('T02', 'rattachement VALIDE : un document sur un journal réel de la même société',
    n = 1, format('documents rattachés au journal %s = %s (attendu 1)', j, n));

  -- T03 — pièce inexistante
  ok := false;
  BEGIN
    PERFORM _l707_doc(ta, 'journals', gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%DOCUMENT_LINK_MISSING%'; END;
  PERFORM _rec('T03', 'refus : rattacher à une pièce INEXISTANTE (DOCUMENT_LINK_MISSING)', ok,
    format('refus nommé DOCUMENT_LINK_MISSING = %s', ok));

  -- T04 — pièce d'une AUTRE société
  ok := false;
  BEGIN
    PERFORM _l707_doc(ta, 'journals', jb);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%DOCUMENT_LINK_MISSING%'; END;
  PERFORM _rec('T04', 'refus : rattacher à une pièce d''une AUTRE société (DOCUMENT_LINK_MISSING)', ok,
    format('refus nommé DOCUMENT_LINK_MISSING = %s', ok));

  -- T05 — type inconnu du registre
  ok := false;
  BEGIN
    PERFORM _l707_doc(ta, 'projets', j);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%DOCUMENT_LINK_TYPE%'; END;
  PERFORM _rec('T05', 'refus : un type de pièce inconnu du REGISTRE (DOCUMENT_LINK_TYPE)', ok,
    format('refus nommé DOCUMENT_LINK_TYPE = %s', ok));

  -- T06 — une moitié seulement (identifiant sans type)
  ok := false;
  BEGIN
    INSERT INTO module_documents
      (tenant_id, module, document_type, title, file_url, file_name, uploaded_by, entity_type, entity_id)
    VALUES (ta, 'general', 'other', 'Moitié', 'tmp/y.pdf', 'y.pdf', u, NULL, j);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%DOCUMENT_LINK_INCOMPLETE%'; END;
  PERFORM _rec('T06', 'refus : une moitié de rattachement — identifiant sans type (DOCUMENT_LINK_INCOMPLETE)', ok,
    format('refus nommé DOCUMENT_LINK_INCOMPLETE = %s', ok));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'document sans rattachement', false, SQLERRM);
  PERFORM _rec('T02', 'rattachement valide', false, SQLERRM);
  PERFORM _rec('T03', 'pièce inexistante', false, SQLERRM);
  PERFORM _rec('T04', 'pièce d''une autre société', false, SQLERRM);
  PERFORM _rec('T05', 'type inconnu', false, SQLERRM);
  PERFORM _rec('T06', 'rattachement incomplet', false, SQLERRM);
END $$;

-- Garde-fou anti-faux-vert : la suite EXIGE ses 7 verdicts
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _audit_results WHERE file = '707';
  IF n <> 7 THEN
    RAISE EXCEPTION '[707] % verdict(s) enregistré(s) au lieu de 7 — un scénario n''a pas été joué', n;
  END IF;
END $$;

SELECT _audit_assert('707');
