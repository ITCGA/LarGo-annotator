package SIMsearch::mapping::MAP;

########################################
## Documentation
########################################

=head1 NAME

mapping::MAP

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

This module contains some functions that are involved in the
mapping procedure applied in the Rice Annotation Project (RAP) analysis.

=head1 EXPORT

&read_option
&split_seq
&run_blast
&parse_blast
&getseq
&select_fragments
&join_fragments_1
&join_fragments_2
&clip_seq
&rmv_redundancy_1
&rmv_redundancy_2
&make_gff
&run_exonerate
&exonerate_tbl
&calculate_idcov
&join_gff
&gff2fna
&clustering
&clustering_2
&add_clusterid
&make_orfgff
&translate_fasta
&makeRep
=cut

########################################
## Modules
########################################

# Perl modules
use strict;
use warnings;
use diagnostics;

use File::Basename;
use File::Path;
use Getopt::Long;
use Exporter;
use Switch;

# BioPerl modules
use Bio::SearchIO;
use Bio::SeqIO;
use Bio::AlignIO;

use Data::Dumper;
########################################
## Export functions
########################################

use vars qw(@ISA @EXPORT);
@ISA = ('Exporter');
@EXPORT = qw(
		 &read_option
		 &split_seq
		 &run_blast
		 &parse_blast
		 &getseq
		 &select_fragments
		 &join_fragments_1
		 &join_fragments_2
		 &clip_seq
		 &rmv_redundancy_1
		 &rmv_redundancy_2
		 &make_gff
		 &run_exonerate
		 &exonerate_tbl
		 &calculate_idcov
		 &join_gff
		 &gff2fna
		 &clustering
		 &clustering_2
		 &add_clusterid
		 &make_orfgff
		 &translate_fasta
		 &makeRep
);

########################################
## Functions
########################################

=head1 FUNCTIONS

=cut


########################
## Function: read_option
########################

=head2 read_option

 Function : This function loads a control file and creates a hash for options.
 Usage	: &read_option($file, \%hash)

=cut

sub read_option{
	my ($file, $option) = @_;

	if(-f $file){
		open(FILE, $file);
		while(<FILE>){
			chomp;
			if($_ !~ /^\#/){
				if($_ =~ /^(\S+)\=(.+)\;/){
					$option->{$1} = $2;
				}
			}
		}
	}else{
		print STDERR "ERROR: Can't find the file.\n";
		die "ERROR:$!";
	}
	return 1;
}

######################
## Function: split_seq
######################

=head2 split_seq

 Function : This function splits a multi-FASTA format file into single-FASTA format files.
 Usage	: &split_seq($directory, $file)

=cut

sub split_seq{
	my ($swd, $stseq) = @_;

	my $sdir_query = "./" . $swd;
	if(-d $sdir_query){
		print STDERR "ERROR:Directory exists. (&split_seq)\n";
		die "ERROR:$!";
	}else{
		mkdir($sdir_query, 0755);
		if(-f $stseq){
			my ($s0, $frg0, $frg1) = (0, 0, 0);
			open(QSEQ, $stseq);
			while(<QSEQ>){
				chomp;
				$s0 = $_;
				if($s0 =~ /^>(\S+)/){
					if($frg1 == 1){
						close FASTA;
						my $sfile = $sdir_query . "/" . $1;
						open(FASTA, ">$sfile");
						print FASTA "$s0\n";
					}else{
						my $sfile = $sdir_query . "/" . $1;
						open(FASTA, ">$sfile");
						print FASTA "$s0\n";
						$frg0 = 1;
					}
				}else{
					if($frg0 == 1){
						print FASTA "$s0\n";
						$frg1 = 1;
					}
				}
			}
			close FASTA;
			close QSEQ;
		}else{
			print STDERR "ERROR:File does not exist. (\&split_seq)\n";
			die "ERROR:$!";
		}
	}
}

######################
## Function: run_blast
######################

=head2 run_blast

 Function : This function conducts BLAST search using a set of transcripts as a query
			against a genomic sequence.
 Usage	: &run_blast($sWD, $exe, $option, $file, $file)

=cut

sub run_blast{
	my ($swd, $sblast_exe, $soption, $sformatdb_exe, $sfile_q, $sfile_s, $stype) = @_;

	if($sfile_s){
		my $frgdb = 0;
		my @asuffix = (".nhr",".nin",".nsq",".phr",".pin",".psq",".pal");
		foreach my $ssuffix (@asuffix){
			my $sdb = $sfile_s . $ssuffix;
			if(-f $sdb){
			$frgdb = 1;
			}
		}
		if($frgdb != 1){
			if(-f $sfile_s){
				my $sformatdb = "";
				if($stype eq "protein"){
					$sformatdb = $sformatdb_exe . " -i " . $sfile_s . " -o F -p T";
				}elsif($stype eq "nucleotide"){
					$sformatdb = $sformatdb_exe . " -i " . $sfile_s . " -o F -p F";
				}else{
					print STDERR "ERROR: \$stype must be \"protein\" or \"nucleotide\".\n";
					die "ERROR:$!";
				}
				system("$sformatdb");
			}else{
				print STDERR "ERROR: Can't find the blast database.\n";
				die "ERROR:$!\n";
			}
		}

		my $sfile_out = $swd . "/" . basename($sfile_s) . ".b";
		my $sblastall = $sblast_exe . " -i " . $sfile_q . " -d " . $sfile_s . " -o " . $sfile_out ." " . $soption;
		print "[SIMsearch::mapping::MAP::run_blast]: Blast command is: " . $sblastall . "\n";

		system("$sblastall");
	}else{
		print STDERR "ERROR: The name of a blast database or a FASTA name must be specified. (\&run_blast)\n";
		die "ERROR:$!";
	}
}

########################
## Function: parse_blast
########################

=head2 parse_blast

 Function : This function parses a BLAST search result.
 Usage	: &parse_blast($file)

=cut


sub parse_blast{
	my $sblast = $_[0];
	my $blast_report = new Bio::SearchIO ('-format' => 'blast', '-file' => $sblast);
	my @ablast_line = ();

	while(my $result = $blast_report->next_result()){
		my ($sAlgorithm, $frg_blx) = ($result->algorithm, 0);
		if($sAlgorithm eq "BLASTX"){
			$frg_blx = 1;
		}
		my ($sQname, $nQlen) = ($result->query_name(), $result->query_length());
		while(my $hit = $result->next_hit()){
			my ($sSname, $nSlen) = ($hit->name(), $hit->length());
			while(my $hsp = $hit->next_hsp()){
				my ($nEval, $nScor, $nBits, $nId) =
					($hsp->evalue(), $hsp->score(), $hsp->bits(), $hsp->frac_identical());
				my ($nHSPlen, $nHSPhit) = ($hsp->length('total'), $hsp->num_identical);
				my ($nQaln, $nSaln, $nQbeg, $nQend, $nSbeg, $nSend, $nQstr, $nSstr, $nQfrm, $nSfrm) =
					($hsp->length('query'), $hsp->length('hit'), $hsp->start('query'), $hsp->end('query'),
					 $hsp->start('hit'), $hsp->end('hit'), $hsp->strand('query'), $hsp->strand('hit'), $hsp->query->frame(), $hsp->hit->frame());
				my ($sQseq, $sSseq) = ($hsp->query_string(), $hsp->hit_string());
				my $nCov = sprintf ("%.4lf", ($nQaln / $nQlen));
				my ($nQgap, $nSgap) = (($hsp->length('total'))-$nQaln, ($hsp->length('total'))-$nSaln);

				if($frg_blx == 1){
					$nId = $nHSPhit/int($nQaln/3);
				}else{
					$nId = $nHSPhit/$nQaln;
				}

				if($nQstr == 1){
					$nQstr = "+";
				}else{
					$nQstr = "-";
				}
				if($nSstr == 1){
					$nSstr = "+";
				}else{
					$nSstr = "-";
				}

				$nId = sprintf ("%.4lf", $nId);
				my $s0 = sprintf join("\t", $sQname,$nQlen,$nQbeg,$nQend,$nQstr,$sSname,$nSlen,$nSbeg,$nSend,$nSstr,
							  $nHSPlen,$nHSPhit,$nEval,$nScor,$nBits,$nId,$nCov);
				push(@ablast_line, $s0);
			}
		}
	}
	return @ablast_line;
}

###################
## Function: getseq
###################

=head2 getseq

 Function : This function extracts a sequence from a FASTA file.
			Note that the FASTA file MUST BE a single FASTA file.
 Usage	: &getseq($file)

=cut


sub getseq{
	my $fgseq = $_[0];
	my ($sheader, $sgseq) = ("", "");
	my $ngcount = 0;

	if (-f $fgseq) {
		open(GSEQ, "$fgseq");
		my @agseq = <GSEQ>;
		chomp(@agseq);
		foreach my $sg0 (@agseq){
			if($sg0 =~ /^>(\S+)/){
				$sheader = $1;
				$ngcount++;
				if($ngcount > 1){
					print STDERR "ERROR:Sequence file must be single FASTA file!\n";
					die "ERROR:$!";
				}
			}else{
				$sg0 =~ s/[^\S]//g;
				$sgseq .= $sg0;
			}
		}
	}else{
		print STDERR "ERROR:Input genome sequence!\n";
		die "ERROR:$!";
	}
	return ($sheader, $sgseq);
}

#############################
## Function: select_fragments
#############################

=head2 select_fragments

 Function : This function selects of HSP fragments that have higher identities
			than threshold and sort the resulted fragments by scores.
 Usage	: &select_fragments(@array, $number)

=cut


sub select_fragments{
	my ($aline, $nid0) = @_;
	my ($s100, @a110) = ("", ());

	for(my $i10=0; $i10<=$#$aline; $i10++){
		my @a100 = split(/\t/, $aline->[$i10]);
		if($a100[15] >= $nid0){
			push(@a110, $aline->[$i10]);
		}
	}
	return @a110;
}

#############################
## Function: join_fragments_1
#############################

=head2 join_fragments_1

 Function : This function concatenates HSP fragments for each query sequence
			and outputs coordinate files.
 Usage	: &join_fragments_1(@array, $directory, $number, $number, $number);

=cut


