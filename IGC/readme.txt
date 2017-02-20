Ce dossier contient des scripts perl pour lire un fichier igc, et pour g�n�rer des trames NMEA � partir des enregistrements IGC.

- IGC.pm : c'est l'objet perl permettant de manipuler des infos IGC
- readIGC.pl : script de test
- sendIGCtoNMEA.pl : lit un fichier IGC, et le "rejoue" en envoyant des trames NMEA GPGGA et GPRMC dans une connexion TCP ou UDP.
  Ces trames peuvent �tre lues par XCSoar.

- sample.igc : un fichier IGC pour les essais


Ex�cuter sans param�tre, pour avoir de l'info de syntaxe.
Exemple d'utilisation : 
sendIGCtoNMEA.pl -file sample.igc -ip 192.168.0.106 -proto UDP -GGA -RMC -time NOW

A noter, un fonctionement �trange avec XCSOar :
###############################################

Si on n'envoie que la trame GGA :
---------------------------------
$GPGGA,173314,4843.403,N,00612.265,E,1,12,10,367.0,M,,,,*34

Message "Mauvaise r�ception GPS" (Attente du signal GPS) ; L'infobox Alt GPS indique 313m (alors que la trame donne 367m), le vario donne des indications

Si on n'envoie que la trame RMC : 
---------------------------------
$GPRMC,181943,A,4843.403,N,00612.265,E,,,,*3F
L'infobox Alt GPS est vide, le vario reste � 0. La partie horizontale du GPS fonctionne : le planeur avance, la vitesse sol est indiqu�e

