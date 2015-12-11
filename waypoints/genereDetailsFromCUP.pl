#!/usr/bin/perl

# Utilitaire XCSoar
#
# generation d'un fichier de details de waypoints a partir d'un fichier .cup pass� en parametre
# ce fichier de details permettra dans XCSoar de faire le lien avec le fichier pdf du waypoint s'il existe dans les bases SIA, MIL ou baseULM
# Cet utilitaire utilise un fichier de r�f�rence (FranceVacEtUlm.cup) qui r�pertorie tous les terrains VAC (dispos sur site SIA), MIL (militaires) et basULM
#
# le fichier resultat est cree dans le meme repertoire que le .cup passe en parametre
#
# exemple : genereDetailsFromCUP.pl -file ../dossier1/myFichier.cup
#           dans ce cas, le fichier de details sera ../dossier1/myFichier_details.cup
#                                                ou ../dossier1/myFichier_details_noulm.cup si option --noULM
#
# peut �galement cr�er un fichier archive (.zip) avec tous les terrains VAC et/ou MIL (militaires) et/ou baseULM r�f�renc�s, s'ils sont bien sur 
#       stock�s dans un ou des dossiers (ou repositories) locaux
#       ce fichier sera ../dossier1/myFichier.zip ou ..../myFichier_noulm.zip
#
# Cet utilitaire peut utiliser deux algos diff�rents pour associer un terrain du fichier .cup avec ceux du fichier de r�f�rence :
#  - par d�faut, comparaison des coordonn�es g�ographiques du terrain avec ceux du fcihier de r�f�rence
#       La variable $toleranceGeog permet d'indiquer la marge d'erreur acceptable
#
#  - si parametre "-searchByCode <x>", o� <x> est une valeur num�rique :
#            recherche le code OACI ou FFPLUM du terrain dans un des champs du fichier .cup
#            En g�n�ral, <x> peut avoir la valeur 0, 1 ou 10
#            Si 1, suppose que le champ ne contien que le code ; sinon, le code peut �tre inclus dans le champ
#
# si ex�cut� sans parametre, donne de l'aide
#
# parametres accept�s :
#
# . -file <fichier> : obligatoire. C'est le fichier .cup � analyser
# . --zip : facultatif. Si pr�sent, g�n�re un fichier zip contenant les PDF des terrains concern�s
# . --noulm : facultatif. Si pr�sent, ne traite pas les terrains de BASULM
# . -searchByCode <x> : facultatif. Ne recherche pas la correspondance de terrain avec les coordonn�es GPS, mais dans la colonne x du fichier .cup
#        x commence par 0 : 0 est la colonne 1, et ainsi de suite

use VAC;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev);
use File::Basename;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use Data::Dumper;

use strict;

my $ficREF      = "FranceVacEtUlm.cup";  # le fichier de reference. 

my %cibles =      # dirPDF donne le repertoire qui contient les PDF, pour la cible.
(                 # necessaire si $createZip != 0
  vac  =>   { dirPDF => "./vac",    founds => 0 },
  mil =>    { dirPDF => "./mil",    founds => 0 },
  basulm => { dirPDF => "./basulm", founds => 0 },
);


# $toleranceGeog est la tol�rance en centi�me de degr�s lors de comparaisons de 2 points g�ographiques
#     1 mn de latitude  =~ 1km300 ; 1 mn de longitude =~ 1km900
#     $toleranceGeog = 1 donne 0.01 degr� de latitude =~ 800m, 0.01 degr� de longitude =~ 1km100
#   ne pas monter trop haut, sinon beaucoup de faux-positifs. Une valeur de 1 ou 2 semble raisonnable
my $toleranceGeog = 1;

