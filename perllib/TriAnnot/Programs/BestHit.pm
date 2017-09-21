#!/usr/bin/env perl

package TriAnnot::Programs::BestHit;

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
use TriAnnot::Programs::Programs;
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Programs::Programs);

##################################################
## Methods
##################################################
=head1 TriAnnot::Programs::BestHit - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class (TriAnnot::Programs::Programs)
	my $self = $class->SUPER::new(\%attrs);

	$self->{'allowMultiFasta'} = 'yes';

	bless $self => $class;

	return $self;
}


#####################
## Method execute() #
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Log and Warning
	$logger->info('The selected database is: ' . $self->{'database'});

	# Check if the protein sequence file contains at least one sequence
	if (-z $self->{'fullSequencePath'}) {
		$logger->logwarn('WARNING: Trying to run BestHit (' . $self->{'type'} . ' on ' . $self->{'database'} . ') on an empty protein sequence file (' . $self->{'sequence'} . '). Execution is skipped.');

		# Creation of an empty output file
		$logger->debug('');
		$logger->debug('Note: Creation of an empty BestHit brut output file (' . $self->{'outFile'} . ')');
		open(EMPTY_OUT, '>' . $self->{'outFile'}) or $logger->logdie('Error: Cannot create the empty output file: ' . $self->{'outFile'});
		close(EMPTY_OUT);

		# Mark the execution procedure as SKIP
		$self->{'Execution_skipped'} = 'yes';
		$self->{'Skip_reason'} = 'Empty protein sequence file';

		return;
	}

	# Building of the command line
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'} .
		' -p ' . $self->{'type'} .
		' -d ' . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'database'}}->{'path'} .
		' -i ' . $self->{'fullSequencePath'} .
		' -e ' . $self->{'evalue'} .
		' -o ' . $self->{'outFile'} .
		' -m 7' . # XML output format
		' -b ' . $self->{'nbAlignHit'} .
		' -v ' . $self->{'nbOneLineHit'} .
		' -g ' . $self->{'performAlign'} .
		' -F ' . $self->{'filterSeq'} .
		' -a ' . $self->{'nbCore'};

	# Log the newly build command line
	$logger->debug('BestHit (' . $self->{'type'} . ' on ' . $self->{'database'} . ') will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	my $cmdOutput = `$cmd 2>&1`;
	$logger->debug(">>>>>>>> Start of execution output <<<<<<<<");
	$logger->debug($cmdOutput);
	$logger->debug(">>>>>>>>  End of execution output  <<<<<<<<");
}

1;
