// @ts-nocheck — Deno shared module for Supabase Edge Functions

// ============================================
// SHARED EMAIL SENDER (Resend API)
// Used by: create-user (invitations), send-notification-email (notifications)
// ============================================

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") || ""
const RESEND_FROM = Deno.env.get("RESEND_FROM") || "Onusuite <notifications@onusuite.com>"

interface SendEmailParams {
  to: string
  subject: string
  html: string
  replyTo?: string
}

export async function sendEmailViaResend(params: SendEmailParams): Promise<{ success: boolean; id?: string; error?: string }> {
  if (!RESEND_API_KEY) {
    console.error("RESEND_API_KEY not configured")
    return { success: false, error: "Service email non configuré" }
  }

  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: RESEND_FROM,
        to: params.to,
        subject: params.subject,
        html: params.html,
        reply_to: params.replyTo || "no-reply@onusuite.com",
      }),
    })

    if (!response.ok) {
      const errText = await response.text()
      console.error("Resend API error:", errText)
      return { success: false, error: errText }
    }

    const result = await response.json()
    return { success: true, id: result.id }
  } catch (err) {
    console.error("sendEmailViaResend error:", err)
    return { success: false, error: String(err) }
  }
}

// ============================================
// SHARED EMAIL TEMPLATES (trilingual fr/en/ar)
// ============================================

interface EmailTemplateData {
  locale: string
  tenantName: string
  title: string
  message: string
  actionUrl?: string | null
  actionLabel?: string
}

export function buildEmailTemplate(data: EmailTemplateData): { subject: string; html: string } {
  const lang = ["fr", "en", "ar"].includes(data.locale) ? data.locale : "en"
  const dir = lang === "ar" ? "rtl" : "ltr"
  const appName = "Onusuite"

  const translations: Record<string, { greeting: string; cta: string; footer: string }> = {
    fr: {
      greeting: "Bonjour,",
      cta: data.actionLabel || "Voir dans l'application",
      footer: `Ceci est un message automatique de ${appName}. ${data.tenantName}`,
    },
    en: {
      greeting: "Hello,",
      cta: data.actionLabel || "View in application",
      footer: `This is an automated message from ${appName}. ${data.tenantName}`,
    },
    ar: {
      greeting: "مرحباً،",
      cta: data.actionLabel || "عرض في التطبيق",
      footer: `هذه رسالة تلقائية من ${appName}. ${data.tenantName}`,
    },
  }

  const tr = translations[lang]

  const button = data.actionUrl
    ? `<a href="${data.actionUrl}" style="display:inline-block;padding:12px 24px;background:#C44536;color:#fff;text-decoration:none;border-radius:6px;font-weight:600;margin-top:16px">${tr.cta}</a>`
    : ""

  const html = `<!DOCTYPE html>
<html lang="${lang}" dir="${dir}">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;font-family:system-ui,-apple-system,sans-serif;background:#F5F0E8;color:#1E2A4A">
  <div style="max-width:600px;margin:0 auto;padding:24px">
    <div style="background:#fff;border-radius:12px;padding:32px;box-shadow:0 1px 3px rgba(0,0,0,0.08)">
      <div style="font-size:20px;font-weight:700;color:#C44536;margin-bottom:8px">${appName}</div>
      <p style="color:#1E2A4A;margin:0 0 16px">${tr.greeting}</p>
      <h2 style="font-size:18px;font-weight:600;color:#1E2A4A;margin:0 0 12px">${data.title}</h2>
      <p style="font-size:14px;color:#4A5568;line-height:1.6;margin:0 0 16px">${data.message}</p>
      ${button}
    </div>
    <p style="font-size:12px;color:#A0AEC0;text-align:center;margin-top:24px">${tr.footer}</p>
  </div>
</body>
</html>`

  return { subject: `[${appName}] ${data.title}`, html }
}

// ============================================
// INVITATION EMAIL TEMPLATE
// ============================================

interface InvitationEmailData {
  email: string
  name: string
  tenantName: string
  locale: string
  magicLinkUrl: string
  isReinvitation?: boolean
  inviterName?: string
  role?: string
  modules?: string
}

