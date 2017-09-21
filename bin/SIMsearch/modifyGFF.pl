#!/usr/bin/env perl

# Perl modules
use strict;
use warnings;
use diagnostics;

use File::Basename;
use File::Copy;
use Getopt::Long;

# BioPerl modules
use Bio::SeqIO;

die "Usage: $0 -dir [working directory] -seq [BAC sequence file] -gff [GFF file] -category\n" if(!@ARGV);

my ($wd, $gff, $seq, $category) = (".", "", "", "default");
GetOptions(	"dir=s"   => \$wd, "gff=s"   => \$gff, "seq=s"   => \$seq, "category=s" => \$category) || die "Usage: $0 -dir [working directory] -seq [BAC sequence file] -gff [GFF file] -category\n";

if(-s $gff && -s $seq){
	my ($bac_name, $bac_seq, $bac_id, $bac_length) = ("", "", "", 0);
	my $in = Bio::SeqIO->new(-file => $seq);

	while (my $fasta = $in->next_seq) {
		$bac_name = $fasta->id;
		$bac_seq = $fasta->seq;
		$bac_length = length($bac_seq);
		$bac_id = $bac_name;
		$bac_id =~ s/_masked//g;
	}

	open(my $orf_fna_handle, ">$wd/for_annotation_orf_$category.fna");
	open(my $exon_fna_handle, ">$wd/for_annotation_exon_$category.fna");
	open(my $gff_handle, ">$wd/for_annotation_$category.gff");
	print $gff_handle "##gff-version 3\n";
	#print $gff_handle join("\t", $bac_name,"TriAnnotPipeline","sequence","1",$bac_length,".",".","."), "\t", "ID=", $bac_id, "\n"; # Not useful when SIMsearch is run by the TriAnnotPipeline

	open(my $GFF, '<', $gff);
	my ($acc, $strand) = ("", "");
	my $flg0 = 0;
	my $gene_number = 0;
	my @a10 = ();
	while(<$GFF>){
		chomp;
		my @a0 = split(/\t/);
		my $acc0 = "";
		if($a0[8] =~ /ID=([^;]+)/ || $a0[8] =~ /Parent=([^;]+)/){
			$acc0 = $1;
		}

		my $flg1 = 0;
		if($acc0 ne $acc){
			$flg1 = 1;
		}

		if($flg0 == 1 && $flg1 == 1){
			$gene_number++;
			&proc1($acc, $strand, $gene_number, $gff_handle, $orf_fna_handle, $exon_fna_handle, $bac_seq, @a10);
			@a10 = ();
		}

		push(@a10, $_);
		$acc = $acc0;
		$flg0 = 1;
		$strand = $a0[6];
	}
	close $GFF;

	if($#a10 > -1){
		$gene_number++;
		&proc1($acc, $strand, $gene_number, $gff_handle, $orf_fna_handle, $exon_fna_handle, $bac_seq, @a10);
	}

	close $gff_handle;
	close $orf_fna_handle;
	close $exon_fna_handle;

	if(-s "$wd/for_annotation_orf_$category.fna"){
		&translate_fasta("$wd/for_annotation_orf_$category.fna");
	}

}else{
	print STDERR "[modifyGFF.pl]: ERROR: Can't open the GFF file (" . $gff . ") or the sequence file (" . $seq . ").\n";
	exit;
}

