// ============================================================
// W6 — « un jeton, une réponse » : le contrat d'entrée des 20 fonctions Edge
//
// Le plan correctif le demandait ainsi : « un test par fonction Edge, y compris
// **sans jeton** (le 401 doit être un refus, pas un silence) ». Ces tests
// **exécutent** chaque fonction (elle est importée, son gestionnaire est
// appelé) avec une requête sans identité, et vérifient qu'elle refuse — par un
// code explicite, pas en rendant `null`.
//
// Deux défauts réels sont tombés de ce harnais :
//   * `refresh-exchange-rates` lisait le jeton et **ne s'en servait pas** : un
//     appel anonyme déclenchait la mise à jour des taux (deux tests 401 rouges
//     avant le correctif : sans jeton, et avec un jeton étranger) ;
//   * `ai-import-mapping` **exige** un jeton, et le front n'en envoyait aucun :
//     le repli IA répondait 401, l'écran disait « IA indisponible ». Le test
//     « le fetch porte le jeton » est dans `app/src/lib/__tests__/edge-wiring.test.ts`.
//
// Lancer : `deno test --allow-env --import-map=…/import_map.json __tests__/`
// ============================================================

import { appeler, type Contrat } from "./stubs/harness.ts"

const CONTRATS_JETON: Contrat[] = [
  { fonction: "ai-import-mapping", corps: {}, attendu: 401, motif: /Token/i,
    raison: "exige un jeton : elle consomme la clé OpenAI de la société" },
  { fonction: "create-user", corps: {}, attendu: 401, motif: /Token/i,
    raison: "crée des comptes : jamais sans identité" },
  { fonction: "generate-pdf", corps: {}, attendu: 401, motif: /Token/i,
    raison: "la clé de service ne doit pas servir un anonyme" },
  { fonction: "ocr-invoice-import", corps: {}, attendu: 401, motif: /Token/i,
    raison: "OCR payant : appel nominatif" },
  { fonction: "parse-bank-statement", corps: {}, attendu: 401, motif: /Token/i,
    raison: "relève le texte d'un document : donnée du client" },
  { fonction: "request-signature", corps: {}, attendu: 401, motif: /Token/i,
    raison: "engage un prestataire payant (Yousign)" },
  { fonction: "send-notification-email", corps: {}, attendu: 401, motif: /Token/i,
    raison: "envoie un e-mail au nom de la société" },
  { fonction: "submit-e-invoice", corps: {}, attendu: 401, motif: /Token/i,
    raison: "dépose une facture chez un tiers (Chorus Pro / PEPPOL)" },
  { fonction: "submit-vat-return", corps: {}, attendu: 401, motif: /Token/i,
    raison: "télédéclare la TVA : l'acte le plus engageant du produit" },
  { fonction: "sync-bank-transactions", corps: {}, attendu: 401, motif: /Token/i,
    raison: "interroge la banque du client" },
  { fonction: "transmit-dsn", corps: {}, attendu: 401, motif: /Token/i,
    raison: "transmet une déclaration sociale" },
  { fonction: "validate-vat-vies", corps: {}, attendu: 401, motif: /Token/i,
    raison: "interroge VIES au nom de la société" },
  { fonction: "verify-iban", corps: {}, attendu: 401, motif: /Token/i,
    raison: "donnée bancaire d'un tiers" },
  { fonction: "verify-siret", corps: {}, attendu: 401, motif: /Token/i,
    raison: "interroge l'INSEE au nom de la société" },
]

// Points d'entrée SANS session utilisateur : chacun porte sa propre garde.
const CONTRATS_PUBLICS: Contrat[] = [
  { fonction: "cron-payment-reminders", corps: {}, attendu: 401, motif: /Non autorisé/i,
    raison: "cron : refuse sans l'en-tête `x-cron-secret`" },
  { fonction: "refresh-exchange-rates", corps: {}, attendu: 401, motif: /Jeton de service/i,
    raison: "cron : refuse sans la clé de service (elle lisait le jeton sans s'en servir)" },
  { fonction: "refresh-exchange-rates", corps: {}, entetes: { Authorization: "Bearer pas-la-cle" },
    attendu: 401, motif: /Jeton de service/i,
    raison: "cron : un jeton ÉTRANGER est refusé, pas seulement l'absence de jeton" },
  { fonction: "handle-stripe-webhook", corps: {}, attendu: 500, motif: /STRIPE_WEBHOOK_SECRET non configuré/i,
    raison: "Stripe : sans secret configuré, elle refuse de traiter quoi que ce soit" },
  { fonction: "handle-stripe-webhook", corps: {}, env: { STRIPE_WEBHOOK_SECRET: "whsec_de_test" },
    attendu: 400, motif: /[Ss]ignature/i,
    raison: "Stripe : secret configuré mais en-tête `stripe-signature` absent — refus nommé" },
  { fonction: "public-api", corps: {}, attendu: 401, motif: /X-API-Key/i,
    raison: "API publique : clé d'API exigée" },
  { fonction: "outgoing-webhooks", methode: "GET", attendu: 405, motif: /Method/i,
    raison: "seul POST est accepté" },
  { fonction: "auth-signup", corps: {}, attendu: 400, motif: /email|mot de passe|password|requis/i,
    raison: "public par nature : sans e-mail ni mot de passe, elle refuse" },
]

const CONTRATS: Contrat[] = [...CONTRATS_JETON, ...CONTRATS_PUBLICS]

for (const contrat of CONTRATS) {
  Deno.test(`${contrat.fonction} — sans identité, elle refuse (${contrat.attendu})`, async () => {
    const reponse = await appeler(contrat)
    const texte = await reponse.text()

    if (reponse.status !== contrat.attendu) {
      throw new Error(
        `${contrat.fonction} : attendu ${contrat.attendu} (${contrat.raison}), ` +
        `reçu ${reponse.status} — ${texte.slice(0, 200)}`,
      )
    }
    if (!contrat.motif.test(texte)) {
      throw new Error(
        `${contrat.fonction} : refus sans motif lisible (${contrat.motif}) — ${texte.slice(0, 200)}`,
      )
    }
  })
}