sub join_fragments_1{
	my ($a210, $swd210, $sheader210, $ntg210, $ngg210, $ncv210, $nm) = @_;
	my (@a212, @a213, @a214) = ((), (), ());
	my ($frg210, $frg211) = (0, 0);
	my $sacc210 = "";

	my $sfile_cutpos = $swd210 . "/cut_position.txt";
	if(-f $sfile_cutpos){
		print STDERR "ERROR:File exists. $sfile_cutpos (\&join_fragments_1)\n";
		die "ERROR:$!";
	}else{
		open(CUTPOS, ">$sfile_cutpos");
		my $sdir_tbl210 = $swd210 . "/bln_tbl";
		if(! -d $sdir_tbl210){
			mkdir($sdir_tbl210, 0755);
		}

		for(my $i210=0; $i210<=$#$a210; $i210++){
			my @a211 = split(/\t/, $a210->[$i210]);

			$frg210 = 0;
			if($a211[0] ne $sacc210){
				$frg210 = 1;
			}
			if($frg210 == 1 && $frg211 == 1){
				my $ncv211 = $ncv210;
				while($ncv211>=0){
					@a213 = &join_fragments_2(\@a212, $ntg210, $ngg210, $ncv211, $sdir_tbl210, $nm, $sheader210);
					if($#a213>=0){
						last;
					}else{
						$ncv211 -= 0.05;
					}
				}
				push(@a214, @a213);
				@a212 = ();
			}
			push(@a212, $a210->[$i210]);
			$sacc210 = $a211[0];
			$frg211 = 1;
		}
		if($frg211){
			my $ncv211 = $ncv210;
			while($ncv211>=0){
				@a213 = &join_fragments_2(\@a212, $ntg210, $ngg210, $ncv211, $sdir_tbl210, $nm, $sheader210);
				if($#a213>=0){
					last;
				}else{
					$ncv211 -= 0.05;
				}
			}
			push(@a214, @a213);
		}
		close CUTPOS;
	}
	return @a214;
}

