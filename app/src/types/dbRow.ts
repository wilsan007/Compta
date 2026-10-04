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
export type Row<T extends TableName> = Tables[T]['Row']

/**
 * Colonnes d'une ressource jointe (`select('*, employees(first_name, last_name)')`).
 * PostgREST renvoie `null` quand la relation est vide : l'appelant doit donc tester,
 * ce que le `any` précédent laissait passer.
 *
 * **Deux paramètres, deux rôles** — c'est la convention que tout le dépôt suit déjà
 * (mesuré : `{ products: Joined<'products', 'name' | 'sku'> }` dans
 * `queries/stock.ts`, `{ fixed_assets: Joined<'fixed_assets', 'name'> }` dans
 * `queries/accounting/assets.ts`) :
 *
 *   - `T` = la table **cible** de la jointure (celle dont on lit des colonnes) ;
 *   - `C` = les colonnes **réellement sélectionnées**, validées contre `Row<T>`.
 *
 * Ce que ce type garantit, et qu'il ne garantissait pas :
 *   1. une colonne qui n'existe pas dans la table cible est **refusée** — mesuré :
 *      `employees.prenom_fantaisiste` donne `TS2339` ;
 *   2. une table cible qui n'existe pas du tout est **refusée** : `T extends TableName`.
 *
 * ⚠️ Avant le 2026-10-02, `C` était contraint à `keyof Row<T>`, ce qui était FAUX même
 * lorsque les relations étaient déclarées : le second paramètre portait les colonnes
 * mais il était confronté aux colonnes de la SOURCE, jamais de la cible. Et aucune
 * relation n'était nommée, faute de `Relationships` dans le fichier généré — donc le
 * type ne contrôlait **rien**, et **109 appels** ont survécu à cette absence de
 * vérification.
 *
 * Le générateur décrit désormais les **692** clés étrangères du schéma. Sans lui,
 * ce type ne peut nommer aucune cible : il serait inutilisable.
 *
 * ⚠️ Ce type vérifie la CIBLE, pas le chemin. Il ne dit pas que `products` est
 * réellement une clé étrangère de `stock_movements` — cela se vérifie contre la base
 * (ou `PostgREST`), pas dans le type. Voir la limite dite dans
 * `doc/audit/ETAT-DES-LIEUX-TYPAGE-ETATS-TRANCHE-2-2026-10-02.md` §9.
 */
export type Joined<T extends TableName, C extends keyof Row<T>> = Pick<Row<T>, C> | null
