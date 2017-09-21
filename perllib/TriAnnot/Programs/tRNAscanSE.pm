#!/usr/bin/env perl

package TriAnnot::Programs::tRNAscanSE;

##################################################
## Documentation POD
##################################################

##################################################
## Modules
##################################################
## Perl modules
use strict;
use warnings;
use diagnostics;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Programs::Programs;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Programs::Programs);

##################################################
## Methods
##################################################
=head1 TriAnnot::Programs::tRNAscanSE - Methods
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
## Method execute() #
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Building of the command line
	# my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'} .
		# ' -b -Q' .
		# ' -X ' . $self->{'report_cutoff'} .
		# ' -L ' . $self->{'tRNA_maxlength'} .
		# ' -z ' . $self->{'nucleotide_padding'} .
		# ' -t ' . $self->{'tRNAscan_mode'} .
		# ' -e ' . $self->{'EufindtRNA_mode'} .
		# ' -o ' . $self->{'outFile'} .
		# ' ' . $self->{'sequence'};
### modify by Ph. Leroy on October 8th, 2015 because error message
### Can't locate object method "find_long_tRNAs" via package "tRNAscanSE::Options" at /home/banks3b/triannot_Tools/tRNAscan/tRNAscan_1.3.1_install/bin/tRNAscan-SE line 969.
		
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'} .
		' -b -Q' .
		' -X ' . $self->{'report_cutoff'} .
		' -z ' . $self->{'nucleotide_padding'} .
		' -t ' . $self->{'tRNAscan_mode'} .
		' -e ' . $self->{'EufindtRNA_mode'} .
		' -o ' . $self->{'outFile'} .
		' ' . $self->{'sequence'};		
		
	# Log the newly build command line
	$logger->debug('tRNAscan-SE will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	my $cmdOutput = `$cmd 2>&1`;
	$logger->debug(">>>>>>>> Start of execution output <<<<<<<<");
	$logger->debug($cmdOutput);
	$logger->debug(">>>>>>>>  End of execution output  <<<<<<<<");
}

1;
