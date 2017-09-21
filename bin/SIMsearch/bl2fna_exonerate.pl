#!/usr/bin/env perl

# Perl modules
use strict;
use warnings;
use diagnostics;

use File::Basename;
use Getopt::Long;
use Data::Dumper;

# BioPerl modules
use Bio::SearchIO;
use Bio::AlignIO;

# TriAnnot SIMsearch modules
use SIMsearch::mapping::MAP;

my ($opt_ctl, $opt_output, $opt_help) = ("", 0, "", 0);
&GetOptions('ctl|c=s' => \$opt_ctl, 'output|o=s' => \$opt_output, 'help|h' => \$opt_help);


my $help = <<'&EOT&';
 Usage:
	-c <file path> -o <file path>

 Options:
	-c control file
	-o output file (optional)
	-h help

	e.g.
	bl2fna_exonerate.pl -c map.ctl

&EOT&

if ( $opt_help ) {
   print $help;
   exit 1;
}

if (!$opt_ctl) {
	print STDERR "ERROR:Input control file path.\n";
	die "ERROR:$!";
}

print "[bl2fna_exonerate.pl]: Start! " , `date`;

my ($sCtl, $sOutput) = ($opt_ctl, $opt_output);

my %rap_option = ();
&read_option($sCtl, \%rap_option);

my $sWD = $rap_option{'WD'};

my $nT_GAP = $rap_option{'T_GAP'};
my $nG_GAP = $rap_option{'G_GAP'};
my $nID_HSP = $rap_option{'ID_HSP'};
my $nCV_HIT = $rap_option{'CV_HIT'};
my $nCLIP_MGN = $rap_option{'CLIP_MGN'};

my $sG_SEQ = $rap_option{'G_SEQ'};
my $sT_SEQ = $rap_option{'T_SEQ'};
my $sT_DB = $rap_option{'T_DB'};

my $nID_FIN = $rap_option{'ID_FIN'};
my $nCV_FIN = $rap_option{'CV_FIN'};

my $sBLAST_EXE = $rap_option{'BLAST_EXE'};
my $sBLAST_OPT = $rap_option{'BLAST_OPT'};
my $sFORMATDB_EXE = $rap_option{'FORMATDB_EXE'};
my $sFASTACMD_EXE = $rap_option{'FASTACMD_EXE'};

my $sEXONERATE_EXE = $rap_option{'EXONERATE_EXE'};
my $sEXONERATE_OPT = "";
$sEXONERATE_OPT = $rap_option{'EXONERATE_OPT'} if($rap_option{'EXONERATE_OPT'});
die "EXONERATE_OPT: '--model', '--bestn', and '--ryo' can not be specified.\n" if($sEXONERATE_OPT =~ /--bestn/ || $sEXONERATE_OPT =~ /--ryo/);

my $sSOURCE = $rap_option{'SOURCE'};
if(!$sSOURCE){
	$sSOURCE = ".";
}

### Get genomic sequence ###
my (%hGSEQ, @aGSEQ) = ((), ());

if(-f $sG_SEQ){
	my $sGDIR00 = "genome";
	&split_seq($sGDIR00, $sG_SEQ);
	# Following line fixed by Nicolas GUILHOT (added [. "/genome"] to rename method)
	rename 'genome',$sWD . "/genome";
	my $sGDIR01 = $sWD . "/genome";
	my @ag00 = split(/\n/, `ls $sGDIR01`);
	foreach my $sg00 (@ag00){
		my $sg01 = $sGDIR01 . "/" . $sg00;
		my ($sGseq_header, $sGseq) = &getseq($sg01);
		push(@aGSEQ, $sGseq_header);
		$hGSEQ{$sGseq_header} = $sGseq;
	}
}else{
	print STDERR "ERROR:File does not exist.\n";
	die "ERROR:$!";
}

my $validatedGeneCounter = 0;

foreach my $s00 (@aGSEQ){
	my $sGDIR10 = $sWD . "/" . $s00;
	if(! -d $sGDIR10){
		mkdir($sGDIR10, 0755);
	}else{
		print STDERR "ERROR:Directory exists.\n";
		die "ERROR:$!";
	}
}

if (! $sT_SEQ || !-f $sT_SEQ) {
	print STDERR "ERROR: Input a transcripts file.\n";
	die "ERROR:$!";
}

