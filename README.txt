Depot xcsoar de vmath54 - README.txt
------------------------------------
Ce depot contient certains outils en lien avec xcsoar

Dossier "vac"
-------------
Contient des scripts et fichiers permettant d'acc�der aux cartes VAC pdf depuis les waypoints des a�rodromes propos�s par FRA_FULL_HighRes.xcm ou France.cup

- waypointsDetailsWithVAC.txt : a d�poser dans XCSoarData. Fichier de d�tail de waypoints permettant de lier les fichiers pdf aux terrains

- genereDetailsWaypoints.pl : script perl, qui permet de g�n�rer le fichier waypointsDetailsWithVAC.txt
                              Il utilise en entr�e la base WELT2000.txt, disponible a http://www.segelflug.de/vereine/welt2000/download/WELT2000.TXT
							  
- getVACfiles.pl : script perl, qui permet de r�cup�rer les cartes VAC de France, depuis le site du SIA

- getBASULMfiles.pl : script perl, qui permet de r�cup�rer les cartes PDD du site baseULM
