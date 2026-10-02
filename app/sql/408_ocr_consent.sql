-- ============================================================
-- 318_ocr_consent.sql — le consentement à l'envoi de données à un tiers (D-5)
--
-- LE DÉFAUT (AUD-H04). Des fonctions Edge envoient des documents et des données
-- de la société à OpenAI : `ocr-invoice-import` (l'image d'une facture
-- fournisseur), `parse-bank-statement` (le contenu d'un relevé), et
-- `ai-import-mapping` (les en-têtes et lignes d'un fichier d'import). Aucun
-- consentement n'était demandé — et **il n'y avait nulle part où le donner**.
--
-- CE QUE LA PRATIQUE EXIGE. Un sous-traitant suppose un contrat de sous-traitance
-- (DPA), une base légale, et, pour un transfert hors Union européenne, des
-- clauses contractuelles et une analyse d'impact. Les éditeurs du marché gardent
-- l'OCR — c'est le service de la reprise de comptabilité — encadré par un DPA et
-- un RÉGLAGE PAR DOSSIER (Pennylane, Dext, Qonto, Sage AutoEntry, NetSuite
-- Document Capture). C'est ce réglage que cette migration rend possible.
--
-- POURQUOI UNE TRACE, ET PAS UN DRAPEAU. Un booléen se falsifie : un client peut
-- l'écrire, l'antidater ou se l'attribuer. Le consentement posé ici porte QUAND
-- et PAR QUI, et c'est le DÉCLENCHEUR qui les écrit — jamais le client.
--
-- CE QUE CETTE MIGRATION NE FAIT PAS, dit franchement : elle ne signe aucun DPA,
-- et elle ne couvre QUE `ocr-invoice-import` (le garde est dans la fonction ;
-- voir `_shared/ocrConsent.ts`). Les deux autres fonctions qui parlent au même
-- prestataire restent à garder — la limite est nommée dans la preuve, pas tue.
-- ============================================================

ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS ocr_consent    boolean NOT NULL DEFAULT false;
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS ocr_consent_at timestamptz;
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS ocr_consent_by uuid;

COMMENT ON COLUMN company_settings.ocr_consent IS
  'D-5 (318) : consentement de la société à l''envoi de ses documents à un prestataire d''OCR/IA. '
  'Faux par défaut : une société neuve n''a rien consenti, et l''OCR le lui dit.';
COMMENT ON COLUMN company_settings.ocr_consent_at IS
  'D-5 (318) : date du consentement. Écrite par le déclencheur, jamais par le client (preuve).';
COMMENT ON COLUMN company_settings.ocr_consent_by IS
  'D-5 (318) : auteur du consentement (auth.uid()). Écrit par le déclencheur, jamais par le client.';

-- ─────────────────────────────────────────────────────────────
-- Le déclencheur : il DATE et il SIGNE. Le client ne peut pas mentir.
-- ─────────────────────────────────────────────────────────────
-- `SECURITY INVOKER` (le défaut) : cette fonction ne lit aucune table, elle ne
-- fait que renseigner la ligne en cours. Elle n'a donc rien à contourner — et
-- c'est aussi ce qui la tient hors des deux règles de `check_tenant_guard`.
CREATE OR REPLACE FUNCTION stamp_ocr_consent() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.ocr_consent IS TRUE THEN
      NEW.ocr_consent_at := now();
      NEW.ocr_consent_by := auth.uid();
    ELSE
      NEW.ocr_consent    := false;
      NEW.ocr_consent_at := NULL;
      NEW.ocr_consent_by := NULL;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.ocr_consent IS DISTINCT FROM OLD.ocr_consent THEN
    IF NEW.ocr_consent THEN
      NEW.ocr_consent_at := now();
      NEW.ocr_consent_by := auth.uid();
    ELSE
      -- Retirer son consentement est un droit : la trace du RETRAIT vit dans le
      -- journal d'activité, pas ici. La date et l'auteur de l'ancien
      -- consentement ne sont donc pas conservés sur la ligne — c'est dit.
      NEW.ocr_consent_at := NULL;
      NEW.ocr_consent_by := NULL;
    END IF;
  ELSE
    -- On ne RÉÉCRIT pas une preuve : un enregistrement sans changement de
    -- consentement ne rafraîchit ni la date ni l'auteur.
    NEW.ocr_consent_at := OLD.ocr_consent_at;
    NEW.ocr_consent_by := OLD.ocr_consent_by;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_stamp_ocr_consent ON company_settings;
CREATE TRIGGER trg_stamp_ocr_consent
  BEFORE INSERT OR UPDATE ON company_settings
  FOR EACH ROW EXECUTE FUNCTION stamp_ocr_consent();

-- Le visiteur n'a rien à faire de ce déclencheur : il ne s'exécute pas sur appel.
REVOKE ALL ON FUNCTION stamp_ocr_consent() FROM PUBLIC, anon;
