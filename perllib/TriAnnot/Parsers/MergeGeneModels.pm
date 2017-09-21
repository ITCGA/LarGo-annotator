#!/usr/bin/env perl

package TriAnnot::Parsers::MergeGeneModels;
##################################################
## Included modules
##################################################
## Perl modules
use strict;
use warnings;
use diagnostics;

# CPAN modules
use File::Basename;
use File::Copy;
use Data::Dumper;
use Clone;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Parsers::Parsers;
use TriAnnot::Tools::Logger;

## BioPerl modules
use Bio::Tools::GFF;
use Bio::SeqIO;
use Bio::SearchIO;

## Inherits
our @ISA = qw(TriAnnot::Parsers::Parsers);

##################################################
## Methods
##################################################

=head1 TriAnnot::Parsers::MergeGeneModels - Methods
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

	$logger->debug('Parsing file: ' . $self->{'fullFileToParsePath'} . '.');

	# Initializations
	my $gffIO = Bio::Tools::GFF->new ( '-file' => $self->{'fullFileToParsePath'}, '-gff_version' => "3" ) ;
	my $feature;
	my @tabFeature;

	# Loop through the raw features
	while($feature = $gffIO->next_feature()){
		if ($feature->primary_tag() eq 'mRNA') {
			# Get the original source tag
			my $original_source = $feature->source_tag();

			# Store the original as a new attribute for mRNA features
			$feature->add_tag_value('original_source', $original_source);
		}

		# Define the new source tag
		$feature->source_tag('GENEMODEL');

		push(@tabFeature, $feature);
	}

	$logger->debug('End of parsing (Stop at ' . localtime() . ')');

	return @tabFeature;
}


######################
## Overridden Methods
######################

sub getSoftList {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my @Soft_list = ();

	# Return an empty list, Merge is not an external tool
	return \@Soft_list;
}

1;
