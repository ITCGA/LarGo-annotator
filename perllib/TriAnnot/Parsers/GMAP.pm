#!/usr/bin/env perl

package TriAnnot::Parsers::GMAP;

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

## TriAnnot modules
use TriAnnot::Parsers::Parsers;
use TriAnnot::Tools::MergeHits;
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::GetInfo;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Parsers::Parsers);


##################################################
## Methods
##################################################
=head1 TriAnnot::Parsers::GMAP - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class
	my $self = $class->SUPER::new(\%attrs);

	# Define $self as a $class type object
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
	($self->{'Last_gene_short_name'}, $self->{'Last_gene_identifier'}, $self->{'Last_mRNA_short_name'}, $self->{'Last_mRNA_identifier'}) = ('', '', '', '');
	my (%subFeatures_counters, %subFeatures_lists) = ((), ());
	my (@GMAP_features, @Coordinates) = ((), ());

	# Display a warning message when the file to parse is missing
	if (! -e $self->{'fullFileToParsePath'}) {
		$logger->logwarn('GMAP output file is missing (' . $self->{'fullFileToParsePath'} . '). Parse method will return an empty feature array.');
		return @GMAP_features;
	}

	# Open GMAP brut output file
	open(GMAP_OUT, '<' . $self->{'fullFileToParsePath'}) or $logger->logdie('Error: Cannot open/read file: ' . $self->{'fullFileToParsePath'});
	while(<GMAP_OUT>){

		if ($_ =~ /^[^#]/) { # If the current line ins't a comment line we analyse it

			# Gets the differents elements of the line
			my ($seqid, $source, $type, $start, $stop, $score, $strand, $phase, $GFF2_attributes) = split("\t", $_);

			# Change type name according to TriAnnot rules
			if ($type eq 'CDS') { $type = $TRIANNOT_CONF{Global}->{'CDS_or_POLY'}; }

			# Update the number of element of type $type for the current gene prediction
			if (defined ($subFeatures_counters{$type})) {
				$subFeatures_counters{$type}++;
			} else {
				$subFeatures_counters{$type} = 1;
			}

			# Build a correct and well formated feature
			my $Neo_Feature = $self->_buildNewFeature($self->{'sequenceName'}, $self->getSourceTag(), $type, $start, $stop, $score, $strand, $phase, $GFF2_attributes, "%04d", \%subFeatures_counters);

			# The following loop is used to add low level subfeatures (intron, exon, etc.) in a specific order to the global list of GMAP feature after a gene/mRNA change
			# The else statement is used to temporarily store and separate low level subfeatures into specific arrays
			if ($type eq 'gene') {
				if ($subFeatures_counters{'gene'} > 1) {
					$self->_addSubFeatures(\%subFeatures_counters, \%subFeatures_lists, \@GMAP_features); # Add sub features of the last mRNA of the previous gene
					$subFeatures_counters{'mRNA'} = ();
				}
				push(@GMAP_features, $Neo_Feature);
				push(@Coordinates, $start . "\t" . $stop);

			} elsif ($type eq 'mRNA') {
				if ($subFeatures_counters{'mRNA'} > 1) {
					$self->_addSubFeatures(\%subFeatures_counters, \%subFeatures_lists, \@GMAP_features); # Add sub features of the previous mRNA of the current gene (In case of multiple mRNA for a single gene)
				}
				push(@GMAP_features, $Neo_Feature);

			} else {
				if (!defined ($subFeatures_lists{$type})) { $subFeatures_lists{$type} = (); }
				push(@{$subFeatures_lists{$type}}, $Neo_Feature);
			}
		}
	}

	# Add all the leftover subfeatures and exit the main while loop
	$self->_addSubFeatures(\%subFeatures_counters, \%subFeatures_lists, \@GMAP_features);

	# Closes the REPET output file
	close(GMAP_OUT);

	# Merged hit creation
	my $All_merged_hit = TriAnnot::Tools::MergeHits::Merge_all_hit(\@Coordinates, $self->{'sequenceName'}, 'GMAP_' . $self->{'database'});
	push(@GMAP_features, @{$All_merged_hit});

	return @GMAP_features;
}

######################
## Internal Methods
######################

