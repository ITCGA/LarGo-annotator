#!/usr/bin/env perl

package TriAnnot::Parsers::FuncAnnot_ORF;

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
=head1 TriAnnot::Parsers::FuncAnnot_ORF - Methods
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


###################
# Other methods
###################

sub _needToRejectFeature {

	# Recovers parameters
	my ($self, $currentFeature, $noResultMessage) = @_;

	# Make a decision based on the output of the parent method and specific checks
	if ($self->SUPER::_needToRejectFeature($currentFeature) eq 'yes') {
		return 'yes';
	} else {
		# Reject features tagged "No_biological_evidence"
		if ($currentFeature->has_tag('Note') && join(',', $currentFeature->get_tag_values('Note')) eq $noResultMessage) {
			return 'yes';
		} else {
			return 'no';
		}
	}

	return 'no';
}

1;
