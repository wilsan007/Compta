# L4, tranche 3 — Le dernier invariant mesurable, et les six preuves (02/10/2026)

> **Tâche 3.8 du plan de la partie 3** : « Rendre **mesurables** les 7
> invariants "non mesurables" (ou en retirer avec raison écrite) ».
> Point de départ mesuré : **13 / 20** mesurables, **7** nommés sans
> contrôle — `INV-05, 06, 07, 08, 10, 12, 19`.
>
> **Base** : PostgreSQL 16, conteneur `compta-pg16` (port 5433), base
> neuve reconstruite dans l'ordre de la CI (`00_supabase_stubs` +
> `00_schema_dump` + **275 migrations, 0 erreur**).
> **Branche** : `l4-invariants`. **Migration** : `431`.

## 1. La mesure a donné une réponse différente de celle attendue

La 413 avait nommé ces sept invariants « non mesurables » en expliquant
**pourquoi**. On a d'abord vérifié ces explications **en base** plutôt que
de les recopier. Six des sept ne manquaient pas d'une *méthode* de mesure :
ils manquaient d'une **donnée**.

| Invariant | Ce que la base porte réellement | Suite |
|---|---|---|
| `INV-05` | `purchase_orders` : 13 colonnes, **aucune** de facturé ni de reçu ; et `document_links` ne porte **aucun** lien de type `purchase_orders` (types relevés : `pay_runs`, `journal_entries`) | non mes. |
| `INV-06` | `budgets` : 17 colonnes, dont les 12 `period_1..12` qui sont le **budget**. Aucun « réalisé » stocké | non mes. |
| `INV-07` | `lettrage_groups` : aucune clé vers `journal_lines`. `bank_transactions.reconciled_entry_id` existe mais pointe vers une **écriture**, pas vers le groupe de lettrage | non mes. |
| `INV-08` | `bank_transactions` : 33 colonnes, **aucun solde de relevé** ; aucune table de relevé dans le schéma | non mes. |
| `INV-10` | `dsn_declarations` : 11 colonnes, dont **zéro numérique** — le brut n'existe que dans le fichier produit | non mes. |
| `INV-12` | `projects.actual_cost` existe (3 projets relevés), mais les **deux** recalculs concurrents du référentiel (« PROJ-02 ») subsistent : l'égalité n'a pas de terme de droite | non mes. |
| `INV-19` | `amont_type` texte + `amont_id` uuid, sans clé étrangère — **mais** les types en usage sont `pay_runs` et `journal_entries`, et **les deux tables existent** | ✅ **mes.** |

## 2. Ce que la 431 livre