sub _buildNewFeature {

	# Recovers parameters
	my ($self, $seqid, $source, $type, $start, $stop, $score, $strand, $phase, $GFF2_attributes_as_string, $sprintf_size, $Counter_hash_ref) = @_;

	# Split the attribute list of the brut GMAP GFF2 file and store it in a hash table
	my $GFF2_attribute_list_ref = $self->_getGFF2Attributes($GFF2_attributes_as_string);

	# Build all attributes (GFF field 9) of the new feature
	my $New_feature_attributes = {};

	if ($type eq 'gene') {
		$New_feature_attributes->{'Name'} = $source . '_' . $start . '_' . $stop . '_' . $type . '_' . sprintf($sprintf_size, $Counter_hash_ref->{$type});
	} elsif ($type eq 'mRNA') {
		$New_feature_attributes->{'Name'} = $source . '_' . $start . '_' . $stop . $self->{'Last_gene_short_name'} . '_' . $type . '_' . sprintf($sprintf_size, $Counter_hash_ref->{$type});
		$New_feature_attributes->{'Parent'} = $self->{'Last_gene_identifier'};
	} else {
		$New_feature_attributes->{'Name'} = $source . '_' . $start . '_' . $stop . $self->{'Last_mRNA_short_name'} . '_' . $type . '_' . sprintf($sprintf_size, $Counter_hash_ref->{$type});
		if ($type eq 'CDS' || $type eq 'polypeptide') {
			$New_feature_attributes->{'Derives_from'} = $self->{'Last_mRNA_identifier'};
		} elsif ($type ne 'gene') {
			$New_feature_attributes->{'Parent'} = $self->{'Last_mRNA_identifier'};
		}
	}
	$New_feature_attributes->{'ID'} = $seqid . '_' . $New_feature_attributes->{'Name'};

	if ($type eq 'mRNA') {
		my $info;
		$info = TriAnnot::Tools::GetInfo->new(database => $TRIANNOT_CONF{PATHS}->{db}->{$self->{database}}->{path}, type => 'F' , id => $GFF2_attribute_list_ref->{'Name'});
		$New_feature_attributes->{'Note'} = $info->{description};
	}

	foreach (keys %{$GFF2_attribute_list_ref}) {

		if ($_ =~ /^[a-z].*/) {
			$New_feature_attributes->{$_} = $GFF2_attribute_list_ref->{$_};

		} elsif ($_ eq 'Target') {
			my ($Target_ID, $Target_start, $Target_end, $Target_strand) = split(' ', $GFF2_attribute_list_ref->{$_});
			$New_feature_attributes->{'Target'} = [$Target_ID, $Target_start, $Target_end]; # Target Tag must be a reference to a table (anonymous or not)
		}
	}

	# Creation of the new feature
	my $New_feature = Bio::SeqFeature::Generic->new(
		 -seq_id      => $seqid,
		 -source_tag  => $source,
		 -primary_tag => $type,
		 -start       => $start,
		 -end         => $stop,
		 -strand      => $strand,
		 -frame       => $phase,
		 -tag         => $New_feature_attributes
	);

	# Add score attributes if $score is different than "." (avoid the error with the score field during the execution of the Bio::SeqFeature::Generic set_attributes methods)
	if ($score ne ".") { $New_feature->score($score); }

	# If the current feature is a gene or a mRNA then we save useful information to build future parent tag
	$self->_parentNameManagement($New_feature, $Counter_hash_ref, $sprintf_size);

	return $New_feature;
}


sub _getGFF2Attributes {

	# Recovers parameters
	my ($self, $All_GFF2_attributes) = @_;

	# Initializations
	my %GFF2_attribute_list = ();

	# Remove line separator
	chomp($All_GFF2_attributes);

	# Split the string containing all attributes
	my @Attribute_list_tab = split(';', $All_GFF2_attributes);

	# Separate each attribute name from its value and fill GFF2_attribute_list hash table
	foreach my $attribute (@Attribute_list_tab) {
		my ($GFF_Attribute_Name, $GFF_Attribute_value) = split('=', $attribute);

		# Checik if the current Attribute name is in the Official list of reserved character in GFF Field 9 - See http://www.sequenceontology.org/gff3.shtml for more information
		if ($GFF_Attribute_Name !~ /^(ID|Name|Alias|Parent|Target|Gap|Derives_from|Note|Dbxref|Ontology_term|Is_circular)/) {
			$GFF_Attribute_Name = lcfirst($GFF_Attribute_Name);
		}
		if ($GFF_Attribute_Name =~ /^Name/){
			$GFF_Attribute_value =~ s/^lcl\|// ;
		}

		$GFF2_attribute_list{$GFF_Attribute_Name} = $GFF_Attribute_value;
	}

	return \%GFF2_attribute_list;
}

