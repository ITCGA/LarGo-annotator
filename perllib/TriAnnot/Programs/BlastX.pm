#!/usr/bin/env perl

package TriAnnot::Programs::BlastX;

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

## Inherits
use base ("TriAnnot::Programs::BlastPlus");


##################################################
## Methods
##################################################
=head1 TriAnnot::Programs::BlastX - Methods
=cut

################
# Constructor
################

sub new {
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class (TriAnnot::Programs::BlastPlus)
	my $self = $class->SUPER::new(\%attrs);

	bless $self => $class;

	return $self;
}


#####################
## Method _execute()
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Building of the command line addon
	my $cmd_addon = '';

	# Always defined parameters
	$cmd_addon .= ' -strand ' . $self->{'strand'};
	$cmd_addon .= ' -query_gencode ' . $self->{'queryGeneticCode'};
	$cmd_addon .= ' -matrix ' . $self->{'matrix'};
	$cmd_addon .= ' -seg "' . $self->{'queryFiltering'} . '"';
	$cmd_addon .= ' -out ' . $self->{'outFile'};

	# Optional parameters
	if(defined($self->{'maxIntronLength'})) { $cmd_addon .= ' -max_intron_length ' . $self->{'maxIntronLength'}; }

	# Store BlastX specific options in the BlastX Object
	$self->{'Command_addon'} = $cmd_addon;

	# Call the _execute method of the parent class (BlastPlus)
	$self->SUPER::_execute();
}

1;
