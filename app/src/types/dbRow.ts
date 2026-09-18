// LOT7-04 — types dérivés du schéma PostgreSQL réel.
//
// `database-generated.ts` est régénéré et vérifié par la CI (`db-integration`) mais
// n'était importé nulle part : ses types ne protégeaient donc rien. Ces alias le
// rendent utilisable là où le gain est immédiat — décrire les ressources jointes
// d'un `select('*, autre_table(colonnes))`, qui étaient jusqu'ici typées `any`.
//
// L'intérêt de passer par le schéma plutôt que d'écrire les types à la main :
// si une colonne jointe est renommée ou supprimée en base, la régénération des
// types fait échouer la compilation au lieu de laisser une valeur `undefined`
// se propager silencieusement dans l'interface.
import type { Database } from './database-generated'

// Internes : n'exporter que ce qui sert, pour ne pas gonfler la dette d'exports morts
// que surveille `check-knip-ceiling.mjs`.
type Tables = Database['public']['Tables']
type TableName = keyof Tables

/** Ligne complète d'une table, telle que PostgREST la renvoie. */
type Row<T extends TableName> = Tables[T]['Row']

/**
 * Colonnes d'une ressource jointe (`select('*, employees(first_name, last_name)')`).
 * PostgREST renvoie `null` quand la relation est vide : l'appelant doit donc tester,
 * ce que le `any` précédent laissait passer.
 */
export type Joined<T extends TableName, K extends keyof Row<T>> = Pick<Row<T>, K> | null

// Une relation « plusieurs » (PostgREST renvoie alors un tableau, jamais null) se
// décrirait par `Pick<Row<T>, K>[]` — à ajouter le jour où un tel embed sera typé.
