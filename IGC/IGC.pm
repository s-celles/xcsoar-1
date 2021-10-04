package IGC;

# traitments sur fichier IGC
#
# voir :
#   . https://www.fai.org/sites/default/files/civl/documents/sporting_code_s7_h_-_civl_flight_recorder_specification_2018_v0.9.0.pdf
#   . https://github.com/twpayne/igc2kmz/blob/master/igc2kmz/igc.py
#   . http://www.gpspassion.com/forumsen/topic.asp?TOPIC_ID=17661
#
# Ne lit que certains types de record
# Librairie tr�s tr�s partielle en terme de fonctionnalit�s ; a utiliser avec mod�ration
#
#
# type A : Manufacturer code. Un seul enregistrement dans le fichier, c'est le premier. Les 3 premiers caract�res sont le code constructeur. format libre
#---------------------------
#
# type H : Header. Diff�rentes informations g�n�rales � l'IGC
#----------------
#
# type I : permet de sp�cifier le contenua de l'extension du format du record B. Un seul record I, apr�s les records H
# -------------------------
# exemple : I023638FXA3940SIU : I,02,36,38,FXA,39,40,SIU  (extension pour un flarm ou xcsoar)
#  02 : 2 extensions
#  36, 38, FXA : le 1ere extension est le FXA, du 36eme au 38 eme caractere. FXA = Fix Accuracy : Estimated Position Error, en m�tres
#  39,40,SIU : la seconde extention est le SIU, du 39eme au 40eme caractere. SIU = Satellites In Use
#
# type C : Task. Le circuit param�tr�
# ----------------
# doit �tre apr�s types H, I, J et avant type B
#   pour le moment, on ne decodera pas ces enregistrements.
#  . le premier donne la date et le time UTC de la d�claration, la date pr�vue du vol, le task-id, le nbre de 'turn points' (sans d�but et fin), et eventuellement du texte libre
#       C080915130551000000000002 : C,080915,130551,000000,0000,02
#  . Les enregistrements C suivants donnent les points pr�vus, le 1er �tant le d�collage et le dernier l'atterrissage
#                 latitude, longitude, description
#       C4800983N00635916EREMIREMONT GARE
#
# type B : basic tracklog record
# ------------------------------
# c'est celui qui nous int�resse le plus
# exemple : B1101355206343N00006198WA0058700558  (ce sont les infos minimum du type B. il peut y avoit des infos compl�mentaires apr�s)
# B,110135,5206343N,00006198W,A,00587,00558
# 
# autre exemple, avec un flarm (pr�c�d� d'une trame I023638FXA3940SIU)
# B 1340114843374N00612901EA003710042100309
# B 134011 4843374N 00612901E A 00371 00421 003 09
#
# B: record type is a basic tracklog record
# 134011: <time UTC>. Heure d'�t�, donc en r�alit� 15:40:11
# 4843374N : <lat> : 48� 43.374" Nord
# 00612901E : <long> : 006� 12.901" Est
# A: <alt valid flag> confirming this record has a valid altitude value
# 00371 : <altitude from pressure sensor>
# 00421 : <altitude from GPS>
#
# 003 : extension 1 flarm : <FXA> : Fix Accuracy. Erreur de position estim�e = 3m
# 09  : extension 2 flarm : <SIU> : Satellites In Use
#
# type F : Satellite constellation
# --------------------------------
# enregistrement obligatoire
#   
# F160240 04 06 09 12 36 24 22 18 21 : F,060240,04,0609,1236,2422,1821
# 16h02mn40s - 4 satellites : 0609, 1236, 2422, 1821
#
# type E : Event
# --------------
# enregistrement d'�venements sp�cifiques
#   pour le moment, on ne decodera pas ces enregistrements
#
# type G : Scurity
# ----------------
# cheksum du message IGC, pour v�rifier l'int�grit�. C'est une 'signature' du fichier, pour assurer la v�rit�
#on ne d�code pas ces enregistrements


use Data::Dumper;

use strict;

my $defaultQNH = 1013.25;   # pression par d�faut � 0m
my $flarmEXT = 0;           #mis a un si le record I est I023638FXA3940SIU


