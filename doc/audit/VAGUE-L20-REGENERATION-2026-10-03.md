# L20 — régénération généralisée, **tranche 1 : le retour arrière**

> Date : **2026-10-03**. Migration **`422`** · suite **`422`** (**8 scénarios**)
> · branche `partie-5-integrite-chainages`.
> Lot **L20** du plan (phase F, ≈ 5 j), innovation **M-04**.

## 1. Ce que le plan demande, mot pour mot

> **M-04 — Régénération plutôt que correction.** *Pennylane : changer le
> compte d'une transaction lettrée **supprime et recrée** l'écriture.*
> Tout effet paramétrique (comptes, taux, diviseurs, seuils) se **régénère** ;
> on ne corrige jamais une ligne à la main. Régénération **en cascade** :
> changer un taux ou un prix de revient régénère l'écriture **et** les
> couches **et** la facture liée, avec **historique**.
> Livrables : `chain_regenerate(type, id)` + `chain_regeneration_log`.

La seconde moitié — **« avec historique »** — avait été **anticipée** par le
socle. La troisième — **« possibilité de revenir à la version précédente »** —
n'existait pas. C'est ce que la 422 livre.

## 2. Mesuré avant

Sur la base du jour, avant la 422 :

| Objet | État mesuré |
|---|---|
| `chain_regeneration_log` | **existe** (252), 9 colonnes dont `avant` / `apres` — **2 lignes**, celles de sa propre suite T13 |
| `chain_regenerate(...)` | **existe** (252) : photographie, journalise, émet `chain.regenerated`. **Ne régénère rien** — `apres` est un argument |
| Appelants de `chain_regenerate` | **0** (`grep src/`, `grep supabase/functions/`) |
| **Rollback / revert / annulation** | **ZÉRO** fonction |

**Le défaut, formulé** : on peut régénérer, l'historique s'écrit — et on ne peut
pas revenir. Or c'est la moitié qui **protège** : sans retour possible, une
régénération est un *aller simple*, c'est-à-dire une décision irréversible
habillée en édition. Le `avant` que la 252 écrit depuis trois semaines était
une donnée que personne ne pouvait atteindre.

## 3. Ce que la 422 livre

`chain_regeneration_rollback(p_tenant, p_regeneration_id, p_attendu)` :
restaure les payloads `avant` dans `document_links`, journalise son propre
retour (donc **réversible lui-même**) et émet `chain.regeneration_reverted`.

### Le conflit est le cœur du lot

`chain_regenerate` reçoit `apres` **de l'appelant** : la suite 252 T13 passe
`{"prix": 12}` pendant que le lien vivant porte encore `{"prix": 10}`. `apres`
est donc une **déclaration**, pas un constat. On ne peut pas s'en servir pour
détecter que l'état a bougé — et **on ne le change pas ici** : ce contrat
## 4. La porte G4 a trouvé un vrai défaut — et elle avait raison

Au premier essai, la fonction était `SECURITY DEFINER`, exposée à
`authenticated`, et **`p_tenant` venait du client sans vérification**.
G4 l'a refusée : *« sans garde de société »*. Ce n'était pas une formalité :
un utilisateur connecté aurait pu passer l'identifiant d'une autre société et
faire revenir **son** état — c'est-à-dire écrire chez un autre. La garde 1b
compare `current_tenant_id()` à `p_tenant` ; un contexte nul (service_role,
pg_cron, migration) passe, ce qui est dit dans la migration.

> ⚠️ **Et le même défaut est probablement dans `chain_regenerate`**, que je
> n'ai pas touché : c'est le socle, et sa suite T13 fige son contrat. Voir §6.

## 5. Preuve

Suite **`422`**, **8/8** :

| # | Scénario | Ce qu'il interdit |
|---|---|---|
| T01 | le retour **restaure** l'état précédent | que « historique » reste une impasse |
| T02 | sans société → refus | un retour sans garantie de cloisonnement |
| T03 | id inconnu / **autre société** → refus nommé | qu'une société en fasse revenir une autre |
| **T04** | **CONFLIT** → refus, **rien n'est détruit** | d'écraser un travail plus récent |
| T05 | le retour **se journalise** + son événement | qu'un retour invisible soit rejoué |
| T06 | **second** retour → refus | le double effet (idempotence = refus, pas no-op) |
| T07 | lien **rompu** non ressuscité | confondre *revenir* et *réparer* |
| T08 | l'historique se **relit** (avant/après/cause) | qu'il existe sans être consultable |

**Mesures** : **838 verdicts verts, 0 rouge** sur l'ensemble des suites ·
`plpgsql_check` **0 erreur, 0 avertissement** · **G4 verte** (113 fonctions) ·
G1/G2/G5 vertes (**G5 110/110**) · migration **rejouable** · **8/8 également
sur base neuve**.

**Le test rouge a été pris avant la migration** :
`function chain_regeneration_rollback(uuid, bigint, jsonb) does not exist`.

### La preuve est autonome

La première version empruntait `_p5_doc`, le helper privé de la **suite 252**.
Elle a été réécrite avec son propre décor — une preuve qui dépend du décor
d'une autre preuve cesse d'en être une le jour où cette autre change. Vérifié
en supprimant `_p5_doc` de la base : **8/8 quand même**.

## 6. Limites dites

1. **La régénération en cascade n'est PAS livrée.** La 422 fait la moitié
   « revenir ». Faire *régénérer* réellement — changer un taux et voir
   l'écriture, les couches et la facture se refaire — est la **tranche 2**,
   et c'est le gros du lot.
2. **`chain_regenerate` a probablement le même défaut de garde que la 422 avait**
   (252, `SECURITY DEFINER`, `p_tenant` du client). Je ne l'ai pas touché : sa
   suite T13 fige son contrat, et le corriger relèverait du socle. **À trancher.**
3. **Deux messages distincts révèlent l'existence d'une ligne dans une autre
   société** (id `bigserial` global). Assumé et écrit dans la migration : la
   séquence est déjà globale et séquentielle, donc l'existence se déduit des
   trous. Le masquer ne protégerait rien et coûterait le diagnostic dont
   l'utilisateur a besoin. Si le cloisonnement exige ce silence, il faudra une
   séquence **par société**, pas un message.
4. **Le retour restaure des `payload`, pas des écritures comptables.** C'est
   ce que la 252 photographie ; restaurer une écriture de grand livre est
   l'affaire de la tranche 2 et du lettrage (L21).
5. **Un lien dont l'instantané et le vivant n'ont pas la même longueur est
   refusé** — mieux vaut le dire que laisser un lien commander un état qu'il
   n'a pas eu.
appartient au socle, dont la suite le fige, et la 422 n'est pas son lot.

Le rollback exige donc que l'appelant **déclare l'état vivant attendu**
(`p_attendu`) et **refuse** si le réel ne colle pas. C'est de la **concurrence
optimiste**, et c'est la seule honnête quand le journal ne sait pas dire la
vérité. **Refuser est le comportement correct** : l'alternative écraserait un
travail plus récent sous couvert d'un retour, et personne ne verrait l'alerte.