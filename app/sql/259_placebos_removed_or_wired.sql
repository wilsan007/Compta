-- ============================================================
-- 259_placebos_removed_or_wired.sql — un écran ne peut plus tamponner un
--                                     succès que rien n'a produit
--                                     (EF-03, EF-06, TVA-01)
--
-- Trois écrans disaient « fait » sans qu'une transmission ait eu lieu, et
-- **la base les laissait faire** :
--
--   EF-03 / TVA-01 `syncBankConnection` (banking.ts) et `submitEdiTva`
--           (misc.ts) n'appelaient **aucune** fonction Edge. Le premier
--           tamponnait `bank_connections.last_sync_at = now()` et effaçait le
--           message d'erreur ; le second fabriquait un identifiant local
--           `EDI-<Date.now()>` et écrivait `edi_status = 'submitted'`. Dans les
--           deux cas l'écran affichait un succès — et l'erreur réelle d'une
--           panne était **masquée**.
--   EF-06   `EInvoicePage` ne soumettait rien : elle générait le XML Factur-X
--           et le téléchargeait. Aucune trace de dépôt (les colonnes n'existaient
--           pas — 257), donc un second clic aurait retransmis la facture.
--
-- Le code est corrigé dans le même commit : les trois écrans passent par les
-- fonctions Edge, qui seules savent si la transmission a réussi.
--
-- CE QUE CE FICHIER AJOUTE, et que le code seul ne peut pas garantir : la
-- **porte**. Une colonne de transmission (`edi_status`, `e_invoice_status`) et
-- l'horodatage d'une synchronisation (`last_sync_at`) ne peuvent être écrits
-- par un client (`anon`, `authenticated`) — seul le `service_role`, c'est-à-dire
-- la fonction Edge après un appel réel, le peut. Un futur écran qui
-- réintroduirait le placebo échouerait à l'écriture, pas dans le dos de
-- l'utilisateur.
--
-- Les valeurs ne sont jamais comparées à un littéral : la porte refuse **tout
-- changement** de la colonne vue par un client. Un écran qui recopie la valeur
-- existante (enregistrement d'un formulaire) passe.
-- ============================================================

CREATE OR REPLACE FUNCTION public.refuse_client_success_stamp()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_col  text  := TG_ARGV[0];
  v_role text  := COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
  v_motif text := COALESCE(TG_ARGV[1], 'transmission');
BEGIN
  -- Sans JWT (superutilisateur, migration, cron SQL) ou depuis le service, la
  -- transmission a bien eu lieu : la porte est ouverte.
  IF v_role NOT IN ('anon', 'authenticated') THEN
    RETURN NEW;
  END IF;

  IF to_jsonb(NEW) -> v_col IS DISTINCT FROM to_jsonb(OLD) -> v_col THEN
    RAISE EXCEPTION '% : un utilisateur connecté ne peut pas écrire « % » — % n''a pas eu lieu', TG_TABLE_NAME, v_col, v_motif
      USING ERRCODE = '42501',
            HINT = 'La trace d''une transmission s''écrit par la fonction Edge, après l''appel réel.';
  END IF;

  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.refuse_client_success_stamp() IS
  '259 (W6) : refuse, pour anon/authenticated, toute modification de la colonne passée en TG_ARGV[0] — la trace d''une transmission ne peut être tamponnée par un écran (EF-03, EF-06, TVA-01).';

-- ── La déclaration TVA (EDI-TVA) : seul le service transmet ────────────────
DROP TRIGGER IF EXISTS trg_refuse_client_edi_stamp ON public.vat_returns;
CREATE TRIGGER trg_refuse_client_edi_stamp
  BEFORE UPDATE ON public.vat_returns
  FOR EACH ROW
  EXECUTE FUNCTION public.refuse_client_success_stamp('edi_status', 'la télédéclaration EDI-TVA');

-- ── Le dépôt électronique d'une facture : seul le service dépose ───────────
DROP TRIGGER IF EXISTS trg_refuse_client_einvoice_stamp ON public.invoices;
CREATE TRIGGER trg_refuse_client_einvoice_stamp
  BEFORE UPDATE ON public.invoices
  FOR EACH ROW
  EXECUTE FUNCTION public.refuse_client_success_stamp('e_invoice_status', 'le dépôt à Chorus Pro / PEPPOL');

-- ── La synchronisation bancaire : seul le service synchronise ──────────────
DROP TRIGGER IF EXISTS trg_refuse_client_sync_stamp ON public.bank_connections;
CREATE TRIGGER trg_refuse_client_sync_stamp
  BEFORE UPDATE ON public.bank_connections
  FOR EACH ROW
  EXECUTE FUNCTION public.refuse_client_success_stamp('last_sync_at', 'la synchronisation bancaire');

-- ── Droits — un déclencheur n'est pas une RPC (leçon de la 228) ────────────
REVOKE ALL ON FUNCTION public.refuse_client_success_stamp() FROM PUBLIC, anon, authenticated;
