#!/usr/bin/env perl

package TriAnnot::Programs::Blast;

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
=head1 TriAnnot::Programs::Blast - Methods
=cut

################
# Constructor
################

sub new {
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
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'} .
		' -p ' . $self->{'type'} .
		' -d ' . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'database'}}->{'path'} .
		' -i ' . $self->{'sequence'} .
		' -e ' . $self->{'evalue'} .
		' -o ' . $self->{'outFile'}	.
		' -m 7' . # XML output format
		' -b ' . $self->{'nbAlignHit'} .
		' -v ' . $self->{'nbOneLineHit'} .
		' -g ' . $self->{'performAlign'} .
		' -F ' . $self->{'filterSeq'} .
		' -U ' . $self->{'lowerCaseFilter'} .
		' -a ' . $self->{'nbCore'} .
		' -K ' . $self->{'nbHitByRegion'};

	# Log the newly build command line
	$logger->info('The selected database is: ' . $self->{'database'});
	$logger->debug('Blast (' . $self->{'type'} . ') will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	my $cmdOutput = `$cmd 2>&1`;
	$logger->debug(">>>>>>>> Start of execution output <<<<<<<<");
	$logger->debug($cmdOutput);
	$logger->debug(">>>>>>>>  End of execution output  <<<<<<<<");
}

1;
