#!/usr/bin/env perl

# Perl modules
use strict;
use warnings;
use diagnostics;

use File::Basename;
use Getopt::Long;

# BioPerl modules
use Bio::SeqIO;

# TriAnnot SIMsearch modules
use SIMsearch::mapping::MAP;

my ($opt_gff, $opt_inf, $opt_fna, $opt_genome, $opt_dir, $opt_help) = ("", "", "", "", "", 0);
&GetOptions('gff=s' => \$opt_gff, 'inf=s' => \$opt_inf, 'fna=s' => \$opt_fna, 'genome=s' => \$opt_genome, 'dir=s' => \$opt_dir, 'help|h' => \$opt_help);

my $help = <<'&EOT&';
Usage: -gff [GFF file] -inf [orf.inf] -fna [transcript FASTA file] -genome [genome FASTA file] -dir [working directory]
&EOT&

if( $opt_help || !$opt_gff || !$opt_inf || !$opt_fna || !$opt_genome || !$opt_dir){
	print $help;
	exit 1;
}

my ($gff, $orf_inf, $fna, $genome, $wd) = ($opt_gff, $opt_inf, $opt_fna, $opt_genome, $opt_dir);

open(OUT_GFF, ">$wd/modified.gff");
open(OUT_INF, ">$wd/modified.inf");
open(OUT_FNA, ">$wd/modified.fna");

my %hGENOME = ();
my $in = Bio::SeqIO->new(-file => $genome);
while (my $fasta = $in->next_seq) {
	my $id = $fasta->id;
	my $seq = $fasta->seq;
	$seq =~ tr/[a-z]/[A-Z]/;
	$hGENOME{$id} = $seq;
}

my %hFNA = ();
my $in2 = Bio::SeqIO->new(-file => $fna);
while (my $fasta = $in2->next_seq) {
	my $id = $fasta->id;
	my $seq = $fasta->seq;
	$seq =~ tr/[a-z]/[A-Z]/;
	$hFNA{$id} = $seq;
}

my %hAllPos = ();
my %hORF_INF = ();
open(INF, $orf_inf);
while(<INF>){
	chomp;
	my @a0 = split(/\t/);
	@{$hORF_INF{$a0[0]}} = @a0;
}
close INF;

open(GFF1, $gff);
my ($acc, $strand, $chr) = ("", "", "");
my $flg0 = 0;
my @a10 = ();