### Conduct BLAST search ###
foreach my $s20 (@aGSEQ){
	my $sWD_2 = $sWD . "/" . $s20;
	my $sFILE_GSEQ = $sWD . "/genome/" . $s20;
	&run_blast($sWD_2, $sBLAST_EXE, $sBLAST_OPT, $sFORMATDB_EXE, $sT_SEQ, $sFILE_GSEQ, "nucleotide");
	print "[bl2fna_exonerate.pl - $s20]: BLAST has done. " ,  `date`;
}

foreach my $s20 (@aGSEQ){
	my $sWD_2 = $sWD . "/" . $s20;
	my $sjoblist = $sWD_2 . "/" . "joblist.txt";
	my $sFILE_GSEQ = $sWD . "/genome/" . $s20;
	my $sGSEQ = $hGSEQ{$s20};

	my $sblast_out = $sWD_2 . "/" . basename($sFILE_GSEQ) . ".b";

	my @aLINE = &parse_blast($sblast_out);
	my @a12 = &select_fragments(\@aLINE, $nID_HSP);
	my @a13 = &join_fragments_1(\@a12, $sWD_2, $s20, $nT_GAP, $nG_GAP, $nCV_HIT, $nCLIP_MGN);

	my $scut_position = $sWD_2 . "/cut_position.txt";
	&rmv_redundancy_1($scut_position);

	my ($sGseq_header, $sGseq) = &getseq($sFILE_GSEQ);
	&clip_seq($sWD_2, $scut_position, $sGseq);

	print "[bl2fna_exonerate.pl - $s20]: Clipping the genomic sequences has done. " , `date`;
}

my $smap_inf = $sWD . "/map.inf";
open(INF, ">$smap_inf");

my $sfhandle = \*INF;

foreach my $s20 (@aGSEQ){
	my $sWD_2 = $sWD . "/" . $s20;

	my $sTSEQ_E2G = $sWD_2 . "/transcript_fore2g";
	mkdir($sTSEQ_E2G, 0755);
	my $sGSEQ_E2G = $sWD_2 . "/genome_fore2g";
	my @agseq00 = split(/\n/, `ls $sGSEQ_E2G`);
	my $se2g_filelist = $sWD_2 . "/e2g_filelist.txt";
	open(E2G_LIST, ">$se2g_filelist");

	foreach my $s16 (@agseq00){
		my $sfile_gseq00 = $sGSEQ_E2G . "/" . $s16;
		my @atseq00 = split(/\_\_/, $s16);
		$atseq00[1] =~ s/\.fa$//g;
		my $sfile_tseq00 = $sTSEQ_E2G . "/" . $atseq00[1];
		if(!-f $sfile_tseq00){
			my $sfastacmdCommand = $sFASTACMD_EXE . ' -s ' . $atseq00[1] . ' -d ' . $sT_DB . ' > ' . $sfile_tseq00;
			print "[bl2fna_exonerate.pl - $s20]: fastacmd command is: " . $sfastacmdCommand . "\n";

			system($sfastacmdCommand);
			print "[bl2fna_exonerate.pl - $s20]: fastacmd has done. " , `date`;
		}
		print E2G_LIST "$sfile_gseq00\t$sfile_tseq00\n";
	}
	close E2G_LIST;

	&run_exonerate($sWD_2, $se2g_filelist, $sEXONERATE_EXE, $sEXONERATE_OPT);

	unlink $se2g_filelist;

	print "[bl2fna_exonerate.pl - $s20]: exonerate has done. " , `date`;


	### Make coordinate files from est2genome result files ###
	my $sE2G = $sWD_2 . "/e2g_out";
	my $sfile_epos = $sWD_2 . "/exon_position.txt";
	unlink $sfile_epos;
	&exonerate_tbl($sWD_2, $sE2G);

	print "[bl2fna_exonerate.pl - $s20]: exonerate parsing has done. " , `date`;


	my $sWD_3 = $sWD . "/" . $s20;
	$validatedGeneCounter = &makeGFF($sWD_3, $s20, $hGSEQ{$s20}, $sfhandle);
	print "[bl2fna_exonerate.pl - $s20]: Making GFF files has done. " , `date`;
	my $sgff = $sWD_3 . "/" . $s20 . "_RAP.gff";
	my $sgseq = $sWD . "/genome/" . $s20;
	&gff2fna($sWD_3, $sgff, $sgseq);
	print "[bl2fna_exonerate.pl - $s20]: Making transcripts file has done. " , `date`;
	my $sgfftmp = $sWD_3 . "/" . $s20 . "_RAP.gff.tmp";
	open(GFF, ">$sgfftmp");
	open(TMP, $sgff);
	my @agfftmp = <TMP>;
	chomp(@agfftmp);
	close TMP;
	foreach my $s00 (@agfftmp){
		if($s00 !~ /\#/){
			my @a00 = split(/\t/, $s00);
			if($a00[2] eq "exon"){
				print GFF $s00 , "\n";
			}
		}
	}
	close GFF;
	&clustering($sgfftmp, $sgfftmp, $sWD_3);
	my $sclst = $sWD_3 . "/clst.txt";
	my $ssngl = $sWD_3 . "/sngl.txt";
	&add_clusterid($sclst, $ssngl, $sgff);
	print "[bl2fna_exonerate.pl - $s20]: Clustering has done. " , `date`;
	unlink $sgfftmp;

}
close INF;

