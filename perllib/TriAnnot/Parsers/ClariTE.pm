#!/usr/bin/env perl

package TriAnnot::Parsers::ClariTE;
##################################################
## Included modules
##################################################
## Perl modules
use strict;
use warnings;
use diagnostics;

# CPAN modules
use File::Basename;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Parsers::Parsers;
use TriAnnot::Tools::Logger;

## BioPerl modules
use Bio::SeqIO;

## DEBUG
use Data::Dumper;

## Inherits
our @ISA = qw(TriAnnot::Parsers::Parsers);

##################################################
## Methods
##################################################

=head1 TriAnnot::Parsers::ClariTE - Methods
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
	my ($repeatRegionCounter, $nestedRepeatCounter) = (0, 0);
	my @clariteFeatures = ();

	# Display a warning message when the file to parse is missing
	if (! -e $self->{'fullFileToParsePath'}) {
		$logger->logwarn('ClariTE output file is missing (' . $self->{'fullFileToParsePath'} . '). Parse method will return an empty feature array.');
		return @clariteFeatures;
	}

	# Create an EMBL input stream
	my $inputStream = Bio::SeqIO->new(-format => 'EMBL', -file => $self->{'fullFileToParsePath'});

	# Read the EMBL file
	while (my $currentSequence = $inputStream->next_seq()) {
		# Remove the sequence from the Bio::Seq object
		$currentSequence->seq('');

		# Get all features
		foreach my $currentFeature ($currentSequence->get_SeqFeatures()) {
			# Reject feature that are not TE
			next if ($currentFeature->primary_tag() ne 'repeat_region');

			# If the feature has a parent tag and is a join we have to create the nested_repeat and repeat_fragment features
			if ($currentFeature->has_tag('parent')) {
				# Temporary check to avoid the building of erroneous features due to two major bugs in clari-TE.pl 1.0
				my @rangeTagValues = split(',', ($currentFeature->get_tag_values('range'))[0]);
				my ($nbLocation, $nbRange) = (scalar($currentFeature->location->each_Location()), scalar(@rangeTagValues));

				if ($nbRange < $nbLocation) {
					$logger->logwarn('The number of range (' . $nbRange . ') is lower (<) than the number of location (' . $nbLocation . ') for feature ' . ($currentFeature->get_tag_values('id'))[0]);
					$logger->logwarn('ClariTE known bug number 1 detected (Bad storage of range data) ! No nested_repeat feature will be created from feature ' . ($currentFeature->get_tag_values('id'))[0]);
					$logger->logwarn('Problematic feature:' . "\n" . Dumper($currentFeature));
				} elsif ($nbRange > $nbLocation) {
					$logger->logwarn('The number of range (' . $nbRange . ') is greater (>) than the number of location (' . $nbLocation . ') for feature ' . ($currentFeature->get_tag_values('id'))[0]);
					$logger->logwarn('ClariTE known bug number 2 detected (Bad management of nested nested repeats) ! No nested_repeat feature will be created from feature ' . ($currentFeature->get_tag_values('id'))[0]);
					$logger->logwarn('Problematic feature:' . "\n" . Dumper($currentFeature));
				} else {
					# Increase the counter of repeat_region features
					$nestedRepeatCounter++;

					# Build and Store the nested_repeat feature
					push(@clariteFeatures, $self->generateNestedRepeatFeature($currentFeature, $nestedRepeatCounter));

					# Build and Store the associated repeat_fragment features
					push(@clariteFeatures, @{$self->generateRepeatFragmentFeatures($currentFeature, $nestedRepeatCounter)});
				}

			} else {
				# Increase the counter of repeat_region features
				$repeatRegionCounter++;

				# Update and Store the current repeat_region feature
				push(@clariteFeatures, $self->updateRepeatRegionFeature($currentFeature, $repeatRegionCounter));
			}
		}
	}

	return @clariteFeatures;
}


sub updateRepeatRegionFeature {

	# Recovers parameters
	my ($self, $repeatRegionFeature, $repeatRegionCounter) = @_;

	# Create valid ID and Name tag
	if ($repeatRegionFeature->has_tag('id')) {
		$repeatRegionFeature->add_tag_value('Name', $self->getSourceTag() . '_' . $repeatRegionFeature->start() . '_' . $repeatRegionFeature->end() . '_Repeat_region_' . $repeatRegionCounter);
		$repeatRegionFeature->add_tag_value('ID', $self->{'sequenceName'} . '_' . ($repeatRegionFeature->get_tag_values('Name'))[0]);

		$repeatRegionFeature->remove_tag('id');
	}

	# Create valid Target tag
	if ($repeatRegionFeature->has_tag('post') && $repeatRegionFeature->has_tag('copie')) {
		my ($family, $size, $start, $end) = ($repeatRegionFeature->get_tag_values('post'))[0] =~ /(\S+) (\w+) (\d+)\.\.(\d+)/;
		my $fullTargetIdentifier = ($repeatRegionFeature->get_tag_values('copie'))[0] . '(Family: ' . $family . ')';
		$repeatRegionFeature->add_tag_value('Target', ($fullTargetIdentifier, $start, $end));

		# Remove custom tags
		$repeatRegionFeature->remove_tag('post');
		$repeatRegionFeature->remove_tag('copie');
	}

	# Give the proper seq_id to the feature
	$repeatRegionFeature->seq_id($self->{'sequenceName'});
	$repeatRegionFeature->source_tag($self->getSourceTag());

	# Add ontology
	$repeatRegionFeature->add_tag_value('Ontology_term', $self->getSOTermId('repeat_region'));

	return $repeatRegionFeature;
}