my %typeRecords =      # le type de record que l'on traite. read = fonction qui va traiter le read, ...
(
   "A" => { format => "array", read => \&_read_recordA } ,  # Manufacturer code
   "B" => { format => "array", read => \&_read_recordB } ,  # tracklog
   "H" => { format => "hash",  read => \&_read_recordH } ,  # Headers. format hash : on peut rechercher par la cl�
   "I" => { format => "array", read => \&_read_recordI } ,  # sp�cification de l'extension du record B
   "F" => { format => "array", read => \&_read_recordF } ,   # Les satellites utilis�s par le GPS
   "C" => { format => "array", read => \&_read_record_generic } ,  # Task. On ne fait pas de traitement dessus
   "E" => { format => "array", read => \&_read_record_generic } ,  # Events. On ne fait pas de traitement dessus
   "G" => { format => "array", read => \&_read_record_generic } ,  # Security. controle d'int�grit� des donn�es
   "Z" => { format => "array", read => \&_read_record_generic } ,  # Hors protocole. C'est la poubelle, ou y met ce qui ne va pas ailleurs
);
 
sub new {
  my $proto = shift;
  my %args =  @_;
  
  my $class =  ref($proto) || $proto;
  my $self = {};
  bless($self, $class);
  
  $self->{file} = $args{file} if (defined($args{file}));   # le fichier IGC a traiter
  &_initRecords($self);
    
  return $self;
}

# procedure interne, pour initialiser les structures d'enregistrement des traces igc
sub _initRecords
{
  my $self = shift;

  $self->{types}{all} = { nb => 0, values => []}; # tous les enregistrements du fichier IGC de type connus
  $self->{types}{A} = { nb => 0, values => [] };  # enregistrements de type A. 1 seul
  $self->{types}{B} = { nb => 0, values => []};   # les records de type B
  $self->{types}{H} = { nb => 0, values => [], hash => {}};   # les records de type H
  $self->{types}{I} = { nb => 0, values => [] }; # enregistrements de type I. Un seul
  $self->{types}{F} = { nb => 0, values => [] }; # enregistrements de type F
  $self->{types}{C} = { nb => 0, values => [] }; # enregistrements de type C
  $self->{types}{E} = { nb => 0, values => [] };
  $self->{types}{G} = { nb => 0, values => [] };
  $self->{types}{Z} = { nb => 0, values => [] }; # hors protocole. Permet de stocker les records inconnus
}

# recup du tabeau de tous les records
# arguments formels
#   . type : le type de record concern�, ou "all" pour tous. Par d�faut, "all"
#   . hash : si diff�rent de 0, retourne le hash, si c'est un type de format hash
sub getAllRecords
{
  my $self = shift;
  my %args =  (type => "all", hash => 0, @_);
  
  my $type = $args{type};
  my $with_hash = $args{hash};
  
  if (($with_hash == 0) || ($type eq "all"))
  {
    return $self->{types}{$type}{values};
  }
  
  return undef if ($typeRecords{$type}{format} ne "hash");
  return $self->{types}{$type}{hash};
}

# recuperation des enregistrements IGC, d�cod�s
# un argument formel :
#   . type. facultatif. Le type de record concern�, ou "all" pour tous. Par d�faut, "all"
sub getRecords
{
  my $self = shift;
  my %args =  (type => "all", @_);
  
  my $type = $args{type};
  
  return $self->{types}{$type}{values};
}

# recuperation d'un enregistrement IGC, d�cod�s
# deux arguments formels :
#   . index. obligatoire. L'index du record recherch�
#   . type. facultatif. Le type de record concern�, ou "all" pour tous. Par d�faut, "all"
#
# retourne le record, ou undef si index est en dehors du tableau
sub getOneRecord
{
  my $self = shift;
  my %args =  (type => "all", @_);
  
  die "getOneRecord. Il faut au moins passer l'argument formel 'index'" unless(defined($args{index}));
  my $type = $args{type};
  my $index = $args{index};
  
  return undef if ($index >= $self->{types}{$type}{nb} + 1);
  return $self->{types}{$type}{values}[$index];
}


