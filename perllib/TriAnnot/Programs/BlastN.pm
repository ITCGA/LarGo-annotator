#!/usr/bin/env perl

package TriAnnot::Programs::BlastN;

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
=head1 TriAnnot::Programs::BlastN - Methods
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
	$cmd_addon .= ' -task ' . $self->{'task'};
	$cmd_addon .= ' -dust "' . $self->{'queryFiltering'} . '"';
	$cmd_addon .= ' -out ' . $self->{'outFile'};

	# Optional parameters
	if(defined($self->{'mismatchPenalty'})) { $cmd_addon .= ' -penality ' . $self->{'mismatchPenalty'}; }
	if(defined($self->{'matchReward'})) { $cmd_addon .= ' -reward ' . $self->{'matchReward'}; }

	# Store BlastN specific options in the BlastN Object
	$self->{'Command_addon'} = $cmd_addon;

	# Call the _execute method of the parent class (BlastPlus)
	$self->SUPER::_execute();
}

1;
