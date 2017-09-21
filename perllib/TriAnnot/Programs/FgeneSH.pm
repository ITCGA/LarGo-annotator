#!/usr/bin/env perl

package TriAnnot::Programs::FgeneSH;

##################################################
## Documentation POD
##################################################

##################################################
## Modules
##################################################
## Perl modules
use strict;
use warnings;

## TriAnnot modules
use TriAnnot::Programs::Programs;
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Programs::Programs);

##################################################
## Methods
##################################################

=head1 TriAnnot::Programs::FgeneSH - Methods
=cut

#################
# Constructor
#################

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
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'} . ' ' . $TRIANNOT_CONF{PATHS}->{matrices}->{$self->{'programName'}}->{$self->{matrix}}->{'path'} . ' -full_gene -skip_prom -skip_term ' . $self->{'sequence'} . ' > ' . $self->{'outFile'};

	# Log the newly build command line
	$logger->debug('FGeneSH will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	system($cmd);
}

1;