# recup�ration d'un record de type H, par sa cl�
# la cl� correspond aux 3 caract�res � partir du 3eme. Par exemple, la cl� pour la ligne suivante est : CID
# HFCIDCOMPETITIONID:DG
#
# par d�faut, retourne la valeur de la cl�. 
# 
# un argument 'classique' : la cl� recherch�e
# un argument formel :
#   . return : peu avoir les valeurs "value", "record", "raw"
#        value : par d�faut. retourne la valeur de la cl�.  
#        record : le hash contenant les informations du 'record'
#        raw : la ligne d'origine
#
# exemple, pour obtenir la date de l'enregistrement (JJMMAA) :
#  my $date = $igc->getHeaderByKey("DTE");
sub getHeaderByKey
{
  my $self = shift;
  my $key = shift;
  my %args =  ( @_ );
  
  my $return = $args{return};

  return undef unless(defined($self->{types}{H}{hash}{$key}));
  my $record = $self->{types}{H}{hash}{$key};
  return $record if ($return eq "record");
  return $$record{raw} if ($return eq "raw");
  return $$record{value};
}

  
# lecture du fichier igc
sub read
{
  my $self = shift;
  my %args =  @_;
  
  $self->{file} = $args{file} if (defined($args{file}));
  
  die "IGC.read : Il manque le nom de fichier" unless(defined($self->{file}));  
  die "IGC.read : unable to read fic $self->{file}" unless (open (FIC, "<$self->{file}"));
  
  &_initRecords($self);
  
  my $nbLines = 0;
  while (my $line = <FIC>)
  {
    $nbLines++;
	chomp($line);
	
	my $type = substr($line, 0, 1);
    $type = "Z" unless (defined($typeRecords{$type}));  # on triche, pour les records de types inconnus

	my $function = $typeRecords{$type}{read}; # la fonction qui traite la lecture de ce type de record
    next unless (defined($function));         # ne doit pas arriver
	
	my $result = &$function($self, $line);           # on appelle la fonction specifique a ce type de record
	unless(defined($result))
	{
	  die "IGC.read : Erreur ligne $nbLines :\n    $line\n";
	  next;
	}
	
	$$result{lineNumber} = $nbLines;
    $self->{types}{$type}{nb}++;
	my $values = $self->{types}{$type}{values};
	push(@$values, $result);
	
	if ($typeRecords{$type}{format} eq "hash")   # on veut aussi pouvoir acceder aux infos via un hash
	{
	  my $key = $$result{key};     # la cl� du hash
	  my $hash = $self->{types}{$type}{hash};
	  $$hash{$key} = $result;
	}

	$type = "all";
    $self->{types}{$type}{nb}++;
	my $values = $self->{types}{$type}{values};
	push(@$values, $result);
  }
  
  close FIC;
}


# fonction interne, appelee par fonction read. lecture d'un record de type B
# on associe aux recors B le record F imm�diatement pr�c�dent, ou undef s'il n'y en a pas 
#  (il devrait y en avoir au moins un, le record F est obligatoire, et le premier doit se trouvers avant les records B)
sub _read_recordB
{
  my $self = shift;
  my $line = shift;
  
  return undef unless ($line =~ /^B(\d{6})(\d{7}[NS])(\d{8}[EW])(.)(\d{5})(\d{5})(.*)/);

  my ($time, $lat, $long, $flag, $altSensor, $altGPS, $ext) = ($1, $2, $3, $4, $5, $6, $7);
  my $nbRecordF = $self->{types}{F}{nb};
  my $lastRecordF = $nbRecordF > 0 ? $self->{types}{F}{values}[$nbRecordF - 1] : undef; # le dernier record F rencontr�
  my $alt = $altSensor eq "" ? $altGPS : $altSensor;
  $alt =~ s/^0*//;   # on retire les eventuels chiffres 0
  
  my $record =  {type => "B", time => $time, lat => $lat, long => $long, flag => $flag, altSensor => $altSensor, altGPS => $altGPS, alt => $alt, ext => $ext, lastRecordF => $lastRecordF, raw => $line };
  if ($flarmEXT && ($ext =~ /^(\d\d\d)(\d\d)$/))
  {
    $$record{FXA} = $1;  # erreur de position estim�e, en m
	$$record{SIU} = $2;  # nombre de satellites GPS captes
  }
  return $record;
}

# fonction interne, appelee par fonction read. lecture d'un record de type F
# F160240 04 06 09 12 36 24 22 18 21 : F,060240,04,0609,1236,2422,1821
# 16h02mn40s - 4 satellites : 0609, 1236, 2422, 1821

