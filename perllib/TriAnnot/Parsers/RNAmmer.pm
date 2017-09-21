#!/usr/bin/env perl

package TriAnnot::Parsers::RNAmmer;

##################################################
## Documentation POD
##################################################

##################################################
## Included modules
##################################################
## Perl modules
use strict;
use warnings;
use diagnostics;

## BioPerl modules
use Bio::SeqFeature::Generic;
use Bio::Tools::GFF;

## TriAnnot modules
use TriAnnot::Parsers::Parsers;
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Parsers::Parsers);

##################################################
## Methods
##################################################
=head1 TriAnnot::Parsers::RNAmmer - Methods
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
	my $resultCounter = 0;
	my @RNAmmerFeatures = ();

	# Display a warning message when the file to parse is missing
	if (! -e $self->{'fullFileToParsePath'}) {
		$logger->logwarn('RNAmmer output file is missing (' . $self->{'fullFileToParsePath'} . '). Parse method will return an empty feature array.');
		return @RNAmmerFeatures;
	}

	# Bio::Tools::GFF object creation
	my $gffIoObject = Bio::Tools::GFF->new ( '-file' => $self->{'fullFileToParsePath'}, '-gff_version' => "1" ) ;

	# Loop through the raw features
	while(my $currentFeature = $gffIoObject->next_feature()){
		# Increment feature counter
		$resultCounter++;

		# Add new attribute to the feature
		my $featureName = $self->getSourceTag() . '_' . $currentFeature->start() . '_' . $currentFeature->end() . '_rRNA_' . $resultCounter;

		$currentFeature->add_tag_value('Name', $featureName);
		$currentFeature->add_tag_value('ID', $self->{'sequenceName'} . '_' . $featureName);

		# Update the source tag
		$currentFeature->source_tag($self->getSourceTag());

		# Rename the group attribute
		if ($currentFeature->has_tag('group')) {
			$currentFeature->add_tag_value('Note', join(',', $currentFeature->get_tag_values('group')));
			$currentFeature->remove_tag('group');
		}

		# Store the updated feature
		push(@RNAmmerFeatures, $currentFeature);
	}

	$logger->debug('End of parsing (Stop at ' . localtime() . ')');

	return @RNAmmerFeatures;
}

1;
