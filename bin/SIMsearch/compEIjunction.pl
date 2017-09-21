#!/usr/bin/env perl

# Perl modules
use strict;
use warnings;
use diagnostics;

use File::Basename;
use Getopt::Long;

my ($opt_gff1, $opt_gff2, $opt_inf, $opt_help) = ("", "", "", 0);
&GetOptions('gff1=s' => \$opt_gff1, 'gff2=s' => \$opt_gff2, 'inf=s' => \$opt_inf, 'help|h' => \$opt_help);

my $help = <<'&EOT&';
Usage: -gff1 [GFF file] -gff2 [GFF file] -inf [orf.inf]
&EOT&

if( $opt_help || !$opt_gff1 || !$opt_gff2 || !$opt_inf ){
	print $help;
	exit 1;
}

my ($gff1, $gff2, $orf_inf) = ($opt_gff1, $opt_gff2, $opt_inf);

my %hJUNCTIONS = ();
my @aJUNCTIONS = ();

my %hORF_INF = ();

open(INF, $orf_inf);
while(<INF>){
	chomp;
	my @a0 = split(/\t/);
	@{$hORF_INF{$a0[0]}} = @a0;
}
close INF;

open(GFF2, $gff2);
my ($acc, $strand) = ("", "");
my $flg0 = 0;
my @a10 = ();
while(<GFF2>){
	chomp;
	my @a0 = split(/\t/);
	my $acc0 = "";
	if(!/^\#\#/ && $a0[8] =~ /Parent=([^;]+)/ && $a0[2] eq "polypeptide"){
		$acc0 = $1;
		my $flg1 = 0;
		if($acc0 ne $acc){
			$flg1 = 1;
		}
		if($flg0 == 1 && $flg1 == 1){
			my ($junctions, $allpos) = &proc1($acc, $strand, \@a10);
			$hJUNCTIONS{$junctions}->{"junction"} = $junctions;
			$hJUNCTIONS{$junctions}->{"allpos"} = $allpos;
			$hJUNCTIONS{$junctions}->{"acc"} = $acc;
			push(@aJUNCTIONS, $junctions);
			@a10 = ();
		}
		push(@a10, $_);
		($acc, $strand) = ($acc0, $a0[6]);
		$flg0 = 1;
	}
}
close GFF2;

if($#a10 > -1){
	my ($junctions, $allpos) = &proc1($acc, $strand, \@a10);
	$hJUNCTIONS{$junctions}->{"junction"} = $junctions;
	$hJUNCTIONS{$junctions}->{"allpos"} = $allpos;
	$hJUNCTIONS{$junctions}->{"acc"} = $acc;
	push(@aJUNCTIONS, $junctions);
}

open(GFF1, $gff1);
($acc, $strand) = ("", "");
$flg0 = 0;
@a10 = ();
while(<GFF1>){
	chomp;
	my @a0 = split(/\t/);
	my $acc0 = "";
	if(!/^\#\#/ && $a0[8] =~ /Parent=([^;]+)/){
		$acc0 = $1;
		my $flg1 = 0;
		if($acc0 ne $acc){
			$flg1 = 1;
		}
		if($flg0 == 1 && $flg1 == 1){
			my ($junctions, $allpos) = &proc1($acc, $strand, \@a10);
			my $eij_acc = "";
			my $eij_pos = "";
			foreach my $eij (@aJUNCTIONS){
				if($junctions =~ /$eij/){
					$eij_acc = $hJUNCTIONS{$eij}->{"acc"};
					$eij_pos = $hJUNCTIONS{$eij}->{"allpos"};
					last;
				}
			}

			if($eij_acc){
				print join("\t", @{$hORF_INF{$acc}}, $eij_acc, $eij_pos), "\n";
			}else{
				print join("\t", @{$hORF_INF{$acc}}, "-", "-"), "\n";
			}
			@a10 = ();
		}
		push(@a10, $_);
		($acc, $strand) = ($acc0, $a0[6]);
		$flg0 = 1;
	}
}
close GFF1;

if($#a10 > -1){
	my ($junctions, $allpos) = &proc1($acc, $strand, \@a10);
	my $eij_acc = "";
	my $eij_pos = "";
	foreach my $eij (@aJUNCTIONS){
		if($junctions =~ /$eij/){
			$eij_acc = $hJUNCTIONS{$eij}->{"acc"};
			$eij_pos = $hJUNCTIONS{$eij}->{"allpos"};
			last;
		}
	}
	if($eij_acc){
		print join("\t", @{$hORF_INF{$acc}}, $eij_acc, $eij_pos), "\n";
	}else{
		print join("\t", @{$hORF_INF{$acc}}, "-", "-"), "\n";
	}
}

sub proc1{
	my ($acc, $strand, $a10) = @_;

	my @aJunctions = ();
	my @aAllPos = ();
	for(my $ii=0; $ii<=$#$a10-1; $ii++){
		my @a20 = split(/\t/, $a10->[$ii]);
		my @a21 = split(/\t/, $a10->[$ii+1]);

		push(@aAllPos, $a20[3], $a20[4]);
		push(@aAllPos, $a21[3], $a21[4]) if($ii==$#$a10-1);

		if($a20[4]+1 < $a21[3]){
			push(@aJunctions, $a20[4], $a21[3]);
		}elsif($a20[3]-1 > $a21[4]){
			push(@aJunctions, $a20[3], $a21[4]);
		}
	}

	@aJunctions = sort {$a <=> $b} @aJunctions;
	@aAllPos = sort {$a <=> $b} @aAllPos;
	my $junctions = sprintf join("_", @aJunctions);
	my $allpos = sprintf join("_", @aAllPos);
	return ($junctions, $allpos);
}
