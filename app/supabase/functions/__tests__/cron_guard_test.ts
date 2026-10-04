// ============================================================
// W6 — la garde du cron des taux de change : ce qui est accepté, ce qui ne
// l'est pas.
//
// La fonction `refresh-exchange-rates` lisait le jeton **sans jamais le
// comparer** : un appel anonyme déclenchait la mise à jour des taux (appels
// externes + écritures en base). Elle accepte désormais deux identités :
//   * la clé de service (`Authorization: Bearer …`) — ce que le job pg_cron
//     `refresh-exchange-rates-daily` envoie déjà ;
//   * le secret de cron (`x-cron-secret`, le même que `cron-payment-reminders`).
//
// Ce dernier cas est vérifié ici et non dans le tableau des contrats : au-delà
// de la garde, la fonction appelle l'API BCE puis écrit — ce qui n'a pas sa
// place dans un test d'entrée. Ce qui est prouvé ici, c'est que **la garde
// ouvre** avec le bon secret (elle ne répond pas 401).
// ============================================================

import { appeler } from "./stubs/harness.ts"

Deno.test("refresh-exchange-rates — le secret de cron est accepté (la garde ouvre, elle ne répond pas 401)", async () => {
  // L'appel dépasse la garde : l'API BCE n'est pas joignable sans réseau, la
  // fonction le dira elle-même (500 « erreur interne »). Le contrat tenu ici est
  // celui de l'ENTRÉE : le jeton est reconnu.
  const reponse = await appeler({
    fonction: "refresh-exchange-rates",
    corps: {},
    entetes: { "x-cron-secret": "cron-de-test" },
    attendu: 0,
    motif: /./,
    raison: "garde d'entrée",
  })
  const texte = await reponse.text()
  if (reponse.status === 401) {
    throw new Error(`le secret de cron doit être accepté — reçu 401 : ${texte.slice(0, 200)}`)
  }
  if (/Jeton de service requis/i.test(texte)) {
    throw new Error(`la garde a refusé le secret de cron : ${texte.slice(0, 200)}`)
  }
})

Deno.test("refresh-exchange-rates — la clé de service est acceptée (celle du job pg_cron)", async () => {
  const reponse = await appeler({
    fonction: "refresh-exchange-rates",
    corps: {},
    entetes: { Authorization: "Bearer service-de-test" },
    attendu: 0,
    motif: /./,
    raison: "garde d'entrée",
  })
  const texte = await reponse.text()
  if (reponse.status === 401) {
    throw new Error(`la clé de service doit être acceptée — reçu 401 : ${texte.slice(0, 200)}`)
  }
})
