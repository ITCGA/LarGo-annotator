#!/usr/bin/env perl

package TriAnnot::Parsers::BlastP;

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
use base ("TriAnnot::Parsers::BlastPlus");


##################################################
## Methods
##################################################
=head1 TriAnnot::Parsers::BlastP - Methods
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

1;