my $sgname = basename($sG_SEQ);
$sgname =~ s/\.(\S+)$//g;
my $sallgff = $sWD . "/" . $sgname . "_RAP.gff";
my $sallfna = $sWD . "/" . $sgname . "_RAP.fna";
open(ALLGFF, ">$sallgff");
open(ALLFNA, ">$sallfna");
foreach my $s20 (@aGSEQ){
	my $sgff = $sWD . "/" . $s20 . "/" . $s20 . "_RAP.gff";
	my $sfna = $sWD . "/" . $s20 . "/" . $s20 . "_RAP.gff.fna";
	open(GFF, $sgff);
	open(FNA, $sfna);
	my @agff = <GFF>;
	my @afna = <FNA>;
	print ALLGFF @agff;
	print ALLFNA @afna;
	close GFF;
	close FNA;
}
close ALLGFF;
close ALLFNA;

if($opt_output ne ""){
	if(-f $sOutput){
		open(OUTPUT, "+>>$sOutput");
		print OUTPUT "MAP_GFF=" , $sallgff , ";\n";
		print OUTPUT "MAP_FNA=" , $sallfna , ";\n";
		print OUTPUT "MAP_INF=" , $smap_inf , ";\n";
		print OUTPUT "MAP_ABS=" , $sWD . '/bl2fna_exonerate.abstract' , ";\n";
		close OUTPUT;
	}else{
		open(OUTPUT, ">$sOutput");
		print OUTPUT "MAP_GFF=" , $sallgff , ";\n";
		print OUTPUT "MAP_FNA=" , $sallfna , ";\n";
		print OUTPUT "MAP_INF=" , $smap_inf , ";\n";
		print OUTPUT "MAP_ABS=" , $sWD . '/bl2fna_exonerate.abstract' , ";\n";
		close OUTPUT;
	}
}

print "[bl2fna_exonerate.pl]: Number of validated genes written in the intermediate GFF file: " . $validatedGeneCounter . "\n";
writeAbstractFile($sWD, $validatedGeneCounter);

print "[bl2fna_exonerate.pl]: Finish! " , `date`;


sub writeAbstractFile {

	# Recovers parameters
	my ($directory, $nbValidatedGene) = @_;

	# Initialization
	my $abstractFile = $directory . "/bl2fna_exonerate.abstract";

	# Write file
	open (ABSTRACT, '>' . $abstractFile) or die('Error: Cannot create/open file: ' . $abstractFile);
	print ABSTRACT 'Nb_validated_genes=' . $nbValidatedGene;
	close(ABSTRACT);

	return 0; # success
}


