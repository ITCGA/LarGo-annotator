#!/usr/bin/env perl

# Perl modules
use strict;
use warnings;
use diagnostics;

use File::Basename;
use Getopt::Long;

# BioPerl modules
use Bio::SearchIO;
use Bio::AlignIO;

# TriAnnot SIMsearch modules
use SIMsearch::mapping::MAP;
use SIMsearch::orf::ORF;

my ($opt_input, $opt_gff, $opt_ctl, $opt_help) = ("", "", "", "");
&GetOptions('input|i=s' => \$opt_input, 'gff|g=s' => \$opt_gff, 'ctl|c=s' => \$opt_ctl, 'help|h' => \$opt_help);

my $help = <<'&EOT&';
 Usage:
	-i <file path> -c <file path> -g <file path>

  Options:
	-i FASTA format file
	-c control file
	-g GFF file (optional)
	-h help

	e.g.
	fna2orf.pl -i transcripts.fna -c orf.ctl

&EOT&

if ( $opt_help ) {
	print $help;
	exit 1;
}

if (!$opt_input) {
	print STDERR "ERROR:Input sequence file path.\n";
	die "ERROR:$!";
}
if (!$opt_ctl) {
	print STDERR "ERROR:Input control file path.\n";
	die "ERROR:$!";
}

print "[fna2orf.pl]: Start! " , `date`;

my ($sFNA, $sCtl, $sGFF) = ($opt_input, $opt_ctl, $opt_gff);

my %rap_option = ();
&read_option($sCtl, \%rap_option);

my $sWD = $rap_option{'WD'};

my $sBLAST_EXE = $rap_option{'BLAST_EXE'};
my $sBLAST_OPT = $rap_option{'BLAST_OPT'};
my $sFORMATDB_EXE = $rap_option{'FORMATDB_EXE'};

my $sDB = $rap_option{'DB'};
my $nID = $rap_option{'MIN_ID'};
my $nAA = $rap_option{'MIN_AA'};

my $sSOURCE = $rap_option{'SOURCE'};
if(!$sSOURCE){
	$sSOURCE = ".";
}

&run_blast($sWD, $sBLAST_EXE, $sBLAST_OPT, $sFORMATDB_EXE, $sFNA, $sDB, "protein");

print "[fna2orf.pl]: BLAST has done. " , `date`;

my $sBLOUT = $sWD . "/" . basename($sDB) . ".b";

my $fname = basename($sFNA);
$fname =~ s/\.(\S+)$//g;
my $sORF_FNA = $sWD . "/" . $fname . "_orf.fna";
my $sORF_FAA = $sWD . "/" . $fname . "_orf.faa";

my $orf = SIMsearch::orf::ORF->new(-blast => $sBLOUT, -seq => $sFNA);
if($nID){
	$orf->identity_cutoff($nID);
}else{
	$orf->identity_cutoff(0.5);
}

if($nAA){
	$orf->length_cutoff($nAA);
}else{
	$orf->length_cutoff(100);
}

$orf->find;
$orf->write_nuc(-file => $sORF_FNA);
$orf->write_ami(-file => $sORF_FAA);

if($sGFF && $sGFF ne ""){
	if(-f $sGFF){
		my $orf_dat = $sWD . "/orf.dat";
		open(ORFDAT, ">$orf_dat");
		open(ORF, $sORF_FAA);
		while(<ORF>){
			chomp;
			if(/^>/){
				my @a0 = split(/ /);
				my ($sid, $sp, $ep, $sts, $sc, $evalue, $identity) = ($a0[0], $a0[1], $a0[2], $a0[3], $a0[4], $a0[5], $a0[6]);
				$sid =~ s/^>//g;
				$sp =~ s/^start://g;
				$ep =~ s/^end://g;
				$sts =~ s/^orf://g;
				$sc =~ s/^inframe_stop_codon://g;
				if($sp < $ep && $sc eq "false"){
					print ORFDAT join("\t", $sid,$sp,$ep,$sts,$sc,$evalue,$identity),"\n";
				}
			}
		}
		close ORF;
		close ORFDAT;
		my $sgff_out = basename($sGFF);
		$sgff_out =~ s/\.[^.]+$//g;
		$sgff_out = $sWD . "/" . $sgff_out . "_orf.gff";
		&make_orfgff($sWD, $sGFF, $orf_dat, $sSOURCE);
		rename $sgff_out, $sGFF;
	}else{
		print STDERR "ERROR: Can't find the file.\n";
		die "ERROR:$!\n";
	}
}

print "[fna2orf.pl]: Finish! " , `date`;