**Un invariant rendu mesurable, pas sept.** `INV-19` disait dans sa
raison : « Devient mesurable dès qu'un registre des types de documents
est écrit (**c'est la matière de la vue chaîne, lot L6**) ». La mesure
confirme que les types sont énumérables — la 431 écrit donc ce registre
(`chain_document_types`) et rend `INV-19` mesurable. **13 → 14.** Le
lot L6 n'aura plus à l'inventer.

**Six raisons transformées en preuves.** Elles n'étaient que des
affirmations ; ellesbecomment des mesures datées et opposables (nombre de
colonnes, nom de la colonne manquante). C'est le repli que le plan
autorise — « la raison de chaque exclusion » — et une raison vérifiable
vaut mieux qu'un invariant vide.

**⚠️ Le garde anti-faux-vert, qui est le vrai apport.** Un lien dont le
type n'est pas au registre ne peut pas être **prouvé** résolu. Le compter
comme « tenu » serait exactement le faux vert que la 413 refuse. Il compte
donc comme **ligne en écart**, à côté des orphelins réels ; les deux
nombres sont publiés séparément dans `detail`. Conséquence utile :
**`INV-19` se durcit à mesure que le registre grandit**, et il ne peut
jamais être vert sans avoir réellement regardé la chaîne.

## 3. La suite 431 — 7 scénarios, 7 verts

| # | Ce qui est prouvé | Mesure relevée |
|---|---|---|
| T01 | le relevé mesure **14**, les 6 autres nommés, et le détail d'INV-19 publie ses 4 clés | `mesures=14`, `non_mesurables=6` |
| T02 | un orphelin **réel** est compté, une société saine reste tenue | `orphelins_reels=2`, `types_non_resolus=0` |
| T03 | ⚠️ **un lien de type NON ENREGISTRÉ fait rompre l'invariant, et le type est nommé** | `types_hors_registre=["ghost_documents"]` |
| T04 | la délégation aux 13 branches de la 413 est intacte, et la garde « mesurable sans branche **LÈVE** » survit au wrapper | `INV-99` refusée |
| T05 | les six raisons portent chacune une **mesure datée** | `sans preuve datée : (aucun)` |
| T06 | RLS activée **et** forcée, **une** politique, index mené par `tenant_id`, et le client **ne peut pas écrire** | `permission denied for table chain_document_types` |
| T07 | l'entrée standard se lit partout, l'entrée propre à une société **seulement** chez elle | `A=1`, `B=0` |

## 4. Les portes, dans le même commit

| Porte | Verdict | Mesure |
|---|---|---|
| **G1** structure | ✅ vert | `tables_tenant` 363 → **364**, `moins_de_4_commandes` 80 → **81** (+1 chacun : `chain_document_types`) |
| **G5** câblage | ✅ vert | **102** fichiers de test / **102** références dans `ci.yml`, aucune non branchée |
| **G7** RLS forcée | ✅ vert | `tables_forcees` 314 → **315**, `muettes` 15 → **16** |
| `check_plpgsql` | ✅ vert | **0 erreur**, 31 avertissements (préexistants) |
| types générés | ✅ | +39 lignes = **exactement** `chain_document_types`, régénérés sur base neuve **avant** les suites (sinon l'outillage de test se glisse dans le diff — mesuré par la 414) |

Les quatre plafonds sont **relevés avec leur raison écrite**, pas pour
faire verte : la table ne porte qu'une politique de lecture, et sa raison
## 5. Ce qui reste ROUGE, et pourquoi je ne l'ai pas fait verte

**Le plafond des tables non lues est à 80 pour un plafond de 75.** Il
était **déjà rouge avant cette migration** (79 > 75) : les trois tables
de la 413 et de la 414 y sont déjà. La 431 y ajoute `chain_document_types`,
soit **80**.

**Je n'ai pas relevé le plafond**, et c'est délibéré : la règle du dépôt
est qu'un plafond se relève avec une justification datée, **pas pour faire
verter**. Relever 75 → 80 ici effacerait un signal que la partie 1 a
mesuré et qu'une autre session (**tâche 1.1 / 3.10**, sur
`partie-1-stabiliser`) est en train de traiter : faire lire
`chain_invariants` et `chain_invariant_results` par l'écran
(`chainCoherence.ts`).

`chain_document_types` sera lue de la même façon : elle est l'**entrée**
de la page « Cohérence » du lot L5 (elle publie la couverture du
registre). Sa lecture par l'écran est une tâche de l'interface, hors du
périmètre de cette migration, et la faire ici reviendrait à empiéter sur
le fichier qu'une autre session écrit en ce moment.

## 6. Ce que cette migration NE fait pas — nommé

- **Elle ne rend pas les 20 invariants mesurables.** Elle en rend **un**,
  et transforme les six autres raisons en **preuves**. L'indice passe de
  « 13 mesurés sur 20 inscrits » à « 14 mesurés, 6 nommés avec leur
  preuve ». Le plan autorise ce repli ; il n'autorise pas d'écrire un
  contrôle qui compare un montant à un agrégat inventé.
- **Elle ne corrige aucun écart.** Parmi les quatorze mesurés, le
  référentiel en annonçait plusieurs « rompus » (`INV-01`, `INV-02`,
  `INV-03`, `INV-11`). L'indice publié reste bas — et c'est le but.
- **Elle ne comble pas les données manquantes.** `INV-08` (solde de
  relevé), `INV-10` (brut DSN), `INV-06` (réalisé budgétaire) :
  ajouter ces colonnes est un **lot de schéma**, pas une migration de
  contrôle. Elles restent nommées jusqu'à ce qu'un lot les porte.
- **Elle ne mesure pas les 8 épreuves.** La page « Robustesse » (L5) lit
  le banc D1→D8, qui est la tranche 3 du lot L3 et n'existe pas encore.
  Cette migration ne produit que la matière de la page « Cohérence ».
est mesurée par T06.