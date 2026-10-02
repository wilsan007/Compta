# Vague L1 — tranche 6 : la contrepassation de paie — 2 octobre 2026

> **Objet.** Fermer le **sixième candidat direct** de
> [l'inventaire de la tranche 4](INVENTAIRE-CHAINAGES-L1-TRANCHE4-2026-09-30.md)
> §2 — celui que la tranche 5 a laissé. La table des **32 fonctions qui écrivent
> dans ≥ 2 modules** marque **six** lignes « candidat direct » ; la tranche 5
> (migration **316**) en a tracé **cinq**, et son compte (§1 de l'en-tête, §2 et
> §5) répète « 5 candidats directs ». La **ligne 22** — `payroll_reverse_posted_run`
> (déclencheur de la **248**) — portait pourtant le même verdict, et la mesure le
> confirme : **ni trace ni contrat**. C'est l'incohérence de l'inventaire qui rend
> le sixième visible.
> **Livré.** Migration **321** (`321_chain_l1_paie_contrepassation.sql`), un
> déclencheur compagnon `zz_l1_payroll_run_reversal`, son contrat d'effet
> (`payroll.run.reversed`), suite d'acceptation **321**
> (`321_chain_l1_paie_contrepassation_tests.sql`, **6 scénarios**), câblage CI, et
> la mise à jour des documents de compte.

---

## 1. Le maillon, et pourquoi il remplit les deux conditions

La doctrine de la **310** exige **deux conditions** pour qu'un compagnon soit
possible : le maillon doit être un **déclencheur `AFTER`**, et son aval doit être
**identifiable par une clé mesurée dans son propre corps**.

| Condition | `payroll_reverse_posted_run` (248) |
|---|---|
| Déclencheur `AFTER` | **oui** — `payroll_reverse_posted_run_trg AFTER UPDATE OF status ON pay_runs` (ligne 150 de la 248), et `zz_l1_payroll_run_reversal` trie après lui (ordre ASCII du nom : `payroll_…` < `zz_l1_…`) |
| Aval identifiable par une clé du corps | **oui** — l'écriture de contrepassation est référencée `journal_entries.reference = 'PAYROLL-REV-' \|\| OLD.number`. C'est **déjà** la garde d'idempotence du maillon (ligne 124-125 : « déjà contrepassée : ne pas le faire deux fois »), donc une clé stable, écrite par lui. |

Le maillon est `SECURITY DEFINER`, il écrit dans **compta** (`journal_entries`,
`journal_lines`) **et** dans **rh** (`payroll_accounting_entries`, `pay_slips`) :
c'est bien un chaînage transverse, pas un recalcul.

La différence avec la **réconciliation bancaire** (tranche 2), écartée de la
doctrine compagnon « à cause du tour » : l'annulation d'un lot de paie n'est pas
rejouable dans la même transaction — un lot `cancelled` ne redevient `approved`
que par un acte explicite, et le maillon porte une garde d'idempotence
(`reference = 'PAYROLL-REV-' || number`). Le compagnon ne lit pas un marqueur : il
**constate** l'existence de l'écriture que le maillon a nommée.

---

## 2. Le cas ordinaire, et l'anomalie — la retenue de la 315, appliquée

| Situation | Le maillon fait… | Le compagnon fait… |
|---|---|---|
| Lot annulé **jamais comptabilisé** | rien (pas de pont, ou pont sans écriture) | **rien** — ni lien, ni trace. `sans_effet` est réservé à l'anomalie. |
| Écriture de paie **`posted`** sans contrepassation | rien (sa garde exige le pont `transferred`) | trace **`sans_effet`** (valeur de la 315), **zéro lien** — l'effet ATTENDU et ABSENT est visible au lieu d'être muet. |

La distinction n'est pas cosmétique : un import de cent lignes ne doit pas
produire cent bruits, mais une écriture comptable de paie qui reste au grand
---

## 3. Les mesures, et la non-régression

| Mesure | Avant la 321 | Après la 321 | Où c'est prouvé |
|---|---|---|---|
| Effets tracés par un maillon | 22 | **23** | porte G2 : 44 constats |
| Contrats déclarés (effets métier) | 24 | **25** | 321 T05, porte G2 |
| Compagnons `zz_l1_` | 16 | **17** | 321 T05 |
| Liens d'un lot comptabilisé puis annulé | **0** | **1** | 321 T01 |
| Traces de l'effet (ordinaire / anomalie / nominal) | — | **0 / `sans_effet` / `applique`** | 321 T02, T03, T01 |
| Base neuve | 270 migrations | **271 migrations, 0 erreur** | ce document |

**Non-régression rejouée sur base neuve** (271 migrations, **14** contrôles du
dépôt dans l'ordre de la CI, puis les suites) : **14 contrôles à 0 erreur** ; les
suites des chaînages et du module touché vertes — `252` **17**, `310` **15**,
`311` **12**, `312` **12**, `313` **11**, `314` **10**, `316` **12**, `319` **7**,
`320` **8**, **`321` 6**, `241` **7** (réceptions), `247` **7** (pont paie →
comptabilité). `plpgsql_check` **0 erreur**. Les types générés régénérés sur une
base **où les suites n'ont pas tourné** donnent **exactement** le fichier commité
(aucun écart) — la 321 n'ajoute ni table ni colonne.

---

## 4. Ce que la suite 321 mesure, scénario par scénario

| # | Ce qu'il prouve |
|---|---|
| **T01** | lot comptabilisé puis annulé → **un** lien `pay_runs → journal_entries` (`reversed_by`) **vers la contrepassation** (`aval_id` = l'écriture `PAYROLL-REV-<n°>`), un événement `pay_runs.reversed`, **une** trace `applique` ; et la contrepassation du maillon existe (une seule) |
| **T02** | lot annulé **sans avoir été comptabilisé** → **aucun** lien, **aucune** trace (le cas ordinaire ne se trace pas) |
| **T03** | écriture de paie **`posted`** et pont **non `transferred`** → **aucun** lien, **aucune** contrepassation, **une** trace **`sans_effet`** (zéro ligne) |
| **T04** | annuler **deux fois** → **un seul** lien, **une seule** trace `applique` (le rejeu écrit `ignore`), **une seule** contrepassation |
| **T05** | structure : **un** contrat actif, **un** compagnon `SECURITY DEFINER` **non exposé** à `authenticated`, qui s'exécute **après** son maillon métier (aucun déclencheur métier de `pay_runs` ne trie après lui) |
| **T06** | isolation : la société voisine (utilisateur réellement connecté à elle) ne voit **ni** le lien, **ni** l'événement, **ni** la trace — et la société propriétaire les voit tous les trois |

---

## 5. Les limites, dites

1. **Ce document ne compte pas les neuf maillons RPC de l'inventaire** (ticket de
   caisse, avoir de caisse, postes de paie, lettrage manuel, dé-lettrage…) : un
   compagnon ne peut pas s'accrocher à un **appel de fonction** — c'est le lot
   **L3** (les chemins d'annulation de la **320** en sont la première tranche).
   L1, sur le territoire des candidats directs, s'arrête bien ici.
2. **La branche d'anomalie n'a qu'un décor.** T03 fabrique « écriture `posted` +
   aucune contrepassation » en passant le pont à `cancelled` **à la main** :
   c'est le seul moyen, dans les suites actuelles. Un décor qui passerait par un
   chemin métier réel reste à écrire.
3. **L'isolation (T06) porte sur la 321** : les politiques lues
   (`document_links`, `domain_events`, `chain_traces`) sont communes à tous les
   effets, mais seuls le lien, l'événement et la trace de **cet** effet ont été
   lus depuis la société voisine.
4. **La locale n'est pas la CI, et c'est écrit.** La suite 321 s'exécute sous le
   rôle `authenticated`, qui appelle `_mk_tenant` (et donc `uuid_generate_v4()`) :
   ces fonctions doivent être exécutables par `authenticated`. C'est le cas sur
   une base neuve **construite comme la CI** (`00_supabase_stubs.sql` →
   `00_schema_dump.sql` → migrations), où la suite **316** — verte en CI — passe
   **12/12**. Une base locale dérivée par des rejouages manuels de migrations peut
   perdre ces droits : le symptôme (`permission denied for function
   uuid_generate_v4` **sur la 316 aussi**) le dit, et il ne remet pas en cause le
   contenu de la 321.
livre après l'annulation du lot est un **défaut** qui doit se voir.