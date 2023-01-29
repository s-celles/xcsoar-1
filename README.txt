Depot xcsoar de vmath54 - README.txt
------------------------------------
Ce depot contient certains outils en lien avec xcsoar 

Dossier "waypoints"
-------------------
Contient des scripts et fichiers permettant d'acc�der aux cartes VAC pdf depuis les waypoints des a�rodromes propos�s par un fichier .cup
FRA_FULL_HighRes.xcm ou France.cup

- FranceVacEtUlm.cup : c'est le fichier de r�f�rence. Il contient l'ensemble des terrains r�pertori�s sur le site SIA, les terrains militaires et les terrains basULM
                       il est mis � jour � partir des informations provenant de ces 3 sources
					   
- VAC.pm :             librairie perl. Partage des donn�es et proc�dures utilis�es par la plupart des scripts perl d�crits ici
							  
- getVACfiles.pl :     script perl, qui permet de r�cup�rer les cartes VAC de France, depuis le site du SIA :
                       https://www.sia.aviation-civile.gouv.fr/aip/enligne/Atlas-VAC/FR/VACProduitPartie.htm
					  
- getMILfiles.pl :    script perl qui permet de r�cup�rer les cartes VAC des bases militaires, depuis
                      http://www.dircam.air.defense.gouv.fr/index.php/infos-aeronautiques/a-vue-france
					  ne r�cup�re pas les terrains ayant m�me code que des terrains SIA

- getBASULMfiles.pl : script perl, qui permet de r�cup�rer les cartes PDF du site baseULM depuis 
                      http://basulm.ffplum.info/PDF/
					  par d�faut, ne r�cup�re pas les terrains ayant m�me code que des terrains SIA ou MIL

- makeZipFromBasulm.pl : contruit un fichier zip par "grande r�gion", et y d�pose les fichiers de basULM correspondants
                      les fichies basULM sont volumineux, ceci permet d'avoir plusieurs fichiers, plus petits
					  
- getInfosFromVACfiles.pl : analyse les fichires pdf issus des bases SIA et MIL
                      compare avec les infos de FranceVacEtUlm.csv, et produit un fichier interm�diaire : listVACfromPDF.csv
					  ATTENTION : utilise le binaire pdftotext.exe (windows) pour analyser le contenu des fichiers pdf
					  
- getInfosFromApiBasulm.pl : recup�ration des infos basULM, sur tous les terrais r�pertori�s par la FFPLUM
                      n�vessite une cl� API (un mot de passe d'application), qu'on peut demander � admin.basulm@orange.fr
					  compare avec les infos de FranceVacEtUlm.csv, et produit un fichier interm�diaire : listULMfromAPI.csv					  
					  
- genereDetailsFromCUP.pl : permet de cr�er un fichier de d�tails de waypoints a partir d'un fichier .cup
                      ce fichier de d�tails de waypoints permet de faire le lien entre un terrain, et la carte VAC ou basULM correspondante
					  Voir README.details pour plus d'infos

- regenereReferenceCUPfile.pl : permet de mettre � jour les infos du fichier de r�f�rence FranceVacEtUlm.csv
                      g�n�re le fichier FranceVacEtUlm_new.csv � partir du fichier FranceVacEtUlm.csv, et les �ventuelles nouvelles infos
                      provenant de listVACfromPDF.csv et listULMfromAPI.csv
					  Voir README.update pour plus d'infos
					  
- France_details.cup et FranceVacEtUlm_details.cup : des fichiers de d�tail g�n�r�s avec France.cup et FranceVacEtUlm.cup � l'aide de genereDetailsFromCUP.pl
