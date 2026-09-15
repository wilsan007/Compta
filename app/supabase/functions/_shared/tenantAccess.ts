// @ts-nocheck — Deno Edge Function
// Contrôle d'appartenance au tenant pour les fonctions qui utilisent la clé service.
// La clé service contourne la RLS : tout identifiant ou tenant_id reçu du client
// doit être rattaché à un tenant dont l'appelant est membre actif, sinon IDOR.

export function forbidden(corsHeaders: Record<string, string>) {
  return new Response(JSON.stringify({ error: "Accès refusé à cette ressource" }), {
    status: 403,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

/** Vrai si l'utilisateur est membre actif du tenant. */
export async function isTenantMember(admin: any, authId: string, tenantId: string | null | undefined): Promise<boolean> {
  if (!authId || !tenantId) return false
  const { data, error } = await admin
    .from("tenant_users")
    .select("id")
    .eq("auth_id", authId)
    .eq("tenant_id", tenantId)
    .eq("status", "active")
    .limit(1)
  if (error) {
    console.error("isTenantMember:", error)
    return false
  }
  return Array.isArray(data) && data.length > 0
}
