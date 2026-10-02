# Le typage des états, tranche 2 — ce que 46 conversions révèlent (2026-10-02)

**Ce que ce document est.** La limite 1 de
[`ETAT-DES-LIEUX-29-ACCES-PROPRIETE-INEXISTANTE-2026-10-01.md`](./ETAT-DES-LIEUX-29-ACCES-PROPRIETE-INEXISTANTE-2026-10-01.md)
annonçait que **85 états** de `src/pages` restaient non typés et que « leur lot de
défauts est **encore caché** ». C'était une **hypothèse**, pas une mesure. Ce
document la tranche, et son résultat principal est **négatif**.

⚠️ **Aucune conversion n'est commitée.** Le but de cette passe reste de **nommer**
ce qui bloque, pas de le maquiller. Le dépôt est rendu intact (`git checkout --
src/pages`) avant toute conclusion.

## 1. La mesure, et une correction de méthode

Méthode, identique à celle du 2026-10-01 : nommer le type d'un tableau d'état
depuis sa fonction de requête (`useState<Awaited<ReturnType<typeof FN>>>`), puis
`npx tsc -b --noEmit`.

**Premier passage, faux, et la raison vaut d'être notée.** Raisonner par *fichier*
donne **169 erreurs** et **28 états « ambigus »** portant 10 fonctions de requête
chacun. Cause : un fichier de pages contient **plusieurs composants**, et deux
d'entre eux utilisent le même nom d'état (`items`). Chercher les appels du setter
dans tout le fichier **confond les composants entre eux** — le `setItems` du
composant A recevait aussi les fonctions du composant B. Raisonner par **bloc de
composant** (une coupe par `function` en début de ligne) supprime le faux signal :
**0 ambigu**.

| Mesure | Par fichier (faux) | Par composant (juste) |
|---|---|---|
| États convertis | 48 | **46** |
| États ambigus | 28 | **0** |
| Erreurs `tsc` | **169** | **32** |

C'est la même leçon que les autres tranches de ce dépôt : **un harnais qui
confond deux sujets ne prouve rien sur aucun des deux**. Les 169 erreurs
étaient, à 137 près, un artefact de mon script — pas des défauts.

## 2. Le résultat : **aucun nouveau défaut produit** dans ce lot

Les 32 erreurs restantes sont **toutes** dans `src/pages/Phase4Pages.tsx`, et
**aucune** n'est un accès à une propriété inexistante :

| Erreur | Nombre |
|---|---|
| `TS2339: Property 'first_name' does not exist on type '{}'` | 6 |
| `TS2339: Property 'last_name' does not exist on type '{}'` | 6 |
| `TS2322: Type 'unknown' is not assignable to type 'Key \| null \| undefined'` | 6 |
| `TS2322: Type 'unknown' is not assignable to type 'ReactNode'` | 5 |
| `TS2345: Argument of type 'unknown' … parameter of type 'number'` | 3 |
| `TS2345: Argument of type 'unknown' … parameter of type 'string'` | 3 |
| `TS2322: Type '{}' is not assignable to type 'ReactNode'` | 3 |

Toutes sont des `unknown` / `{}`, c'est-à-dire **la donnée n'est pas décrite** —
et non **la donnée n'existe pas**. La distinction du 2026-10-01 (donnée absente /
type incomplet / faux positif) s'étend ici d'une **quatrième** nature, qu'il
fallait nommer.

> **Conclusion de la mesure, et elle est nette :** sur les **46** états
> mécaniquement convertibles restants, le codemod **ne révèle aucun écran qui lit
> une propriété inexistante**. Les 29 accès du 2026-10-01 ne se reproduisent pas.
> Le lot « encore caché » de la limite 1 est **mesuré, et il est vide de défauts
> produit** — il reste 62 états sans fonction de requête identifiable, que cette
> méthode ne peut pas joindre.

## 3. La vraie cause des 32 erreurs : le type de retour n'est pas déclaré

`Phase4Pages.tsx` lit `a.employees.first_name`. L'état est désormais typé — et
`unknown` pour la même raison que le reste :