sub _read_recordF
{
  my $self = shift;
  my $line = shift;
  
  return undef unless ($line =~ /^F(\d{6})(.*)/);

  my ($time, $last) = ($1, $2);
  my $nbSats = 0;
  my $sats = "";
  if ($last =~ /^(\d\d)(.*)/)
  {
    $nbSats = $1;
	$sats = $2;
  }
  
  return {type => "F", time => $time, nbSats => $nbSats, sats => $sats, raw => $line };
}

# fonction interne, appelee par fonction read. lecture d'un record de type H (Header)
sub _read_recordH
{
  my $self = shift;
  my $line = shift;
  
  if ($line =~ /^H([FOP])(DTE)(\d{6})/)       # UTC date, format DDMMYY
  {
    my ($source, $key, $date) = ($1, $2, $3);
    return {type => "H", key => $key, source => $source, raw => $line, value => $date};
  }

  if ($line =~ /^H([FOP])(FXA)(\d+)/)       # precision, en metres
  {
    my ($source, $key, $accuracy) = ($1, $2, $3);
    return {type => "H", key => $key, source => $source, raw => $line, value => $accuracy};
  }

  if ($line =~ /^H([FOP])(\w{3})(.*?):(.*)/)       # autres headers
  {
    my ($source, $key, $ext_key, $value) = ($1, $2, $3, $4);
    return {type => "H", key => $key, source => $source, raw => $line, long_key => "H" . $source . $key . $ext_key, value => $value};
  }
  
  return undef;
}

  
# fonction interne, appelee par fonction read. lecture d'un record de type A
#un seul record de type A
sub _read_recordA
{
  my $self = shift;
  my $line = shift;
  
  return undef unless ($line =~ /^A(.*)/);

  my $value = $1;
  return undef if ($value eq "");
  
  return {type => "A", value => $value, raw => $line};
}

# fonction interne, appelee par fonction read. lecture d'un record de type I
# un seul record de type I
sub _read_recordI
{
  my $self = shift;
  my $line = shift;
  
  my @extends;      #les extensions
  return undef unless ($line =~ /^I(\d\d)(.*)/);
  
  my ($nbreExt, $last) = ($1, $2);
  for (my $ind = 0; $ind < $nbreExt; $ind++)   # parcours des extensions d�clar�es
  {
    return undef unless ($last =~ /(\d\d)(\d\d)(\w{3})(.*)/);
	my ($start, $end, $ext) = ($1, $2, $3);
	$last = $4;
	push(@extends, {ext => $ext, start => $start, end => $end});
  }
  $flarmEXT = 1 if ($line eq "I023638FXA3940SIU");  # extension du flarm et de XCSoar : FXA et SIU
  
  return {type => "I", exts => \@extends, raw => $line };
}

# lecture d'un enregistrement sans traitement.
sub _read_record_generic
{
  my $self = shift;
  my $line = shift;
  
  my $type = substr($line, 0, 1);
  return {type => $type, raw => $line};
}

