#!/usr/bin/env perl

package TriAnnot::Parsers::Augustus;

######################
###     POD Documentation
######################

##################################################
# Modules
##################################################

# Perl modules
use strict;
use warnings;
use diagnostics;

## BioPerl modules
use Bio::SeqFeature::Generic;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Parsers::Parsers;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Parsers::Parsers);

##################################################
## Methods
##################################################

=head1 TriAnnot::Parsers::Augustus - Methods
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
	my $Rejected_feature = 0;
	($self->{'Last_gene_short_name'}, $self->{'Last_gene_identifier'}, $self->{'Last_mRNA_short_name'}, $self->{'Last_mRNA_identifier'}) = ('', '', '', '');
	my (%subFeatures_counters, %subFeatures_lists) = ((), ());
	my @AugustusFeatures = ();

	# Display a warning message when the file to parse is missing
	if (! -e $self->{'fullFileToParsePath'}) {
		$logger->logwarn('Augustus output file is missing (' . $self->{'fullFileToParsePath'} . '). Parse method will return an empty feature array.');
		return @AugustusFeatures;
	}

	# Open Augustus brut output file
	open(AUGUSTUS_OUT, '<' . $self->{'fullFileToParsePath'}) or $logger->logdie('Error: Cannot open/read file: ' . $self->{'fullFileToParsePath'});
	while(<AUGUSTUS_OUT>){

		if ($_ =~ /^# command line/) {
			# Add all the leftover subfeatures and exit the main while loop
			$self->_addSubFeatures(\%subFeatures_counters, \%subFeatures_lists, \@AugustusFeatures);
			last;

		} elsif ($_ =~ /^[^#]/ && $_ !~ /^$/) { # If the current line ins't a comment line or an empty line, we analyse it.

			# Gets the differents elements of the line
			my ($seqid, $source, $type, $start, $stop, $score, $strand, $phase, $attributes) = split("\t", $_);

			# Change type name according to TriAnnot and SO rules
			if ($type eq 'transcript') { $type = 'mRNA'; }
			elsif ($type eq 'CDS') { $type = $TRIANNOT_CONF{Global}->{'CDS_or_POLY'}; }

			# Reject a feature if its type is present in the list of rejected feature type defined in section Augustus from configuration file
			foreach my $rejected_type (values %{$TRIANNOT_CONF{Augustus}->{Rejected_feature_types}}) {
				if ($type eq $rejected_type) {
					$Rejected_feature = 1;
					last;
				}
			}
			if ($Rejected_feature == 1) {
				$Rejected_feature = 0;
				next;
			}

			# Update the number of element of type $type for the current gene prediction
			if (defined ($subFeatures_counters{$type})) {
				$subFeatures_counters{$type}++;
			} else {
				$subFeatures_counters{$type} = 1;
			}

			# Build a correct and well formated feature
			my $Neo_Feature = $self->_buildNewFeature($self->{'sequenceName'}, $self->{sourceTag}, $type, $start, $stop, $score, $strand, $phase, "%03d", \%subFeatures_counters);

			# The following loop is used to add low level subfeatures (intron, exon, etc.) in a specific order to the global list of Augustus feature after a gene/mRNA change
			# The else statement is used to temporarily store and separate low level subfeatures into specific arrays
			if ($type eq 'gene') {
				if ($subFeatures_counters{'gene'} > 1) {
					$self->_addSubFeatures(\%subFeatures_counters, \%subFeatures_lists, \@AugustusFeatures); # Add sub features of the last mRNA of the previous gene
					$subFeatures_counters{'mRNA'} = ();
				}
				push(@AugustusFeatures, $Neo_Feature);

			} elsif ($type eq 'mRNA') {
				if ($subFeatures_counters{'mRNA'} > 1) {
					$self->_addSubFeatures(\%subFeatures_counters, \%subFeatures_lists, \@AugustusFeatures); # Add sub features of the previous mRNA of the current gene (In case of multiple mRNA for a single gene)
				}
				push(@AugustusFeatures, $Neo_Feature);

			} else {
				if (!defined ($subFeatures_lists{$type})) { $subFeatures_lists{$type} = (); }
				push(@{$subFeatures_lists{$type}}, $Neo_Feature);
			}
		}
	}

	# Closes the REPET output file
	close(AUGUSTUS_OUT);
	$logger->debug('End of parsing (Stop at ' . localtime() . ')');

	return @AugustusFeatures;
}


######################
## Internal Methods
######################

sub _buildNewFeature {

	# Recovers parameters
	my ($self, $seqid, $source, $type, $start, $stop, $score, $strand, $phase, $sprintf_size, $Counter_hash_ref) = @_;

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


sub _parentNameManagement {

	# Recovers parameters
	my ($self, $current_feature, $Counter_hash_ref, $sprintf_size) = @_;

	# Storage of the Name and ID Tag of feature of type gene and mRNA
	if ($current_feature->primary_tag() eq 'gene') {
		$self->{'Last_gene_short_name'} = '_gene_' . sprintf($sprintf_size, $Counter_hash_ref->{'gene'});
		$self->{'Last_gene_identifier'} = join (',', $current_feature->get_tag_values('ID'));

	} elsif ( $current_feature->primary_tag() eq 'mRNA') {
		$self->{'Last_mRNA_short_name'} = $self->{'Last_gene_short_name'} . '_mRNA_' . sprintf($sprintf_size, $Counter_hash_ref->{'mRNA'});
		$self->{'Last_mRNA_identifier'} = join (',', $current_feature->get_tag_values('ID'));
	}

	return 0;
}


sub _addSubFeatures {

	# Recovers parameters
	my ($self, $Counter_hash_ref, $Lister_hash_ref, $AugustusFeatures_array_reference) = @_;

	# Add all low-level subfeatures (intron, exon, etc.) in a specific order to the global list of Augustus feature after a gene/mRNA change
	foreach my $key (sort {$a <=> $b} keys %{$TRIANNOT_CONF{SubFeaturesOrder}}) {
		my $current_subfeature_type = $TRIANNOT_CONF{SubFeaturesOrder}->{$key};
		if (defined ($Counter_hash_ref->{$current_subfeature_type})) {
			$self->_addSequenceOntology($Lister_hash_ref->{$current_subfeature_type}, $current_subfeature_type);
			push(@{$AugustusFeatures_array_reference}, @{$Lister_hash_ref->{$current_subfeature_type}});
			$Counter_hash_ref->{$current_subfeature_type} = ();
			$Lister_hash_ref->{$current_subfeature_type} = ();
		}
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