{
    my ($file, $searchByCode, $withZip, $noulm, $help);
  my $ret = GetOptions
     ( 
       "file=s"          => \$file,
       "searchByCode=i"  => \$searchByCode,
	   "zip"             => \$withZip,
	   "noulm"           => \$noulm,
       "h|help"          => \$help,
     );

  die "parametre incorrect" unless($ret);
  &syntaxe() if ($help);
  
  if ($file eq "")
  {
    print 'il faut passer le nom du fichier .cup en parametre "file"' . "\n\n";
	&syntaxe();
  }
  
  die "fichier |$file| non trouve" unless (-f $file);
  my ($ficDetail, $ficZip) = &computeFileNames($file, $noulm, $withZip);     # on calcule le nom des fichiers detail et .zip a partir de celui du .cup
  
  #### on r�cup�re les infos du fichier de r�f�rence.
  my $REFs = &readRefenceCupFile($ficREF);
  
  my $details;
  if (defined($searchByCode))  # lecture et traitement du fichier, en recherchant le code terrain dans une colonne
  {
    $details = &traiteCUPfileByCode($file, $searchByCode, $REFs, \%cibles, $noulm); 
  }
  else     # lecture et traitement du fichier en comparant les coordonnees geographiques
  {
    my $ADs;   # contient les terrains du fichier .cup. Utile uniquement si on veut le re ecrire
    ($details, $ADs) = &traiteCUPfileByCoordsGeog($file, $REFs, \%cibles, $noulm);
	#&rewriteCUPfile($ADs, $REFs); exit;     # decommenter la ligne pour regenerer le fichier CUP
  }
  #print Dumper($details);
  my $nbre = scalar(@$details);
  print "$nbre terrains trouves\n";
  print "    $cibles{vac}{founds} fichiers provenant du SIA\n";
  print "    $cibles{mil}{founds} fichiers provenant des bases militaires\n";
  print "    $cibles{basulm}{founds} fichiers provenant de baseULM\n";
  print "\n";
  print "Fichier de details : $ficDetail\n";
  
  &genereFicDetails($ficDetail, $details);
	
  if ($withZip)
  {
    die "Il manque des fichiers, on ne cree pas le fichier zip" unless (&existFicsPDF($details, \%cibles));   # on verifie que les fichiers PDF existent
    print "Fichier zip : $ficZip\n";	
	&createZip($ficZip, $details);
  }
}

############### ecriture du fichier de details
sub genereFicDetails
{
  my $fic = shift;
  my $details = shift;

  die "unable to write fic |$fic|" unless (open (FIC, ">$fic"));
  foreach my $detail (@$details)
  {
    #print "$$detail{name};$$detail{code}\n";
    #print uc($$detail{name}), ";$$detail{code}\n";
	print FIC "[$$detail{name}]\n";
	print FIC "file=$$detail{cible}/$$detail{code}.pdf\n";
	print FIC "\n";
  }
  close FIC;
}