while(<GFF1>){
	chomp;
	my @a0 = split(/\t/);
	next if(/^\#\#/ || $a0[2] eq "sequence");
	my $acc0 = "";
	if($a0[8] =~ /ID=([^;]+)/ || $a0[8] =~ /Parent=([^;]+)/){
	$acc0 = $1;
	my $flg1 = 0;
	if($acc0 ne $acc){
		$flg1 = 1;
	}
	if($flg0 == 1 && $flg1 == 1){
		&proc1($acc, $strand, $chr, \@a10);
		@a10 = ();
	}
	push(@a10, $_);
	($acc, $strand, $chr) = ($acc0, $a0[6], $a0[0]);
	$flg0 = 1;
	}
}
close GFF1;

if($#a10 > -1){
	&proc1($acc, $strand, $chr, \@a10);
}

foreach my $acc (sort keys %hFNA){
	my $seq = $hFNA{$acc};
	print OUT_FNA ">$acc\n";
	while(substr($seq, 0, 50)){
		print OUT_FNA substr($seq, 0, 50), "\n";
		substr($seq, 0, 50) = "";
	}
}
close OUT_FNA;
close OUT_GFF;
close OUT_INF;

&translate_fasta("$wd/modified.fna");

sub proc1{
	my ($acc, $strand, $chr, $a0) = @_;

	if(!@{$hORF_INF{$acc}} || $hORF_INF{$acc}[2] eq "complete" || $hORF_INF{$acc}[4] eq "-"){
		for(my $ii=0; $ii<=$#$a0; $ii++){
			print OUT_GFF $a0->[$ii], "\n";
		}
		print OUT_INF join("\t", @{$hORF_INF{$acc}}), "\n" if(@{$hORF_INF{$acc}});
	}elsif($hORF_INF{$acc}[4] ne "-"){
		%hAllPos = ();
		my @aAllPos = split(/\_/, $hORF_INF{$acc}[5]);
		foreach my $pos (@aAllPos){
			$hAllPos{$pos} = 1;
		}
		my $aa_length = 0;
		my $codon_seq = "";
		for(my $ii=0; $ii<=$#aAllPos-1; $ii+=2){
			$aa_length += ($aAllPos[$ii+1]-$aAllPos[$ii]+1);
			$codon_seq .= substr($hGENOME{$chr}, $aAllPos[$ii]-1, ($aAllPos[$ii+1]-$aAllPos[$ii]+1));
		}
		if($strand eq "-"){
			$codon_seq = reverse($codon_seq);
			$codon_seq =~ tr/[ATGC]/[TACG]/;
		}
		$hFNA{$acc} = $codon_seq;

		$aa_length = ($aa_length/3)-1;
		($hORF_INF{$acc}[1], $hORF_INF{$acc}[2]) = ($aa_length, "complete");
		print OUT_INF join("\t", @{$hORF_INF{$acc}}), "\n";

		@aAllPos = sort {$b <=> $a} @aAllPos if($strand eq "-");
		my ($orf_sp, $orf_ep) = ($aAllPos[0], $aAllPos[$#aAllPos]);

		my @a00 = split(/\t/, $a0->[0]);
		my ($mrna_sp, $mrna_ep) = (0, 0);
		my @aexon0 = ();
		my @aexonsp0 = ();
		for(my $ii=0; $ii<=$#$a0; $ii++){
			my @a1 = split(/\t/, $a0->[$ii]);
			if($a1[2] eq "mRNA" || $a1[2] eq "match"){
				print OUT_GFF join("\t", @a1), "\n";
				($mrna_sp, $mrna_ep) = ($a1[3], $a1[4]);
			}else{
				push(@aexonsp0, $a1[3]);
				push(@aexon0, $a0->[$ii]);
			}
		}

		if($strand eq "+"){
			@aexon0 = @aexon0[ sort{$aexonsp0[$a] <=> $aexonsp0[$b]}0.. $#aexonsp0];
		}else{
			@aexon0 = @aexon0[ sort{$aexonsp0[$b] <=> $aexonsp0[$a]}0.. $#aexonsp0];
		}

		my ($exon_flg, $init_flg) = (0, 0);
		my ($exon_sp, $exon_ep) = (0, 0);
		for(my $ii=0; $ii<=$#aexon0; $ii++){
			my @a1 = split(/\t/, $aexon0[$ii]);
			if($a1[6] eq "+"){
				if($init_flg == 1){
					if($a1[3] == $exon_ep + 1){
						$exon_ep = $a1[4];
					}else{
						$exon_flg = 1;
					}
				}else{
					($exon_sp, $exon_ep) = ($a1[3], $a1[4]);
				}
			}else{
				if($init_flg == 1){
					if($a1[4] == $exon_sp - 1){
						$exon_sp = $a1[3];
					}else{
						$exon_flg = 1;
					}
				}else{
					($exon_sp, $exon_ep) = ($a1[3], $a1[4]);
				}
			}
			if($exon_flg == 1){
				&proc2($a00[0],$a00[1],$acc,$orf_sp,$orf_ep,$exon_sp,$exon_ep,$strand);
				($exon_sp, $exon_ep) = ($a1[3], $a1[4]);
				$exon_flg = 0;
			}
			$init_flg = 1;
		}
		&proc2($a00[0],$a00[1],$acc,$orf_sp,$orf_ep,$exon_sp,$exon_ep,$strand);
	}
}

sub proc2{
	my ($col1, $col2, $acc, $orf_sp, $orf_ep, $exon_sp, $exon_ep, $strand) = @_;

	if($strand eq "+"){
		if($exon_ep < $orf_sp){
			print OUT_GFF join("\t", $col1,$col2,"five_prime_UTR",$exon_sp,$exon_ep,".",$strand,"."), "\tParent=", $acc, "\n";
		}elsif($exon_sp < $orf_sp && $orf_sp < $exon_ep){
			print OUT_GFF join("\t", $col1,$col2,"five_prime_UTR",$exon_sp,$orf_sp-1,".",$strand,"."), "\tParent=", $acc, "\n";
			print OUT_GFF join("\t", $col1,$col2,"polypeptide",$orf_sp,$exon_ep,".",$strand,"."), "\tParent=", $acc, "\n";
		}elsif($hAllPos{$exon_sp} && $hAllPos{$exon_ep}){
			print OUT_GFF join("\t", $col1,$col2,"polypeptide",$exon_sp,$exon_ep,".",$strand,"."), "\tParent=", $acc, "\n";
		}elsif($exon_sp < $orf_ep && $orf_ep < $exon_ep){
			print OUT_GFF join("\t", $col1,$col2,"polypeptide",$exon_sp,$orf_ep,".",$strand,"."), "\tParent=", $acc, "\n";
			print OUT_GFF join("\t", $col1,$col2,"three_prime_UTR",$orf_ep+1,$exon_ep,".",$strand,"."), "\tParent=", $acc, "\n";
		}elsif($orf_ep < $exon_sp){
			print OUT_GFF join("\t", $col1,$col2,"three_prime_UTR",$exon_sp,$exon_ep,".",$strand,"."), "\tParent=", $acc, "\n";
		}
	}else{
		if($orf_sp < $exon_sp){
			print OUT_GFF join("\t", $col1,$col2,"five_prime_UTR",$exon_sp,$exon_ep,".",$strand,"."), "\tParent=", $acc, "\n";
		}elsif($exon_sp < $orf_sp && $orf_sp < $exon_ep){
			print OUT_GFF join("\t", $col1,$col2,"five_prime_UTR",$orf_sp+1,$exon_ep,".",$strand,"."), "\tParent=", $acc, "\n";
			print OUT_GFF join("\t", $col1,$col2,"polypeptide",$exon_sp,$orf_sp,".",$strand,"."), "\tParent=", $acc, "\n";
		}elsif($hAllPos{$exon_sp} && $hAllPos{$exon_ep}){
			print OUT_GFF join("\t", $col1,$col2,"polypeptide",$exon_sp,$exon_ep,".",$strand,"."), "\tParent=", $acc, "\n";
		}elsif($exon_sp < $orf_ep && $orf_ep < $exon_ep){
			print OUT_GFF join("\t", $col1,$col2,"polypeptide",$orf_ep,$exon_sp,".",$strand,"."), "\tParent=", $acc, "\n";
			print OUT_GFF join("\t", $col1,$col2,"three_prime_UTR",$exon_sp,$orf_ep-1,".",$strand,"."), "\tParent=", $acc, "\n";
		}elsif($exon_ep < $orf_ep){
			print OUT_GFF join("\t", $col1,$col2,"three_prime_UTR",$exon_sp,$exon_ep,".",$strand,"."), "\tParent=", $acc, "\n";
		}
	}
}
