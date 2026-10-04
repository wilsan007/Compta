# Relevés de test (R-10 / AUD-G03)

Un fichier par format de relevé, **mêmes opérations dans tous les fichiers** : compte
fictif `FR7630004000030000000000123` (banque « BANQUE DE L'EXEMPLE », agence 00400),
devise EUR, du 01/01/2025 au 03/01/2025.

| Opération | Date | Montant | Libellé | Référence |
|---|---|---|---|---|
| Virement reçu | 2025-01-01 | +500,00 | VIREMENT RECU CLIENT EXEMPLE | REF-2025-0001 |
| Frais bancaires | 2025-01-02 | −120,00 | FRAIS BANCAIRES TENUE DE COMPTE | FRAIS-2025-01 |
| Prélèvement | 2025-01-03 | −273,00 | PRLV FOURNISSEUR EXEMPLE | PRLV-2025-0001 |

Soldes : ouverture 1 000,00 (01/01) → clôture 1 107,00 (03/01).

## Anonymisation

Toutes les données sont fictives : IBAN de la plage d'exemple de la norme ISO 13616
(`FR76 3000 4000 0300 0000 0000 123`), banque, clients et fournisseurs génériques,
noms de fichiers et références sans lien avec un dossier réel. Les structures
(positionnel CFONB, balises CAMT/OFX, tags MT940) reproduisent celles des extraits
bancaires réels ; c'est **la structure qui est testée**, jamais une donnée de client.

## Fichiers

| Fichier | Format | Ce qu'il prouve |
|---|---|---|
| `releve-cfonb120.txt` | CFONB 120 (positionnel, 120 caractères) | enregistrements `01` (ancien solde), `04` (mouvement), `05` (complément de libellé) et `07` (nouveau solde) ; dates `JJMMAA` ; montants signés par leur 14e caractère |
| `releve-mt940.sta` | MT940 (SWIFT) | `:60F:`/`:62F:` (soldes avec devise), `:61:` avec date de valeur `MMDD`, `:86:` (libellé) |
| `releve-camt053.xml` | CAMT.053 (ISO 20022) | `Acct/Ccy` (devise), balances `OPBD`/`CLBD`, `Ntry` (`CdtDbtInd`, `AddtlNtryInf`, `EndToEndId`) |
| `releve-camt053-usd.xml` | CAMT.053 en **USD** | refus d'un relevé dont la devise diffère de celle du compte (R-10) |
| `releve-ofx1-sgml.ofx` | OFX 1.x (SGML) | les balises de valeur ne se ferment pas ; `CURDEF`, `TRNAMT` signé, `TRNTYPE` en repli, `LEDGERBAL` |
| `releve-ofx2-xml.ofx` | OFX 2.x (XML) | même relevé en XML bien formé, avec l'en-tête `<?OFX …?>` |

Le fichier CFONB est **généré** par positions pour que chaque zone tombe exactement
où la norme la place (une erreur d'un caractère change un montant) ; les autres se
relisent à l'œil. Les positions CFONB viennent de la brochure CFONB « Relevé de
compte sur support informatique » (juillet 2004) :

| Zone | Positions | Longueur |
|---|---|---|
| Code enregistrement | 1-2 | 2 |
| Code banque | 3-7 | 5 |
| Code opération interne | 8-11 | 4 |
| Code guichet | 12-16 | 5 |
| Devise (ISO 4217) | 17-19 | 3 |
| Nombre de décimales | 20 | 1 |
| Numéro de compte | 22-32 | 11 |
| Date `JJMMAA` (01, 04, 07) | 35-40 | 6 |
| Date de valeur (04) | 43-48 | 6 |
| Libellé (04) | 49-80 | 32 |
| Numéro d'écriture (04) | 82-88 | 7 |
| Montant signé (01, 04, 07) | 91-104 | 14 |
| Référence (04) | 105-120 | 16 |

Le montant est `13 chiffres + 1 spécificateur` : le spécificateur porte le signe et le
chiffre des unités (`{`=0 … `I`=9 pour un crédit, `}`=0 … `R`=9 pour un débit), et la
valeur est divisée par `10^(nombre de décimales)`. Exemple : `0000000110700{` avec
2 décimales = 1 107,00. Le **sens n'a pas de colonne**.
