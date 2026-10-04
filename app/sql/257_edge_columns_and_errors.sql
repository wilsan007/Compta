-- ============================================================
-- 257_edge_columns_and_errors.sql — les colonnes que les fonctions Edge
--                                  écrivaient sans qu'elles existent (W6)
--
-- MESURÉ le 24/09/2026 par le scanner `scripts/check-written-columns.mjs`
-- (W0.2), sur le schéma réel : **20 écritures impossibles**, toutes dans
-- `supabase/functions/` sauf deux dans le front, gelées une par une dans
-- `scripts/verify-rules/written-columns.baseline.json`. Aucune ne lisait son
-- erreur : aucune n'échouait visiblement.
--
-- Ce que chaque fonction croyait écrire, et ce que la table porte réellement :
--
--   cron-payment-reminders   collection_reminders.days_overdue, sent_at, email_sent
--                            → la table ne les a pas ; la relance était comptée
--                              comme envoyée et *aucune trace* ne restait.
--   handle-stripe-webhook    notification_email_queue.metadata
--                            → pas de colonne `metadata` : la notification
--                              d'échec de paiement n'était jamais mise en file.
--   outgoing-webhooks        webhook_delivery_logs.http_status
--                            → la colonne s'appelle `response_code` : le journal
--                              de livraison n'enregistrait pas le code réponse
--                              (corrigé côté code dans le même commit).
--   request-signature        electronic_signatures.provider, provider_signature_id,
--                            status, signers, initiated_at
--                            → la table ne porte que `signature_hash`/`signer_name` :
--                              la demande de signature n'était **jamais enregistrée**.
--   submit-e-invoice         invoices.e_invoice_status, e_invoice_platform,
--                            e_invoice_submitted_at, e_invoice_id
--                            → aucune colonne `e_invoice_*` : le dépôt était
--                              transmis à Chorus Pro puis oublié → **double envoi**.
--   sync-bank-transactions   bank_connections.provider_requisition_id, link_url,
--                            user_id ; bank_transactions.provider_transaction_id
--                            → la connexion ne se mémorisait pas et chaque
--                              synchronisation réimportait les mêmes opérations.
--   banking.ts               bank_transactions.matched_line_id
--                            → le pointage manuel ne marquait rien.
--   MobileApproval.tsx       leave_requests.manager_comment
--                            → le refus d'un congé depuis le mobile ne pouvait
--                              pas porter son motif.
--
-- LA RÈGLE, et pourquoi ce fichier ajoute des colonnes plutôt que de renommer le
-- code : une colonne n'est ajoutée que si la notion qu'elle porte **manque** au
-- schéma et qu'aucune colonne existante ne la porte. Là où un équivalent existe,
-- le code est aligné et **aucune** colonne n'est créée (`http_status` →
-- `response_code` ; `provider_requisition_id` → `provider_connection_id` ;
-- `link_url`/`user_id` → `metadata`).
--
-- Les deux colonnes qui portent une garantie d'idempotence naissent avec leur
-- garantie : `provider_transaction_id` est **unique par (société, compte)** —
-- sans quoi rejouer une synchronisation double les écritures — et
-- `matched_line_id` est une **clé composite** vers `journal_lines`, comme les
-- 408 clés de la 237 : elle ne peut pas pointer l'écriture d'une autre société.
-- ============================================================