sub _addSubFeatures {

	# Recovers parameters
	my ($self, $Counter_hash_ref, $Lister_hash_ref, $GMAP_Features_array_reference) = @_;

	# Initializations
	my @Exon_list = ();
	my $Already_created = 0;

	# Add all low-level subfeatures (intron, exon, etc.) in a specific order to the global list of GMAP feature after a gene/mRNA change
	foreach my $key (sort {$a <=> $b} keys %{$TRIANNOT_CONF{SubFeaturesOrder}}) {
		my $current_subfeature_type = $TRIANNOT_CONF{SubFeaturesOrder}->{$key};
		if (defined ($Counter_hash_ref->{$current_subfeature_type})) {

			# If the strand of all subfeatures to add for the current type of subfeature is '-' then we have to reverse the tab and update ID/Name Tag
			if (${$Lister_hash_ref->{$current_subfeature_type}}[0]->strand() != 1) {
				$self->_dealWithMinusStrand($current_subfeature_type, $Lister_hash_ref);
			}

			# Save all exon features in a temporary array for future use
			if ($current_subfeature_type eq 'exon') {
				@Exon_list = @{$Lister_hash_ref->{$current_subfeature_type}};

				# Special case: Create virtual polypeptide feature(s) when, for a given gene prediction, GMAP give at least one exon but no CDS/polypeptide
				if (! defined($Counter_hash_ref->{$TRIANNOT_CONF{Global}->{'CDS_or_POLY'}}) ) {
					$self->_createVirtualPolypeptides($TRIANNOT_CONF{Global}->{'CDS_or_POLY'}, $Lister_hash_ref, $Counter_hash_ref, \@Exon_list);
					$Already_created = 1;
				}
			}

			# Discard CDS/polypeptide features predicted by GMAP and create virtual CDS/polypeptide features if needed (Virtual CDS/polypeptide have the coordinates of the exon features)
			# Important note: We do not recreate polypeptide features if it has already been created during exon turn (Missing predicted CDS special case)
			if ($self->{'keepPredictedCDS'} eq 'no' && ($current_subfeature_type eq 'CDS' || $current_subfeature_type eq 'polypeptide') && $Already_created != 1) {
				$self->_createVirtualPolypeptides($current_subfeature_type, $Lister_hash_ref, $Counter_hash_ref, \@Exon_list);
			}

			# Add the appropriate Sequence Ontology Identifier to current subfeatures
			$self->_addSequenceOntology($Lister_hash_ref->{$current_subfeature_type}, $current_subfeature_type);

			# Add complete subfeatures to the global list of GMAP feature
			push(@{$GMAP_Features_array_reference}, @{$Lister_hash_ref->{$current_subfeature_type}});

			# Empty lists
			$Counter_hash_ref->{$current_subfeature_type} = ();
			$Lister_hash_ref->{$current_subfeature_type} = ();
		}
	}

	return 0;
}


sub _dealWithMinusStrand {

	# Recovers parameters
	my ($self, $Current_feature_type, $Lister_hash_ref) = @_;

	# Initializations
	my $Subfeature_counter = 0;

	# Sort sub features of type $Current_feature_type by ascending start position
	@{$Lister_hash_ref->{$Current_feature_type}} = sort {$a->start() <=> $b->start()} @{$Lister_hash_ref->{$Current_feature_type}};

	# Modify ID and Name Tag of all subfeatures to adapt it to the new order + Add all sub features to the global feature list
	foreach my $feature (@{$Lister_hash_ref->{$Current_feature_type}}) {
		$Subfeature_counter++;

		if (join (',', $feature->get_tag_values('Name')) =~ /(.*)?_\d+?/) {
			$feature->remove_tag('Name');
			$feature->remove_tag('ID');

			$feature->add_tag_value('Name', $1 . '_' . sprintf("%04d", $Subfeature_counter));
			$feature->add_tag_value('ID', $self->{'sequenceName'} . '_' . $1 . '_' . sprintf("%04d", $Subfeature_counter));
		}
	}

	return 0;
}


