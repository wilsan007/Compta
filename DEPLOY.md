# Onusuite — Guide de déploiement

## Stack complète

| Service | Rôle | Prix/mo |
|---------|------|---------|
| Cloudflare Pages | Hébergement frontend (React/Vite) | $0 |
| Supabase Pro | Backend: PostgreSQL + Auth + RLS + Storage + Realtime + Edge Functions | $25 |
| Zoho Mail Free | Boîtes email professionnelles (5 users, 5 Go chacune) | $0 |
| Resend | Email transactionnel (password reset, notifications, reçus) | $0 → $20 |
| Cloudflare Registrar | Nom de domaine | $9.15/an |
| Cloudflare R2 | Stockage de fichiers (factures, pièces jointes) | $0.015/Go |
| **Total startup** | | **~$26/mo** |

---

## 1. Cloudflare Pages (frontend)

### Installation

```bash
npm install -g wrangler
wrangler login
```

### Build et déploiement

```bash
cd app
npm run build
wrangler pages deploy dist --project-name=onusuite
```

### Configuration automatique (Git integration)

1. Aller sur https://dash.cloudflare.com → Workers & Pages → Create application → Pages
2. Connecter le repo Git
3. Configuration build:
   - **Framework preset**: Vite
   - **Build command**: `npm run build`
   - **Build output directory**: `dist`
   - **Root directory**: `app`
4. Variables d'environnement (Settings → Environment variables):
   - `VITE_SUPABASE_URL` = votre URL Supabase
   - `VITE_SUPABASE_PUBLISHABLE_KEY` = votre clé publique Supabase
   - `VITE_RESEND_API_KEY` = votre clé API Resend
   - `VITE_R2_PUBLIC_URL` = votre URL publique R2

### Fichiers de config déjà en place

- `wrangler.jsonc` — Configuration Cloudflare Pages (SPA mode, observability)
- `public/_headers` — Headers de sécurité (CSP, HSTS, X-Frame-Options, etc.)
- `public/_redirects` — Redirections SPA + blocage fichiers sensibles

---

## 2. Supabase Pro (backend)

### Étapes

1. Créer un projet sur https://supabase.com
2. Upgrader en Pro ($25/mo): Settings → Billing → Upgrade
3. Récupérer les clés:
   - Project Settings → API → `Project URL`
   - Project Settings → API → `anon public key`
4. Configurer le SMTP pour Resend (voir section 4)
5. Appliquer les migrations SQL:
   ```bash
   cd app
   node run-sql-migrations.mjs
   ```

### Configuration RLS (multi-tenant)

Toutes les tables doivent avoir des policies RLS avec `tenant_id`. Vérifier avec:
```sql
SELECT tablename, policyname, cmd, qual FROM pg_policies WHERE schemaname = 'public';
```

---

## 3. Zoho Mail Free (boîtes email)

### Étapes

