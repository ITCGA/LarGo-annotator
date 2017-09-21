#!/usr/bin/env perl

package TriAnnot::Programs::Augustus;

######################
###     POD Documentation
######################

##################################################
# Modules
##################################################

# Perl modules
use strict;
use warnings;
use diagnostics;

# TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Programs::Programs;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Programs::Programs);

##################################################
## Methods
##################################################

=head1 TriAnnot::Programs::Augustus - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class (TriAnnot::Programs::Programs)
	my $self = $class->SUPER::new(\%attrs);

	bless $self => $class;

	return $self;
}


#####################
## Method _execute() #
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Prepare Environment
	$ENV{'AUGUSTUS_CONFIG_PATH'} = $TRIANNOT_CONF{PATHS}->{config}->{$self->{'programName'}}->{'path'};
	$self->{'finalHintsFile'} = $self->{directory} . '/' . $self->{'tmpFolder'} . '/' . 'hints' ;
	# Building of the command line
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'} .
		' --species=' . $self->{'matrix'} .
		' --strand=' . $self->{'strand'} .
		' --genemodel=' . $self->{'genemodel_type'} .
		' --singlestrand=' . $self->{'singlestrand'} .
		' --UTR=' . $self->{'predict_utr'};

	if ($self->{'use_hints'} eq 'on') {
		if(defined($self->{'RNAseqHintsFile'})){
			$self->{'RNAseqHintsFile'} = $self->{directory} . '/' . $TRIANNOT_CONF{DIRNAME}->{GFF_files} . '/' . $self->{'RNAseqHintsFile'} ;
			if(! -z $self->{'RNAseqHintsFile'} && -e $self->{'RNAseqHintsFile'}){
				$self->_prepareHintsFile($self->{'RNAseqHintsFile'},'RNAseq');
			}
			else{
				$logger->warn('Void hint file, skipping... ' . $self->{'RNAseqHintsFile'});
			}
		}
		if(defined($self->{'proteinHintsFile'})){
			$self->{'proteinHintsFile'} = $self->{directory} . '/' . $TRIANNOT_CONF{DIRNAME}->{GFF_files} . '/' . $self->{'proteinHintsFile'} ;
			if(! -z $self->{'proteinHintsFile'} && -e $self->{'proteinHintsFile'}){
				$self->_prepareHintsFile($self->{'proteinHintsFile'},'protein');
			}
			else{
				$logger->warn('Void hint file, skipping... ' . $self->{'proteinHintsFile'});
			}
		}
		if( -e $self->{'finalHintsFile'}){
			$self->_prepareExtrinsicConfigFile();
			$cmd .= " --hintsfile=" . $self->{'finalHintsFile'} . " --extrinsicCfgFile=" .  $self->{'extrinsicConfigFile'};
		}
		else{
			$logger->warn('Final hint file is void. Skipping...');
		}
	}

	$cmd .=	' --outfile=' . $self->{'outFile'} .
		' --protein=' . $self->{'output_protein'} .
		' --introns=' . $self->{'output_introns'} .
		' --start=' . $self->{'output_start'} .
		' --stop=' . $self->{'output_stop'} .
		' --cds=' . $self->{'output_cds'} .
		' --codingseq=' . $self->{'output_codingseq'} .
		' --gff3=on ' . $self->{'sequence'};

	# Log the newly build command line
	$logger->debug('Augutus (' . $self->{matrix} . ') will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	my $cmdOutput = `$cmd 2>&1`;
	$logger->debug(">>>>>>>> Start of execution output <<<<<<<<");
	$logger->debug($cmdOutput);
	$logger->debug(">>>>>>>>  End of execution output  <<<<<<<<");
}

sub _prepareHintsFile {

	# Recovers parameters
	my ($self,$hintFile,$type) = @_;
	my $hintFh;
	open($hintFh, ">>$self->{'finalHintsFile'}" );
	$self->_retrieveExonerateFeatures($hintFile);
	$self->_countHints();

	$self->_createEpHintFile($hintFh,$type);
	$self->_createIntronHintFile($hintFh,$type);

	close $hintFh;

	return 1;
}

