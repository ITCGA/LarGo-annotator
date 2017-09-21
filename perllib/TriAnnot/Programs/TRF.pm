#!/usr/bin/env perl

package TriAnnot::Programs::TRF;

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
=head1 TriAnnot::Programs::TRF - Methods
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
## Method execute()
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Building of the command line
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'} .
		" " . $self->{'sequence'} .
		" " . $self->{'match'} .
		" " . $self->{'misMatch'} .
		" " . $self->{'delta'} .
		" " . $self->{'pm'} .
		" " . $self->{'pi'} .
		" " . $self->{'minScore'} .
		" " . $self->{'maxPeriod'} . " -d";

	# Log the newly build command line
	$logger->debug('TandemRepeatsFinder will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	my $cmdOutput = `$cmd 2>&1`;
	$logger->debug(">>>>>>>> Start of execution output <<<<<<<<");
	$logger->debug($cmdOutput);
	$logger->debug(">>>>>>>>  End of execution output  <<<<<<<<");

	# Deduce TRF output file name from parameters and rename it
	my $std_outfile_name = $self->{'sequence'} . '.' . $self->{'match'} . '.' . $self->{'misMatch'} . '.' . $self->{'delta'} . '.' . $self->{'pm'} . '.' . $self->{'pi'} . '.' . $self->{'minScore'} . '.' . $self->{'maxPeriod'} . '.dat';

	rename($std_outfile_name, $self->{'outFile'}) or $logger->logdie('TRF brut output file does not exists: ' . $std_outfile_name);
}

1;