export function buildInvitationEmail(data: InvitationEmailData): { subject: string; html: string } {
  const lang = ["fr", "en", "ar"].includes(data.locale) ? data.locale : "en"
  const dir = lang === "ar" ? "rtl" : "ltr"
  const appName = "Onusuite"

  const inviterIntro = data.inviterName
    ? { fr: `${data.inviterName} vous invite à collaborer sur`, en: `${data.inviterName} invites you to collaborate on`, ar: `${data.inviterName} يدعوك للتعاون على` }
    : { fr: `Vous êtes invité à rejoindre`, en: `You are invited to join`, ar: `أنت مدعو للانضمام إلى` }

  const roleLine = data.role
    ? { fr: `En tant que <strong>${data.role}</strong>`, en: `As a <strong>${data.role}</strong>`, ar: `بصفتك <strong>${data.role}</strong>` }
    : { fr: ``, en: ``, ar: `` }

  const modulesLine = data.modules
    ? { fr: `Vous aurez accès à : ${data.modules}`, en: `You will have access to: ${data.modules}`, ar: `سيكون لديك حق الوصول إلى: ${data.modules}` }
    : { fr: ``, en: ``, ar: `` }

  const templates: Record<string, { subject: string; greeting: string; title: string; message: string; cta: string; footer: string }> = {
    fr: {
      subject: `Bienvenue sur ${appName} — ${data.tenantName} vous invite`,
      greeting: `Bonjour ${data.name},`,
      title: `Bienvenue dans l'équipe ${data.tenantName} !`,
      message: data.isReinvitation
        ? `${inviterIntro.fr} ${appName}, la plateforme unifiée de gestion d'entreprise. ${roleLine.fr}. ${modulesLine.fr}<br><br>Cliquez ci-dessous pour activer votre compte — cela prend moins d'une minute.`
        : `${inviterIntro.fr} ${appName}, la plateforme unifiée de gestion d'entreprise. ${roleLine.fr}. ${modulesLine.fr}<br><br>Cliquez ci-dessous pour activer votre compte — cela prend moins d'une minute.`,
      cta: "Activer mon compte",
      footer: `À très vite sur ${appName} ! — The Unified Business Suite`,
    },
    en: {
      subject: `Welcome to ${appName} — ${data.tenantName} invites you`,
      greeting: `Hello ${data.name},`,
      title: `Welcome to the ${data.tenantName} team!`,
      message: data.isReinvitation
        ? `${inviterIntro.en} ${appName}, the unified business management platform. ${roleLine.en}. ${modulesLine.en}<br><br>Click below to activate your account — it takes less than a minute.`
        : `${inviterIntro.en} ${appName}, the unified business management platform. ${roleLine.en}. ${modulesLine.en}<br><br>Click below to activate your account — it takes less than a minute.`,
      cta: "Activate my account",
      footer: `See you soon on ${appName}! — The Unified Business Suite`,
    },
    ar: {
      subject: `مرحباً بك في ${appName} — ${data.tenantName} يدعوك`,
      greeting: `مرحباً ${data.name}،`,
      title: `مرحباً بك في فريق ${data.tenantName}!`,
      message: data.isReinvitation
        ? `${inviterIntro.ar} ${appName}، المنصة الموحدة لإدارة الأعمال. ${roleLine.ar}. ${modulesLine.ar}<br><br>انقر أدناه لتفعيل حسابك — يستغرق أقل من دقيقة.`
        : `${inviterIntro.ar} ${appName}، المنصة الموحدة لإدارة الأعمال. ${roleLine.ar}. ${modulesLine.ar}<br><br>انقر أدناه لتفعيل حسابك — يستغرق أقل من دقيقة.`,
      cta: "تفعيل حسابي",
      footer: `نراك قريباً على ${appName}! — المنصة الموحدة للأعمال`,
    },
  }

  const tr = templates[lang]

  const html = `<!DOCTYPE html>
<html lang="${lang}" dir="${dir}">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;font-family:system-ui,-apple-system,sans-serif;background:#F5F0E8;color:#1E2A4A">
  <div style="max-width:600px;margin:0 auto;padding:24px">
    <div style="background:#fff;border-radius:12px;padding:32px;box-shadow:0 1px 3px rgba(0,0,0,0.08)">
      <div style="font-size:20px;font-weight:700;color:#C44536;margin-bottom:8px">${appName}</div>
      <p style="color:#1E2A4A;margin:0 0 16px">${tr.greeting}</p>
      <h2 style="font-size:18px;font-weight:600;color:#1E2A4A;margin:0 0 12px">${tr.title}</h2>
      <p style="font-size:14px;color:#4A5568;line-height:1.6;margin:0 0 16px">${tr.message}</p>
      <a href="${data.magicLinkUrl}" style="display:inline-block;padding:14px 28px;background:#C44536;color:#fff;text-decoration:none;border-radius:6px;font-weight:600;margin-top:16px;font-size:16px">${tr.cta}</a>
      <p style="font-size:12px;color:#A0AEC0;margin-top:24px;line-height:1.5">
        ${tr.footer}
      </p>
    </div>
  </div>
</body>
</html>`

  return { subject: tr.subject, html }
}

