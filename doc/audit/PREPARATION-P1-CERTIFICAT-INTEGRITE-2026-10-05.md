# Préparation de P1 — le certificat d'intégrité (A3.4)

> **Objet.** Tout ce qu'il faut pour écrire **P1** sans le réinventer : le
> réglage produit (déjà tranché), le contrat de la fonction, ses dépendances
> **vérifiées**, la suite rouge-avant, l'écran, et **ce qui bloque
> aujourd'hui**. C'est une **préparation**, pas une livraison : P1 est du
> ressort d'**A3** (le SQL) et d'**A2** (l'écran).
>
> Rédigée le 05/10/2026, à la demande du produit, après les décisions du §6 bis
> et le dossier de l'expert-comptable.

## 1. Ce qui est déjà tranché — et n'attend plus rien

Les cinq questions du §6 sont **décidées**
([§6 bis](PROPOSITIONS-DIFFERENCIATION-APRES-L24-2026-09-30.md)) :

- le certificat est une **« attestation d'intégrité technique »** — **le système
  émet, la société endosse**, **jamais un tiers** ;
- **deux lectures** pour un seul document : page 1 dirigeant / annexe
  vérifiable (expert-comptable, banque) ;
- l'empreinte NF-525 est **en annexe, comme mécanisme vérifiable — jamais
  « conforme »** ; **« sans objet »** sans caisse ;
- la **mention obligatoire** est écrite **une fois pour toutes** : *« ne
  constitue ni un audit, ni une attestation de l'expert-comptable, ni une
  certification légale »* ;
- l'**expert-comptable référent** est **considéré désigné** (voir le
  [dossier de validation](../validation-expert-comptable/DOSSIER-EXPERT-COMPTABLE-2026-10-05.md)).

**Conséquence :** A3.4 n'a **plus de blocage de décision**. Ce qui manque est
**matériel** (§5).

## 2. Le contrat de la fonction (proposé — à écrire par A3)

```
public.chain_certificat_integrite(p_tenant uuid DEFAULT NULL) RETURNS jsonb
  SECURITY DEFINER, borné par current_tenant_id()
  GRANT EXECUTE TO authenticated        -- comme chain_document_arborescence (460)
```

