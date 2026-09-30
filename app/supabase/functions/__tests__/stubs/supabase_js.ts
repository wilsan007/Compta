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
const LIGNE_NEUTRE = { id: "stub", tenant_id: "00000000-0000-0000-0000-0000000000aa" }
const RESULTAT_NEUTRE = { data: Object.assign([LIGNE_NEUTRE], LIGNE_NEUTRE), error: null }


function chaine(): any {
  const cible = function () {}
  const proxy: any = new Proxy(cible, {
    get(_t, prop) {
      if (prop === "then") {
        return (resolve: (v: unknown) => unknown) => Promise.resolve(RESULTAT_NEUTRE).then(resolve)
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
      if (prop === "rpc") return () => chaine()
      return () => chaine()
    },
  })
}