# analyse du fichier CUP passe en parametre
# on compare avec les coordonnes geographiques (GPS) des terrains du fichier de reference
# %cibles est passe en parametre afin d'indiquer le nombre de sites trouves pour chacune
sub traiteCUPfileByCoordsGeog
{
  my $fic = shift;
  my $REFs = shift;
  my $cibles = shift;
  my $noulm = shift;

  my %ADs;           # on memorise les terrains du fichier .cup

  # $coords va contenir une reference entre coordonnees geographiques t le code d'un terrain de la base de reference
  #                    {$lat => {$long => $code}}
  my $coords = &computeCoords($REFs);
  
  #my $latdec = 4600; my $longdec = 533; my $toleranceGeog = 2;  # Amberieu. LFXA = 4598 et 534
  #my $code = &matchCoords($coords, $latdec, $longdec, $toleranceGeog);
  #print "$latdec, $longdec => $code (on cherche 4598 et 534)\n"; exit;

  die "unable to read fic |$fic|" unless (open (FIC, "<$fic"));
  my $nbADs = 0;         #nombre de lignes du fichier .cup. Sera utilise pour trier la tableau DETAILS
  while (my $line = <FIC>)
  {
    chomp($line);
	next if ($line eq "");
    my ($name, $code1, $country, $lat, $long, $elevation, $nature, $qfu, $dimension, $frequence, $comment) = split(",", $line);
	next if ($name eq "");
	$name =~ s/^\"//;
	$name =~ s/\"$//;
	next if ($name eq "");
	$comment =~ s/^\"//;
	$comment =~ s/\"$//;
	$nbADs++;
	my $rang = $nbADs;
    
	#next if ($name ne "Amberieu");
	
	$ADs{$name} = { name => $name, code => $code1, rang => $rang, lat => $lat, long => $long, elevation => $elevation, nature => $nature, qfu => $qfu, dimension => $dimension, frequence => $frequence, comment => $comment };

	next if (($nature <1) || ($nature > 5));    # on ne prend que les waypoints de type terrain d'atterrissage
	
	my $latdec = &convertCUPtoDec($lat, 2);      # conversion en degres.centiemes
	my $longdec = &convertCUPtoDec($long, 2);
	die "traiteCUPfile. $name : probleme dans coordonnes geographiques. $lat => $latdec, $long => $longdec" if (! defined($lat) || ! defined($long));
	$ADs{$name}{lat_dec} = $latdec;
	$ADs{$name}{long_dec} = $longdec;

	$latdec = sprintf ("%.0f", $latdec * 100);    # on retire le point decimal
	$longdec = sprintf ("%.0f", $longdec * 100);
	
	my $code = &matchCoords($coords, $latdec, $longdec, $toleranceGeog);
	if ($code ne "")    # on a trouve un terrain dans fichier de ref, avec les m�mes coordonnees geographiques
	{
	  my $REF = $$REFs{$code};
	  if (defined($$REF{ADmatch}))   # une autre ligne du fichier .cup matche avec le meme terrain de REF
	  {
	    my $otherName = $$REF{ADmatch};
		my $name2keep = &compareADs($ADs{$otherName}, $ADs{$name});   # on compare les deux terrains, pour en choisir un
		
		unless ($name2keep)
		{
	      print "ATTENTION. $otherName et $name matchent tous les deux le terrain $code, et on n'a pas pu definir de priorite !!!\n";
		  next;
		}
	    next if ($name2keep eq $otherName );  # c'est le premier terrain qui est retenu
	    delete $ADs{$otherName}{codeREF};     # c'est le terrain courrant qui est retenu. On supprime le lien du terrain precedent
	  }

	  $$REF{ADmatch} = $name;         #on memorise le terrain dans le hash de reference
	  $ADs{$name}{codeREF} = $code;   # et le code de reference dans le hash des terrains
	}
  }
  close FIC;
  #print Dumper($ADs{"FERME BEAUCHAMP"}), Dumper($$REFs{LF5453}), Dumper($$coords{4877}); exit;

  #print Dumper($ADs{rang}); exit;
  
  # maintenant, on prepare le tableau @details, qui va contenir les terrains qui sont retenus
  # on trie le hash %ADs sur le rang (ordre d'apparition de la ligne)
  my @details = ();
  foreach my $ad (sort ({$ADs{$a}{rang} <=> $ADs{$b}{rang} } keys %ADs))   # on lit dans le m�me ordre que fichier initial
  {
	my $AD = $ADs{$ad};
    if (defined($$AD{codeREF}))   # c'est un terrain reference
	{
	  my $REF = $$REFs{$$AD{codeREF}};
	  #print "$$AD{name};$$AD{codeREF}\n";
	  my $cible = $$REF{cible};
	  die "$$REF{code};$ad. Cible |$cible| inconnue" if (($cible eq "") || (! defined($$cibles{$cible})));
	  next if (($noulm) && ($cible eq "basulm"));
	  push(@details, { code => $$REF{code}, name => $ad, cible => $cible });
	  $$cibles{$cible}{founds}++;
	}
  }
  return (\@details, \%ADs);
}

