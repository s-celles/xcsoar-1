﻿#!/usr/bin/perl
#
# sendIGCtoNMEA
#
# Lecture d'un fichier IGC, et envoi des infos de vol en format NMEA, dans une "connexion" UDP
#
# executer sendIGCtoNMEA.pl --help pour de l'aide

use IGC;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev);
use Term::ReadKey;
use IO::Socket;
use Data::Dumper;

use strict;

my $port = "4353";             # le port TCP ou UDP par défaut pour envoi des infos NMEA
my $proto = "TCP";             # protocole par defaut

my $defaultSats = 12;          # nombre de satellites qu'on indique voir, si info pas recuperee de l'IGC


{
  my $speed = 1;
  my $withGGA = 0;
  my $withRMC = 0;
  my $withLXWPO = 0;
  my $withPOV = 0;
  my $startTime = "";
  my $minutes2skip = 0;
  my ($file, $output, $ip, $help); 
  my $ret = GetOptions
     ( 
       "file=s"          => \$file,
	   "output=s"        => \$output,
	   "ip=s"            => \$ip,
	   "proto=s"         => \$proto,
	   "port=i"          => \$port,
	   "speed=i"         => \$speed,
	   "minutes2skip=i"  => \$minutes2skip,
	   "time=s"          => \$startTime,
	   "GGA"             => \$withGGA,
	   "RMC"             => \$withRMC,
	   "LXWPO"           => \$withLXWPO,
	   "POV"             => \$withPOV,
	   "h|help"          => \$help,
     );
  
  &syntaxe("parametre incorrect") unless($ret);
  &syntaxe() if ($help);
  
  &syntaxe("Manque un argument oblidatoire : 'file'") unless (defined($file));
  &syntaxe("Manque un argument oblidatoire : 'ip'") unless (defined($ip));
  
  die "fichier $file n'existe pas" unless(-e $file);
  die "adresse ip incorrecte $^$ip" unless($ip =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/);
  $proto = uc($proto);
  die "proto doit etre 'TCP' ou 'UDP'" if (($proto ne "UDP") && ($proto ne "TCP"));
  die "valeur de 'speed' incorrecte : $speed" if (($speed < 1) || ($speed > 10));
  die "valeur de 'time' incorrecte : $startTime" if (($startTime ne "") && ($startTime ne "NOW") && ($startTime !~ /^\^\d{6}$/));

  if (($withGGA == 0) && ($withRMC == 0) && ($withPOV == 0) && ($withLXWPO == 0))
  {
    $withGGA = 1;
    $withRMC = 1;
  }
  
  my $igc = new IGC();  
  $igc->read(file => $file);
  
  #my $recordsI = $igc->getRecords(type => "B");
  #print Dumper($recordsI); exit;
  
  my $dateRecord = $igc->getHeaderByKey("DTE");
  
  print "### On va rejouer le fichier $file en date du $dateRecord vers $ip: $proto/$port, speed $speed";
  print ", vers le fichier $output" if (defined($output));
  print " ###\n";
  
  my $recordsB = $igc->getRecords(type => "B");
  die "pas d'enregistrement de type 'B' (GPS) dans ce fichier IGC" if (scalar(@$recordsB) == 0);
  
  my $sock = IO::Socket::INET->new(Proto    => $proto, PeerAddr => $ip, PeerPort => $port, Timeout => 2);
  die "impossible de creer la soket $proto : $!\n" unless(defined($sock));
  
  my $firstRecordB = $igc->getOneRecord(index => 0, type => "B");
  my $startAltitude = $$firstRecordB{alt};
  print "   altitude de depart : $startAltitude" . "m, heure de depart : $$firstRecordB{time}\n";
  
  my $firstRecordSeconds = IGC::UTC2seconds($$firstRecordB{time});   # le time du 1ere enregistrement de type B, en secondes
  
  my $recordsB = $igc->getRecords(type => "B");
  
  #my $NMEAs = $igc->computeNMEA(output => $output, time => "NOW", nbsats => 12);
  #print Dumper($NMEAs); exit;
  my $nbre = scalar(@$recordsB);
  print "   $nbre trames a emettre\n\n";

  print "appuyer sur une touche pour demarrer l'envoi\n";

  #   en attendant l'appui d'une touche, on envoie la première trame toutes les secondes
  #   on incrémente l'heure si le parametre time a été passé
  ReadMode 'cbreak';
  
  $startTime = IGC::seconds2UTC("NOW") if ($startTime eq "NOW");
  my $startSeconds = $startTime eq "" ? -1 : IGC::UTC2seconds($startTime);
  my $time = $startTime;
  my $seconds = $startSeconds;
  
  while (! defined(ReadKey(-1)))
  {
	&sendNMEA($firstRecordB, $sock, $ip, $port, withGGA => $withGGA, withRMC => $withRMC, withLXWPO => $withLXWPO, withPOV => $withPOV, noprint => 1, time => $time);
	sleep(1);
	$seconds += 1;
	$time = $startTime eq "" ? "" : IGC::seconds2UTC($seconds);
  }
  ReadMode 'normal';
  
  # Maintenant, on deroule les trames NMEA
  if ($startTime ne "")    # on reinitialise l'heure de début
  {                        # si valués, startTime et startSeconds donnent l'heure de départ des trames NMEA
    $startTime = $time;
	$startSeconds = IGC::UTC2seconds($startTime);
  }
  
  my $lastElapsedSeconds = $firstRecordSeconds;   # lastElapsedSeconds contient l'elaspedSeconds du record précédent
  my $lastAlt = 0;                                # altitude du record B précédent
  my $nbre = 0;
  foreach my $record (@$recordsB)    # tous les records de type B
  {
    $nbre ++;
    next if ($nbre <= 1);   # on ne rejoue pas le premier enregistrement : il a été joué lors de l'attente d'une touche pressée
	
	my $elapsedSeconds = IGC::UTC2seconds($$record{time}) - $firstRecordSeconds; # le nombre de secondes entre ce record de type B, et le premier
    next if (($minutes2skip != 0) && ($elapsedSeconds / 60 < $minutes2skip));     # on veut sauter les 1eres minutes de l'enregistrement
  
	my $vario = sprintf("%.2f", ($$record{alt} - $lastAlt) / ($elapsedSeconds - $lastElapsedSeconds));   # le vario. On compare avec l'enregistrement B précédent
	$lastAlt = $$record{alt};
	
	if ($speed > 1)  # on veut accélérer les trames NMEA par rapport aux records de type B
	{
	  $elapsedSeconds /= $speed;  # on triche
	}
	my $sleep = $elapsedSeconds - $lastElapsedSeconds;   # le temps du sleep
	$lastElapsedSeconds = $elapsedSeconds;
	
	select(undef, undef, undef, $sleep);    # equivalent a un sleep, mais accepte les fractions

    my $time = "";
    if ($startTime ne "")   # on ajuste le time de la trame
    {
	  $time = IGC::seconds2UTC($startSeconds + $elapsedSeconds);   # le time de la trame NMEA a emettre
	}
	&sendNMEA($record, $sock, $ip, $port, withGGA => $withGGA, withRMC => $withRMC, withLXWPO => $withLXWPO, withPOV => $withPOV, time => $time, vario => $vario);

  }

}