sub join_fragments_2{
	my ($a220, $ntg, $ngg, $ncv11, $sdir_tbl220, $nm, $sheader) = @_;
	my $ntid20 = 0;
	my ($s5join, $s3join) = ("", "");
	my $stid20 = $sheader . "_Transcript_";
	my (@a200, @a221, @ascr) = ((), (), ());
	my (@a230, @a240, @a2300, @a2400) = ((), (), (), ());
	my ($scdna, $sgenome, $stranscript, $ncdna_len, $ngenome_len) = ("", "", "", 0, 0);

	for(my $i20=0; $i20<=$#$a220; $i20++){
		push(@a221, $a220->[$i20]);
	}

	my ($nmintsp, $nmaxtep) = (100000, 0);
	foreach my $s100 (@a221){
		my @a120 = split(/\t/, $s100);
		push(@ascr, $a120[13]);
		if($a120[2] < $nmintsp){
			$nmintsp = $a120[2];
		}
		if($a120[3] > $nmaxtep){
			$nmaxtep = $a120[3];
		}
	}
	@a221 = @a221[sort {$ascr[$b] <=> $ascr[$a]} 0 .. $#ascr];

	my $nmaxth = 0;
	while($#a221 > -1){
		$ntid20++;
		my $s20 = shift(@a221);
		my @a222 = split(/\t/, $s20);
		my ($ntsp0, $ntep0, $ngsp0, $ngep0, $sstr0) = ($a222[2], $a222[3], $a222[7], $a222[8], $a222[9]);
		my $stid21 = $stid20 . $ntid20 . "__" . $a222[0];
		$s20 .= "\t" . $stid21;
		my $frg21 = 1;
		my @aIdent = ();
		while($frg21 == 1){
			my ($n5tgap, $n3tgap, $nmin5tgap, $nmin3tgap) = (0, 0, 100000, 100000);
			my ($n5ggap, $n3ggap, $nmin5ggap, $nmin3ggap) = (0, 0, 100000000, 100000000);
			my ($frg20_5, $frg20_3, $n20, $n21_5, $n21_3) = (0, 0, 0, 0, 0);
			foreach my $s31 (@a221){
				my $frg_tmp = 0;
				my @a223 = split(/\t/, $s31);
				if($a222[2] == $a223[2] && $a222[3] == $a223[3] && $a222[12] == $a223[12] && $a222[13] == $a223[13] && $a222[15] == $a223[15]){
					push(@aIdent, $s31);
				}
				if($a223[2] < $ntsp0 && $a223[3] < $ntep0){
					$n5tgap = $ntsp0 - $a223[3];
					if($n5tgap > (0-$ntg) && abs($n5tgap) <= $nmin5tgap && $a223[9] eq $sstr0){
						if($sstr0 eq "+"){
							$n5ggap = $ngsp0 - $a223[8];
							if($n5ggap > 0){
								if(abs($n5tgap) == $nmin5tgap){
									if($a223[8] < $ngsp0 && $n5ggap < $ngg && $n5ggap < $nmin5ggap){
										$frg_tmp = 1;
									}
								}else{
									if($a223[8] < $ngsp0 && $n5ggap < $ngg){
										$frg_tmp = 1;
									}
								}
							}
						}else{
							$n5ggap = $a223[7]-$ngep0;
							if($n5ggap > 0){
								if(abs($n5tgap) == $nmin5tgap){
									if($a223[7] > $ngep0 && $n5ggap < $ngg && $n5ggap < $nmin5ggap){
										$frg_tmp = 1;
									}
								}else{
									if($a223[7] > $ngep0 && $n5ggap < $ngg){
										$frg_tmp = 1;
									}
								}
							}
						}
					}
					if($frg_tmp == 1){
						if($#aIdent == -1){
							$frg20_5 = 1;
							$s5join = $s31;
							$nmin5tgap = abs($n5tgap);
							$nmin5ggap = $n5ggap;
							$n21_5 = $n20;
						}else{
							my $frg_join = 0;
							foreach my $s00 (@aIdent){
								my @a300 = split(/\t/, $s00);
								if($sstr0 eq "+"){
									if($ngsp0-$a300[8] > 0 && $n5ggap > $ngsp0-$a300[8]){
										$frg_join = 1;
									}
								}else{
									if($a300[7]-$ngep0 > 0 && $n5ggap > $a300[7]-$ngep0){
										$frg_join = 1;
									}
								}
							}
							if($frg_join == 0){
								$frg20_5 = 1;
								$s5join = $s31;
								$nmin5tgap = abs($n5tgap);
								$nmin5ggap = $n5ggap;
								$n21_5 = $n20;
							}
						}
					}
				}elsif($a223[3] > $ntep0 && $a223[2] > $ntsp0){
					$n3tgap = $a223[2] - $ntep0;
					if($n3tgap > (0-$ntg) && abs($n3tgap) <= $nmin3tgap && $a223[8] && $a223[9] eq $sstr0){
						if($sstr0 eq "+"){
							$n3ggap = $a223[7]-$ngep0;
							if($n3ggap > 0){
								if(abs($n3tgap) == $nmin3tgap){
									if($a223[7] > $ngep0 && $n3ggap < $ngg && $n3ggap < $nmin3ggap){
										$frg_tmp = 1;
									}
								}else{
									if($a223[7] > $ngep0 && $n3ggap < $ngg){
										$frg_tmp = 1;
									}
								}
							}
						}else{
							$n3ggap = $ngsp0-$a223[8];
							if($n3ggap > 0){
								if(abs($n3tgap) == $nmin3tgap){
									if($a223[8] < $ngsp0 && $n3ggap < $ngg && $n3ggap < $nmin3ggap){
										$frg_tmp = 1;
									}
								}else{
									if($a223[8] < $ngsp0 && $n3ggap < $ngg){
										$frg_tmp = 1;
									}
								}
							}
						}
					}
					if($frg_tmp == 1){
						if($#aIdent == -1){
							$frg20_3 = 1;
							$s3join = $s31;
							$nmin3tgap = abs($n3tgap);
							$nmin3ggap = $n3ggap;
							$n21_3 = $n20;
						}else{
							my $frg_join = 0;
							foreach my $s00 (@aIdent){
								my @a300 = split(/\t/, $s00);
								if($sstr0 eq "+"){
									if($a300[7]-$ngep0 > 0 && $n3ggap > $a300[7]-$ngep0){
										$frg_join = 1;
									}
								}else{
									if($ngsp0-$a300[8] > 0 && $n3ggap > $ngsp0-$a300[8]){
										$frg_join = 1;
									}
								}
							}
							if($frg_join == 0){
								$frg20_3 = 1;
								$s3join = $s31;
								$nmin3tgap = abs($n3tgap);
								$nmin3ggap = $n3ggap;
								$n21_3 = $n20;
							}
						}
					}
				}
				$n20++;
			}
			if($frg20_5 == 1 && $frg20_3 == 1){
				$s5join .= "\t" . $stid21;
				$s3join .= "\t" . $stid21;
				$s20 = sprintf join("|", $s5join, $s20, $s3join);
				my @a224 = split(/\t/, $s5join);
				my @a225 = split(/\t/, $s3join);
				if($sstr0 eq "+"){
					($ntsp0, $ntep0, $ngsp0, $ngep0) = ($a224[2], $a225[3], $a224[7], $a225[8]);
				}else{
					($ntsp0, $ntep0, $ngsp0, $ngep0) = ($a224[2], $a225[3], $a225[7], $a224[8]);
				}
				if($n21_5 < $n21_3){
					splice(@a221, $n21_3, 1);
					splice(@a221, $n21_5, 1);
				}else{
					splice(@a221, $n21_5, 1);
					splice(@a221, $n21_3, 1);
				}
			}elsif($frg20_5 == 1 || $frg20_3 == 1){
				if($frg20_5 == 1){
					$s5join .= "\t" . $stid21;
					$s20 = sprintf join("|", $s5join, $s20);
					my @a224 = split(/\t/, $s5join);
					if($sstr0 eq "+"){
						($ntsp0, $ngsp0) = ($a224[2], $a224[7]);
					}else{
						($ntsp0, $ngep0) = ($a224[2], $a224[8]);
					}
					splice(@a221, $n21_5, 1);
				}else{
					$s3join .= "\t" . $stid21;
					$s20 = sprintf join("|", $s20, $s3join);
					my @a225 = split(/\t/, $s3join);
					if($sstr0 eq "+"){
						($ntep0, $ngep0) = ($a225[3], $a225[8]);
					}else{
						($ntep0, $ngsp0) = ($a225[3], $a225[7]);
					}
					splice(@a221, $n21_3, 1);
				}
			}else{
				$frg21 = 0;
			}
		}

		@a230 = split(/\|/, $s20);
		@a240 = split(/\t/, $a230[0]);
		if($#a230 == 0){
			my @a250 = split(/\t/, $a230[0]);
			my ($ncv0, $nid0) = ($a250[16], $a250[15]);
			my $nth0 = $nid0;
			if($ncv0 >= $ncv11){
				if($nmaxth-0.05 <= $nth0 && $nth0 <= $nmaxth+0.05){
					push(@a200, $s20);
					if($nth0 > $nmaxth){
						$nmaxth = $nth0;
					}
				}elsif($nth0 > $nmaxth){
					@a200 = ();
					push(@a200, $s20);
					$nmaxth = $nth0;
				}
			}
		}else{
			my ($nsum0, $nsum1) = (0, 0);
			my ($ncv0, $nid0) = (0, 0);
			foreach my $s10 (@a230){
				my @a231 = split(/\t/, $s10);
				$nsum0 += ($a231[3]-$a231[2]+1);
				$nsum1 += int(($a231[3]-$a231[2]+1)*$a231[15]);
			}
			my @a250 = split(/\t/, $a230[0]);
			if($nsum0/$a250[1] > 1){
				$ncv0 = 1;
			}else{
				$ncv0 = $nsum0/$a250[1];
			}
			if($nsum1/$nsum0 > 1){
				$nid0 = 1;
			}else{
				$nid0 = $nsum1/$nsum0;
			}
			my $nth0 = $nid0;
			if($ncv0 >= $ncv11){
				if($nmaxth-0.05 <= $nth0 && $nth0 <= $nmaxth+0.05){
					push(@a200, $s20);
					if($nth0 > $nmaxth){
						$nmaxth = $nth0;
					}
				}elsif($nth0 > $nmaxth){
					@a200 = ();
					push(@a200, $s20);
					$nmaxth = $nth0;
				}
			}
		}
	}
	if($#a200>-1){
	foreach my $s00 (@a200){
		@a2300 = split(/\|/, $s00);
		@a2400 = split(/\t/, $a2300[0]);
		($scdna, $sgenome, $stranscript, $ncdna_len, $ngenome_len) =
		($a2400[0], $a2400[5], $a2400[17], $a2400[1], $a2400[6]);
		my ($ngsp30, $ngep30, $ngsp00, $ngep00) = (0, 0, 0, 0);
		if($#a2300 == 0){
			my @a320 = split(/\t/, $a2300[0]);
			($ngsp00, $ngep00) = ($a320[7], $a320[8]);
			if($a320[9] eq "+"){
				if($a320[2] == 1){
					$ngsp30 = $a320[7];
				}else{
					if($a320[7]<10){
						$ngsp30 = $a320[7] - 1000;
					}else{
						$ngsp30 = $a320[7] - $nm;
					}
					if($ngsp30 < 1){
						$ngsp30 = 1;
					}
				}
				if($a320[3] == $a320[1]){
					$ngep30 = $a320[8];
				}else{
					if($a320[1]-$a320[3] < 10){
						$ngep30 = $a320[8] + 1000;
					}else{
						$ngep30 = $a320[8] + $nm;
					}
					if($ngep30 > $ngenome_len){
						$ngep30 = $ngenome_len;
					}
				}
			}else{
				if($a320[2] == 1){
					$ngep30 = $a320[8];
				}else{
					if($a320[2] < 10){
						$ngep30 = $a320[8] + 1000;
					}else{
						$ngep30 = $a320[8] + $nm;
					}
					if($ngep30 > $ngenome_len){
						$ngep30 = $ngenome_len;
					}
				}
				if($a320[3] == $a320[1]){
					$ngsp30 = $a320[7];
				}else{
					if($a320[1]-$a320[3] < 10){
						$ngsp30 = $a320[7] - 1000;
					}else{
						$ngsp30 = $a320[7] - $nm;
					}
					if($ngsp30 < 1){
						$ngsp30 = 1;
					}
				}
			}
		}else{
			my @a320 = split(/\t/, $a2300[0]);
			my @a321 = split(/\t/, $a2300[$#a2300]);
			if($a320[9] eq "+"){
				($ngsp00, $ngep00) = ($a320[7], $a321[8]);
				if($a320[2] == 1){
					$ngsp30 = $a320[7];
				}else{
					$ngsp30 = $a320[7] - $nm;
					if($ngsp30 < 1){
						$ngsp30 = 1;
					}
				}
				if($a321[3] == $a321[1]){
					$ngep30 = $a321[8];
				}else{
					$ngep30 = $a321[8] + $nm;
					if($ngep30 > $ngenome_len){
						$ngep30 = $ngenome_len;
					}
				}
			}else{
				($ngsp00, $ngep00) = ($a321[7], $a320[8]);
				if($a320[2] == 1){
					$ngep30 = $a320[8];
				}else{
					$ngep30 = $a320[8] + $nm;
					if($ngep30 > $ngenome_len){
						$ngep30 = $ngenome_len;
					}
				}
				if($a321[3] == $a321[1]){
					$ngsp30 = $a321[7];
				}else{
					$ngsp30 = $a321[7] - $nm;
					if($ngsp30 < 1){
						$ngsp30 = 1;
					}
				}
			}
		}
		print CUTPOS join("\t", $scdna, $ncdna_len, $sgenome, $ngenome_len, $stranscript, $ngsp30, $ngep30, $ngep30-$ngsp30+1, $ngsp00, $ngep00),"\n";

		my $sfile_tbl210 = $sdir_tbl220 . "/" . $a2400[17] . ".tbl";
		if(-f $sfile_tbl210){
			print STDERR "ERROR:File exists. $sfile_tbl210(\&join_fragments_2)\n";
			die "ERROR:$!";
		}else{
			open(BLNTBL, ">$sfile_tbl210");
			if($a2400[4] eq "+" && $a2400[9] eq "-"){
				my @agsp200 = ();
				foreach my $s200 (@a2300){
					my @a231 = split(/\t/, $s200);
					push(@agsp200, $a231[7]);
				}
				@a2300 = @a2300[sort {$agsp200[$a] <=> $agsp200[$b]} 0 .. $#agsp200];
				for(my $i200=0; $i200<=$#a2300; $i200++){
					my @a232 = split(/\t/, $a2300[$i200]);
					($a232[4], $a232[9]) = ("-", "+");
					print BLNTBL join("\t", @a232),"\n";
				}
			}elsif($a2400[4] eq "+" && $a2400[9] eq "+"){
				print BLNTBL join("\n", @a2300),"\n";
			}else{
				print STDERR "ERROR:Irregular strand information(\&join_fragments_2)\n";
				die "ERROR:$!";
			}
			close BLNTBL;
		}
	}
	}
	return @a200;
}

#####################
## Function: clip_seq
#####################

=head2 clip_seq

 Function : This function clips the roughly estimated regions for each hit region.
 Usage	: &clip_seq(@array, $number, $number, $directory);

=cut


sub clip_seq{
	my ($swd1 , $scutpos, $sgs1) = @_;

	my $sGSEQ_E2G = $swd1 . "/genome_fore2g";
	if(! -d $sGSEQ_E2G){
		mkdir($sGSEQ_E2G, 0755);
	}

	if(! -f $scutpos){
		print STDERR "ERROR:File does not exist. $scutpos (\&clip_seq)\n";
		die "ERROR:$!";
	}else{
		open(CUTPOS, "$scutpos");
		my @acutpos = <CUTPOS>;
		chomp(@acutpos);
		foreach my $s10 (@acutpos){
			my @a10 = split(/\t/, $s10);
			my $s11 = $sGSEQ_E2G . "/" . $a10[4] . ".fa";
			my $s12 = substr($sgs1, $a10[5]-1, $a10[6]-$a10[5]+1);

			open(SEQ, ">$s11");
			print SEQ ">$a10[4]\n";
			print SEQ $s12 . "\n";
			close SEQ;
		}
	}

}

sub rmv_redundancy_1{
	my $sfile_clip00 = $_[0];
	my ($frg00, $frg01, $sacc, @aclip_02) = (0, 0, "", ());

	if(-f $sfile_clip00){
		open(CLIP, $sfile_clip00);
		my @aclip00 = <CLIP>;
		close CLIP;
		open(CLIP, ">$sfile_clip00");
		chomp(@aclip00);
		for(my $ii=0; $ii<=$#aclip00; $ii++){
			my @aclip01 = split(/\t/, $aclip00[$ii]);

			$frg00 = 0;
			if($aclip01[0] ne $sacc){
				$frg00 = 1;
			}
			if($frg00 == 1 && $frg01 == 1){
				&rmv_redundancy_2(\@aclip_02);
				@aclip_02 = ();
			}
			push(@aclip_02, $aclip00[$ii]);
			$sacc = $aclip01[0];
			$frg01 = 1;
		}
		if($frg01){
			&rmv_redundancy_2(\@aclip_02);
		}
		close CLIP;
	}else{
		print STDERR "ERROR:File does not exist. (\&rmv_redundancy_1)\n";
		die "ERROR:$!";
	}
}

sub rmv_redundancy_2{
	my $a00 = $_[0];
	my (@a10, @a12) = ((), ());

	for(my $ii=0; $ii<=$#$a00; $ii++){
		push(@a10, $a00->[$ii]);
	}

	foreach my $s00 (@a10){
		my @a11 = split(/\t/, $s00);
		push(@a12, $a11[5]);
	}
	@a10 = @a10[sort {$a12[$a] <=> $a12[$b]} 0 .. $#a12];

	my %hCLUSTER = ();
	my $cl_number = 0;
	my $cl_name = "";
	my ($nsp, $nep) = (1000000000, 0);
	foreach my $s20 (@a10){
		my @a20 = split(/\t/, $s20);
		if($a20[5] > $nep){
			$cl_number++;
			$cl_name = "cl_". $cl_number;
			push(@{$hCLUSTER{$cl_name}}, $s20);
			($nsp, $nep) = ($a20[5], $a20[6]);
		}else{
			push(@{$hCLUSTER{$cl_name}}, $s20);
			if($a20[6] > $nep){
				$nep = $a20[6];
			}
		}
	}
	foreach my $s0 (keys %hCLUSTER){
		my @asp = ();
		foreach my $s1 (@{$hCLUSTER{$s0}}){
			my @a0 = split(/\t/, $s1);
			push(@asp, $a0[8]);
		}
		@{$hCLUSTER{$s0}} = @{$hCLUSTER{$s0}}[sort {$asp[$a] <=> $asp[$b]}0..$#asp];

		my %hOVLP = ();
		foreach my $s1 (@{$hCLUSTER{$s0}}){
			my @a1 = split(/\t/, $s1);
			if(!$hOVLP{$a1[4]}){
				my ($sp, $ep) = ($a1[5], $a1[6]);
				foreach my $s2 (@{$hCLUSTER{$s0}}){
					my @a2 = split(/\t/, $s2);
					if($a1[4] eq $a2[4]){
					}else{
						if($a2[9] < $a1[8]){
							$sp = $a2[9]+1;
						}elsif($a1[9] < $a2[8]){
							$ep = $a2[8]-1;
							last;
						}else{
							my $ovlp = (($a1[6]-$a1[5]+1+$a2[6]-$a2[5]+1)-(abs($a1[5]-$a2[5])+abs($a1[6]-$a2[6])))/2;
							if($ovlp/($a2[6]-$a2[5]+1)>= 0.9){
								$hOVLP{$a2[4]} = 1;
							}
						}
					}
				}
				($a1[5], $a1[6]) = ($sp, $ep);
				print CLIP join("\t", @a1), "\n";
			}
		}
	}
}

#####################
## Function: make_gff
#####################

=head2 make_gff

	Function : This function creates GFF files from coordinate files
	Usage	: &make_gff($directory, $file);

=cut


sub make_gff{

	my ($sdir_wd00, $sfile_tbl00, $source) = @_;
	my (@agff00, @atsp00) = ((), ());
	my (@agff_100, @agff_110, @agff_120, @agff_111, @agff_130) = ((), (), (), (), ());
	my ($stranscript_id, $sparent_id, $sseq_id, $scol9_mRNA, $scol9_exon) = ("", "", "", "", "", "", "");

	if(-f $sfile_tbl00){
		my $sfile_gff00 = $sdir_wd00 . "/GFF/" . basename($sfile_tbl00) . ".gff";
		if(-f $sfile_gff00){
			print STDERR "ERROR:File exists. (\&make_gff)\n";
			die "ERROR:$!";
		}else{
			open(GFF, ">$sfile_gff00");
			if (!-z $sfile_tbl00){
				print GFF "##gff-version 3\n";
				open(TBL, $sfile_tbl00);
				@agff00 = <TBL>;
				chomp(@agff00);
				my @agff01 = split(/\t/, $agff00[0]);
				if($agff01[4] eq "-"){
					my @agff10 = ();
					foreach my $sgff00 (@agff00){
						my @agff11 = split(/\t/, $sgff00);
						push(@atsp00, $agff11[2]);
					}
					@agff00 = @agff00[sort {$atsp00[$a] <=> $atsp00[$b]} 0 .. $#atsp00];
				}

				if($#agff00 == 0){
					@agff_100 = split(/\t/, $agff00[0]);
					$stranscript_id = "ID\=" . $agff_100[17];
					$sparent_id = "Parent\=" . $agff_100[17];
					$sseq_id = "Seq_id\=" . $agff_100[0];
					$scol9_mRNA = $stranscript_id . ";" . $sseq_id;
					$scol9_exon = $sparent_id . ";" . $sseq_id;
					print GFF join("\t", $agff_100[5],$source,"mRNA",$agff_100[7],$agff_100[8], ".",$agff_100[4],".",$scol9_mRNA),"\n";
					print GFF join("\t", $agff_100[5],$source,"exon",$agff_100[7],$agff_100[8], ".",$agff_100[4],".",$scol9_exon),"\n";
				}else{
					@agff_100 = split(/\t/, $agff00[0]);
					$stranscript_id = "ID\=" . $agff_100[17];
					$sparent_id = "Parent\=" . $agff_100[17];
					$sseq_id = "Seq_id\=" . $agff_100[0];
					$scol9_mRNA = $stranscript_id . ";" . $sseq_id;
					$scol9_exon = $sparent_id . ";" . $sseq_id;
					if($agff_100[4] eq "+"){
						@agff_110 = split(/\t/, $agff00[0]);
						@agff_111 = split(/\t/, $agff00[$#agff00]);
					}else{
						@agff_110 = split(/\t/, $agff00[$#agff00]);
						@agff_111 = split(/\t/, $agff00[0]);
					}
					print GFF join("\t", $agff_110[5],$source,"mRNA",$agff_110[7],$agff_111[8], ".",$agff_100[4],".",$scol9_mRNA),"\n";
					for(my $igff1=0; $igff1<=$#agff00; $igff1++){
						@agff_120 = split(/\t/, $agff00[$igff1]);
						print GFF join("\t", $agff_120[5],$source,"exon",$agff_120[7],$agff_120[8], ".",$agff_100[4],".",$scol9_exon),"\n";
					}
				}
			}
			close GFF;
		}
	}else{
		print STDERR "ERROR:File does not exist. (\&make_gff)\n";
		die "ERROR:$!";
	}
}

####################
## Function: run_exonerate
####################

=head2 run_exonerate

 Function : This function conducts exonerate.
	Usage	: &run_exonerate($directory, $file, $command, $option);

=cut


sub run_exonerate{
	my ($sdir_wd00, $se2g_file00, $sexonerate_exe0, $sexonerate_opt0) = @_;

	### Make a directory to stock exonerate output files ###
	my $sdir_e2gout = $sdir_wd00 . "/e2g_out";
	if(! -d $sdir_e2gout){
		mkdir($sdir_e2gout, 0755);
	}

	if(-f $se2g_file00){
		open(E2GLIST, $se2g_file00);
		while(<E2GLIST>){
			chomp;
			my @ae2g00 = split(/\t/, $_);
			my ($sfile_gseq0, $sfile_tseq0) = ($ae2g00[0], $ae2g00[1]);
			my $sgseq00 = basename($sfile_gseq0);
			if(-f $sfile_tseq0 && -f $sfile_gseq0){
				my $sfile_exonerateout = $sdir_e2gout . "/" . $sgseq00 . ".e2g";
				if(-f $sfile_exonerateout){
					print STDERR "WARNING: File exists. ($sfile_exonerateout) (\&run_exonerate)\n";
					#die "ERROR:$!";
				}else{
					my $scommand = $sexonerate_exe0 . " " . $sexonerate_opt0 .  " --bestn 1 -q " . $sfile_tseq0 . " -t " . $sfile_gseq0 . " > " . $sfile_exonerateout;
					print "[SIMsearch::mapping::MAP::run_exonerate]: Exonerate command is: " . $scommand . "\n";
					system("$scommand");
				}
			}else{
				print STDERR "ERROR: Can't find the file. ($sfile_tseq0 and/or $sfile_gseq0) (\&run_exonerate)\n";
				die "ERROR:$!";
			}
		}
		close E2GLIST;
	}else{
		print STDERR "ERROR: Can't find the file. ($se2g_file00) (\&run_exonerate)\n";
		die "ERROR:$!";
	}
}

##########################
## Function: exonerate_tbl
##########################

=head2 exonerate_tbl

 Function : This function creates coordinate files from exonerate result files.
	Usage	: &exonerate_tbl($directory, $directory);

=cut

sub exonerate_tbl{
	my ($sdir_wd10, $sdir_e2g10) = @_;

	### Make a directory to stock est2genome output files ###
	my $sdir_e2gtbl = $sdir_wd10 . "/e2g_tbl";
	if(! -d $sdir_e2gtbl){
		mkdir($sdir_e2gtbl, 0755);
	}

	my $sfile_epos = $sdir_wd10 . "/exon_position.txt";
	open(EPOS, "+>>$sfile_epos");

	my $sE2G_LEN = $sdir_wd10 . "/cut_position.txt";
	my %hG_LEN = ();
	if(-f $sE2G_LEN){
		open(G_LEN, $sE2G_LEN);
		while(<G_LEN>){
			chomp;
			my @aG_LEN = split(/\t/, $_);
			$hG_LEN{$aG_LEN[4]} = [@aG_LEN];
		}
		close G_LEN;
	}else{
		print STDERR "ERROR: Can't find the file. ($sE2G_LEN) (\&e2g_tbl).\n";
		die "ERROR:$!";
	}

	if(-d $sdir_e2g10){
		my @ae2gout10 = glob("$sdir_e2g10/*.fa.e2g");
		foreach my $se2gout11 (@ae2gout10){
			my $sfile_e2gout10 = $se2gout11;
			my $sfile_e2gtbl10 = $sdir_e2gtbl. "/". basename($se2gout11) . ".tbl";
			if(-f $sfile_e2gtbl10){
				print STDERR "WARNING: File exists. ($sfile_e2gtbl10) (\&e2g_tbl)\n";
			}else{
				open(E2GTBL, ">$sfile_e2gtbl10");
				open(E2GOUT, "$sfile_e2gout10");
				my $line_count = 0;
				my ($query_id, $query_strand, $query_sp, $query_ep, $query_line) = ("", "", 0, 0, "");
				my ($hit_id, $sbjct_strand, $sbjct_sp, $sbjct_ep, $sbjct_line) = ("", "", 0, 0, "");
				my ($query_strand2, $sbjct_strand2) = ("", "");
				my $status_line = "";
				my ($query_line_tmp, $sbjct_line_tmp, $margin) = ("","");
				my $vulgar = "";
				while(my $line = <E2GOUT>){
					chomp $line;
					if($line =~ /^([ ]*\d+[ ]*:[ ])(.+)[ ]:[ ]*\d+/){
						$line_count++;
						if($line_count == 1){
							($margin, $query_line_tmp) = ($1, $2);
							$query_line .= $query_line_tmp;
							$line_count++;
						}elsif($line_count == 3){
							($margin, $sbjct_line_tmp) = ($1, $2);
							$sbjct_line .= $sbjct_line_tmp;
							$line_count = 0;
						}
					}elsif($line_count == 2){
						my $tmp_line = substr($line, length($margin), length($query_line_tmp));
						$status_line .= $tmp_line;
					}elsif($line =~ /^vulgar: (\S+) (\d+) (\d+) ([+-]) (\S+) (\d+) (\d+) ([+-]) \d+ (.+)/){
						($query_id, $query_sp, $query_ep, $query_strand, $hit_id, $sbjct_sp, $sbjct_ep, $sbjct_strand, $vulgar) = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
						last;
					}else{}
				}
				next if($query_id eq "");
				if($query_strand eq "+"){
					$query_sp++;
				}else{
					$query_ep++;
					($query_sp, $query_ep) = ($query_ep, $query_sp);
				}
				if($sbjct_strand eq "+"){
					$sbjct_sp++;
				}else{
					$sbjct_ep++;
				}
				$sbjct_sp = $sbjct_sp + $hG_LEN{$hit_id}[5] - 1;
				$sbjct_ep = $sbjct_ep + $hG_LEN{$hit_id}[5] - 1;
				my ($query_length, $sbjct_length, $chr_name) = ($hG_LEN{$hit_id}[1], $hG_LEN{$hit_id}[3], $hG_LEN{$hit_id}[2]);
				close E2GOUT;
				my @aexon_base = split(/\.+/, $sbjct_line);
				my @aintron_base = $sbjct_line =~ /(\.+)/g;
				my @aintron_inf = $vulgar =~ /([53] \d+ \d+ I \d+ \d+ [35] \d+ \d+)/g;
				die "ERROR: Can't retrieve intron information.($se2gout11)\n" if($#aintron_base != $#aintron_inf);
				my $sbstr_sp = 0;
				my ($query_exon_sp, $query_exon_ep, $sbjct_exon_sp, $sbjct_exon_ep) = ($query_sp, 0, $sbjct_sp, 0);

				my @aExon_lines = ();
				my @aSbjct_sp = ();
				foreach my $sbjct_aln_line (@aexon_base){
					my $tmp_length = length($sbjct_aln_line);
					my $query_aln_line = substr($query_line, $sbstr_sp, $tmp_length);
					my $status_aln_line = substr($status_line, $sbstr_sp, $tmp_length);
					my $intron_aln_length = 0;
					my $intron_aln_line = shift(@aintron_base);
					$intron_aln_length = length($intron_aln_line) if($intron_aln_line);
					my ($intron_len1, $intron_len2, $ss_five_len2, $ss_three_len2) = (0, 0, 0, 0);
					if($#aintron_inf > -1){
						my $intron_inf = shift(@aintron_inf);
						($ss_five_len2, $intron_len1, $intron_len2, $ss_three_len2) = $intron_inf =~ /[53] \d+ (\d+) I (\d+) (\d+) [35] \d+ (\d+)/;
						print STDERR "WARNING: irregular intron inf. in vulgar ($se2gout11)\n" if($intron_len1 != 0 || $ss_five_len2 == 0 || $ss_three_len2 == 0);
					}
					my ($ss_five, $ss_three) = ("", "");
					if($status_aln_line =~ /^([+-]+)/){
						$ss_five = $1;
					}
					if($status_aln_line =~ /([+-]+)$/){
						$ss_three = $1;
					}
					my $intron_length = $intron_len2 + $ss_five_len2 + $ss_three_len2;
					if($ss_five){
						substr($query_aln_line, 0, length($ss_five)) = "";
						substr($sbjct_aln_line, 0, length($ss_five)) = "";
						substr($status_aln_line, 0, length($ss_five)) = "";
					}
					if($ss_three){
						substr($query_aln_line, 0-length($ss_three), length($ss_three)) = "";
						substr($sbjct_aln_line, 0-length($ss_three), length($ss_three)) = "";
						substr($status_aln_line, 0-length($ss_three), length($ss_three)) = "";
					}

					my @aquery_string = split(//, $query_aln_line);
					my @asbjct_string = split(//, $sbjct_aln_line);
					my @astatus_string = split(//, $status_aln_line);
					my ($query_aln_length, $sbjct_aln_length, $aln_length, $match_length) = (0, 0, 0, 0);
					for(my $ii=0; $ii<=$#aquery_string; $ii++){
						$aln_length++;
						$query_aln_length ++ if($aquery_string[$ii] =~ /[a-zA-Z]/);
						$sbjct_aln_length ++ if($asbjct_string[$ii] =~ /[a-zA-Z]/);
						if($aquery_string[$ii] =~ /[a-zA-Z]/ && $asbjct_string[$ii] =~ /[a-zA-Z]/){
							$match_length ++ if($aquery_string[$ii] eq $asbjct_string[$ii]);
						}
					}

					my $exon_identity = sprintf("%.4f", 0);
					if ($aln_length != 0) { $exon_identity = sprintf("%.4f", $match_length/$aln_length); }
					my $exon_coverage = sprintf("%.4f", 0);
					if ($query_length != 0) { $exon_coverage = sprintf("%.4f", $query_aln_length/$query_length); }

					$query_exon_ep = $query_exon_sp + $query_aln_length - 1;
					my ($sbjct_exon_sp2, $sbjct_exon_ep2) = (0, 0);

					if($sbjct_strand eq "+"){
						$sbjct_exon_ep = $sbjct_exon_sp + $sbjct_aln_length - 1;
						($sbjct_exon_sp2, $sbjct_exon_ep2) = ($sbjct_exon_sp, $sbjct_exon_ep);
						($query_strand2, $sbjct_strand2) = ("+", "+");
					}else{
						$sbjct_exon_ep = $sbjct_exon_sp - $sbjct_aln_length + 1;
						($sbjct_exon_sp2, $sbjct_exon_ep2) = ($sbjct_exon_ep, $sbjct_exon_sp);
						($query_strand2, $sbjct_strand2) = ("-", "+");
					}
					my $exon_line = join("\t", $query_id,$query_length,$query_exon_sp,$query_exon_ep,$query_strand2,$chr_name,$sbjct_length,$sbjct_exon_sp2,$sbjct_exon_ep2,$sbjct_strand2,$aln_length,$match_length,"-","-","-",$exon_identity,$exon_coverage,$hit_id);
					push(@aExon_lines, $exon_line);
					push(@aSbjct_sp, $sbjct_exon_sp2);
					$sbstr_sp = $sbstr_sp + $tmp_length + $intron_aln_length;
					$query_exon_sp = $query_exon_ep+1;
					if($sbjct_strand eq "+"){
						$sbjct_exon_sp = $sbjct_exon_ep + $intron_length + 1;
					}else{
						$sbjct_exon_sp = $sbjct_exon_ep - $intron_length - 1;
					}
				}
				@aExon_lines = @aExon_lines[sort{$aSbjct_sp[$a] <=> $aSbjct_sp[$b]}0..$#aExon_lines];
				my @aQuery_sp = ();
				my @aQuery_ep = ();
				my @aGenome_sp = ();
				my @aGenome_ep = ();
				foreach my $exon_line (@aExon_lines){
					my @aLine = split(/\t/, $exon_line);
					push(@aQuery_sp, $aLine[2]);
					push(@aQuery_ep, $aLine[3]);
					push(@aGenome_sp, $aLine[7]);
					push(@aGenome_ep, $aLine[8]);
				}
				my $query_sp_line = join(";", @aQuery_sp);
				my $query_ep_line = join(";", @aQuery_ep);
				my $genome_sp_line = join(";", @aGenome_sp);
				my $genome_ep_line = join(";", @aGenome_ep);
				print EPOS join("\t", $query_id,$query_strand2,$query_sp_line,$query_ep_line,$hit_id,$sbjct_strand2,$genome_sp_line,$genome_ep_line), "\n";
				print E2GTBL join("\n", @aExon_lines), "\n";
				close E2GTBL;
			}
		}
	}
	close EPOS;
}

############################
## Function: calculate_idcov
############################

=head2 calculate_idcov

 Function : This function calculates nucleotide identities and coverages
			for each mapped sequence.
 Usage	: &calculate_idcov($file);

=cut


sub calculate_idcov{
	my ($sfile_tbl00) = @_;

	if(-f $sfile_tbl00){
		open(TBL, $sfile_tbl00);
		my @atbl00 = <TBL>;
		chomp(@atbl00);
		my @atbl01 = split(/\t/, $atbl00[0]);
		if($atbl01[4] eq "-"){
			my @atsp00 = ();
			foreach my $stbl00 (@atbl00){
				my @atbl10 = split(/\t/, $stbl00);
				push(@atsp00, $atbl10[2]);
			}
			@atbl00 = @atbl00[sort {$atsp00[$a] <=> $atsp00[$b]} 0 .. $#atsp00];
		}

		my ($nalnquery, $nalnsum, $novlp, $nhitsum) = (0, 0, 0, 0);
		my (@atbl02, @atbl03, $nidfin01, $ncvfin01) = ((), (), 0, 0);
		for(my $itbl=0; $itbl<=$#atbl00-1; $itbl++){
			@atbl02 = split(/\t/, $atbl00[$itbl]);
			@atbl03 = split(/\t/, $atbl00[$itbl+1]);

			$nalnquery += ($atbl02[3]-$atbl02[2]+1);
			$nalnsum += $atbl02[10];
			$nhitsum += $atbl02[11];
			if($atbl03[2] <= $atbl02[3]){
				$novlp += ($atbl02[3]-$atbl03[2]+1);
			}
		}
		@atbl03 = split(/\t/, $atbl00[$#atbl00]);

		$nalnquery += ($atbl03[3]-$atbl03[2]+1);
		$nalnsum += $atbl03[10];
		$nhitsum += $atbl03[11];
		$nidfin01 = sprintf("%.4lf", $nhitsum/$nalnsum);
		$ncvfin01 = sprintf("%.4lf", ($nalnquery-$novlp)/$atbl01[1]);
		if($nalnquery-$novlp > $atbl01[1] || $nidfin01 > 1){
			print STDERR "ERROR:Identity or Coverage exceeded 1.0: $sfile_tbl00 (\&calculate_idcov)\n";
			die "ERROR:$!";
		}else{
			return ($nidfin01, $ncvfin01);
		}
	}else{
		print STDERR "ERROR:File does not exist. (\&calculate_idcov)\n";
		die "ERROR:$!";
	}
}

#####################
## Function: join_gff
#####################

=head2 join_gff

 Function : This function joins all GFF files under the specified directory.
 Usage	: &join_gff($directory, $name, $sequence);

=cut


sub join_gff{
	my ($swd, $sheader, $sseq) = @_;

	my $nseq_len = length($sseq);
	my $sdir_gff = $swd . "/GFF";
	if(! -d $sdir_gff){
		print STDERR "ERROR:Directory does not exist. (\&join_gff)\n";
		die "ERROR:$!";
	}else{
		my $sfile_gff = $swd . "/" . $sheader . "_RAP.gff";
		if(-f $sfile_gff){
			print STDERR "ERROR:File exists. (\&join_gff)\n";
			die "ERROR:$!";
		}else{
			open(GFF, ">$sfile_gff");
			print GFF "##gff-version 3\n";
			print GFF join("\t", $sheader,"TriannotPipeline","sequence","1",$nseq_len,".",".",".","ID="),$sheader,"\n";
			my $sgff_list = `ls $sdir_gff`;
			my @agff_list = split(/\n/, $sgff_list);
			foreach my $s00 (@agff_list){
				my $sgff00 = $sdir_gff . "/" . $s00;
				my @agff00 = split(/\n/, `cat $sgff00`);
				foreach my $s01 (@agff00){
					if($s01 !~ /^\#\#gff-version 3/){
						print GFF $s01 , "\n";
					}
				}
			}
			close GFF;
		}
	}
}

####################
## Function: gff2fna
####################

=head2 gff2fna

 Function : This function makes a multi-FASTA format file from a GFF file.
 Usage	: &gff2fna(GFF file path, Sequence file path)

=cut

sub gff2fna{
	my ($swd, $sgff, $sseq) = @_;

	if(! -f $sseq){
		print STDERR "ERROR: File does not exist.\n";
		die "ERROR:$!";
	}else{
		my ($sGseq_header, $sGseq) = &getseq($sseq);
		if(! -f $sgff){
			print STDERR "ERROR: File does not exist.\n";
			die "ERROR:$!";
		}else{
			my $fFNA = $swd . "/" . basename($sgff) . ".fna";
			open(FNA, ">$fFNA");
			open(GFF, $sgff);
			my @agff = <GFF>;
			chomp(@agff);
			close GFF;
			my @a10 = ();
			foreach my $s00 (@agff){
				my @a00 = split(/\t/, $s00);
				if($a00[0] eq $sGseq_header){
					my @a01 = split(/\;/, $a00[8]);
					if($a00[2] =~ /exon/ || $a00[2] =~ /CDS/){
						my $sparent = "";
						foreach my $s0 (@a01){
							if($s0 =~ /^Parent\=(\S+)/){
								$sparent = $1;
							}
						}
						push(@a10, sprintf join("\t", $sparent,$a00[3],$a00[4],$a00[6]));
					}
				}
			}
			my (@aacc, @asp) = ((), ());
			foreach my $s00 (@a10){
				my @a00 = split(/\t/, $s00);
				push(@aacc, $a00[0]);
				push(@asp, $a00[1]);
			}
			@a10 = @a10[sort {$aacc[$a] cmp $aacc[$b] or $asp[$a] <=> $asp[$b]} 0 .. $#aacc];

			my ($frg00, $frg01) = (0, 0);
			my ($sacc, $sstr, $stseq) = ("", "", "");
			foreach my $s00 (@a10){
				my @a00 = split(/\t/, $s00);
				$frg01 = 0;
				if($a00[0] ne $sacc){
					$frg01 = 1;
				}
				if($frg00 == 1 && $frg01 == 1){
					if($sstr eq "-"){
						$stseq = reverse($stseq);
						$stseq =~ tr/[atgcurymkswhbvdnATGCURYMKSWHBVDN]/[tacgayrkmswdvbhnTACGAYRKMSWDVBHN]/;
					}
					print FNA ">$sacc\n";
					while(substr($stseq, 0, 50)){
						print FNA substr($stseq, 0, 50) , "\n";
						substr($stseq, 0, 50) = "";
					}
					$stseq = "";
				}
				($sacc, $sstr) = ($a00[0], $a00[3]);
				$stseq .= substr($sGseq, $a00[1]-1, ($a00[2]-$a00[1]+1));
				$frg00 = 1;
			}
			if($frg00 == 1){
				if($sstr eq "-"){
					$stseq = reverse($stseq);
					$stseq =~ tr/[atgcurymkswhbvdnATGCURYMKSWHBVDN]/[tacgayrkmswdvbhnTACGAYRKMSWDVBHN]/;
				}
				print FNA ">$sacc\n";
				while(substr($stseq, 0, 50)){
					print FNA substr($stseq, 0, 50) , "\n";
					substr($stseq, 0, 50) = "";
				}
			}
			close FNA;
		}
	}
}

#######################
## Function: clustering
#######################

=head2 clustering

 Function : This function conducts clustering between two GFF files.
 Usage	: &clustering(GFF file path, GFF file path)

=cut

sub clustering{
	my ($sGFF1, $sGFF2, $swd) = @_;

	if(! -f $sGFF1 || ! -f $sGFF2){
		print STDERR "ERROR: Can't find GFF file(s).\n";
		die "ERROR:$!";
	}else{
		open(F0, $sGFF1);
		open(F1, $sGFF2);

		my (@aACC, %h10, %h11) = ((), (), ());

		my @a00 = <F0>;
		chomp(@a00);
		my @a10 = ();
		foreach my $s0 (@a00){
			my @a0 = split(/\t/, $s0);
			my @a1 = split(/\;/, $a0[8]);
			if($a1[0] =~ /^Parent\=(\S+)/ || $a1[0] =~ /^[iI]D\=(\S+)/){
				my $s1 = sprintf join("\t", $1, $a0[3], $a0[4], $a0[6]);
				$h10{$s1} = $s1;
				push(@a10, $s1);
				push(@aACC, $1);
			}
		}
		close F0;

		my @a01 = <F1>;
		chomp(@a01);
		my @a11 = ();
		foreach my $s0 (@a01){
			my @a0 = split(/\t/, $s0);
			my @a1 = split(/\;/, $a0[8]);
			if($a1[0] =~ /^Parent\=(\S+)/ || $a1[0] =~ /^[iI]D\=(\S+)/){
				my $s1 = sprintf join("\t", $1, $a0[3], $a0[4], $a0[6]);
				$h11{$s1} = $s1;
				push(@a11, $s1);
				push(@aACC, $1);
			}
		}
		close F1;

		my %tmp = ();
		@aACC = grep(!$tmp{$_}++, @aACC);

		my @a20 = (@a10, @a11);
		my @a1 = ();
		foreach my $s0 (@a20){
			my @a0 = split(/\t/, $s0);
			push(@a1, $a0[1]);
		}
		@a20 = @a20[sort {$a1[$a] <=> $a1[$b]} 0 .. $#a1];

		%tmp = ();
		@a20 = grep(!$tmp{$_}++, @a20);

		my $nPos = 1;
		my $nInterval = 10000;
		my $n0 = 0;
		my (@a21, @a22) = ((), ());
		my @aRes = ();
		while($#a20>-1){
			my @a30 = @a22;
			(@a21, @a22) = ((), ());
			if($#a30>-1){
				foreach my $s1 (@a30){
					my @a1 = split(/\t/, $s1);
					if($a1[2] >= $nPos+$nInterval){
						push(@a22, $s1);
					}
				}
			}
			$n0 = 0;
			foreach my $s0 (@a20){
			my @a0 = split(/\t/, $s0);
				if($nPos <= $a0[1] && $a0[1] < $nPos+$nInterval){
					push(@a21, $s0);
					$n0++;
					if($a0[2] >= $nPos+$nInterval){
						push(@a22, $s0);
					}
				}else{
					last;
				}
			}
			splice(@a20, 0, $n0);
			if($#a21>-1){
				my @atmp = &clustering_2(\@a21, \@a30, \%h10, \%h11);
				if($#atmp>-1){
					push(@aRes, @atmp);
				}
			}
			$nPos+=$nInterval;
		}

		my ($CLST, $SNGL) = ("", "");
		if(! $swd || $swd eq ""){
			$CLST = "./" . "clst.txt";
			$SNGL = "./" . "sngl.txt";
		}else{
			$CLST = $swd . "/clst.txt";
			$SNGL = $swd . "/sngl.txt";
		}

		open(CLST, ">$CLST");
		open(SNGL, ">$SNGL");

		%tmp = ();
		@aRes = grep(!$tmp{$_}++, @aRes);
		print CLST join("\n", @aRes), "\n";

		my %hACC = ();
		foreach my $s00 (@aRes){
			my @a00 = split(/\t/, $s00);
			$hACC{$a00[0]} = $a00[0];
			$hACC{$a00[5]} = $a00[5];
		}
		foreach my $s00 (@aACC){
			if(!$hACC{$s00}){
				print SNGL $s00 , "\n";
			}
		}
		close CLST;
		close SNGL;
	}
}

#########################
## Function: clustering_2
#########################

=head2 clustering_2

 Function : This function is a part of the function, clustering.

=cut

sub clustering_2{
	my ($a0, $a1, $h0, $h1) = @_;
	my (@a10, @a11) = ((), ());

	my $frg0 = 0;
	if($#$a1>-1){
		for(my $ii=0; $ii<=$#$a1; $ii++){
			my @a01 = split(/\t/, $a1->[$ii]);
			for(my $ij=0; $ij<=$#$a0; $ij++){
				my @a02 = split(/\t/, $a0->[$ij]);
				if($a02[1] <= $a01[2] && $a01[3] eq $a02[3]){
					$frg0 = 1;
					last;
				}elsif($a01[2] < $a02[1]){
					last;
				}
			}
		}
	}

	if($frg0 == 1){
		for(my $ii=0; $ii<=$#$a1; $ii++){
			if($h0->{$a1->[$ii]}){
				push(@a10, $h0->{$a1->[$ii]});
			}
			if($h1->{$a1->[$ii]}){
				push(@a11, $h1->{$a1->[$ii]});
			}
		}
	}

	for(my $ii=0; $ii<=$#$a0; $ii++){
		if($h0->{$a0->[$ii]}){
			push(@a10, $h0->{$a0->[$ii]});
		}
		if($h1->{$a0->[$ii]}){
			push(@a11, $h1->{$a0->[$ii]});
		}
	}

	my @aout = ();
	foreach my $s0 (@a10){
		my @a20 = split(/\t/, $s0);
		foreach my $s1 (@a11){
			my @a21 = split(/\t/, $s1);
			if($a20[0] eq $a21[0] && $a20[1] == $a21[1] && $a20[2] == $a21[2]){
			}else{
				if($a20[2] < $a21[1]){
					last;
				}else{
					if($a21[2] < $a20[1]){
					}else{
						if($a20[3] eq $a21[3]){
							push(@aout, sprintf join("\t", $a20[0],$a20[3],$a20[1],$a20[2],$a20[0],$a21[0],$a21[3],$a21[1],$a21[2],$a21[0]));
						}
					}
				}
			}
		}
	}
	return @aout;
}

##########################
## Function: add_clusterid
##########################

=head2 add_clusterid

 Function : This function adds cluster-IDs to each transcript.
 Usage	: &add_clusterid(cluster list, singlet list, GFF file)

=cut

sub add_clusterid{
	my ($clst, $sngl, $gff) = @_;

	if(! -f $clst || ! -f $sngl || ! -f $gff){
		print STDERR "ERROR: Can't find the file(s).\n";
		die "ERROR:$!";
	}else{
		open(F1, $sngl);
		my @asngl = ();
		while(<F1>){
			chomp;
			push(@asngl, $_);
		}
		close F1;

		my @aclst = split(/\n/, `cut -f1,6 $clst | sort | uniq`);
		my (%hCLST, %hACC, @aACC) = ((), (), ());
		foreach my $s00 (@aclst){
			my @a10 = split(/\t/, $s00);
			my @a11 = ();
			if(!$hCLST{$a10[0]} && !$hCLST{$a10[1]}){
				$hCLST{$a10[0]} = sprintf join("\|", $a10[0], $a10[1]);
				$hCLST{$a10[1]} = sprintf join("\|", $a10[0], $a10[1]);
			}else{
				if($hCLST{$a10[0]} && !$hCLST{$a10[1]}){
					@a11 = (split(/\|/, $hCLST{$a10[0]}), $a10[1]);
				}elsif(!$hCLST{$a10[0]} && $hCLST{$a10[1]}){
					@a11 = (split(/\|/, $hCLST{$a10[1]}), $a10[0]);
				}else{
					if($hCLST{$a10[0]} ne $hCLST{$a10[1]}){
						@a11 = (split(/\|/, $hCLST{$a10[0]}), split(/\|/, $hCLST{$a10[1]}));
					}

				}
				foreach my $s01 (@a11){
					$hCLST{$s01} = sprintf join("\|", @a11);
				}
			}
			if(!$hACC{$a10[0]}){
				push(@aACC, $a10[0]);
			}elsif(!$hACC{$a10[1]}){
				push(@aACC, $a10[1]);
			}
		}
		close F0;

		my (%ha0, @a0) = ((), ());
		foreach my $s0 (@aACC){
			if(!$ha0{$hCLST{$s0}}){
				push(@a0, $hCLST{$s0});
				$ha0{$hCLST{$s0}} = $hCLST{$s0};
			}
		}

		open(GFF, $gff);
		my @agfftmp = <GFF>;
		chomp(@agfftmp);
		close GFF;
		my $sprefix = "";
		foreach my $s00 (@agfftmp){
			if($s00 !~ /^\#/){
				my @a30 = split(/\t/, $s00);
				$sprefix = $a30[0];
				last;
			}
		}

		push(@a0, @asngl);
		my %hCL = ();
		my $sCL = "";
			for(my $ij=0; $ij<=$#a0; $ij++){
				if($ij+1 <10){
					$sCL = $sprefix . "_cl00000" . ($ij+1);
				}elsif($ij+1 < 100){
					$sCL = $sprefix . "_cl0000" . ($ij+1);
				}elsif($ij+1 < 1000){
					$sCL = $sprefix . "_cl000" . ($ij+1);
				}elsif($ij+1 < 10000){
					$sCL = $sprefix . "_cl00" . ($ij+1);
				}else{
					$sCL = $sprefix . "_cl0" . ($ij+1);
				}
			my @a20 = split(/\|/, $a0[$ij]);
			foreach my $s10 (@a20){
			$hCL{$s10} = $sCL;
			}
		}

		open(OUT, ">$gff");
		foreach my $s00 (@agfftmp){
			if($s00 !~ /^\#/){
				my @a30 = split(/\t/, $s00);
				my @a31 = split(/\;/, $a30[8]);
				if($a31[0] =~ /^ID\=(\S+)/){
					if($hCL{$1}){
						$a30[8] .= ";cluster_id=" . $hCL{$1};
					}
				}elsif($a31[0] =~ /^Parent\=(\S+)/){
					if($hCL{$1}){
						$a30[8] .= ";cluster_id=" . $hCL{$1};
					}
				}
				print OUT join("\t", @a30),"\n";
			}else{
				print OUT $s00 , "\n";
			}
		}
		close OUT;
	}
}

########################
## Function: make_orfgff
########################

=head2 make_orfgff

 Function : This function generates GFF file including ORF information
 Usage	: &make_orfgff($directory, $file, $file)

=cut

sub make_orfgff{
	my ($swd, $gff, $orf_dat, $source) = @_;

	if(-f $gff && -f $orf_dat){
		my %hORFDAT = ();
		open(ORFDAT, $orf_dat);
		my @aORFDAT = <ORFDAT>;
		chomp(@aORFDAT);
		close ORFDAT;
		foreach my $s0 (@aORFDAT){
			my @a0 = split(/\t/, $s0);
			$hORFDAT{$a0[0]} = [@a0];
		}

		my $sout = basename($gff);
		$sout =~ s/\.(\S+)$//g;
		$sout = $swd ."/" . $sout ."_orf.gff";
		open(OUT, ">$sout");

		my $frg_cds = 0;
		my ($nsp_orf, $nep_orf) = (0, 0);
		my $nsum_exon = 0;
		open(GFF, $gff);
		my @aGFF = <GFF>;
		chomp(@aGFF);
		close GFF;
		foreach my $s0 (@aGFF){
			if($s0 !~ /\#/){
				my @a0 = split(/\t/, $s0);
				my @a1 = split(/\;/, $a0[8]);
				if($a0[2] eq "sequence"){
					print OUT "$s0\n";
				}elsif($a0[2] eq "mRNA"){
					my $sid = "";
					$frg_cds = 0;
					if($a1[0] =~ /^ID=(\S+)/){
						$sid = $1;
					}else{
						print STDERR "ERROR: Can't get sequence ID.\n";
						die "ERROR:$!\n";
					}
					($nsp_orf, $nep_orf) = ($hORFDAT{$sid}[1], $hORFDAT{$sid}[2]);
					if($nsp_orf && $nsp_orf >0){
						$frg_cds = 1;
					}
					$nsum_exon = 0;

					if($frg_cds == 1){
						print OUT join("\t", @a0),"\n";
					}

				}elsif($a0[2] eq "exon"){
					if($frg_cds == 1){
						my ($nsp_5utr,$nep_5utr,$nsp_3utr,$nep_3utr) = (0,0,0,0);
						my ($frg_5utr, $frg_3utr) = (0, 0);
						if($a0[6] eq "+"){
							if($nsum_exon+($a0[4]-$a0[3]+1) < $nsp_orf){
								$a0[2] = "five_prime_UTR";
								print OUT join("\t", @a0),"\n";
							}elsif($nsum_exon+1 > $nep_orf){
								$a0[2] = "three_prime_UTR";
								print OUT join("\t", @a0),"\n";
							}else{
								if($nsum_exon+1 < $nsp_orf && $nsp_orf <= $nsum_exon+($a0[4]-$a0[3]+1)){
									$frg_5utr= 1;
								}
								if($nsum_exon+1 <= $nep_orf && $nep_orf < $nsum_exon+($a0[4]-$a0[3]+1)){
									$frg_3utr = 1;
								}
								if($frg_5utr == 1 && $frg_3utr == 1){
									($nsp_5utr, $nep_5utr) = ($a0[3], $a0[3]+($nsp_orf-($nsum_exon+1))-1);
									($nsp_3utr, $nep_3utr) = ($a0[3]+($nep_orf-($nsum_exon+1))+1,$a0[4]);
									print OUT join("\t",$a0[0],$source,"five_prime_UTR",$nsp_5utr,$nep_5utr,".",$a0[6],".",$a0[8]),"\n";
									print OUT join("\t",$a0[0],$source,"polypeptide",$nep_5utr+1,$nsp_3utr-1,".",$a0[6],".",$a0[8]),"\n";
									print OUT join("\t",$a0[0],$source,"three_prime_UTR",$nsp_3utr,$nep_3utr,".",$a0[6],".",$a0[8]),"\n";
								}else{
									if($frg_5utr == 1){
										($nsp_5utr, $nep_5utr) = ($a0[3], $a0[3]+($nsp_orf-($nsum_exon+1))-1);
										print OUT join("\t",$a0[0],$source,"five_prime_UTR",$nsp_5utr,$nep_5utr,".",$a0[6],".",$a0[8]),"\n";
										print OUT join("\t",$a0[0],$source,"polypeptide",$nep_5utr+1,$a0[4],".",$a0[6],".",$a0[8]),"\n";
									}elsif($frg_3utr == 1){
										($nsp_3utr, $nep_3utr) = ($a0[3]+($nep_orf-($nsum_exon+1))+1,$a0[4]);
										print OUT join("\t",$a0[0],$source,"polypeptide",$a0[3],$nsp_3utr-1,".",$a0[6],".",$a0[8]),"\n";
										print OUT join("\t",$a0[0],$source,"three_prime_UTR",$nsp_3utr,$nep_3utr,".",$a0[6],".",$a0[8]),"\n";
									}else{
										$a0[2] = "polypeptide";
										print OUT join("\t", @a0),"\n";
									}
								}
							}
						}else{
							if($nsum_exon+($a0[4]-$a0[3]+1) < $nsp_orf){
								$a0[2] = "five_prime_UTR";
								print OUT join("\t", @a0),"\n";
							}elsif($nsum_exon+1 > $nep_orf){
								$a0[2] = "three_prime_UTR";
								print OUT join("\t", @a0),"\n";
							}else{
								if($nsum_exon+1 < $nsp_orf && $nsp_orf <= $nsum_exon+($a0[4]-$a0[3]+1)){
									$frg_5utr = 1;
								}
								if($nsum_exon+1 <= $nep_orf && $nep_orf < $nsum_exon+($a0[4]-$a0[3]+1)){
									$frg_3utr = 1;
								}
								if($frg_5utr == 1 && $frg_3utr == 1){
									($nsp_5utr, $nep_5utr) = ($a0[4]-($nsp_orf-($nsum_exon+1))+1, $a0[4]);
									($nsp_3utr, $nep_3utr) = ($a0[3],$a0[4]-($nep_orf-($nsum_exon+1))-1);
									print OUT join("\t",$a0[0],$source,"five_prime_UTR",$nsp_5utr,$nep_5utr,".",$a0[6],".",$a0[8]),"\n";
									print OUT join("\t",$a0[0],$source,"polypeptide",$nep_3utr+1,$nsp_5utr-1,".",$a0[6],".",$a0[8]),"\n";
									print OUT join("\t",$a0[0],$source,"three_prime_UTR",$nsp_3utr,$nep_3utr,".",$a0[6],".",$a0[8]),"\n";
								}else{
									if($frg_5utr == 1){
										($nsp_5utr, $nep_5utr) = ($a0[4]-($nsp_orf-($nsum_exon+1))+1, $a0[4]);
										print OUT join("\t",$a0[0],$source,"five_prime_UTR",$nsp_5utr,$nep_5utr,".",$a0[6],".",$a0[8]),"\n";
										print OUT join("\t",$a0[0],$source,"polypeptide",$a0[3],$nsp_5utr-1,".",$a0[6],".",$a0[8]),"\n";
									}elsif($frg_3utr == 1){
										($nsp_3utr, $nep_3utr) = ($a0[3],$a0[4]-($nep_orf-($nsum_exon+1))-1);
										print OUT join("\t",$a0[0],$source,"polypeptide",$nep_3utr+1,$a0[4],".",$a0[6],".",$a0[8]),"\n";
										print OUT join("\t",$a0[0],$source,"three_prime_UTR",$nsp_3utr,$nep_3utr,".",$a0[6],".",$a0[8]),"\n";
									}else{
										$a0[2] = "polypeptide";
										print OUT join("\t", @a0),"\n";
									}
								}
							}
						}
						$nsum_exon += ($a0[4]-$a0[3]+1);
					}else{
						#print OUT join("\t", @a0),"\n";
					}
				}
			}else{
				print OUT "$s0\n";
			}
		}
		close GFF;
	}else{
		print STDERR "ERROR: Can't find the file.\n";
		die "ERROR:$!\n";
	}
}

############################
## Function: translate_fasta
############################

=head2 translate_fasta

 Function : This function generates GFF file including ORF information
 Usage	: &translate_fasta($directory, $file, $file)

=cut

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
				}
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

####################
## Function: makeRep
####################

=head2 makeRep

 Function : This function determines representative sequences within a GFF file.
 Usage	: &makeRep($file, $file)

=cut

sub makeRep{
	my ($sGFF, $sInf, $sOrfInf, $sExtOrfInf, $sFNA, $sORFFNA, $sORFFAA, $priority, $category) = @_;

	my $sout_tmp = dirname($sGFF);
	if($sout_tmp){
		$sout_tmp .= "/" . $category;
	}else{
		$sout_tmp = "./" . $category;
	}
	my $sGFF_out = $sout_tmp . "_rep.gff";

	if(! -f $sGFF || ! -f $sInf || ! -f $sOrfInf || ! -f $sExtOrfInf){
		print STDERR "ERROR:Can't find the file.\n";
		die "ERROR:$!";
	}else{
		open(INF, $sInf);
		my @a00 = <INF>;
		chomp(@a00);
		close INF;
		my %hINF = ();
		foreach my $s00 (@a00){
			my @a01 = split(/\t/, $s00);
			$hINF{$a01[0]} = $s00;
		}
		open(ORF, $sOrfInf);
		my @a01 = <ORF>;
		chomp(@a01);
		close ORF;
		my %hORF = ();
		foreach my $s00 (@a01){
			my @a02 = split(/\t/, $s00);
			$hORF{$a02[0]} = $s00;
		}
		open(EXTORF, $sExtOrfInf);
		my @a011 = <EXTORF>;
		chomp(@a011);
		close EXTORF;
		my %hEXTORF = ();
		foreach my $s00 (@a011){
			my @a012 = split(/\t/, $s00);
			$hEXTORF{$a012[0]} = $s00;
		}
		open(GFF, $sGFF);
		my @a10 = <GFF>;
		chomp(@a10);
		my (@aCID, %hCID) = ((), ());
		foreach my $s00 (@a10){

			if($s00 !~ /^\#\#/){
				my @a11 = split(/\t/, $s00);
				if($a11[2] =~ /mRNA/){
					my @a12 = split(/\;/, $a11[8]);
					my ($sID, $sCID) = ("", "");
					foreach my $s00 (@a12){
						if($s00 =~ /^ID\=(\S+)/){
							$sID = $1;
						}elsif($s00 =~ /^cluster_id\=(\S+)/){
							$sCID = $1;
						}
					}
					push(@{$hCID{$sCID}}, $sID);
					push(@aCID, $sCID);
				}
			}
		}
		my %hREP = ();
		foreach my $s00 (@aCID){
			my @a20 = ();
			foreach my $s01 (@{$hCID{$s00}}){
				my @a01 = split(/\t/, $hEXTORF{$s01});
				if($a01[2] eq "complete"){
					my $s02 = $hINF{$s01}. "\t". $hORF{$s01}. "\t". $hEXTORF{$s01};
					push(@a20, $s02);
				}
			}

			if($#a20 > -1){
				my @aORDER = split(/,/, $priority);
				my %hORDER = ();
				foreach my $s00 (@a20){
					my @a00 = split(/\t/, $s00);

					switch ($category) {
						case /CAT00/i	{ push(@{$hORDER{'CAT'}}, '4'); }
						case /CAT01/i	{ push(@{$hORDER{'CAT'}}, '3'); }
						case /CAT02/i	{ push(@{$hORDER{'CAT'}}, '2'); }
						case /CAT03/i	{ push(@{$hORDER{'CAT'}}, '1'); }
						else			{ push(@{$hORDER{'CAT'}}, '0'); }
					}

					push(@{$hORDER{'EXON'}}, $a00[1]);
					push(@{$hORDER{'RANGE'}}, $a00[4]);
					push(@{$hORDER{'ID_NA'}}, $a00[5]);
					push(@{$hORDER{'CV_NA'}}, $a00[6]);
					push(@{$hORDER{'ID_AA'}}, $a00[13]);
					push(@{$hORDER{'ORF_LEN'}}, $a00[15]);
				}
				@a20 = @a20[sort {$hORDER{$aORDER[0]}[$b] <=> $hORDER{$aORDER[0]}[$a] or
									  $hORDER{$aORDER[1]}[$b] <=> $hORDER{$aORDER[1]}[$a] or
									  $hORDER{$aORDER[2]}[$b] <=> $hORDER{$aORDER[2]}[$a] or
									  $hORDER{$aORDER[3]}[$b] <=> $hORDER{$aORDER[3]}[$a] or
									  $hORDER{$aORDER[4]}[$b] <=> $hORDER{$aORDER[4]}[$a] or
									  $hORDER{$aORDER[5]}[$b] <=> $hORDER{$aORDER[5]}[$a] or
									  $hORDER{$aORDER[6]}[$b] <=> $hORDER{$aORDER[6]}[$a]}0..$#a20];
				my @a21 = split(/\t/, $a20[0]);
				$hREP{$a21[0]} = $a21[0];
			}
		}

		open(OUT, ">$sGFF_out");
		foreach my $s00 (@a10){
			if($s00 =~ /^\#\#/){
				print OUT $s00 , "\n";
			}else{
				my @a00 = split(/\t/, $s00);
				if($a00[2] eq "sequence"){
					print OUT $s00 , "\n";
				}else{
					my @a01 = split(/\;/, $a00[8]);
					my @a02 = ();
					foreach my $s10 (@a01){
						if($s10 =~ /^cluster_id\=/){
						}else{
							push(@a02, $s10);
						}
					}
					$a00[8] = sprintf join("\;", @a02);
					if($a00[2] =~ /mRNA/){
						foreach my $s01 (@a02){
							if($s01 =~ /^ID\=(\S+)/){
								if($hREP{$1}){
									print OUT join("\t", @a00) , "\n";
								}
							}
						}
					}else{
						foreach my $s01 (@a02){
							if($s01 =~ /^Parent\=(\S+)/){
								if($hREP{$1}){
									print OUT join("\t", @a00) , "\n";
								}
							}
						}
					}
				}
			}
		}
		close (OUT);

		if(-f $sFNA){
			my $srep_all = $sout_tmp . "_rep.fna";
			my $sall_out = new Bio::SeqIO ('-format' => 'fasta', '-file' => ">$srep_all");
			my $sall = new Bio::SeqIO ('-format' => 'fasta', '-file' => $sFNA);
			my $s0 = "";
			while($s0 = $sall->next_seq()){
				my $s1 = $s0->display_id; #desc
				if($hREP{$s1}){
					$sall_out->write_seq($s0);
				}
			}
		}
		if(-f $sORFFNA){
			my $srep_fna = $sout_tmp . "_rep_orf.fna";
			my $sfna_out = new Bio::SeqIO ('-format' => 'fasta', '-file' => ">$srep_fna");
			my $sfna = new Bio::SeqIO ('-format' => 'fasta', '-file' => $sORFFNA);
			my $s0 = "";
			while($s0 = $sfna->next_seq()){
				my $s1 = $s0->display_id; #desc
				if($hREP{$s1}){
					$sfna_out->write_seq($s0);
				}
			}
		}
		if(-f $sORFFAA){
			my $srep_faa = $sout_tmp . "_rep_orf.faa";
			my $sfaa_out = new Bio::SeqIO ('-format' => 'fasta', '-file' => ">$srep_faa");
			my $sfaa = new Bio::SeqIO ('-format' => 'fasta', '-file' => $sORFFAA);
			my $s0 = "";
			while($s0 = $sfaa->next_seq()){
				my $s1 = $s0->display_id;
				if($hREP{$s1}){
					$sfaa_out->write_seq($s0);
				}
			}
		}
	}

	if (-z $sGFF_out) {
		return 1; # Empty GFF file = Error
	} else {
		return 0;
	}
}


=head1 AUTHOR

Hiroaki Sakai, C<< <hirsakai at affrc.go.jp> >>

=head1 BUGS

Please report any bugs or feature requests to C<hirsakai@affrc.go.jp>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

	perldoc mapping::MAP

=head1 COPYRIGHT & LICENSE

Copyright 2007 Hiroaki Sakai, all rights reserved.


=cut

1; # End of mapping::MAP