1. Aller sur https://www.zoho.com/mail/ → Sign up → Forever Free Plan
2. Ajouter votre domaine `onusuite.com`
3. Vérifier le domaine (ajouter les enregistrements DNS TXT/MX)
4. Créer jusqu'à 5 boîtes: `info@onusuite.com`, `support@onusuite.com`, etc.
5. ⚠️ Le plan gratuit est **webmail uniquement** (pas d'IMAP/POP)
6. Pour IMAP/POP (Outlook, Apple Mail): upgrader vers Mail Lite ($1/user/mo)

### Limites du plan gratuit
- 5 utilisateurs maximum
- 5 Go par boîte
- 30 Mo max par pièce jointe
- Webmail ou app mobile Zoho uniquement

---

## 4. Resend (email transactionnel)

### Pourquoi c'est obligatoire

Supabase envoie des emails d'authentification par défaut, mais ils sont **limités à 3-4 emails/heure**. En production, il faut un service externe.

### Étapes

1. Créer un compte sur https://resend.com
2. Ajouter et vérifier votre domaine (DNS: SPF + DKIM)
3. Récupérer l'API key
4. Configurer Supabase pour utiliser Resend:
   - Supabase Dashboard → Authentication → SMTP Settings
   - Activer "Custom SMTP"
   - Host: `smtp.resend.com`
   - Port: `465`
   - Username: `resend`
   - Password: `your_resend_api_key`
   - Sender email: `noreply@onusuite.com`
   - Minimum interval: `0`

### Tarification Resend
- **Gratuit**: 3,000 emails/mois
- **$20/mois**: 50,000 emails/mois
- **$200/mois**: 1,000,000 emails/mois

---

## 5. Cloudflare Registrar (nom de domaine)

### Étapes

1. Aller sur https://dash.cloudflare.com → Registrar → Register Domain
2. Chercher `onusuite.com`
3. Prix: ~$9.15/an (prix coûtant, sans markup)
4. Activer l'auto-renew

### Si le domaine est déjà ailleurs (GoDaddy, etc.)

1. Déverrouiller le transfert chez le registrar actuel
2. Récupérer l'EPP code (auth code)
3. Cloudflare Registrar → Transfer → entrer le code
4. Attendre 5-7 jours pour le transfert
5. Économie: ~$12/an vs GoDaddy

---

## 6. Cloudflare R2 (stockage de fichiers)

### Étapes

1. https://dash.cloudflare.com → R2 → Create bucket
2. Nom: `onusuite-files`
3. Activer l'accès public: Settings → Public access → R2.dev subdomain
4. Récupérer les credentials:
   - R2 → Manage R2 API Tokens → Create API token
   - Permissions: Object Read & Write
5. Ajouter au `.env`:
   - `R2_ACCOUNT_ID` = votre account ID
   - `R2_ACCESS_KEY_ID` = access key
   - `R2_SECRET_ACCESS_KEY` = secret key
   - `R2_BUCKET_NAME` = onusuite-files
   - `VITE_R2_PUBLIC_URL` = https://pub-xxxxx.r2.dev

### Tarification R2
- 10 Go gratuits
- $0.015/Go/mois au-delà
- **Egress (téléchargement): $0** (gratuit, contrairement à AWS S3)

---

## 7. DNS Cloudflare

### Enregistrements DNS à configurer

| Type | Nom | Valeur | Note |
|------|-----|--------|------|
| A | `@` | IP Cloudflare Pages | Auto-configuré |
| CNAME | `www` | `onusuite.pages.dev` | |
| MX | `@` | `mx.zoho.com` (priorité 10) | Email Zoho |
| MX | `@` | `mx2.zoho.com` (priorité 20) | Email Zoho |
| TXT | `@` | `v=spf1 include:zoho.com include:resend.com ~all` | SPF (email) |
| TXT | `_dmarc` | `v=DMARC1; p=quarantine; rua=mailto:admin@onusuite.com` | DMARC |
| CNAME | `resend._domainkey` | (fourni par Resend) | DKIM Resend |

---

## Checklist de déploiement

- [ ] Cloudflare Pages: projet créé et connecté au repo Git
- [ ] Variables d'environnement configurées dans Cloudflare Pages
- [ ] Supabase Pro: projet créé et upgradé
- [ ] Supabase: migrations SQL appliquées
- [ ] Supabase: SMTP Resend configuré
- [ ] Supabase: RLS policies activées sur toutes les tables
- [ ] Zoho Mail: domaine vérifié et boîtes créées
- [ ] Resend: domaine vérifié (SPF + DKIM)
- [ ] Cloudflare Registrar: domaine enregistré ou transféré
- [ ] Cloudflare R2: bucket créé et credentials récupérés
- [ ] DNS: tous les enregistrements configurés (A, MX, TXT, DKIM)
- [ ] Build de test: `npm run build` réussit
- [ ] Déploiement: `wrangler pages deploy dist` réussit
- [ ] Test: site accessible sur le domaine personnalisé
- [ ] Test: inscription utilisateur reçoit l'email de confirmation
- [ ] Test: reset password reçoit l'email

---

## Coût mensuel estimé

| Phase | Users | Coût/mo |
|-------|-------|---------|
| **Startup** (0-100 users) | < 100 MAU | ~$26 (Supabase Pro + domaine) |
| **Early growth** (100-1K) | < 1K MAU | ~$26-46 (+ Resend si >3K emails) |
| **Growth** (1K-10K) | 1K-10K MAU | ~$46-80 (+ Resend + R2 storage) |
| **Scale** (10K-100K) | 10K-100K MAU | ~$80-300 (Supabase compute upgrade) |

Pas de renouvellement surprise. Pas de coût par siège. Pas de prix d'appel.