sub generateNestedRepeatFeature {

	# Recovers parameters
	my ($self, $joinFeature, $nestedRepeatCounter) = @_;

	# Initializations
	my $nestedFeatureTags = {};

	# Creation of the new nested_repeat feature
	$nestedFeatureTags->{'Name'} = $self->getSourceTag() . '_' . $joinFeature->start() . '_' . $joinFeature->end() . '_Nested_repeat_' . $nestedRepeatCounter;
	$nestedFeatureTags->{'ID'} = $self->{'sequenceName'} . '_' . $nestedFeatureTags->{'Name'};
	$nestedFeatureTags->{'Ontology_term'} = $self->getSOTermId('nested_repeat');

	my $nestedFeature = Bio::SeqFeature::Generic->new(
						-seq_id      => $self->{'sequenceName'},
						-source_tag  => $self->getSourceTag(),
						-primary_tag => 'nested_repeat',
						-start       => $joinFeature->start(),
						-end         => $joinFeature->end(),
						-strand      => $joinFeature->strand(),
						-tag         => $nestedFeatureTags
						);

	# Add important tags from the original join feature
	my @tagToKeep = ('status', 'compo');

	foreach my $tag(@tagToKeep) {
		if ($joinFeature->has_tag($tag)) {
			foreach my $tagValue ($joinFeature->get_tag_values($tag)) {
				$nestedFeature->add_tag_value($tag, $tagValue);
			}
		}
	}

	# Build a valid Target tag from several tags of the join feature
	if ($joinFeature->has_tag('post') && $joinFeature->has_tag('copie')) {
		my ($family, $size, $start, $end) = ($joinFeature->get_tag_values('post'))[0] =~ /(\S+) (\w+) (\d+)\.\.(\d+)/;
		my $fullTargetIdentifier = ($joinFeature->get_tag_values('copie'))[0] . '(Family: ' . $family . ')';
		$nestedFeature->add_tag_value('Target', ($fullTargetIdentifier, $start, $end));
	}

	return $nestedFeature;
}


sub generateRepeatFragmentFeatures {

	# Recovers parameters
	my ($self, $joinFeature, $nestedRepeatCounter) = @_;

	# Initializations
	my @generatedFeatures = ();
	my (@locations, @ranges) = ((), ());
	my $locationCounter = 0;

	# Get all locations and ranges of the join feature
	# Some explanation about ranges:
	#	- Clarity 1.0 does not use add_tag_value correctly so there is always only one value for the range tag (ie. a string with ont to several coordinate couples separated by ",")
	#	- Josquin (ie ClariTE developper) also said that ranges are always written in the same order (strand independant)
	# So, we have to take the strand into consideration to affect the right range to the right repeat_fragment
	if ($joinFeature->strand == 1) {
		@locations = $joinFeature->location->each_Location();
		@ranges = split(',', ($joinFeature->get_tag_values('range'))[0]);
	} else {
		@locations = reverse($joinFeature->location->each_Location());
		@ranges = reverse(split(',', ($joinFeature->get_tag_values('range'))[0]));
	}

	# Create a repeat_fragment feature for each location
	foreach my $location (@locations) {
		# Initializations and counter management
		my $repeatFragmentTags = {};
		$locationCounter++;

		# Creation of the new repeat_fragment feature
		$repeatFragmentTags->{'Parent'} = $self->{'sequenceName'} . '_' . $self->getSourceTag() . '_' . $joinFeature->start() . '_' . $joinFeature->end() . '_Nested_repeat_' . $nestedRepeatCounter;
		$repeatFragmentTags->{'Name'} = $self->getSourceTag() . '_' . $location->start() . '_' . $location->end() . '_Nested_repeat_' . $nestedRepeatCounter . '_Repeat_fragment_' . $locationCounter;
		$repeatFragmentTags->{'ID'} = $self->{'sequenceName'} . '_' . $repeatFragmentTags->{'Name'};
		$repeatFragmentTags->{'Ontology_term'} = $self->getSOTermId('repeat_fragment');

		my $repeatFragmentFeature = Bio::SeqFeature::Generic->new(
									-seq_id      => $self->{'sequenceName'},
									-source_tag  => $self->getSourceTag(),
									-primary_tag => 'repeat_fragment',
									-start       => $location->start(),
									-end         => $location->end(),
									-strand      => $location->strand(),
									-tag         => $repeatFragmentTags
									);

		# Build a valid Target tag from several tags of the join feature
		if ($joinFeature->has_tag('post') && $joinFeature->has_tag('copie') && $joinFeature->has_tag('range')) {
			my ($family) = split(" ", ($joinFeature->get_tag_values('post'))[0], 2);
			my $fullTargetIdentifier = ($joinFeature->get_tag_values('copie'))[0] . '(Family: ' . $family . ')';

			my ($start, $end) = split(/\.\./, $ranges[$locationCounter -1]);
			$repeatFragmentFeature->add_tag_value('Target', ($fullTargetIdentifier, $start, $end));
		}

		push(@generatedFeatures, $repeatFragmentFeature);
	}

	return \@generatedFeatures;
}
