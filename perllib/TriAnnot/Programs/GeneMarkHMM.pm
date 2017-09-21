#!/usr/bin/env perl

package TriAnnot::Programs::GeneMarkHMM;

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
=head1 TriAnnot::Programs::GeneMarkHMM - Methods
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
	my $cmd;

	if ($TRIANNOT_CONF{PATHS}->{matrices}->{$self->{programName}}->{$self->{'matrix'}}->{'path'} =~ /mod$/) {
		$cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'} . '3'}->{'bin'};
	} elsif ($TRIANNOT_CONF{PATHS}->{matrices}->{$self->{programName}}->{$self->{'matrix'}}->{'path'} =~ /mtx$/) {
		$cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'} . '2'}->{'bin'};
	}

	$cmd .= ' -m ' . $TRIANNOT_CONF{PATHS}->{matrices}->{$self->{programName}}->{$self->{'matrix'}}->{'path'} . ' -o ' . $self->{'outFile'} . ' ' . $self->{'sequence'};

	# Log the newly build command line
	$logger->debug('GeneMarkHMM (' . $self->{'matrix'} . ' matrix) will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	my $cmdOutput = `$cmd 2>&1`;
	$logger->debug(">>>>>>>> Start of execution output <<<<<<<<");
	$logger->debug($cmdOutput);
	$logger->debug(">>>>>>>>  End of execution output  <<<<<<<<");
	if ($cmdOutput =~ /Failure in Termin...on stage of viterbi algorithm/) {
		# Creation of an empty output file
		$logger->logwarn("Execution failed, but the viterbi algorithm failure message generally appears when there is no result, so we create an empty result file");
		open(EMPTY_OUT, '>' . $self->{'outFile'}) or $logger->logdie('Error: Cannot create the empty output file: ' . $self->{'outFile'});
		close(EMPTY_OUT);
	}
}

1;