sub makeGFF{
	my ($swd, $sGseq_header, $sGseq, $handle) = @_;

	my $nbValidatedGene = 0;

	my $sBLN_TBL = $swd . "/bln_tbl";
	my $sE2G_TBL = $swd . "/e2g_tbl";
	my $sGFF = $swd . "/GFF";

	if(! -d $sGFF){
		mkdir($sGFF, 0755);
	}

	if(-d $sE2G_TBL){
		my $sExon_Pos = $swd . "/exon_position.txt";
		if(-f $sExon_Pos){
			open(EXPOS, $sExon_Pos);
			my @aExon_Pos = <EXPOS>;
			chomp(@aExon_Pos);
			my %h10 = ();
			my @a101 = ("tacc","tstr","tsp","tep","gacc","gstr","gsp","gep");
			foreach my $s100 (@a101){
				@{$h10{$s100}} = ();
			}
			foreach my $s10 (@aExon_Pos){
				my @a10 = split(/\t/, $s10);
				for(my $ii=0; $ii<=$#a10; $ii++){
					push(@{$h10{$a101[$ii]}}, $a10[$ii]);
				}
			}

			@aExon_Pos= @aExon_Pos[sort {$h10{"tacc"}[$a] cmp $h10{"tacc"}[$b] or
							 $h10{"tstr"}[$a] cmp $h10{"tstr"}[$b] or
							 $h10{"tsp"}[$a] cmp $h10{"tsp"}[$b] or
							 $h10{"tep"}[$a] cmp $h10{"tep"}[$b] or
							 $h10{"gstr"}[$a] cmp $h10{"gstr"}[$b] or
							 $h10{"gsp"}[$a] cmp $h10{"gsp"}[$b] or
							 $h10{"gep"}[$a] cmp $h10{"gep"}[$b]} 0 .. $#aExon_Pos];

			my ($stacc, $ststr, $stsp, $step, $sgstr, $sgsp, $sgep) = ("", "", "", "", "", "", "");
			foreach my $s11 (@aExon_Pos){
				my @a11 = split(/\t/, $s11);
				if($a11[0] ne $stacc){
					my $se2g_tbl = $sE2G_TBL . "/" . $a11[4] . ".fa.e2g.tbl";
					my ($nID, $nCV) = &calculate_idcov($se2g_tbl);
					if($nID >= $nID_FIN && $nCV >= $nCV_FIN){
						my @a00 = split(/\;/, $a11[6]);
						my @a01 = split(/\;/, $a11[7]);
						print $handle join("\t", $a11[4], $#a00+1, $a00[0], $a01[$#a01], ($a01[$#a01]-$a00[0]+1),$nID,$nCV),"\n";
						&make_gff($swd, $se2g_tbl, $sSOURCE);
						$nbValidatedGene++;
					}

					($stacc, $ststr, $stsp, $step, $sgstr, $sgsp, $sgep) =
					($a11[0],$a11[1],$a11[2],$a11[3],$a11[5],$a11[6],$a11[7]);
				}else{
					if($a11[1] eq $ststr && $a11[2] eq $stsp && $a11[3] eq $step &&
					   $a11[5] eq $sgstr && $a11[6] eq $sgsp && $a11[7] eq $sgep){
					}else{
						my $se2g_tbl = $sE2G_TBL . "/" . $a11[4] . ".fa.e2g.tbl";
						my ($nID, $nCV) = &calculate_idcov($se2g_tbl);
						if($nID >= $nID_FIN && $nCV >= $nCV_FIN){
							my @a00 = split(/\;/, $a11[6]);
							my @a01 = split(/\;/, $a11[7]);
							print $handle join("\t", $a11[4], $#a00+1, $a00[0], $a01[$#a01], ($a01[$#a01]-$a00[0]+1),$nID,$nCV),"\n";
							&make_gff($swd, $se2g_tbl, $sSOURCE);
							$nbValidatedGene++;
						}

						($stacc, $ststr, $stsp, $step, $sgstr, $sgsp, $sgep) = ($a11[0],$a11[1],$a11[2],$a11[3],$a11[5],$a11[6],$a11[7]);
					}
				}
			}
		}else{
			print STDERR "ERROR:File does not exist.\n";
			die "ERROR:$!";
		}
	}elsif(-d $sBLN_TBL){
		my @aTBL_list = split(/\n/, `ls $sBLN_TBL`);
		foreach my $stbl00 (@aTBL_list){
			my $stbl01 = $sBLN_TBL . "/" . $stbl00;
			my ($nID, $nCV) = &calculate_idcov($stbl01);
			if($nID >= $nID_FIN && $nCV >= $nCV_FIN){
				&make_gff($swd, $stbl01, $sSOURCE);
			}
		}
	}else{
		print STDERR "ERROR:Directory does not exist.\n";
		die "ERROR:$!";
	}
	&join_gff($swd, $sGseq_header, $sGseq);

	return $nbValidatedGene;
}
