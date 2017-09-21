#!/usr/bin/env perl

package TriAnnot::Parsers::ssrFinder;
##################################################
## Included modules
##################################################
## Perl modules
use strict;
use warnings;
use diagnostics;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Parsers::Parsers;
use TriAnnot::Tools::Logger;

## BioPerl modules
use Bio::Tools::GFF;

## Debug module
use Data::Dumper;

## Inherits
our @ISA = qw(TriAnnot::Parsers::Parsers);

##################################################
## Methods
##################################################

=head1 TriAnnot::Parsers::ssrFinder - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class
	my $self = $class->SUPER::new(\%attrs);

	bless $self => $class;

	return $self;
}


##################
# Method parse() #
##################

sub _parse {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my @ssrFinderFeatures;

	# Log
	$logger->debug('Parsing file: ' . $self->{'fullFileToParsePath'} . '.');

	# Bio::Tools::GFF object creation
	my $gffIoObject = Bio::Tools::GFF->new ( '-file' => $self->{'fullFileToParsePath'}, '-gff_version' => "3" ) ;

	# Loop through the raw features
	while(my $currentFeature = $gffIoObject->next_feature()){
		next if ($currentFeature->primary_tag() eq 'region');
		push(@ssrFinderFeatures, $currentFeature);
	}

	$logger->debug('End of parsing (Stop at ' . localtime() . ')');

	return @ssrFinderFeatures;
}

1;