##################### computeNMEA ##############################
# calcule les trames MNEA a partir des records de type B
# peut recevoir un ensemble de parametres, qui seront pass�s � la fonction &NMEAfromIGC, 
#    voir les commentaires de cette fonction &NMEAfromIGC pour de l'info sur les param�tres
# sauf les param�tres suivants :
#   . output. facultatif. si pr�sent, les trames NMEA seront �crites dans le fichier sp�cifi� par ce param�tre
#   . format. facultatif. Format des trames NMEA dans le fichier output. valeurs possibles : "GGA", "RMC", "GGA_RMC"
#   . time. facultatif. Format "NOW", ou <HHMMSS>. Si pr�sent, les trames NMEA d�buteront � l'heure pr�cis�e ;
#              et l'heure des trames suivantes seront d�cal�es de la m�me facon que le fichier IGC
#              par exemple, si time = "120000" et que l'heure des 3 premi�res trames IGC de type B est "130551", "130557", "130602",
#                 l'heure des trames NMEA corespondantes sera "120000", "200006", "200011"
#              Si valeur "NOW", l'heure de d�but sera l'heure du moment (en fait, HHMMSS)
# 
sub computeNMEA
{
  my $self = shift;
  my %args =  ( output => "", @_ );
  
  my $output = $args{output};
  my $format = $args{format};
  
  my $startSecond;   # l'heure de demarrage souhait�e des trames NMEA, en secondes
  
  if (defined($args{time}))
  {
    $startSecond = &UTC2seconds($args{time});
	die "computeNMEA. Le parametre 'time' n'est pas correct : $args{time}" if ($startSecond < 0);
  }
  
  my $firstRecord = $self->getOneRecord(index => 0, type => "B");   # preier record de type B
  return [] unless(defined($firstRecord));   # pas de records de type B
  
  my @NMEA = ();      # va contenir toutes les trames NMEA
  
  if ($output ne "")   # on veut ecrire dans un fichier
  {
    die "ouverture du fichier $output impossible" unless (open OUTPUT, ">$output");
  }
  
  my $firstSecond = &UTC2seconds($$firstRecord{time});  # secondes du premier record de type B
  my $deltaSeconds = $startSecond - $firstSecond;    # la diff�rence de temps souhait�e, en secondes. Peut �tre n�gatif
  
  my $records = $self->{types}{B}{values};
  foreach my $record (@$records)    # tous les records de type B
  {
    if (defined($startSecond))     #on veut modifier l'heure des trames NMEA
	{
	  my $recordSecond = &UTC2seconds($$record{time});   # le time du record B, en secondes
	  my $newSecond = $recordSecond + $deltaSeconds;     # le time que l'on souhaite maintenant
	  $args{time} = &seconds2UTC($newSecond); # le nouveau time, en HHMMSS
	}
	my $res = &NMEAfromIGC($record, %args);
    push(@NMEA, $res);

	if ($output ne "")
	{
	  if (($format eq "GGA") || ($format eq "GGA_RMC") || ($format eq "RMC_GGA"))
	  {
	    print OUTPUT "$$res{GPGGA}\n";
	  }
	  if (($format eq "RMC") || ($format eq "GGA_RMC") || ($format eq "RMC_GGA"))
	  {
	    print OUTPUT "$$res{GPRMC}\n";
	  }
	}
  }
  close OUTPUT if ($output ne "");
  
  return \@NMEA;
}

##################### NMEAfromIGC ##############################
# calcul d'une trame NMEA a partir d'un record de type B
# parametres formels :
#  . time. facultatif. format : "HHMMSS" ou "HHMMSS.mmm". Si pr�sent, �crit ce time dans la trame NMEA, au lieu de celle du record de type B
#  . fix. facultatif. Pour les trames GGA, indique le "fix quality". 1 par d�faut
#                     . 0 : invalid. Ceci mettra le nbre de satellites et le HDOP � 0.
#                     . 1 : GPS. On recuperera le nombre de satellites dans la trame IGC de type "F" la plus proche. 
#                                Ou la valeur du parametre nbsats si le nbre de satellites IGC est inf�rieur � 4
#                                Si pas de trame F, ou si trame F ne contient pas de satellite et pas de parametre nbsats, on traite comme fix=0
#                     . 8 : simulation. On traite comme 0
#  . nbsats. facultatif. Force le nombre de satellites de la trame NMEA, si fix = 1 et que le nbre de satellites de l'IGC est inf�rieur � cette valeur
#  . hdop. facultatif. Pour les trames GGA, fixe le hdop si fix = 1. Si pas valu� et pas satellites, mis � "0.0". par d�faut : "10" (au pif)
#
# Format d'une trame NMEA GGA et RMC  (voir http://www.gpsinformation.org/dale/nmea.htm#GGA et #RMC)
#    Voir aussi http://www.gpspassion.com/forumsen/topic.asp?TOPIC_ID=17661
#
# GPGGA
#------
#exemple condor :
#      $GPGGA,120023.068,4843.8718,N,00610.7960,E,1,12,10,609.3,M,,,,,0000*0D
# $GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47
# 123519 : hhmmss. peut �tre suivi de milli�mes de secondes : 123519.289
# 4807.038,N : latitude
# 01131.000,E : longitude
# 1 : "fix quality" : type de positionnement. 0=invalid, 1=GPS, ..., 8=simulation
# 08 : nombre de satellites
# 0.9 : HDOP : pr�cision horizontale. Fonction du nombre de satellites, et de leur positionnement
# 545.4,M : altitude en m�tres, au dessus du niveau de la mer
# 46.9,M : Height of geoid (mean sea level) above WGS84 ellipsoid (peut �tre laiss�e vide, ou 0.0,M)
# 2 champs vides : "time in seconds since last DGPS update" et "DGPS station ID number"
# *47 : le checksum de la trame. Commence par "*"
#
# GPRMC
# -----
# exemple condor :
#      $GPRMC,120023.068,A,4843.8718,N,00610.7960,E,48.54,270.00,,,,*19
#
# $GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A
# 123519 heure UTC. peut �tre suivi de milli�mes de secondes : 123519.289
# A            Status A=active or V=Void.
# 4807.038,N   Latitude 48 deg 07.038' N
# 01131.000,E  Longitude 11 deg 31.000' E
# 022.4        Speed over the ground in knots
# 084.4        Track angle in degrees True
# 230394       Date - 23rd of March 1994
# 003.1,W      Magnetic Variation
# *6A          The checksum data, always begins with *
#
#
# LXWP0 (LXNAV)
# $LXWP0,Y,222.3,1665.5,1.71,,,,,,239,174,10.1
#
# loger_stored (Y/N)
# IAS (kph) ----> Condor uses TAS!
# baroaltitude (m)
# 3-8 vario (m/s) (last 6 measurements in last second)
# heading of plane
# windcourse (deg)
# windspeed (kph)
#
# on se limite ici aux infos de baroaltitude et de vario
#
# POV : openvario
# ---------------
# voir http://www.openvario.org/doku.php?id=projects:series_00:software:nmea


