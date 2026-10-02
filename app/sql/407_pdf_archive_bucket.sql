-- ============================================================
-- 317_pdf_archive_bucket.sql — le bucket où `generate-pdf` ARCHIVE ses pièces
--
-- 1. LE DÉFAUT QUE CE FICHIER FERME (mesuré, décision D-4)
-- ---------------------------------------------------------
-- `generate-pdf` rangeait son PDF dans `storage.from("documents")` — un bucket
-- qui n'existe NULLE PART : les sept buckets du dépôt sont déclarés par la
-- `68_module_documents_storage_rls.sql` (project-docs, accounting-docs, hr-docs,
-- commercial-docs, general-docs, employee-documents, tax-grid-sources). Mesuré
-- le 30/09 : `grep -rln 'INSERT INTO storage.buckets' app/sql/` ne rend qu'un
-- fichier, et il ne nomme jamais `documents`. Conséquence exacte :
--   • l'`upload` échoue ;
--   • l'erreur n'était pas lue ;
--   • la fonction rendait `success: true` avec `url: null` — un succès sans
--     pièce, c'est-à-dire un mensonge, pas un incident.
--
-- 2. CE QUE CE FICHIER POSE
-- -------------------------
--   a. le bucket `generated-pdfs` — privé, PDF seulement, 25 Mo ;
--   b. la SEULE politique d'accès : la LECTURE, bornée à la société ET au
--      module porté par le chemin `{société}/{module}/{type}/{fichier}.pdf` ;
--   c. et l'absence DÉLIBÉRÉE des trois autres commandes, qui est la décision
--      de gestion autant que la règle technique :
--        • pas d'INSERT  → un utilisateur ne fabrique pas une pièce d'archive ;
--          seule la clé de service écrit, et elle seule peut donc attester ;
--        • pas d'UPDATE  → une pièce archivée n'est jamais réécrite (le PDF est
--          une COPIE de la pièce à un instant donné) ;
--        • pas de DELETE → une pièce archivée ne s'efface pas. `service_role`,
--          qui contourne la RLS, reste le seul à pouvoir purger — c'est l'acte
--          de gestion (fin de conservation), pas l'acte courant.
--
-- 3. POURQUOI LE MODULE DANS LE CHEMIN
-- -------------------------------------
-- Un bulletin de paie n'a pas à être lisible par un commercial. La politique
-- lit le 2e segment du chemin et le confronte à `has_module_access()` — la
-- même fonction que les buckets de la `68` (`project-docs` →
-- `projectManagement`, `hr-docs` → `hr`, etc.), donc le même vocabulaire.
-- Le module est écrit par la fonction, depuis une LISTE FERMÉE
-- (`invoice`/`credit_note`/`purchase_invoice` → `accounting`, `quote` →
-- `commercial`, `payslip` → `hr`) : il n'est jamais choisi par l'appelant.
-- Un segment inconnu (ou absent) ne rend PAS l'accès plus large : le 2e
-- segment vaut alors NULL, `has_module_access(NULL)` est faux, et seul un
-- administrateur passe — l'échec est fermé (scénario T06 de la suite).
--
-- 4. CE QUE CE FICHIER NE FAIT PAS (dit, pas contourné)
-- -----------------------------------------------------
--   • il ne DÉPLOIE pas `generate-pdf` : la fonction reste non déployée
--     (`deploy-all-functions.sh`) tant que `GOTENBERG_URL` n'est pas posé et
--     que le convertisseur n'est pas injoignable du réseau interne — c'est la
--     première exigence de l'option A, et elle n'est pas dans ce dépôt ;
--   • il ne remplit pas le bucket : c'est la fonction qui écrit, et elle refuse
--     désormais d'annoncer un succès quand elle n'a rien rangé ;
--   • il ne pose aucune politique d'écriture : voir 2.c.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. Le bucket : privé, PDF seulement, 25 Mo
-- ─────────────────────────────────────────────────────────────
-- `ON CONFLICT DO NOTHING` ne suffit pas : un bucket créé à la main dans le
-- tableau de bord peut déjà porter ce nom avec les mauvais réglages. Une
-- archive de pièces comptables ne doit pas pouvoir devenir publique parce
-- qu'un bucket existe — les trois garanties sont donc RÉÉCRITES à chaque
-- exécution, comme la `68` le fait pour ses sept buckets.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('generated-pdfs', 'generated-pdfs', false, 26214400, ARRAY['application/pdf'])
ON CONFLICT (id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 2. La politique de LECTURE — société + module du chemin
-- ─────────────────────────────────────────────────────────────
-- `TO authenticated` est écrit exprès : les politiques de la `68` ne nomment
-- aucun rôle (elles valent donc pour PUBLIC, `anon` compris, et ne tiennent que
-- parce que `current_tenant_id()` rend NULL). Ici `anon` est exclu par
-- construction, pas par effet de bord.
DROP POLICY IF EXISTS generated_pdfs_download ON storage.objects;

CREATE POLICY generated_pdfs_download ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'generated-pdfs'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND (
      current_user_role() = 'admin'
      OR has_module_access((storage.foldername(name))[2])
    )
  );