# compare 2 terrains du fichier .cup qui matchent avec une terrain de REF
# essai de determiner un terrain prioritaire
sub compareADs
{
  my $AD1 = shift;
  my $AD2 = shift;
  
  ###  si on est sur le fichier France.cup, on donne priorite au terrain en "Landefeld" ou "Flugplatz"
  return $$AD1{name}   # on est sur le fichier France.cup
    if ((($$AD1{comment} eq "Landefeld") || ($$AD1{comment} eq "Flugplatz")) && ($$AD2{comment} ne "Landefeld") && ($$AD2{comment} ne "Flugplatz"));
  return $$AD2{name}
    if ((($$AD2{comment} eq "Landefeld") || ($$AD2{comment} eq "Flugplatz")) && ($$AD1{comment} ne "Landefeld") && ($$AD1{comment} ne "Flugplatz"));
	
  ### on donne ensuite priorite aux type de terrain 2 (terrain d'aviation en herbe) 3 () et 5 (terrain d'aviation en dur)
  return $$AD1{name}
    if ((($$AD1{nature} == 2) || ($$AD1{nature} == 5)) && ($$AD2{nature} =! 2) && ($$AD2{nature} != 5));
  return $$AD2{name}
    if ((($$AD2{nature} == 2) || ($$AD2{nature} == 5)) && ($$AD1{nature} =! 2) && ($$AD1{nature} != 5));
  ### puis aux terrains de type 3 (atterrissage en campagne)
  return $$AD1{name}
    if (($$AD1{nature} == 3) && ($$AD2{nature} =! 2) && ($$AD2{nature} =! 3) && ($$AD2{nature} != 5));
  return $$AD2{name}
    if (($$AD2{nature} == 3) && ($$AD1{nature} =! 2) && ($$AD1{nature} =! 3) && ($$AD1{nature} != 5));
	
  ## maintenant, priorite a celui qui a une frequence, une dimension ou un qfu value
  return $$AD1{name} if (($$AD1{frequence} ne "") && ($$AD2{frequence} eq ""));
  return $$AD2{name} if (($$AD2{frequence} ne "") && ($$AD1{frequence} eq ""));
  return $$AD1{name} if (($$AD1{qfu} ne "") && ($$AD2{qfu} eq ""));
  return $$AD2{name} if (($$AD2{qfu} ne "") && ($$AD1{qfu} eq ""));
  return $$AD1{name} if (($$AD1{dimension} ne "") && ($$AD2{dimension} eq ""));
  return $$AD2{name} if (($$AD2{dimension} ne "") && ($$AD1{dimension} eq ""));
  
  return undef;
}

####### recherche la correspondance d'un couple latitude = longitude avec la reference $coords
# $tolerance donne la marche de tolerance, en 100eme de degres (=~ 800m pour latitude, =~ 1km100 pour longitude)
sub matchCoords
{
  my $coords = shift;
  my $lat = shift;
  my $long = shift;
  my $tolerance = shift;
    
  return $$coords{$lat}{$long} if (defined($$coords{$lat}{$long}));  # egalite 'distance = 0) ; on fait simple

  for (my $indLat = 0; $indLat <= $tolerance; $indLat++)
  {
    for (my $indLong = 0; $indLong <= $tolerance; $indLong++)
    {
	  return $$coords{$lat + $indLat}{$long + $indLong} if (defined($$coords{$lat + $indLat}{$long + $indLong}));
	  return $$coords{$lat + $indLat}{$long - $indLong} if (defined($$coords{$lat + $indLat}{$long - $indLong}));
	  return $$coords{$lat - $indLat}{$long + $indLong} if (defined($$coords{$lat - $indLat}{$long + $indLong}));
	  return $$coords{$lat - $indLat}{$long - $indLong} if (defined($$coords{$lat - $indLat}{$long - $indLong}));
    }
  }
  return undef;
}