# envoi du ou des messages NMEA correspondant à un record de type B
sub sendNMEA
{
  my $record = shift;
  my $sock = shift;
  my $ip - shift;
  my $port = shift;
  my %args = (@_);
  
  my $withGGA = $args{withGGA};    # trames GPGGA
  my $withRMC = $args{withRMC};    # trames GPRMC
  my $withPOV = $args{withPOV};    # trames openvario
  my $withLXWPO = $args{withLXWPO};  # trames LXWPO
  my $noprint = $args{noprint};
  
  delete $args{withGGA};
  delete $args{withRMC};
  delete $args{withPOV};
  delete $args{withLXWPO};
  delete $args{noprint};
  
  my $nbsats = $$record{SIU} > 0 ? $$record{SIU} : $defaultSats;    #nombre de satellites GPS captés
  $args{nbsats} = $nbsats;
  my $NMEAs = IGC::NMEAfromIGC($record, %args);

  if ($withGGA)
  {
    print "$$NMEAs{GPGGA}\n" unless($noprint);
	&sendNetwork($sock, $ip, $port, $$NMEAs{GPGGA} . "\n");
  }
  
  if ($withRMC)
  {
    print "$$NMEAs{GPRMC}\n" unless($noprint);
	&sendNetwork($sock, $ip, $port, $$NMEAs{GPRMC} . "\n");
  }  

  if ($withLXWPO)
  {
    print "$$NMEAs{LXWPO}\n" unless($noprint);
	&sendNetwork($sock, $ip, $port, $$NMEAs{LXWPO} . "\n");
  }  

  if ($withPOV)
  {
    print "$$NMEAs{POV_E}\n" unless($noprint);
	&sendNetwork($sock, $ip, $port, $$NMEAs{POV_E} . "\n");
    print "$$NMEAs{POV_P}\n" unless($noprint);
	&sendNetwork($sock, $ip, $port, $$NMEAs{POV_P} . "\n");
  }  

}

