#!/usr/bin/env perl

package TriAnnot::Programs::RNAmmer;

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
=head1 TriAnnot::Programs::RNAmmer - Methods
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

	$cmd .= ' -s ' . $self->{'superKingdom'};
	$cmd .= ' -m ' . join(',', @{$self->{'moleculeType'}});
	$cmd .= ' -gff ' . $self->{'outFile'};

	$cmd .= ' ' . $self->{'sequence'};

	# Log the newly build command line
	$logger->debug('RNAmmer will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	system($cmd);
}

1;