-- ─────────────────────────────────────────────────────────────
-- 3. Les commandes qui N'ONT PAS de politique — et pourquoi
-- ─────────────────────────────────────────────────────────────
-- PostgreSQL ne sait pas exprimer une politique « de refus » : l'absence de
-- politique EST le refus. Les trois commandes sont donc gardées par leur
-- absence, et la suite les mesure une par une (T02) — une politique ajoutée ici
-- par distraction ferait rougir la suite, ce qui est le but.
--
--   INSERT : `generated_pdfs_upload`     — VOLONTAIREMENT ABSENTE
--            (la clé de service contourne la RLS : c'est le seul écrivain)
--   UPDATE : `generated_pdfs_update`     — VOLONTAIREMENT ABSENTE
--   DELETE : `generated_pdfs_delete`     — VOLONTAIREMENT ABSENTE
--            (purge réservée à `service_role`, fin de conservation)

-- ─────────────────────────────────────────────────────────────
-- 4. Contrôle de cohérence, joué à l'application de la migration
-- ─────────────────────────────────────────────────────────────
-- Échouer ICI plutôt que de laisser la fonction écrire dans le vide : si le
-- bucket est absent, public, ou s'il accepte autre chose que du PDF, la
-- migration n'a pas atteint son but et doit le dire. Elle est idempotente.
DO $$
DECLARE
  v_public  boolean;
  v_mimes   text[];
  v_polices int;
BEGIN
  SELECT public, allowed_mime_types INTO v_public, v_mimes
  FROM storage.buckets WHERE id = 'generated-pdfs';

  IF v_public IS DISTINCT FROM false THEN
    RAISE EXCEPTION '317 : le bucket generated-pdfs doit rester privé (public = %)', v_public;
  END IF;

  IF v_mimes IS DISTINCT FROM ARRAY['application/pdf'] THEN
    RAISE EXCEPTION '317 : le bucket generated-pdfs n''accepte que des PDF (mimes = %)', v_mimes;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname = 'storage' AND tablename = 'objects'
                   AND policyname = 'generated_pdfs_download') THEN
    RAISE EXCEPTION '317 : la politique de lecture generated_pdfs_download est absente';
  END IF;

  SELECT count(*) INTO v_polices FROM pg_policies
  WHERE schemaname = 'storage' AND tablename = 'objects'
    AND policyname LIKE 'generated_pdfs_%';

  IF v_polices <> 1 THEN
    RAISE EXCEPTION '317 : une seule politique est attendue sur ce bucket (la lecture), % trouvée(s)', v_polices;
  END IF;
END $$;


UPDATE storage.buckets
   SET public             = false,
       file_size_limit    = 26214400,
       allowed_mime_types = ARRAY['application/pdf']
 WHERE id = 'generated-pdfs';