# envoi d'un message en TCP ou UDP
sub sendNetwork
{
  my $sock = shift;
  my $ip - shift;
  my $port = shift;
  my $message = shift;
  
  $sock->send($message) or die "Send error: $!\n";
}

sub syntaxe
{
  my $mess = shift;
  
  if ($mess ne "")
  {
     print "\n### ERREUR : $mess ###\n\n" 
  }
  
  print "sendIGCtoNMEA.pl\n";
  print "Ce script lit un fichier IGC et transmet les infos de vol en UDP, en format NMEA\n";
  print "L'objectif est de rejouer un vol dans XCSoar, comme en mode simulation\n\n";
  print "les parametres sont :\n";
  print "  . -file <fichier>. obligatoire. C'est le fichier .igc a analyser\n";
  print "  . -output <fichier>. facultatif. Pour ecrire les infos NMEA dans un fichier\n";
  print "  . -ip <adresseIP>. obligatoire. L'adresse IP a laquelle envoyer les infos NMEA\n";
  print "  . -proto <TCP|UDP>. facultatif. Le protocole reseau utilise. UDP par defaut\n";
  print "  . -port <port UDP>. facultatif. Le eport UDP pour l'envoi des informations. 4353 par defaut\n";
  print "  . -speed <speed>. facultatif. Valeur entiere de 1 a 10. Permet d'accelerer la simulation. 1 par defaut\n";
  print "  . -minutes2skip <mn>. facultatif. Le nombre de minutes en debut de fichier qu'on desire court-circuiter\n";
  print "  . -time <time>. facultatif. L'heure de depart des trames envoyees. format : 'HHMMSS', ou 'NOW' pour l'heure courante\n";
  print "  . --GGA. facultatif. Envoi de trames NMEA GPGGA\n";
  print "  . --RMC. facultatif. Envoi de trames NMEA GPRMC\n";
  print "  . --LXWPO. facultatif. Envoi de trames NMEA LXWPO \(LXNAV\)\n";
  print "  . --POV. facultatif. Envoi de trames NMEA POV \(openvario\)\n";
  print "  . --help. facultatif. Affiche cette aide\n\n";
  print "Si aucune des options '--GGA', '--RMC', '--LXWPO', '--POV' choisie, alors le defaut est d'envoyer les trames GPGGA et GPRMC\n";
  
  exit;
}