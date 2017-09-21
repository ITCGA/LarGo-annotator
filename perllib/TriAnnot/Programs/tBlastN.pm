#!/usr/bin/env perl

package TriAnnot::Programs::tBlastN;

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
=head1 TriAnnot::Programs::tBlastN - Methods
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
	$cmd_addon .= ' -db_gencode ' . $self->{'dbGeneticCode'};
	$cmd_addon .= ' -matrix ' . $self->{'matrix'};
	$cmd_addon .= ' -seg "' . $self->{'queryFiltering'} . '"';
	$cmd_addon .= ' -out ' . $self->{'outFile'};

	# Optional parameters
	if(defined($self->{'maxIntronLength'})) { $cmd_addon .= ' -max_intron_length ' . $self->{'maxIntronLength'}; }

	# Store tBlastN specific options in the tBlastN Object
	$self->{'Command_addon'} = $cmd_addon;

	# Call the _execute method of the parent class (BlastPlus)
	$self->SUPER::_execute();
}

1;
