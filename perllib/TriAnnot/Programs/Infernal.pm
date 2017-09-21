#!/usr/bin/env perl

package TriAnnot::Programs::Infernal;

##################################################
## Documentation POD
##################################################

##################################################
## Included modules
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
=head1 TriAnnot::Programs::Infernal - Methods
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
######################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Building of the command line
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'};

	$cmd .= ' -E ' . $self->{'reportingEvalueThreshold'};
	$cmd .= ' --cpu ' . $self->{'nbCore'};
	$cmd .= ' --tblout ' . $self->{'outFile'};
	$cmd .= ' -o ' . $self->{'outFile'} . '.big';

	# Restrict search to a single strand if needed
	if ($self->{'targetStrandToSearch'} eq 'top') {
		$cmd .= ' --toponly';
	} elsif ($self->{'targetStrandToSearch'} eq 'bottom') {
		$cmd .= ' --bottomonly';
	}

	# Turn off truncated hit detection if needed
	if ($self->{'truncatedHitDetection'} eq 'off') {
		$cmd .= ' --notrunc';
	}

	$cmd .= ' ' . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'database'}}->{'path'} . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'database'}}->{'InfernalExtension'};
	$cmd .= ' ' . $self->{'sequence'};

	# Log the newly build command line
	$logger->debug('Infernal (cmscan) will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	system($cmd);
}

1;