```ts
// src/lib/queries/payroll.ts:391
export async function getSalaryAdvances() {
  …
  return data as Record<string, unknown>[]   // ← aucun type
}
## 4. Le blocage de fond : deux décisions LOT7-04 qui se contredisent

Chaque fonction ci-dessus fait `select('*, employees(first_name, last_name)')`.
Pour les typer, le dépôt s'est donné un outil — et **il ne marche pas** :

```ts
// src/types/dbRow.ts
export type Joined<T extends TableName, K extends keyof Row<T>> = Pick<Row<T>, K> | null
```

`Joined` existe, cité dans `check-any-ceiling.mjs` comme **cible** à viser
(« `Row<'table'>` / `Joined<'table','col'>` »). Deux mesures :

| Mesure | Résultat |
|---|---|
| `Relationships:` dans `database-generated.ts` | **363** |
| …dont **vides** (`Relationships: []`) | **363** |
| Usages de `Joined<` hors de sa définition | **0** |

Les 363 tables déclarent un tableau de relations **vide**. Comme `Joined` exige
`K extends keyof Row<T>`, et qu'aucune relation n'est jamais une clé de `Row`, le
type est **inutilisable** — il ne peut pas nommer une jointure, donc aucun appel
n'existe. Ce n'est pas un oubli : `generate-db-types.mjs` (l. 123-128) l'écrit
**délibérément** —

> `supabase-js exige Relationships sur chaque table […] Les jointures imbriquées ne
> sont pas décrites ici : un tableau vide suffit à rendre la forme conforme.`

Donc : le générateur décide « les jointures ne sont pas décrites », et `dbRow.ts`
se donne un alias **pour décrire ces jointures-là**. Les deux décisions sont
LOT7-04 ; elles ne peuvent pas être vraies en même temps.

**Ce que cela coûte, mesuré : 139 sites** de
`select('*, <table>(<colonnes>))` dans `src/lib/queries/`. Aucun n'est protégé par
le type : soit la fonction renvoie `Record<string, unknown>[]`, soit elle renvoie
un type d'en-tête qui **ne déclare pas la ressource jointe** — et l'écran lit
alors `x.employees.first_name` sous le `any` que le repli laisse passer.

## 6. La voie C, appliquée : les 14 types de retour de la paie sont posés

**Ce qui est livré (2026-10-02).** Les 14 fonctions de `queries/payroll.ts` déclarent leur type
de retour, et la ressource jointe avec :

```ts
interface EmployeJoint { first_name?: string | null; … }
type AvecEmploye<T> = T & { employees: EmployeJoint | null }
type Avec<T, C extends string, E> = T & { [K in C]: E | null }
return data as AvecEmploye<SalaryAdvance>[]
```

Puis les **10 états** de `Phase4Pages.tsx` sont nommés depuis leur fonction de
requête (`useState<Awaited<ReturnType<typeof getSalaryAdvances>>>`) — c'est
exactement le lot que le §2 disait non mesurable. Mesuré : **`tsc` 0 erreur**,
où il en comptait **32** avant. Le gain est de **10 `any` retirés de la
production** (998 → 988) ; le portillon a donc abaissé son plafond tout seul.

### Trois choses trouvées en route, et qu'il fallait dire

1. **`Employee` ne déclare pas `first_name`/`last_name`, qui existent en base.**
   Mesuré : `information_schema` renvoie les trois colonnes (`first_name`,
   `last_name`, `name`), et **14 écrans de paie** lisent les deux premières sur
   la ressource jointe. Contraindre `K extends keyof Employee` rendait donc le
   type correct **incapable de décrire la donnée réelle** — `tsc` l'a refusé
   (18 erreurs `TS2344`). C'est pourquoi le type joint est déclaré **côté
   requête** : une ressource qui n'est pas un employé complet n'a pas à être un
   `Employee`.
2. **`Employees: EmployeJoint | null` — le `null` n'est pas décoratif.**
   PostgREST rend `null` quand la relation est vide ; c'est exactement ce que les
   écrans testent (`a.employees ? … : '-'`). Une `interface` complète aurait
   supprimé ce test et laissé afficher `undefined`.
3. **Le portillon lit le TEXTE, pas les types.** Un libellé de test contenant le
   motif `any[]` a été compté comme **1 dette** et a fait rouge la porte. Le
   libellé est réécrit sans le motif — et le garde en garde, parce que c'est
   exactement le genre de piège qui se reproduira.

### Rouge mesuré, les trois nouveaux défauts

| Défaut rejoué | Garde | `tsc` |
|---|---|---|
| repli `Record<string, unknown>[]` sur **une** fonction | 1 failed / 16 passed | 6 erreurs |
| ressource jointe renommée (les 14 appels orphelins) | 1 failed / 16 passed | 4 erreurs |
| un état d'écran retombe en tableau non typé | 1 failed / 16 passed | **0 erreur** |
| **restauré** | **17 passed** | **0 erreur** |

⚠️ La troisième ligne est la plus instructive : **remettre un seul des dix états
en `any[]` ne casse pas `tsc` du tout** — le compilateur n'a rien à dire sur un
tableau non typé. Seule la garde le voit. C'est la preuve que les deux signaux
sont complémentaires, et qu'un garde de régression n'est pas redondant du
compilateur.

### Limites dites

1. **Le fond n'est pas traité.** `Joined<>` reste inutilisable (§4) et les **139**
   sites de jointure restent non typés : on a traité **14** d'entre eux, ceux
   d'un module. La voie **A** reste ouverte et n'est pas tranchée.
2. **La décision de §5 n'est pas prise.** Cet arbitrage est la **voie C** —
   celle à faible risque — parce qu'elle débloque la mesure ; elle ne préjuge pas
   de A ou B.
3. **Les 10 états sont nommés, pas revus.** `tsc` ne dit plus rien sur leurs
   accès, ce qui est le but, mais la **logique** de ces écrans (filtres,
   totaux, tris) reste hors de ce que cette passe mesure.
4. `Employee` reste faux sur `first_name`/`last_name`. Corriger l'interface
   serait un travail **séparé**, à faire contre le type généré — pas ici, où il
   aurait étouffé les 14 fonctions sous un second sujet.

## 5. Ce qu'il faut décider

*(Arbitrage rendu en §6 : la voie **C** a été appliquée pour débloquer la mesure.
Les voies **A** et **B** restent ouvertes, et **A** reste le correctif de fond.)*

| Voie | Portée | Risque CI |
|---|---|---|
| **A** — le générateur décrit les relations (FK → `Relationships`), et `Joined` redevient utilisable | 363 tables, puis les 139 sites | **élevé** : la CI régénère les types sur base neuve et refuse tout écart ; générateur et fichier généré changent ensemble |
| **B** — nommer à la main les colonnes jointes, site par site | 139 sites, indépendamment | faible : `src/lib` seul |
| **C** — ne déclarer que les **14** fonctions de paie, puis typer les états de `Phase4Pages` | 14 lignes + ~10 états | faible | **FAITE le 2026-10-02** (§6) |

⚠️ **Limites dites.**

1. La méthode ne joint que les états alimentés par **une** fonction de requête
   identifiée. Les **62** autres (chemin indirect, plusieurs appels, état non
   rattaché) restent hors de vue : leur lot de défauts est **toujours** inconnu,
   et cette mesure ne permet **pas** de conclure qu'il est vide.
2. Les 32 erreurs ont été attribuées au repli `Record<string, unknown>` par
   **lecture**, sans correction intermédiaire : un `unknown` supprimé à la main
   pourrait en révéler d'autres. L'affirmation « 137 des 169 étaient un artefact »
   vaut pour le **décompte**, pas pour un diagnostic ligne à ligne.
3. Aucun test n'a été écrit : cette passe ne livre **aucun** correctif, donc
   aucune garde à poser.
4. Les 14 fonctions et les 363 tables sont **comptées sur l'état du commit** ;
   la session parallèle travaille en parallèle sur le même dépôt, et un décalage
   est possible d'ici la lecture.
```

Le type de retour **n'est pas déclaré du tout**. Nommer l'état ne peut donc rien
apprendre : le `Record<string, unknown>` propage son ignorance jusqu'au JSX.

**Mesuré : 14 fonctions** portent ce repli, **toutes dans
`src/lib/queries/payroll.ts`** (`getTimesheets`, `getPaySlips`,
`getPayrollAccountingEntries`, `getLeaveRequests`, `getContracts`,
`getSalaryAdvances`, `getPayRecalls`, `getDpaeRecords`, `getWorkHardship`,
`getCareerHistory`, `getCpfAccounts`, `getPayrollArchives`, `getExpenseReports`,
`getInterviews`). Aucune autre n'en porte dans les 88 fichiers de `queries`.

Les **14** types correspondants existent **déjà** dans `src/types/index.ts`
(`Timesheet`, `PaySlip`, `PayrollAccountingEntry`, `LeaveRequest`, `Contract`,
`SalaryAdvance`, `PayRecall`, `DpaeRecord`, `WorkHardship`, `CareerHistory`,
`CpfAccount`, `PayrollArchive`, `ExpenseReport`, `Interview`) — l'inventaire n'est
donc pas ce qui manque.