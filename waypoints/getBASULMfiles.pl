#!/usr/bin/perl
#
# recuperation des cartes BASULM, depuis le site http://basulm.ffplum.info/PDF/<terrain>.pdf
#
# recupere 
#    - tous les fichiers au format "LFdddd.pdf" ou dddd sont des caracteres num�riques
#    - et, pour les fichiers au format "LFss.pdf" o� ss sont des caracteres non num�riques
#        . si $noSIA == 0, tous ces fichiers sont recuperes
#        . sinon, ne r�cup�re que ceux qui ne se trouvent pas dans le repertoire "$dirVAC" et le repertoire "$dirMIL" : ce sont des fichiers issus du site SIA ou des bases militaires
#                 ceci �limine, par exemple, les fichiers comme LFEZ.pdf
#
# Il faut disposer de la liste des terrains (le dossier n'est plus listable). On l'a � partir du fichier listULMfromAPI.csv, g�n�r� depuis le script getInfosFromApiBasulm.pl
#
# parametres facultatifs de ce script
#  . -partial <siteULM>. permet de faire une reprise des chargements � partie de ce site
#                        Utile si incident lors de l'op�ration, pour ne pas tout reprendre
#  . --help : facultatif. Affiche cette aide\n\n";  


use LWP::Simple;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev);
use Data::Dumper;

use strict;

my $dirDownload = "basulm";    # le r�pertoire qui va contenir les documents pdf charges
my $URL = "http://basulm.ffplum.info/PDF/";
my $ficULM = "listULMfromAPI.csv";

my $dirVAC = "./vac";
my $dirMIL = "./mil";     
my $noSIA = 1;


{
  my $partial;              # pour une reprise, � un terrain donn�
  my $help;
  
  my $ret = GetOptions
   ( 
     "partial=s"       => \$partial,
	 "h|help"         => \$help,
   );
  
  die "parametre incorrect" unless($ret);
  &syntaxe() if ($help);

  my $ads = &getADs($ficULM);     # la liste des codes terrain
  
  my $SIAs = {};  # la liste des fichiers SIA et MIL
  if ($noSIA)
  {
    &listFicsSIA($dirVAC, $SIAs);
    &listFicsSIA($dirMIL, $SIAs);
  }

  mkdir $dirDownload;
  
  foreach my $ad (@$ads)
  {
  
    next if (($partial ne "") && ($ad lt $partial));
	# exit if (-ad eq "LF3023"); pour arreter le chargement sur un site donn�
  
    if ($noSIA && ($ad =~ /^LF\S\S$/) && defined($$SIAs{$ad}))
	{
	  # print "$ad dans basulm et SIA\n";
	  next;
	}

    my $urlPDF = $URL . $ad . ".pdf";
	#print "$urlPDF\n";
	print "$ad\n";
	
	my $status = getstore($urlPDF, "$dirDownload/$ad" . ".pdf");   #download de la fiche pdf
    unless ($status =~ /^2\d\d/)
    {
	  print "code retour http $status lors du chargement du doc $urlPDF\n";
	  print "Arret du traitement\n";
	  exit 1;
	}
	sleep 1;
  }
}

# ajoute au hash passe en second parametre les fichiers pdf qui sont dans le repertoire $rep. Ce sont, normalement, les fichiers issus des sites SIA ou MIL
sub listFicsSIA
{
  my $dir = shift;
  my $SIAs = shift;
  
  die "$dir n'est pas un repertoire" unless (-d $dir);
  
  my @fics = glob("$dir/*.pdf");
  return if (scalar(@fics) == 0);
  
  foreach my $ad (@fics)
  {
    my ($rep,$fic) = $ad =~ /(.+[\/\\])([^\/\\]+)$/;
    $fic =~ s/\.pdf$//;
	$$SIAs{$fic} = 1;
  }
}

# recuperation de la liste des codes terrain a partir du fichier listULMfromAPI.csv
sub getADs
{
  my $fic = shift;
  
  my @ADs;
  
  die "unable to read fic $fic" unless (open (FIC, "<$fic"));

  while (my $line = <FIC>)
  {
	chomp ($line);
	next if ($line eq "");
	
	my ($code) = split(";", $line);
	next if ($code eq "");
	
	push(@ADs, $code);
  }
  close FIC;
  return \@ADs;
}

sub syntaxe
{
  print "getBASULMfiles.pl\n";
  print "Ce script permet de recuperer les cartes ULM sur le site BASULM\n";
  print "Il utilise en entree le fichier listULMfromAPI.csv, genere auparavant a l'aide du script getInfosFromApiBasulm.pl\n";
  print "les parametres facultatifs sont :\n";
  print "  . -partial <siteULM>. permet de faire une reprise des chargements a partie de ce site\n";
  print "                        Utile si incident lors de l'operation, pour ne pas tout reprendre\n";
  print "  . --help : facultatif. Affiche cette aide\n\n";
  print "Exemple :\n";
  print "getBASULMfiles.pl -partial \n";
  print "\n";
  
  exit;
}