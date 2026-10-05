// ============================================================
// W6 — stub du client Supabase pour les tests d'entrée.
//
// Le contrat vérifié est l'ENTRÉE : aucune requête ne doit partir. Tout ce qui
// dépasserait le contrôle d'entrée est donc simulé, jamais exécuté :
//   * `auth.getUser()` rend l'utilisateur posé par le test (`__stubUser`), ou
//     une erreur quand aucun n'est posé ;
//   * toute autre chaîne (`from(...).select()...`) est « thenable » et rend une
//     ligne neutre, ce qui suffit aux lectures de garde.
// ============================================================

// PostgREST rend DEUX formes selon l'appel :
//   • `.select()` / `.limit()`        → un TABLEAU de lignes ;
//   • `.single()` / `.maybeSingle()`  → une LIGNE.
// Le harnais n'a qu'un résultat neutre : il rend donc un TABLEAU qui porte AUSSI
// les champs de la ligne. Les appelants qui lisent `data[0]` ou
// `Array.isArray(data)` — comme `isTenantMember` — trouvent le tableau ; ceux
// qui lisent `doc.tenant_id` après `maybeSingle()` — comme `generate-pdf` —
// trouvent le champ. Sans ce champ, toute fonction qui vérifie l'appartenance
// AVANT d'agir s'arrêtait sur `forbidden()` (403), et le chemin situé derrière
// n'était jamais atteint : ni exécuté, ni testable.
//
// Un test peut COMPLÉTER cette ligne (`globalThis.__stubLigne`) : un rôle pour
// passer une garde de rôle, `ocr_consent` pour la garde de consentement (D-5).
// Sans complément, la ligne n'a ni rôle ni consentement — le cas qui refuse.
const LIGNE_NEUTRE = { id: "stub", tenant_id: "00000000-0000-0000-0000-0000000000aa" }
function resultatNeutre() {
  const ligne = { ...LIGNE_NEUTRE, ...((globalThis as any).__stubLigne || {}) }
  return { data: Object.assign([ligne], ligne), error: null }
}

// Un test peut répondre À LA PLACE d'une RPC (`globalThis.__stubRpc`) : la
// clé est le NOM de la fonction, la valeur est le `{ data, error }` rendu.
// Sans entrée pour ce nom, le résultat neutre est rendu — le comportement de
// tous les tests existants (W6) est inchangé.
//
// C'est le crochet qui rend « clé révoquée → 401 » testable (ORPH-01/SEC-02,
// 700) : la vérité du cycle de vie d'une clé vit dans la base
// (`authenticate_api_key`), et le test Edge n'a ni base ni réseau — il pose
// le VERDICT de la base et prouve que public-api l'OBÉIT.
function rpcResultat(nom: string) {
  const perso = (globalThis as any).__stubRpc
  if (perso && Object.prototype.hasOwnProperty.call(perso, nom)) return perso[nom]
  return resultatNeutre()
}


function chaine(nomRpc?: string): any {
  const cible = function () {}
  const proxy: any = new Proxy(cible, {
    get(_t, prop) {
      if (prop === "then") {
        const valeur = nomRpc === undefined ? resultatNeutre() : rpcResultat(nomRpc)
        return (resolve: (v: unknown) => unknown) => Promise.resolve(valeur).then(resolve)
      }
      if (prop === "auth") {
        return {
          getUser: async () => {
            const u = (globalThis as any).__stubUser
            return u ? { data: { user: u }, error: null } : { data: { user: null }, error: new Error("anon") }
          },
        }
      }
      if (prop === "storage") {
        return {
          from: () => ({
            upload: async () => ({ error: null }),
            createSignedUrl: async () => ({ data: { signedUrl: "https://exemple.test/pdf" }, error: null }),
          }),
        }
      }
      return () => proxy
    },
    apply() {
      return proxy
    },
  })
  return proxy
}

export function createClient(..._args: unknown[]): any {
  return new Proxy({}, {
    get(_t, prop) {
      if (prop === "auth") return chaine().auth
      if (prop === "storage") return chaine().storage
      if (prop === "rpc") return (nom: string) => chaine(nom)
      return () => chaine()
    },
  })
}
