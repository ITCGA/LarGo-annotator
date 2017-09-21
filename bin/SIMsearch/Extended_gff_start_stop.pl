#!/usr/bin/env perl

# Perl modules
use strict;
use warnings;
use diagnostics;

use Getopt::Long;

# TriAnnot SIMsearch modules
use SIMsearch::ext::Extendregion;

if(@ARGV==0){
	print "Usage::Extended_gff_start_stop.pl -h";
	exit(0);
}

my $chrseq="";
my $gff_file="";
my $extlim=-1;
my $outname="";
my $opt_help=0;
my $debug=0;
my $atg_start=0;
my $outformat=0;

&GetOptions('b|bac=s'=>\$chrseq,'g|gff=s'=>\$gff_file,'o|outfile=s'=>\$outname,'f|outformat=i'=>\$outformat,'e|extionlim=i'=>\$extlim,'a|atg_start=i'=>\$atg_start,'help|h' =>\$opt_help,'debug=i'=>\$debug);


my $help = <<'&EOT&';
Usage:
	-b bac/genomic(fasta file) -g gff_file(GFF ver3) -o outfilename

	Options:
	-e xx bp :limit bp of extension (default is no limit for extension)
	-f 0(default):only GFFfile(.gff), 1:GFFfile(.gff) ORF file(.faa), ORF nucleotide file(.fna), inftable(orfinf.dat)
	-a 0(default):extension , 1:never extended atg start, 2:extended only when 5-prime-UTR is less than 3;
	-h help

	e.g.
	Extended_gff_start_stop.pl -b barley_bac.fa -g before.gff -o after

	Extended_gff_start_stop.pl -b barley_bac.fa -g before.gff -o after -e 100


	Result file is   after.gff, after.fnt, after.faa


&EOT&

if($opt_help) {
	print $help;
	exit 1;
}


my %flghash;
$flghash{"atg_start"}=$atg_start;

my @cand;

my %seqhash;
&fastafile_to_seqhash($chrseq,\%seqhash);

my $ver=3;
#&convert_gff_to_line($gff_file,$ver,\@cand);
&general_convert_gff_to_line($gff_file,$ver,\@cand);


if($outformat==1){
	open(FAA,">${outname}.faa");
	open(FNA,">${outname}.fna");
	open(INF,">${outname}_orf.inf");
}

my $fastalen=60;
my %infhash;
for (my $i=0;$i<@cand;$i++){
	my @items=split(/\t/,$cand[$i]);

	my $id=$items[0];
	my $chr=$items[1];
	my $start=$items[2];
	my $end=$items[3];
	my $di=$items[4];
	my $exon=$items[5];

	my $inf=$items[11];

	if(defined $seqhash{$chr}){
		my ($cmb_exon,$cmb_CDS)=&conv_CDS_to_exon2($exon,$di);
		my ($ext_start,$ext_stop)=&extend_start_stop(\$seqhash{$chr},$exon,$di,$extlim,\%flghash);
		my $res_exon=&insert_startend_exon($ext_start,$ext_stop,$cmb_exon,$di);
		my ($fin_start,$fin_end)=&exon_start_end_ext($start,$end,$ext_start,$ext_stop,$di);

		$items[2]=$fin_start;
		$items[3]=$fin_end;
		$items[5]=$res_exon;

		my $res_sen=join("\t",@items);

		my ($nuc,$amino)=&CDS_trans2(\$seqhash{$chr},$res_exon,$di);

		my $orfinf=&report_ORF($id,$amino);

		if($outformat==1){
			print INF "$orfinf\n";

			my $faadata=&printfasta2($id,$amino,$fastalen);
			print FAA "$faadata";

			my $fnadata=&printfasta2($id,$nuc,$fastalen);
			print FNA "$fnadata";
		}

		my $fin_res=&make_gff_from_sen($res_sen,9,11);

		$infhash{$id}=$fin_res;
	}
}

if($outformat==1){
	close(FAA);
	close(FNA);
	close(INF);
}

my $fin_sen=&replace_gff_file($gff_file,\%infhash,$ver);

open(OUT,">${outname}.gff");
print OUT $fin_sen;
close(OUT);