-- ── 1. leave_requests.manager_comment — le refus porte son motif ──────────
-- (expense_reports l'avait déjà ; la demande de congé, non.)
ALTER TABLE public.leave_requests ADD COLUMN IF NOT EXISTS manager_comment text;

COMMENT ON COLUMN public.leave_requests.manager_comment IS
  '257 (W6) : motif de la décision du responsable (refus, notamment). Écrit par MobileApproval.tsx — la colonne manquait, le refus mobile ne pouvait rien écrire.';

-- ── 2. bank_transactions.matched_line_id — l'écriture que la ligne pointe ──
ALTER TABLE public.bank_transactions ADD COLUMN IF NOT EXISTS matched_line_id uuid;

DO $$ BEGIN
  ALTER TABLE public.bank_transactions
    ADD CONSTRAINT bank_transactions_matched_line_id_fkey
    FOREIGN KEY (tenant_id, matched_line_id)
    REFERENCES public.journal_lines (tenant_id, id)
    ON DELETE SET NULL (matched_line_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON COLUMN public.bank_transactions.matched_line_id IS
  '257 (W6) : ligne d''écriture pointée par le rapprochement manuel. Clé composite (société, ligne) — une société ne pointe pas l''écriture d''une autre.';

-- ── 3. bank_transactions.provider_transaction_id — la clé anti-doublon ────
ALTER TABLE public.bank_transactions ADD COLUMN IF NOT EXISTS provider_transaction_id text;

-- L'unicité est par (société, compte) : deux comptes différents peuvent porter
-- le même identifiant de fournisseur, mais rejouer une synchronisation sur le
-- même compte ne réimporte pas deux fois la même opération.
CREATE UNIQUE INDEX IF NOT EXISTS bank_transactions_provider_transaction_key
  ON public.bank_transactions (tenant_id, account_id, provider_transaction_id)
  WHERE provider_transaction_id IS NOT NULL;

COMMENT ON COLUMN public.bank_transactions.provider_transaction_id IS
  '257 (W6) : identifiant de l''opération chez l''agrégateur (GoCardless…). Unique par (société, compte) — rejouer une synchronisation ne double plus les lignes.';

-- ── 4. collection_reminders — la relance dit quand, combien, et si elle est partie ──
ALTER TABLE public.collection_reminders ADD COLUMN IF NOT EXISTS days_overdue integer;
ALTER TABLE public.collection_reminders ADD COLUMN IF NOT EXISTS sent_at timestamptz;
ALTER TABLE public.collection_reminders ADD COLUMN IF NOT EXISTS email_sent boolean DEFAULT false;
ALTER TABLE public.collection_reminders ADD COLUMN IF NOT EXISTS last_error text;

COMMENT ON COLUMN public.collection_reminders.sent_at IS
  '257 (W6) : horodatage réel de l''envoi. Sans lui, le cron ne pouvait pas savoir qu''il avait déjà relancé (`EF-01`, `EF-02`).';
COMMENT ON COLUMN public.collection_reminders.email_sent IS
  '257 (W6) : vrai seulement si Resend a accepté le message — la relance n''est plus comptée comme envoyée à tort.';

-- Les deux énumérations de la table n'admettaient pas ce que le cron écrit :
--   * `reminder_level` s'arrêtait à 3 → le niveau 4 (« procédure de
--     recouvrement », ≥ 60 jours) **ne pouvait pas être enregistré du tout** ;
--   * `status` n'admettait que draft/sent/paid/cancelled → un envoi **en cours**
--     (`pending`) et un envoi **en échec** (`failed`) étaient refusés, donc
--     perdus dans une erreur non lue.
ALTER TABLE public.collection_reminders DROP CONSTRAINT IF EXISTS collection_reminders_reminder_level_check;
ALTER TABLE public.collection_reminders ADD CONSTRAINT collection_reminders_reminder_level_check
  CHECK (reminder_level BETWEEN 1 AND 4);

ALTER TABLE public.collection_reminders DROP CONSTRAINT IF EXISTS collection_reminders_status_check;
ALTER TABLE public.collection_reminders ADD CONSTRAINT collection_reminders_status_check
  CHECK (status IN ('draft', 'pending', 'sent', 'paid', 'failed', 'cancelled'));

-- Une relance ne peut pas se dire envoyée sans l'heure à laquelle elle l'a été.
ALTER TABLE public.collection_reminders DROP CONSTRAINT IF EXISTS collection_reminders_email_sent_needs_date;
ALTER TABLE public.collection_reminders ADD CONSTRAINT collection_reminders_email_sent_needs_date
  CHECK (email_sent IS NOT TRUE OR sent_at IS NOT NULL);

-- ── 5. notification_email_queue.metadata — le contexte de la notification ──
ALTER TABLE public.notification_email_queue ADD COLUMN IF NOT EXISTS metadata jsonb;

COMMENT ON COLUMN public.notification_email_queue.metadata IS
  '257 (W6) : contexte de la notification (numéro de facture, identifiant Stripe, message d''erreur). La file ne pouvait pas le porter : l''échec de paiement Stripe n''était jamais mis en file.';

-- ── 6. electronic_signatures — la demande de signature est traçable ────────
ALTER TABLE public.electronic_signatures ADD COLUMN IF NOT EXISTS provider text;
ALTER TABLE public.electronic_signatures ADD COLUMN IF NOT EXISTS provider_signature_id text;
ALTER TABLE public.electronic_signatures ADD COLUMN IF NOT EXISTS status text;
ALTER TABLE public.electronic_signatures ADD COLUMN IF NOT EXISTS signers jsonb;
ALTER TABLE public.electronic_signatures ADD COLUMN IF NOT EXISTS initiated_at timestamptz;

-- Reprise des lignes antérieures : une signature déjà horodatée est « signed »,
-- une demande sans suite reste « pending ». Aucune ligne n'est effacée.
UPDATE public.electronic_signatures
   SET status = CASE WHEN signature_hash IS NOT NULL THEN 'signed' ELSE 'pending' END
 WHERE status IS NULL;

ALTER TABLE public.electronic_signatures ALTER COLUMN status SET DEFAULT 'pending';

ALTER TABLE public.electronic_signatures DROP CONSTRAINT IF EXISTS electronic_signatures_status_check;
ALTER TABLE public.electronic_signatures ADD CONSTRAINT electronic_signatures_status_check
  CHECK (status IN ('pending', 'signed', 'refused', 'expired', 'cancelled'));

CREATE UNIQUE INDEX IF NOT EXISTS electronic_signatures_provider_key
  ON public.electronic_signatures (tenant_id, provider, provider_signature_id)
  WHERE provider_signature_id IS NOT NULL;

COMMENT ON COLUMN public.electronic_signatures.provider_signature_id IS
  '257 (W6) : identifiant de la procédure chez le prestataire (Yousign). Unique par (société, prestataire) — la demande ne peut plus être enregistrée deux fois pour la même procédure.';

-- ── 7. invoices.e_invoice_* — le dépôt électronique laisse une trace ──────
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS e_invoice_status text;
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS e_invoice_platform text;
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS e_invoice_submitted_at timestamptz;
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS e_invoice_id text;

COMMENT ON COLUMN public.invoices.e_invoice_status IS
  '257 (W6) : état du dépôt électronique (Chorus Pro / PEPPOL). Sans cette trace, un second clic **retransmettait** la facture déjà déposée.';

CREATE UNIQUE INDEX IF NOT EXISTS invoices_e_invoice_id_key
  ON public.invoices (tenant_id, e_invoice_platform, e_invoice_id)
  WHERE e_invoice_id IS NOT NULL;
