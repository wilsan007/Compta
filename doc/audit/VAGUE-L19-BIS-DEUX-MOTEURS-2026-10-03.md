proof : le previsionnel avait DEUX moteurs (L19 bis)

getTreasuryForecast ne rappelait pas cash_flow_forecast : c etait une seconde
implementation du previsionnel en JavaScript, et les deux divergeaient.

Le caractere distinctif est le SOLDE : SQL = toute la classe 5 (4 000),
JS = bank_accounts.calculated_balance (0). Ecart 4 000, soit exactement la
caisse que la lecture bancaire ignore.

Les montants divergeaient aussi : amount_due contre total.

Correcif 5653181 : le SQL redevient le seul moteur ; l ecran affiche l
engagement et les deux nets ; le bouton ne lit plus deux cles inexistantes.

Effet de bord documente : le solde de l ecran peut BAISSER pour une societe
dont l argent est en caisse plutot qu en banque. C est la bonne valeur — le
previsonnel de tresorerie parle de tresorerie, pas de comptes bancaires — mais
c est un changement visible, et il est intentionnel.

Et cette tranche corrige une affirmation de la preuve L19 : j y ecrivais que
l ecran lisait des cles qu aucune fonction ne rendait. C etait faux — l
ecran avait ses cles, mais de son propre moteur JS. La 420 rendait les
bonnes cles cote SQL sans que l ecran les lise. Le moteur etait juste, le
cable non.

limites : la ligne de temps reste en JS (c est une liste d affichage, pas
une grandeur, et elle lit amount_due desormais pour coller au moteur). Le
solde projete reste calcule en JS a partir des sorties du moteur. Et la
suppression de la lecture bank_accounts doit encore etre confirmee : le test
sabotage a bien rougi, mais une table qui n a plus d appelant declenche
knip ou check-unused-tables.