sub NMEAfromIGC
{
  my $record = shift;
  my %args =  (format => "RMC", fix => 1, hdop => "0.0", nbsats => 0, @_ );
  
  my $fix = $args{fix};
  my $nbsats = $args{nbsats};
  my $hdop = $args{hdop};
  my $time = $args{time};
  my $vario = $args{vario};
  
  my $ref = ref $record;
  die "NMEAfromIGC. Le parametre doit etre une reference vers un hash" if ($ref ne "HASH");
  die "NMEAfromIGC. Le parametre doit etre un record IGC de type B" if ($$record{type} ne "B");
  
  my $retour = {};     # la valeur de retour
  
  my $HHutc = $$record{time} . ".000";
  $$record{lat} =~ /^(\d{4})(\d{3})(\w)/;
  my $latitude = $1 . "." . $2 . "," . $3;
  $$record{long} =~ /^(\d{5})(\d{3})(\w)/;
  my $longitude = $1 . "." . $2 . "," . $3;

  my $pressure = &getPressureFromAlti($$record{alt});     # la pression atmosph�rique standard OACI, d�duite de l'altitude
  
  if ($fix == 1)   # positionnement de type GPS. On essair de recuperer les infos de satellites
  {
    my $recordF = defined($$record{lastRecordF}) ? $$record{lastRecordF} : undef;  # le dernier record F rencontr� avant ce record B
	$nbsats = $$recordF{nbSats} if (defined($recordF) && ($$recordF{nbSats} > $nbsats));
	if ($nbsats > 0)
	{
	  $hdop = "10" if ($hdop eq "0.0");     # valeur arbitraire
	}
	else
	{
	  $fix = 0;     # invalid : on ne recupere pas d'infos de satellites
	}
  }

  if ($fix != 1)    # 0 (invalid, ou 8 (simulation"). On positionne le nbre de  satellites a 0
  {
    $nbsats = 0;
	$hdop = "0.0";
  }  
  
  $time = (($time =~ /^\d{6}$/) || ($time =~ /^\d{6}\.\d{3}/)) ? $time : $$record{time};    # time pass� en parametre, ou time du record F

# ----  trame RMC ------
      #                   UTC     A=valid   Latitude       Longitude    vitesse sol    angle de route
  my $RMC = "\$GPRMC" . ",$time" . ",A" . ",$latitude" . ",$longitude" . ","         .  "," .
      #                 date   var. magn.
                        ","  .   ",";
  $RMC .= "*" . &checksumNMEA($RMC);    # on ajoute le checksum a la trame NMEA
  $$retour{GPRMC} = $RMC;
  
# ----  trame GGA ------ 
#                          UTC        Latitude       Longitude       fix           hdop
  my $GGA = "\$GPGGA" . ",$time" . ",$latitude" . ",$longitude" . ",$fix" . "," . sprintf("%02d", $nbsats) . ",$hdop" .
#                         altitude AMSL              correction hauteur    vide, vide
                        ",$$record{alt}.0" . ",M" .   ",,"              . ",,";
  
  $GGA .= "*" . &checksumNMEA($GGA);    # on ajoute le checksum a la trame NMEA
  $$retour{GPGGA} = $GGA;
  
# --- trame LXWP0 -----
  #$vario = -10;    # pour essais
  my $LXWP0 = "\$LXWP0,Y,,$$record{alt},$vario,,,,,,,,";
  $LXWP0 .= "*" . &checksumNMEA($LXWP0);    # on ajoute le checksum a la trame
  $$retour{LXWP0} = $LXWP0;
  
  # ---- trame POV -------
  my $POV_P = "\$POV,P," . $pressure;
  $POV_P .= "*" . &checksumNMEA($POV_P);    # on ajoute le checksum a la trame POV
  $$retour{POV_P} = $POV_P;
  
  if (defined($vario))
  {
    my $POV_E = "\$POV,E," . $vario;
    $POV_E .= "*" . &checksumNMEA($POV_E);    # on ajoute le checksum a la trame POV
    $$retour{POV_E} = $POV_E;
  }
  
  return $retour;
}


