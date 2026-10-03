# Patch T06 (D8) — le témoin était tiré au hasard

> **Pourquoi un patch et pas un commit.** Ce correctif concerne
> `app/sql/434_chain_banc_epreuves_tests.sql`, qui appartient à la session
> `partie-3-chainages`. J'ai **appliqué, testé, puis restauré** ce fichier
> (md5 vérifié avant et après : `936e026b3c921eabdc91253349130aa0`) — la
> branche est exactement comme je l'ai trouvée. Le correctif est donc livré
> **prêt à appliquer**, sans rien imposer à l'autre session.
>
> ```bash
> # depuis la racine du dépôt, sur la branche partie-3-chainages
> git apply doc/audit/patches/T06-d8-temoin.patch
> ```
>
> Testé le 02/10 : `git apply` sans conflit, et le fichier obtenu est
> **identique** à celui qui a été joué.

---

## 1. Le défaut

`T06` (épreuve D8 — isolation) était rouge : `verdict=rompu`, avec
`liens_visibles_depuis_la_voisine=20`.

**Le produit n'a aucune fuite.** Vérifié avant de conclure :

| Contrôle | Résultat |
|---|---|
| Politique de `document_links` | `tenant_id = current_tenant_id()`, RLS **activée et forcée** |
| Lecture sous `authenticated`, contexte du voisin | **3 liens** — ceux *du voisin* |
| `chain_banc_liens_visibles` | pas `SECURITY DEFINER` → la RLS filtre, la mesure est correcte |

La cause : la suite choisissait sa société voisine par

```sql
WHERE t2.id <> ta AND EXISTS (SELECT 1 FROM tenant_users …)
LIMIT 1;                       -- aucun ORDER BY : tirage au hasard
```

Or **8 sociétés ont des liens** dans la base de la suite. Le voisin tiré en
avait **3 à lui** : la RLS les lui rendait légitimement, et l'épreuve
concluait à un défaut d'isolation inexistant.

> Une preuve d'isolation exige une société **sans lien de ce maillon**. Sinon
> « le voisin voit 3 liens » ne se distingue pas de « le voisin voit les liens
> du propriétaire ». C'est le **même défaut de témoin** que le T07 de la 414.

## 2. Le correctif

1. **Le tri des candidats** : on ne retient que des sociétés *sans lien de ce
   maillon*, et on les trie par nombre de liens croissant — la plus neutre
   d'abord. Le `NOT EXISTS` porte sur `amont_type`, `effet` et `v_depuis`,
   c'est-à-dire sur **ce** maillon et **ce** tour.
2. **Si aucun voisin neutre n'existe**, le scénario le dit et échoue — il
   n'invente pas un témoin. `non tenu` serait un mensonge.
3. **Le témoin du propriétaire** (`v_proprio`) est compté **hors RLS et avant**
   tout changement de société. C'est lui qui distingue « la RLS a filtré » de
   « le propriétaire n'a rien produit » : D8 exige les deux, sinon l'épreuve
   ne prouve rien. Les deux nombres apparaissent désormais dans le détail.

## 3. Preuves

| Mesure | Avant | Après |
|---|---|---|
| Suite 434 (base neuve, 278 migrations, 0 erreur) | **7 / 8** | **8 / 8** |
| T06 | `rompu`, 20 liens vus | `tenu`, **0** vu, propriétaire = 1 lien |

**Et il détecte encore un vrai défaut** : RLS rouverte sur `document_links`
(`USING (true)`) → T06 **rougit**, `104 liens visibles depuis la voisine`.
Un test qui ne rougit pas sur une fuite réelle ne prouve rien.

## 4. Ce que ce patch ne fait pas

Il ne touche qu'à `T06`. Les épreuves **D2, D3 et D5 restent `non_joue` avec
leur raison** (T07 le vérifie, et `tenues_par_défaut = 0`) : elles demandent
une seconde connexion, un point de panne instrumenté et un chemin de
réouverture décrit. Elles ne sont pas acquises.