sub _createVirtualPolypeptides {

	# Recovers parameters
	my ($self, $Current_feature_type, $Lister_hash_ref, $Counter_hash_ref, $Ref_to_Exon_list) = @_;

	# Clean the original list of polypeptide features
	$Lister_hash_ref->{$Current_feature_type} = ();

	# Create the virtual polypeptide features from data of the exon features
	if (scalar(@{$Ref_to_Exon_list}) > 0) {
		foreach my $Base_feature (@{$Ref_to_Exon_list}) {

			# Initializations
			my $Virtual_polypeptide_attributes = {};

			# Get all the tags of the exon feature
			my @All_tags = $Base_feature->get_all_tags();

			foreach my $Current_TAG (@All_tags) {

				# Avoid the redondant tag "score" and exon specific tags
				if ($Current_TAG eq 'score' || $Current_TAG =~ /exon|Ontology/i) { next; }

				# Get all values for current tag
				my @All_tag_values = $Base_feature->get_tag_values($Current_TAG);

				if ($Current_TAG eq 'Parent') {
					# Convert the Parent tag into a Derives_from tag
					$Virtual_polypeptide_attributes->{'Derives_from'} = $All_tag_values[0];

				} elsif ($Current_TAG eq 'ID' || $Current_TAG eq 'Name') {
					# Replace the term exon by the term CDS/polypeptide in the ID and Name tags
					$All_tag_values[0] =~ s/exon/$Current_feature_type/ig;
					$Virtual_polypeptide_attributes->{$Current_TAG} = $All_tag_values[0];

				} elsif ($Current_TAG eq 'Target') {
					my ($Target_ID, $Target_start, $Target_end, $Target_strand) = @All_tag_values;
					$Virtual_polypeptide_attributes->{'Target'} = [$Target_ID, $Target_start, $Target_end]; # Target Tag must be a reference to a table (anonymous or not)

				} else {
					$Virtual_polypeptide_attributes->{$Current_TAG} = join(',', @All_tag_values);
				}
			}

			# Creation of the new virtual feature
			my $Virtual_polypeptide_feature = Bio::SeqFeature::Generic->new(
				 -seq_id      => $Base_feature->seq_id(),
				 -source_tag  => $Base_feature->source_tag(),
				 -primary_tag => $Current_feature_type,
				 -start       => $Base_feature->start(),
				 -end         => $Base_feature->end(),
				 -strand      => $Base_feature->strand(),
				 -frame       => $Base_feature->frame(),
				 -tag         => $Virtual_polypeptide_attributes
			);

			push(@{$Lister_hash_ref->{$Current_feature_type}}, $Virtual_polypeptide_feature);
			$Counter_hash_ref->{$Current_feature_type}++;
		}

	} else {
		$logger->logwarn('Unlikely event: The exon list to use for virtual polypeptide features creation is empty ! Please check feature\'s order in config file section SubFeaturesOrder !');
	}

	return 0;
}


sub _addSequenceOntology {

	# Recovers parameters
	my ($self, $feature_array_ref, $feature_type) = @_;

	# Initializations
	my $Number_of_element = scalar(@{$feature_array_ref});
	my $Strand = $feature_array_ref->[0]->strand();

	# Warning on an unlikely event
	if ($Number_of_element < 1) {
		$logger->logwarn('Unlikely event: Empty list of ' . $feature_type . ' features in _addSequenceOntology method !');
		return;
	}

	# Browse the list of sub features and recover the appropriate Sequence Ontology identifier for each feature
	for (my $i = 0; $i < $Number_of_element; $i++) {

		# Initializations
		my ($Ontology, $Sub_type) = ('', '');

		if ($feature_type eq 'intron') {
			$Sub_type = 'Internal';
			$Ontology = $self->getSOTermId('intron', $Sub_type);

		} elsif ($feature_type eq 'exon' || $feature_type eq 'CDS' || $feature_type eq 'polypeptide') {

			if ($Number_of_element == 1) {
				$Sub_type = 'Single';
				$Ontology = $self->getSOTermId($feature_type, $Sub_type);

			} elsif ($i == 0) {
				if ($Strand == -1) {
					$Sub_type = 'Terminal';
					$Ontology = $self->getSOTermId($feature_type, $Sub_type);
				} else {
					$Sub_type = 'Initial';
					$Ontology = $self->getSOTermId($feature_type, $Sub_type);
				}

			} elsif ($i == $Number_of_element - 1) {
				if ($Strand == -1) {
					$Sub_type = 'Initial';
					$Ontology = $self->getSOTermId($feature_type, $Sub_type);
				} else {
					$Sub_type = 'Terminal';
					$Ontology = $self->getSOTermId($feature_type, $Sub_type);
				}

			} else {
				$Sub_type = 'Internal';
				$Ontology = $self->getSOTermId($feature_type, $Sub_type);
			}

		} else {
			$Ontology = $self->getSOTermId($feature_type)
		}

		# Complete current feature tag list
		$feature_array_ref->[$i]->add_tag_value('Ontology_term', $Ontology);
		if ($Sub_type ne '') {
			$feature_array_ref->[$i]->add_tag_value($feature_type . '_type', $Sub_type);
		}
	}
}

1;