sub _retrieveExonerateFeatures{
	my ($self,$file) = @_;
	open(GFF,$file) || $logger->logdie('Cannot read hint file: ' . $file . '.');
	my $parentID = '';
	while(<GFF>){
		chomp;
		if(/^##/){next;}
		my @line = split("\t",$_);
		my @field9 = split(";",$line[8]);
		if($line[2] eq 'match'){
			$field9[0] =~ s/ID=//;
			$parentID = $field9[0];
		}
		elsif($line[2] eq 'match_part'){
			$field9[2] =~ s/Target=//;
			$field9[2] =~ /(\S+)/;
			my $hint = {	start	=>	$line[3],
							end		=>	$line[4],
							strand	=>	$line[6],
							seq_id	=>	$line[0],
							target  =>  $1,
						};
			push(@{$self->{hints}->{$parentID}},$hint) ;
		}
	}
}


sub _countHints {
	my ($self) = @_;
	foreach my $k1 (keys(%{$self->{hints}})){
		for(my $i = 0 ; $i<=$#{$self->{hints}->{$k1}} ; $i++){
			my $tmpKey =  $self->{hints}->{$k1}->[$i]->{start} . '_' . $self->{hints}->{$k1}->[$i]->{end} . '_' . $self->{hints}->{$k1}->[$i]->{strand};
			if(! defined($self->{mult}->{$tmpKey})){
				$self->{mult}->{$tmpKey} = [] ;
			}
			my $t = { id => $k1, index => $i } ;
			push(@{$self->{mult}->{$tmpKey}},$t);
		}
	}
}



sub _createEpHintFile {
	my ($self,$fh,$type) = @_;
	my $t = "\t" ;
	foreach my $key (keys(%{$self->{mult}})){
		my $mult = scalar(@{$self->{mult}->{$key}}) ;
		my $gffLine = '' ;
		$gffLine  =  $self->{hints}->{ $self->{mult}->{$key}->[0]->{id} }->[ $self->{mult}->{$key}->[0]->{index} ]->{ seq_id } . $t;
		$gffLine .=  'hint' . $t;
		if($type eq 'protein'){
			$gffLine .=  'CDSpart' . $t;
		}
		elsif($type eq 'RNAseq'){
			$gffLine .=  'ep' . $t;
		}

		$gffLine .=  $self->{hints}->{ $self->{mult}->{$key}->[0]->{id} }->[ $self->{mult}->{$key}->[0]->{index} ]->{ start } . $t;
		$gffLine .=  $self->{hints}->{ $self->{mult}->{$key}->[0]->{id} }->[ $self->{mult}->{$key}->[0]->{index} ]->{ end } . $t;
		$gffLine .=  $mult . $t;
		$gffLine .=  $self->{hints}->{ $self->{mult}->{$key}->[0]->{id} }->[ $self->{mult}->{$key}->[0]->{index} ]->{ strand } . $t;
		$gffLine .=  '.' . $t;
		if($type eq 'protein'){
			$gffLine .=  'src=P;';
		}
		elsif($type eq 'RNAseq'){
			$gffLine .=  'src=W;';
		}
		$gffLine .=  'mult=' . $mult . ';' ;

		push(@{$self->{_tmp}->{ $self->{hints}->{ $self->{mult}->{$key}->[0]->{id} }->[ $self->{mult}->{$key}->[0]->{index} ]->{ start } }}, $gffLine) ;
	}
	foreach my $s ( sort { $a <=> $b }(keys( %{$self->{_tmp}} ) ) ){
		foreach my $l ( @{$self->{_tmp}->{$s}} ){
			print $fh $l . "\n" ;
		}
	}
	delete($self->{_tmp});
}


sub _createIntronHintFile {
	my ($self,$fh,$type) = @_;
	my $t = "\t";
	foreach my $k1 (keys(%{$self->{hints}})){
		my $lastStop;
		my $gffLine='';
		for(my $i = 0 ; $i<=$#{$self->{hints}->{$k1}} ; $i++){
			if($self->{hints}->{$k1}->[$i]->{strand} eq '-'){
				if($i != 0){
					my $intronStart = $lastStop;
					my $intronStop = $self->{hints}->{$k1}->[$i]->{start};
					$gffLine = $self->{hints}->{$k1}->[$i]->{seq_id} . $t
						. 'hint' . $t
						. 'intron' . $t
						. $intronStop . $t
						. $intronStart . $t
						. '0' . $t
						. $self->{hints}->{$k1}->[$i]->{strand} . $t
						. '.' . $t
						. 'grp=' . $self->{hints}->{$k1}->[$i]->{target} . ';pri=4;';
					if($type eq 'protein'){
						$gffLine .= 'src=P;';
					}
					elsif($type eq 'RNAseq'){
						$gffLine .= 'src=W;';
					}
					push(@{$self->{_tmp}->{$intronStart}},$gffLine);
				}
				$lastStop = $self->{hints}->{$k1}->[$i]->{end} ;
			}
			else{
				if($i != 0){
					my $intronStart = $lastStop;
					my $intronStop = $self->{hints}->{$k1}->[$i]->{start};
					$gffLine = $self->{hints}->{$k1}->[$i]->{seq_id} . $t
						. 'hint' . $t
						. 'intron' . $t
						. $intronStart . $t
						. $intronStop . $t
						. '0' . $t
						. $self->{hints}->{$k1}->[$i]->{strand} . $t
						. '.' . $t
						. 'grp=' . $self->{hints}->{$k1}->[$i]->{target} . ';pri=4;' ;
					if($type eq 'protein'){
						$gffLine .= 'src=P;';
					}
					elsif($type eq 'RNAseq'){
						$gffLine .= 'src=W;';
					}
					push(@{$self->{_tmp}->{$intronStart}},$gffLine);
				}
				$lastStop = $self->{hints}->{$k1}->[$i]->{end} ;
			}
		}
	}
	foreach my $s ( sort { $a <=> $b }(keys( %{$self->{_tmp}} ) ) ){
		foreach my $l ( @{$self->{_tmp}->{$s}} ){
			print $fh $l . "\n" ;
		}
	}
	delete($self->{_tmp});
}

sub _prepareExtrinsicConfigFile {

	# Recovers parameters
	my $self = shift;

	if(-e $self->{'extrinsicConfigFile'} && ! -z $self->{'extrinsicConfigFile'}){
		$logger->debug('DEBUG: Using ' . $self->{'extrinsicConfigFile'} . ' extrinsic config file for Augustus.');
	}
	else{
		$logger->logdie('Extrinsic file does not exist or it is void.');
	}

	return 1;
}

1;
