#!/usr/bin/env perl

package TriAnnot::Programs::BlastP;

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
=head1 TriAnnot::Programs::BlastP - Methods
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
	$cmd_addon .= ' -task ' . $self->{'task'};
	$cmd_addon .= ' -matrix ' . $self->{'matrix'};
	$cmd_addon .= ' -seg "' . $self->{'queryFiltering'} . '"';
	$cmd_addon .= ' -out ' . $self->{'outFile'};

	# Parameters without value (presence/absence)
	if (defined($self->{'useSmithWaterman'}) && $self->{'useSmithWaterman'} eq 'true') { $cmd_addon .= ' -use_sw_tback '; }

	# Store BlastP specific options in the BlastP Object
	$self->{'Command_addon'} = $cmd_addon;

	# Call the _execute method of the parent class (BlastPlus)
	$self->SUPER::_execute();
}

1;