# construction d'une reference entre coordonnees geographiques ({$lat => {$long => $code}}) et le code d'un terrain de la base de reference
sub computeCoords
{
  my $REFs = shift;
  
  my %coords;
  
  foreach my $code (keys %$REFs)
  {
    my $REF = $$REFs{$code};
	my $lat = &convertCUPtoDec($$REF{lat}, 2);      # conversion en degres.centiemes
	my $long = &convertCUPtoDec($$REF{long}, 2);
	die "computeCoords. $code : probleme dans coordonnes geographiques. $$REF{lat} => $lat, $$REF{long} => $long" if (! defined($lat) || ! defined($long));
	$$REF{lat_dec} = $lat;
	$$REF{long_dec} = $long;
	$lat = sprintf ("%.0f", $lat * 100);    # on retire le point decimal
	$long = sprintf ("%.0f", $long * 100);
	
	if (defined($coords{$lat}{$long}))
	{
	  my $altCode = $coords{$lat}{$long};
	  die "computeCoords. $code et $altCode : Conflit dans les coordonnes geographiques : $lat et $long";
    }
	$coords{$lat}{$long} = $code;
  }
  return \%coords;
}

# analyse du fichier CUP passe en parametre
# analyse en recherchant le sode terrain dans un champ du fichier ($column)
# %cibles est passe en parametre afin d'indiquer le nombre de sites trouves pour chacune
sub traiteCUPfileByCode
{
  my $fic = shift;
  my $column = shift;
  my $REFs = shift;
  my $cibles = shift;
  my $noulm = shift;

  my @ADs = ();
  die "unable to read fic |$fic|" unless (open (FIC, "<$fic"));

  while (my $line = <FIC>)
  {
    chomp($line);
	next if ($line eq "");
	my @columns = split(",", $line);
	my $name = $columns[0];
	$name =~ s/^\"//;
	$name =~ s/\"$//;
	my $val = $columns[$column];
	chomp($val);
	next if ($val eq "");
	$val =~ s/^\"//;
	$val =~ s/\"$//;

	next unless (($val =~ /^(LF\S\S)$/) || ($val =~ /^(LF\S\S) /) || ($val =~ / (LF\S\S)$/) || ($val =~ / (LF\S\S) /) || ($val =~ / (LF\S\S)$/) ||
	    ($val =~ /^(LF\d\d\d\d)$/) || ($val =~ /^(LF\d\d\d\d) /) || ($val =~ / (LF\d\d\d\d)$/) || ($val =~ / (LF\d\d\d\d) /) || ($val =~ / (LF\d\d\d\d)$/));
	my $code = $1;

    my $REF = $$REFs{$code};
	unless (defined($REF))
	{
	  print "### $code pas trouve dans le fichier de reference\n";
	  next;
	}
	my $cible = $$REF{cible};
	die "$code;$name. Cible |$cible| inconnue" if (($cible eq "") || (! defined($$cibles{$cible})));
	next if (($noulm) && ($cible eq "basulm"));
	push(@ADs, { code => $code, name => $name, cible => $cible });
	$$cibles{$cible}{founds}++;
  }

  close FIC;
  return \@ADs;
}

sub createZip
{
 my $ficZip = shift;
  my $ADs = shift;

  my $zip = Archive::Zip->new();
  foreach my $AD (@$ADs)
  {
	my $file_member = $zip->addFile($$AD{ficPDF}, "$$AD{cible}/$$AD{code}.pdf");
  }
  die "probleme ecriture du fichier $ficZip" unless ( $zip->writeToFileNamed($ficZip) == AZ_OK );
}

# Calcul du nom des fichiers detail et .zip a partir de celui du .cup
sub computeFileNames
{
  my $cupFile = shift;
  my $noulm = shift;
  
  my($filename, $dirs) = fileparse($cupFile);   # on recupere le chemin et le 'petit' nom du fichier
  $dirs =~ s/\\/\//g;
  $dirs =~ s/\/$//;
  die "$filename : doit avoir l'extension .cup ou .CUP" unless ($filename =~ /(.*)\.cup/i);
  my $name = $1;    # le nom de fichier, sans extension
  my $comp = "";
  $comp = "_noulm" if ($noulm);
  return ("$dirs/${name}${comp}_details.txt", "$dirs/${name}${comp}.zip");
}
 