// ============================================
// SIGNUP CONFIRMATION EMAIL TEMPLATE
// ============================================

interface SignupConfirmationEmailData {
  email: string
  name: string
  locale: string
  confirmationUrl: string
}

export function buildSignupConfirmationEmail(data: SignupConfirmationEmailData): { subject: string; html: string } {
  const lang = ["fr", "en", "ar"].includes(data.locale) ? data.locale : "en"
  const dir = lang === "ar" ? "rtl" : "ltr"
  const appName = "Onusuite"

  const templates: Record<string, { subject: string; greeting: string; title: string; message: string; cta: string; footer: string }> = {
    fr: {
      subject: `Bienvenue sur ${appName} — Confirmez votre compte`,
      greeting: `Bonjour ${data.name},`,
      title: `Bienvenue sur ${appName} !`,
      message: `${appName} est la plateforme unifiée de gestion d'entreprise : comptabilité, commercial, RH/paie, trésorerie, stock, production — 17 modules dans une seule application, trilingue (français, anglais, arabe).<br><br>Vous y êtes presque. Cliquez ci-dessous pour confirmer votre adresse email et créer l'espace de votre entreprise.`,
      cta: "Confirmer mon compte",
      footer: `Ce lien expire dans 24 heures. Si vous n'avez pas créé de compte, vous pouvez ignorer cet email.<br>${appName} — The Unified Business Suite`,
    },
    en: {
      subject: `Welcome to ${appName} — Confirm your account`,
      greeting: `Hello ${data.name},`,
      title: `Welcome to ${appName}!`,
      message: `${appName} is the unified business management platform: accounting, sales, HR/payroll, treasury, inventory, production — 17 modules in a single application, trilingual (French, English, Arabic).<br><br>You're almost there. Click below to confirm your email address and set up your company workspace.`,
      cta: "Confirm my account",
      footer: `This link expires in 24 hours. If you didn't create an account, you can ignore this email.<br>${appName} — The Unified Business Suite`,
    },
    ar: {
      subject: `مرحباً بك في ${appName} — أكّد حسابك`,
      greeting: `مرحباً ${data.name}،`,
      title: `مرحباً بك في ${appName}!`,
      message: `${appName} هي المنصة الموحدة لإدارة الأعمال: محاسبة، مبيعات، موارد بشرية/رواتب، خزانة، مخزون، إنتاج — 17 وحدة في تطبيق واحد، ثلاثية اللغة (فرنسية، إنجليزية، عربية).<br><br>أنت على بعد خطوة واحدة. انقر أدناه لتأكيد عنوان بريدك الإلكتروني وإنشاء مساحة عمل شركتك.`,
      cta: "تأكيد حسابي",
      footer: `هذا الرابط ينتهي خلال 24 ساعة. إذا لم تقم بإنشاء حساب، يمكنك تجاهل هذا البريد.<br>${appName} — المنصة الموحدة للأعمال`,
    },
  }

  const tr = templates[lang]

  const html = `<!DOCTYPE html>
<html lang="${lang}" dir="${dir}">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;font-family:system-ui,-apple-system,sans-serif;background:#F5F0E8;color:#1E2A4A">
  <div style="max-width:600px;margin:0 auto;padding:24px">
    <div style="background:#fff;border-radius:12px;padding:32px;box-shadow:0 1px 3px rgba(0,0,0,0.08)">
      <div style="font-size:20px;font-weight:700;color:#C44536;margin-bottom:8px">${appName}</div>
      <p style="color:#1E2A4A;margin:0 0 16px">${tr.greeting}</p>
      <h2 style="font-size:18px;font-weight:600;color:#1E2A4A;margin:0 0 12px">${tr.title}</h2>
      <p style="font-size:14px;color:#4A5568;line-height:1.6;margin:0 0 16px">${tr.message}</p>
      <a href="${data.confirmationUrl}" style="display:inline-block;padding:14px 28px;background:#C44536;color:#fff;text-decoration:none;border-radius:6px;font-weight:600;margin-top:16px;font-size:16px">${tr.cta}</a>
      <p style="font-size:12px;color:#A0AEC0;margin-top:24px;line-height:1.5">
        ${tr.footer}
      </p>
    </div>
  </div>
</body>
</html>`

  return { subject: tr.subject, html }
}
