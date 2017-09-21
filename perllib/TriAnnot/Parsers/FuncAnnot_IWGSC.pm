#!/usr/bin/env perl

package TriAnnot::Parsers::FuncAnnot_IWGSC;

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
use base ("TriAnnot::Parsers::FuncAnnot");


##################################################
## Methods
##################################################
=head1 TriAnnot::Parsers::FuncAnnot_IWGSC - Methods
=cut

################
# Constructor
################

sub new {
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class (TriAnnot::Programs::FuncAnnot)
	my $self = $class->SUPER::new(\%attrs);

	bless $self => $class;

	return $self;
}

1;