# calcul du checksum d'une trame NMEA
# "The checksum field consists of a '*' and two hex digits representing an 8 bit exclusive OR of all characters between, but not including, the '$' and '*'"
sub checksumNMEA
{
  my $trame = shift;
  
  $trame =~ s/^\$//;       # le $ en tete de trame ne participe pas au calcul du checksum
  $trame =~ s/\*\d\d$//;   # on supprime un ancien checksum �ventuel
  my $v = 0;
  $v ^= $_ for unpack 'C*', $trame;
  sprintf '%02X', $v;
}

# transfo d'une heure en format HHMMSS ou HHMMSS.mmm en secondes
# l'heure peut aussi �tre "NOW" ; dans ce cas, la fonction retourne le nombre de secondes depuis 00h00m00s
sub UTC2seconds
{
  my $time = shift;
  
  my $millis;
  
  if ($time eq "NOW")
  {
	my ($sec, $min, $hour) = localtime(time);
	my $seconds = ($hour * 3600) + ($min * 60) + $sec;
	return $seconds;
  }

  ($time, $millis) = ($1, $2) if ($time =~ /^(\d{6})\.(\d*)$/);
  
  return -1 unless($time =~ /^(\d\d)(\d\d)(\d\d)$/);
  my $seconds = ($1 * 3600) + ($2 * 60) + $3;
  
  if (defined($millis))
  {
    $seconds .= "." . $millis;
	return sprintf("%.3f", $seconds);
  }
  else
  {
    return $seconds;
  }
}

# transfo de secondes en heure HHMMSS ; si milliemes, celui-ci sera conserv�
# si la parametre est "NOW", retourne l'heure courante
sub seconds2UTC
{
  my $seconds = shift;

  if ($seconds eq "NOW")
  {
	my ($sec, $min, $hour) = localtime(time);
	return sprintf("%02d%02d%02d", $hour, $min, $sec);
  }
  
  my $millis;
  ($seconds, $millis) = ($1, $2) if ($seconds =~ /^(\d*)\.(\d*)$/);
  
  return -1 if ($seconds < 1);
  return -1 if ($seconds > 3600 * 24);

  my $hh = int($seconds / 3600);
  my $mm = int(($seconds % 3600) / 60);
  my $ss = int((($seconds % 3600) % 60));
  my $time = sprintf("%02d%02d%02d", $hh, $mm, $ss); # le nouveau time, en HHMMSS
  if (defined($millis))
  {
    $millis .= "00";
	return $time . "." . substr($millis, 0, 3);
  }
  return $time;
}

# calcul de la pression en atmosphere normalisee OACI a partir de l'altitude
#
# voir https://fr.wikipedia.org/wiki/Atmosph%C3%A8re_normalis%C3%A9e
# 
# par d�faut, calcule avec le QNH 1013 ; sinon, ccelui-ci est pass� en param�tre QNH
#
sub getPressureFromAlti
{
  my $alti = shift;
  my %args =  @_;

  
  my $QNH = defined($args{QNH}) ? $args{QNH} : $defaultQNH;   # pression au niveau de la mer
  
  my $pressure = $QNH * (((288 - (0.0065 * $alti )) / 288) ** 5.255);
  return sprintf("%.2f", $pressure);
}
  
1;
__END__