Il **ne rend que des faits**, jamais de prose (le vocabulaire est à l'écran,
pour l'i18n) :

| Champ | Source | Règle |
|---|---|---|
| `emis_le` | `now()` | l'horodatage du certificat |
| `version_migrations` | `sql_migrations_tracker` (dernier `id`) | « la base est **celle-ci** » — un certificat sans version ne se re-vérifie pas |
| `invariants` | `chain_invariant_results`, **dernier relevé par `code`** | `{tenu, rompu, non_mesure, total}` — **`non_mesure` compté à part** (un contrôle manquant n'est **pas** une rupture) |
| `ecarts` | idem, les **`rompu`** | liste `{code, libelle, ecart, lignes_en_ecart, mesure_le}` — **la liste des écarts, jamais cachée** (c'est le différenciateur) |
| `banc` | `chain_banc_resultats`, dernier verdict par `(code, epreuve)` | `{tenues, rompues, non_jouees, total}` — **`non_joue` visible**, jamais un succès par défaut |
| `nf525` | `verify_nf525_chain()` — **retourne `jsonb`** (`134` → `233`) | `{sans_objet, verifie, …}` — **« sans objet »** si aucune caisse, **jamais** « 0 événement » |

**Ce que la fonction ne fait pas** : elle **n'écrit rien** (aucun
`document_links`, aucun `chain_*`), **ne recalcule aucun solde** (elle lit les
relevés déjà publiés), et **n'invente aucun `tenu`** — un relevé absent vaut
`non_mesure`.

## 3. Les dépendances — vérifiées le 05/10

| Dépendance | Où | État |
|---|---|---|
| Les **20 invariants**, mesurés | `chain_invariants` / `chain_invariant_results` (`413`), une seule fonction de mesure (`456`) | ✅ **17/20** mesurables ; les 3 autres **disent** pourquoi |
| Le **rapport du banc** | `chain_banc_resultats` (`433`/`434`/`436`) | ✅ **7 × 8 = 56 verdicts datés** ; `non_joue` dit |
| La **chaîne d'empreintes** | `verify_nf525_chain(timestamptz, timestamptz) RETURNS jsonb` (`134`, réécrit `233`) | ✅ `authenticated` l'exécute |
| L'**attestation par période** | `get_nf525_attestation(p_period text)` (`91`/`152`) | ✅ existe |
| Le **suivi des migrations** | `sql_migrations_tracker` | ✅ existe (au moins 333 lignes) |

## 4. L'écran (A2) — « un artefact, deux lectures »

Une page (**proposée** : `/system/certificat`, sous `AdminRoute`, à côté de
**Robustesse** et **Cohérence**) qui lit la fonction et rend :

- **page 1 — le dirigeant** : le score en clair (« 17/20 invariants tenus, N
  écarts, banc 29/56 »), la date, **et la mention** (i18n) ;
- **l'annexe — l'expert-comptable et la banque** : les invariants, les écarts
  **nommés**, les verdicts du banc, **l'empreinte NF-525** et **le moyen de
  re-vérifier** (`verify_nf525_chain`) ;
- **« qui signe »** : le **système émet** (fait daté, versionné) ; la **société
  endosse** (nom + date). **Jamais** un tiers.

Le **PDF** (« télécharger ») suit **D-4** (`generate-pdf`, voie A) : ce n'est
**pas** dans P1 — on ne bloque pas le certificat sur un convertisseur isolé.

## 5. Ce qui bloque aujourd'hui — et l'ordre

| # | Blocage | Qui le lève |
|---|---|---|
| 1 | **La plage d'A3 est saturée** : `493`→`499` est pris, et l'extension `750`→`759` (« familles restantes ») est **déjà consommée** par L16 (`753`, `754`, `755`…) | **l'intégration** — **inscrire une plage pour A3.4** avant d'écrire le SQL (R2 : un numéro se prend par `migration:prendre`, jamais à la main) |
| 2 | Le **worktree A3 est actif** (L16 en cours : lots 8-10 committés, migrations en vol) | **attendre** qu'il se libère (R1 : une session par worktree — la leçon de la collision A2 du 05/10) |
| 3 | **L'écran** suppose la fonction | **A2**, *après* A3 |

**Ordre recommandé** : **(a)** l'intégration étend la plage d'A3 → **(b)** A3
écrit `chain_certificat_integrite` + sa suite (rouge avant) → **(c)** A2 branche
l'écran.

## 6. La suite (rouge avant) — ce qu'elle doit exiger

Une suite `NNN_chain_certificat_integrite_tests.sql` (sous le marqueur
`plan6:a3`), **rouge avant** l'écriture de la fonction, et qui exige :

1. **La forme** — la fonction rend un `jsonb` **non nul** pour une société de
   test.
2. **Le compte des invariants** = le **dernier relevé par code** ; et **aucun
   `tenu` sans relevé** (un code sans résultat vaut `non_mesure`).
3. **Le banc** — **huit** verdicts par maillon, `non_joue` **compris**.
4. **« Sans objet » sans caisse** — une société sans caisse rend
   `nf525.sans_objet = true`, **pas** un faux « 0 événement ».
5. **Aucune écriture** — l'exécuter deux fois ne change **rien** (ni
   `document_links`, ni `chain_*`) : le certificat est une **lecture**.

## 7. Ce que cette préparation ne fait pas, et pourquoi

- **Aucun SQL, aucun écran** : les écrire maintenant violerait **R1** (worktree
  A3 actif) et **R2** (pas de plage libre). Une préparation qui produirait du
  code non plaçable serait un lot en sursis.
- **Aucune prose dans la fonction** : le vocabulaire (« attestation
  d'intégrité technique », la mention) appartient à l'**i18n de l'écran**, pas
  au SQL — sinon le premier traducteur ne pourrait plus le corriger.
- **Le PDF n'est pas ici** : il dépend de **D-4** et ne doit pas bloquer P1.