sub proc1{
	my ($acc, $strand, $gene_number, $gff_handle, $orf_fna_handle, $exon_fna_handle, $bac_seq, @a0) = @_;

	shift(@a0);
	my $cds_flg = 0;
	my ($bac_name, $source, $cat, $cds_seq, $exon_seq) = ("", "", "", "", "");
	my ($mrna_sp, $mrna_ep) = (0, 0);
	my @aCDS = ();
	my @aEXON = ();

	for(my $ii=0; $ii<=$#a0; $ii++){
		my @a3 = split(/\t/, $a0[$ii]);
		if($a3[2] eq "polypeptide"){
			push(@aCDS, $a0[$ii]);
			$cds_flg = 1;
		}elsif($a3[2] eq "exon"){
			push(@aEXON, $a0[$ii]);
		}
	}

	my @aCDS_sp = ();
	my @aEXON_sp = ();
	foreach my $s0 (@aCDS){
		my @a4 = split(/\t/, $s0);
		push(@aCDS_sp, $a4[3]);
	}
	foreach my $s0 (@aEXON){
		my @a4 = split(/\t/, $s0);
		push(@aEXON_sp, $a4[3]);
	}

	@aCDS = @aCDS[sort {$aCDS_sp[$a] <=> $aCDS_sp[$b]} 0..$#aCDS];
	@aEXON = @aEXON[sort {$aEXON_sp[$a] <=> $aEXON_sp[$b]} 0..$#aEXON];

	for(my $ii=0; $ii<=$#aCDS; $ii++){
		my @a3 = split(/\t/, $aCDS[$ii]);
		$cds_seq .= substr($bac_seq, $a3[3]-1, $a3[4]-$a3[3]+1);
	}
	for(my $ii=0; $ii<=$#aEXON; $ii++){
		my @a3 = split(/\t/, $aEXON[$ii]);
		$exon_seq .= substr($bac_seq, $a3[3]-1, $a3[4]-$a3[3]+1);
	}
	if($strand eq "-"){
		$cds_seq = reverse($cds_seq);
		$cds_seq =~ tr/[atgcATGC]/[tacgTACG]/;
		$exon_seq = reverse($exon_seq);
		$exon_seq =~ tr/[atgcATGC]/[tacgTACG]/;
	}

	$gene_number = sprintf("%04d", $gene_number);

	if($strand eq "+"){
		my @a1 = split(/\t/, $a0[0]);
		my @a2 = split(/\t/, $a0[$#a0]);
		($mrna_sp, $mrna_ep, $bac_name, $source) = ($a1[3], $a2[4], $a1[0], $a1[1]);
	}else{
		my @a1 = split(/\t/, $a0[0]);
		my @a2 = split(/\t/, $a0[$#a0]);
		($mrna_sp, $mrna_ep, $bac_name, $source) = ($a2[3], $a1[4], $a1[0], $a1[1]);
	}

	my $gene_name = $source. "_". $mrna_sp. "_". $mrna_ep. "_gene_". $gene_number;
	my $gene_id = $bac_name . "_" . $gene_name;

	my $mrna_name = $gene_name . "_mRNA_0001";
	my $mrna_id = $gene_id . "_mRNA_0001";

	my @a4 = split(/\_\_/, $acc);
	my $mrna_target = "structure_target=". $a4[$#a4];

	#if($a4[$#a4] =~ /(Cat\d+)_.+/){
		#$cat = $1;
		#$cat =~ tr/[a-z]/[A-Z]/;
	#}else{
		#$cat = $source;
	#}

	$cat = $source;

	print $gff_handle join("\t", $bac_name, $cat, "gene", $mrna_sp, $mrna_ep, ".", $strand, "."), "\t", "ID=", $gene_id, ";Name=". $gene_name, "\n";
	print $gff_handle join("\t", $bac_name, $cat, "mRNA", $mrna_sp, $mrna_ep, ".", $strand, "."), "\t", "ID=", $mrna_id, ";Name=", $mrna_name, ";Parent=", $gene_id, ";", $mrna_target, "\n";

	my @aEXON_lines = ();
	my @aCDS_lines = ();
	@aEXON_sp = ();
	@aCDS_sp = ();

	if($cds_flg == 1){

		my ($exon_flg, $init_flg) = (0, 0);
		my $exon_count = 0;
		my $exon_number = "";
		my ($exon_sp, $exon_ep) = (0, 0);
		my @a01 = ();
		my @asp = ();

		# START of EXON management

		for(my $ii=0; $ii<=$#a0; $ii++){
			my @a1 = split(/\t/, $a0[$ii]);
			push(@a01, $a0[$ii]);
			push(@asp, $a1[3]);
		}
		@a01 = @a01[sort{$asp[$a] <=> $asp[$b]}0..$#a01];

		foreach my $s0 (@a01){
			my @a1 = split(/\t/, $s0);
			$a1[6] = $strand;
			if($init_flg == 1){
				if($a1[3] == $exon_ep + 1){
					$exon_ep = $a1[4];
				}else{
					$exon_flg = 1;
				}
			}else{
				($exon_sp, $exon_ep) = ($a1[3], $a1[4]);
			}
			if($exon_flg == 1){
				$exon_count++;
				$exon_number = sprintf("%04d", $exon_count);

				my $exon_name = $source. "_". $exon_sp. "_". $exon_ep. "_gene_". $gene_number . "_mRNA_". "0001". "_exon_". $exon_number;
				my $exon_id = $bac_name. "_". $exon_name;

				my $exon_line = sprintf join("\t", $bac_name,$cat,"exon",$exon_sp,$exon_ep,".",$strand,"."). "\tID=". $exon_id. ";Name=". $exon_name. ";Parent=". $mrna_id;
				push(@aEXON_lines, $exon_line);
				push(@aEXON_sp, $exon_sp);
				($exon_sp, $exon_ep) = ($a1[3], $a1[4]);
				$exon_flg = 0;
			}
			$init_flg = 1;
		}
		$exon_count++;
		$exon_number = sprintf("%04d", $exon_count);

		my $exon_name = $source. "_". $exon_sp. "_". $exon_ep. "_gene_". $gene_number . "_mRNA_". "0001". "_exon_". $exon_number;
		my $exon_id = $bac_name . "_" . $exon_name;

		my $exon_line = sprintf join("\t", $bac_name,$cat,"exon",$exon_sp,$exon_ep,".",$strand,"."). "\tID=". $exon_id. ";Name=". $exon_name. ";Parent=". $mrna_id;
		push(@aEXON_lines, $exon_line);
		push(@aEXON_sp, $exon_sp);

		# END of EXON management

		my %hTYPE = ();
		for(my $ii=0; $ii<=$#a01; $ii++){
			my @a1 = split(/\t/, $a01[$ii]);
			$a1[1] = $cat;
			$a1[6] = $strand;
			$hTYPE{$a1[2]}++;

			my $ntype = sprintf("%04d", $hTYPE{$a1[2]});

			my $type_name = $source. "_". $a1[3]. "_". $a1[4]. "_gene_". $gene_number. "_mRNA_". "0001". "_". $a1[2]. "_". $ntype;
			my $type_id = $bac_name. "_" . $type_name;

			pop(@a1);
			if($a1[2] eq "polypeptide"){
				my $cds_line = sprintf join("\t", @a1). "\tID=". $type_id. ";Name=". $type_name. ";Derives_from=". $mrna_id;
				push(@aCDS_lines, $cds_line);
				push(@aCDS_sp, $a1[3]);
			}else{
				my $cds_line = sprintf join("\t", @a1). "\tID=". $type_id. ";Name=". $type_name. ";Parent=". $mrna_id;
				push(@aCDS_lines, $cds_line);
				push(@aCDS_sp, $a1[3]);
			}
		}
	}else{
		my @a01 = ();
		my @asp = ();
		for(my $ii=0; $ii<=$#a0; $ii++){
			my @a1 = split(/\t/, $a0[$ii]);
			push(@a01, $a0[$ii]);
			push(@asp, $a1[3]);
		}
		@a01 = @a01[sort{$asp[$a] <=> $asp[$b]}0..$#a01];
		my %hTYPE = ();

		for(my $ii=0; $ii<=$#a01; $ii++){
			my @a1 = split(/\t/, $a01[$ii]);
			$a1[1] = $cat;
			$a1[6] = $strand;
			$hTYPE{$a1[2]}++;

			my $ntype = sprintf("%04d", $hTYPE{$a1[2]});

			my $type_name = $source. "_". $a1[3]. "_". $a1[4]. "_gene_". $gene_number. "_mRNA_". "0001". "_". $a1[2]. "_". $ntype;
			my $type_id = $bac_name . "_" . $type_name;

			pop(@a1);
			if($a1[2] eq "exon"){
				my $exon_line = sprintf join("\t", @a1). "\tID=". $type_id. ";Name=". $type_name. ";Parent=". $mrna_id;
				push(@aEXON_lines, $exon_line);
				push(@aEXON_sp, $a1[3]);
			}
		}
	}

	if($#aEXON_lines > -1){
		print $gff_handle join("\n", @aEXON_lines), "\n";
	}

	if($#aCDS_lines > -1){
		print $gff_handle join("\n", @aCDS_lines), "\n";
	}

	if($cds_seq ne ""){
		print $orf_fna_handle ">", $mrna_id, "\n";
		$cds_seq =~ tr/[a-z]/[A-Z]/;
		while(substr($cds_seq, 0, 50)){
			print $orf_fna_handle substr($cds_seq, 0, 50), "\n";
			substr($cds_seq, 0, 50) = "";
		}
	}else{
		if($exon_seq ne ""){
			print $exon_fna_handle ">", $mrna_id, "\n";
			$exon_seq =~ tr/[a-z]/[A-Z]/;
			while(substr($exon_seq, 0, 50)){
				print $exon_fna_handle substr($exon_seq, 0, 50), "\n";
				substr($exon_seq, 0, 50) = "";
			}
		}
	}
}

sub translate_fasta{
	my $sfna = $_[0];

	my %GCODE = ('TTT'=>'F', 'TTC'=>'F', 'TTA'=>'L', 'TTG'=>'L',
		'TCT'=>'S', 'TCC'=>'S', 'TCA'=>'S', 'TCG'=>'S',
		'TAT'=>'Y', 'TAC'=>'Y', 'TAA'=>'*', 'TAG'=>'*',
		'TGT'=>'C', 'TGC'=>'C', 'TGA'=>'*', 'TGG'=>'W',
		'CTT'=>'L', 'CTC'=>'L', 'CTA'=>'L', 'CTG'=>'L',
		'CCT'=>'P', 'CCC'=>'P', 'CCA'=>'P', 'CCG'=>'P',
		'CAT'=>'H', 'CAC'=>'H', 'CAA'=>'Q', 'CAG'=>'Q',
		'CGT'=>'R', 'CGC'=>'R', 'CGA'=>'R', 'CGG'=>'R',
		'ATT'=>'I', 'ATC'=>'I', 'ATA'=>'I', 'ATG'=>'M',
		'ACT'=>'T', 'ACC'=>'T', 'ACA'=>'T', 'ACG'=>'T',
		'AAT'=>'N', 'AAC'=>'N', 'AAA'=>'K', 'AAG'=>'K',
		'AGT'=>'S', 'AGC'=>'S', 'AGA'=>'R', 'AGG'=>'R',
		'GTT'=>'V', 'GTC'=>'V', 'GTA'=>'V', 'GTG'=>'V',
		'GCT'=>'A', 'GCC'=>'A', 'GCA'=>'A', 'GCG'=>'A',
		'GAT'=>'D', 'GAC'=>'D', 'GAA'=>'E', 'GAG'=>'E',
		'GGT'=>'G', 'GGC'=>'G', 'GGA'=>'G', 'GGG'=>'G');

	if(-f $sfna){
		my $faa = $sfna;
		$faa =~ s/\.[^\/]+$//g;
		$faa .= ".faa";
		open(FAA, ">$faa");
		open(FNA, $sfna);
		my @a0 = <FNA>;
		chomp(@a0);
		my ($frg0, $frg1) = (0, 0);
		my ($sfna, $sfaa) = ("", "");
		foreach my $s0 (@a0){
			if($s0 =~ /^>(\S+)/){
				if($frg1 == 1){
					if((length($sfna))%3 != 0){
						print STDERR "ERROR: The sequence is not in frame.\n";
						die "ERROR:$!\n";
					}else{
						while(substr($sfna, 0, 3)){
							if($GCODE{substr($sfna, 0, 3)}){
								$sfaa .= $GCODE{substr($sfna, 0, 3)};
							}else{
								$sfaa .= "X";
							}
							substr($sfna, 0, 3) = "";
						}
					}
					while(substr($sfaa, 0, 50)){
						print FAA substr($sfaa, 0, 50), "\n";
						substr($sfaa, 0, 50) = "";
					}
					($sfna, $sfaa) = ("", "");
					print FAA "$s0\n";
				}else{
					print FAA "$s0\n";
					$frg0 = 1;
				}
			}else{
				if($frg0 == 1){
					$sfna .= $s0;
					$frg1 = 1;
				}else{}
			}
		}
		if((length($sfna))%3 != 0){
			print STDERR "ERROR: The sequence is not in frame.\n";
			die "ERROR:$!\n";
		}else{
			while(substr($sfna, 0, 3)){
				if($GCODE{substr($sfna, 0, 3)}){
					$sfaa .= $GCODE{substr($sfna, 0, 3)};
				}else{
					$sfaa .= "X";
				}
				substr($sfna, 0, 3) = "";
			}
		}
		while(substr($sfaa, 0, 50)){
			print FAA substr($sfaa, 0, 50), "\n";
			substr($sfaa, 0, 50) = "";
		}
	}else{
		print STDERR "ERROR: Can't find the file.\n";
		die "ERROR:$!\n";
	}
}