sub existFicsPDF
{
  my $ADs = shift;
  my $cibles = shift;

  my $retour = 1;
  foreach my $AD (@$ADs)
  {
    my $dir = $$cibles{$$AD{cible}}{dirPDF};
	my $fic = "$dir/$$AD{code}.pdf";
    # print "$fic\n";
	unless (-f $fic)
	{
	  print "### $fic pas trouve\n";
	  $retour = 0;
	}
	$$AD{ficPDF} = $fic;
  }
  return $retour;
}

############ optionnel. Re ecriture du fichier .cup en stdout
# interet : pouvoir ecraser certains champs du fichier d'origine a partir de la base de reference
sub rewriteCUPfile
{
  my $ADs = shift;
  my $REFs = shift;
  
  
   foreach my $ad (sort ({$$ADs{$a}{rang} <=> $$ADs{$b}{rang} } keys %$ADs))  # on lit dans le m�me ordre que fichier initial
  {
	my $AD = $$ADs{$ad};
    if (defined($$AD{codeREF}))   # lie avec est un terrain reference
	{
	  my $codeRef = $$AD{codeREF};
	  my $REF = $$REFs{$codeRef};
	  
	  if (($$AD{lat} ne $$REF{lat}) || ($$AD{lat} ne $$REF{lat}))
	  {
	    #printf "%-6s;%-25s. Lat ou long : %-22s <- %s\n", $codeRef, $$AD{name}, "$$AD{lat},$$AD{long}", "$$REF{lat},$$REF{long}";
		$$AD{lat} = $$REF{lat};
		$$AD{long} = $$REF{long};
	  }
	  
	  $$AD{elevation} =~ s/m$//;
	  $$AD{elevation} =~ s/\.\d$//;
	  if (abs($$AD{elevation} - $$REF{elevation}) > 2)
	  {
	    #printf "%-6s;%-25s. Altitude : %-6s <- %s\n", $codeRef, $$AD{name}, $$AD{elevation}, $$REF{elevation};
	  }
	  $$AD{elevation} = $$REF{elevation} . "m";
	  
	  # print "$$AD{name},$codeRef,$$AD{nature}     $$REF{nature}\n" if ($$AD{nature} ne $$REF{nature});
	  
	  if ($$AD{frequence} ne $$REF{frequence})
	  {
	    #printf "%-6s;%-25s. Frequence : %-6s  : %s\n", $codeRef, $$AD{name}, $$AD{frequence}, $$REF{frequence};
		$$AD{frequence} = $$REF{frequence};
	  }
	}
    print "\"$$AD{name}\",$$AD{code},FR,$$AD{lat},$$AD{long},$$AD{elevation},$$AD{nature},$$AD{qfu},$$AD{dimension},$$AD{frequence},\"$$AD{comment}\"\n";
    #print "\"$$AD{name}\";$$AD{code};FR;$$AD{lat};$$AD{long};$$AD{elevation};$$AD{nature};$$AD{qfu};$$AD{dimension};$$AD{frequence};\"$$AD{comment}\"\n";
  }
}


# - file <fichier> : obligatoire. C'est le fichier .cup � analyser
# - --withZip : facultatif. Si pr�sent, g�n�re un fichier zip contenant les PDF des terrains concern�s
# - searchByCode <x> : facultatif. Ne recherche pas la correspondance de terrain avec les coordonn�es GPS, mais dans la colonne x du fichier .cup
#        x commence par 0 : 0 est la colonne 1, et ainsi de suite

sub syntaxe
{
  print "genereDetailsFromCUP.pl\n";
  print "Ce script permet de generer un fichier de details de waypoints a partir d'un fichier waypoints '.cup'\n\n";
  print "les parametres sont :\n";
  print "  . -file <fichier>. obligatoire. C'est le fichier .cup a analyser\n";
  print "  . -searchByCode <x> : facultatif. Ne recherche pas la correspondance de terrain avec les coordonnees GPS, mais dans la colonne x du fichier .cup\n";
  print "  . --zip : facultatif. Si present, genere un fichier zip contenant les PDF des terrains concernes\n";
  print "  . --noulm : facultatif. Si present, netraite pas les terrains de basULM\n";
  
  exit;
}