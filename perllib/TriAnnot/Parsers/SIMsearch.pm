#!/usr/bin/env perl

package TriAnnot::Parsers::SIMsearch;

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

=head1 TriAnnot::Parsers::SIMsearch - Methods
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

################
# Parsing
################

sub _parse {

	# Recovers parameters
	my ($self) = @_;

	# Initializations
	my @SIMsearch_features = ();
	my (%Features_counters, %Features_lists) = ((), ());
	my $Gene_number = 0;

	# Read SIMsearch output file
	$logger->debug('Parsing file: ' . $self->{'fullFileToParsePath'} . '.');

	# Create a Bio::Tools::GFF object
	my $gffIO = Bio::Tools::GFF->new ( '-file' => $self->{'fullFileToParsePath'}, '-gff_version' => "3" ) ;

	# Loop through the features of SIMsearch raw GFF file
	while(my $Current_feature = $gffIO->next_feature()){

		my $Feature_type = $Current_feature->primary_tag();

		if ($Feature_type eq 'gene') {
			if ($Gene_number > 0) {
				# Treat the feature group related to a given gene
				my $Valid_features = $self->_updateFeatureGroup($Gene_number, \%Features_counters, \%Features_lists, \@SIMsearch_features);

				# Re-initialize counters and list
				(%Features_counters, %Features_lists) = ((), ());
			}
			$Gene_number++;
		}

		# Count the number of feature of each type
		if (defined ($Features_counters{$Feature_type})) {
			$Features_counters{$Feature_type}++;
		} else {
			$Features_counters{$Feature_type} = 1;
		}

		# Store each type of feature in separated arrays
		if (!defined ($Features_lists{$Feature_type})) { $Features_lists{$Feature_type} = (); }
		push(@{$Features_lists{$Feature_type}}, $Current_feature);
	}

	# Treat the last feature group
	if ($Gene_number > 0) {
		my $Valid_features = $self->_updateFeatureGroup($Gene_number, \%Features_counters, \%Features_lists, \@SIMsearch_features);
	}

	$logger->debug('End of parsing (Stop at ' . localtime() . ')');

	return @SIMsearch_features;
}


# Note: In the SIMsearch brut GFF output file, the start of a given feature is always lower than the end of this feature (Strand independant)
sub _updateFeatureGroup {

	# Recovers parameters
	my ($self, $Gene_number, $Ref_to_Features_counters, $Ref_to_Features_lists, $Ref_to_SIMsearch_features) = @_;

	# Get the strand from any feature
	my $Strand = @{$Ref_to_Features_lists->{'gene'}}[0]->strand();

	# Get generic feature order
	my $Feature_order = $self->getGenericFeatureOrder($Strand);

	# Get boundaries
	my $Boundaries = $self->_getBoundariesOfFeatureTypes($Ref_to_Features_counters, $Ref_to_Features_lists, $Feature_order, $Strand);

	# Store modified features in the correct order
	foreach my $Feature_type (@{$Feature_order}) {
		if (defined ($Ref_to_Features_lists->{$Feature_type})) {
			foreach my $Current_feature (@{$Ref_to_Features_lists->{$Feature_type}}) {
				$self->_addOntologyAndType($Current_feature, $Feature_type, $Strand, $Boundaries);
			}

			push(@{$Ref_to_SIMsearch_features} , @{$Ref_to_Features_lists->{$Feature_type}});
		}
	}

	return 0;
}


sub _getBoundariesOfFeatureTypes {

	# Recovers parameters
	my ($self, $Ref_to_Features_counters, $Ref_to_Features_lists, $Ref_to_Feature_order, $Strand) = @_;

	# Initializations
	my %Boundaries = ();

	# If there is no UTR region, the wildcards UTR_left and UTR_right must be set to default
	if (!defined($Ref_to_Features_counters->{'five_prime_UTR'}) || !defined($Ref_to_Features_counters->{'three_prime_UTR'})) {
		$Boundaries{'UTR_left'} = $Boundaries{'UTR_right'} = {'start' => -99, 'end' => -99};
	}

	# Get the boundaries of every feature type
	foreach my $Feature_type (@{$Ref_to_Feature_order}) {
		if (defined($Ref_to_Features_lists->{$Feature_type}) && defined($Ref_to_Features_counters->{$Feature_type}) && $Ref_to_Features_counters->{$Feature_type} > 0) {
			$Boundaries{$Feature_type} = {'start' => -99, 'end' => -99};

			foreach my $Feature_object (@{$Ref_to_Features_lists->{$Feature_type}}) {
				if ($Boundaries{$Feature_type}->{'start'} == -99) { $Boundaries{$Feature_type}->{'start'} = $Feature_object->start(); }
				if ($Feature_object->end() > $Boundaries{$Feature_type}->{'end'}) { $Boundaries{$Feature_type}->{'end'} = $Feature_object->end(); }
			}

			# Define UTR wildcards boundaries
			if (($Feature_type eq 'five_prime_UTR' && $Strand != -1) || ($Feature_type eq 'three_prime_UTR' && $Strand == -1)) { # 5'+ or 3'-
				$Boundaries{'UTR_left'} = {'start' => $Boundaries{$Feature_type}->{'start'}, 'end' => $Boundaries{$Feature_type}->{'end'}};
			} elsif (($Feature_type eq 'five_prime_UTR' && $Strand == -1) || ($Feature_type eq 'three_prime_UTR' && $Strand != -1)) { # 5'- or 3'+
				$Boundaries{'UTR_right'} = {'start' => $Boundaries{$Feature_type}->{'start'}, 'end' => $Boundaries{$Feature_type}->{'end'}};
			}
		}
	}

	#~ print Dumper(%Boundaries);

	return \%Boundaries;
}


sub _addOntologyAndType {

	# Recovers parameters
	my ($self, $Feature_to_update, $Feature_type, $Strand, $Ref_to_Boundaries) = @_;

	# Initializations
	my ($Ontology, $Sub_type) = ('', '');
	my ($UTR_left_switch, $UTR_right_switch) = (1, 1);

	# Get feature start and end
	my ($Start, $End) = ($Feature_to_update->start(), $Feature_to_update->end());

	# Toggle the switches
	if ($Ref_to_Boundaries->{'UTR_left'}->{'start'} == -99) { $UTR_left_switch = 0; }
	if ($Ref_to_Boundaries->{'UTR_right'}->{'start'} == -99) { $UTR_right_switch = 0; }

	# Determine sub_type
	if ($UTR_left_switch == 0 && $UTR_right_switch == 0) { # Without UTR region
		if ($Feature_type eq 'exon' || $Feature_type eq 'CDS' || $Feature_type eq 'polypeptide') {
			if ($Start == $Ref_to_Boundaries->{'mRNA'}->{'start'} && $End == $Ref_to_Boundaries->{'mRNA'}->{'end'}) {
				$Sub_type = 'Single';
			} elsif ($Start == $Ref_to_Boundaries->{'mRNA'}->{'start'}) {
				if ($Strand == -1) {
					$Sub_type = 'Terminal';
				} else {
					$Sub_type = 'Initial';
				}
			} elsif ($End == $Ref_to_Boundaries->{'mRNA'}->{'end'}) {
				if ($Strand == -1) {
					$Sub_type = 'Initial';
				} else {
					$Sub_type = 'Terminal';
				}
			} else {
				$Sub_type = 'Internal';
			}
		}
	} else { # With UTR region
		if ($Feature_type eq 'exon') { # Exon case
			if (($Start == $Ref_to_Boundaries->{'mRNA'}->{'start'} || $Start == $Ref_to_Boundaries->{'UTR_left'}->{'end'}) && ($End == $Ref_to_Boundaries->{'mRNA'}->{'end'} || $End == $Ref_to_Boundaries->{'UTR_right'}->{'start'})) {
				$Sub_type = 'Single';
			} elsif (($UTR_left_switch == 1 && $End <= $Ref_to_Boundaries->{'UTR_left'}->{'end'}) || ($UTR_right_switch == 1 && $Start >= $Ref_to_Boundaries->{'UTR_right'}->{'start'})) {
				$Sub_type = 'External';
			} elsif ($Start == $Ref_to_Boundaries->{'mRNA'}->{'start'} || ($Start <= $Ref_to_Boundaries->{'UTR_left'}->{'end'} && $End > $Ref_to_Boundaries->{'UTR_left'}->{'end'})) {
				if ($Strand == -1) {
					$Sub_type = 'Terminal';
				} else {
					$Sub_type = 'Initial';
				}
			} elsif ($End == $Ref_to_Boundaries->{'mRNA'}->{'end'} || ($Start < $Ref_to_Boundaries->{'UTR_right'}->{'start'} && $End >= $Ref_to_Boundaries->{'UTR_right'}->{'start'})) {
				if ($Strand == -1) {
					$Sub_type = 'Initial';
				} else {
					$Sub_type = 'Terminal';
				}
			} else {
				$Sub_type = 'Internal';
			}

		} elsif ($Feature_type eq 'CDS' || $Feature_type eq 'polypeptide') { # CDS / Polypeptide case
			if (($Start == $Ref_to_Boundaries->{'mRNA'}->{'start'} || $Start == $Ref_to_Boundaries->{'UTR_left'}->{'end'} + 1) && ($End == $Ref_to_Boundaries->{'mRNA'}->{'end'} || $End == $Ref_to_Boundaries->{'UTR_right'}->{'start'} - 1)) {
				$Sub_type = 'Single';
			} elsif ($Start == $Ref_to_Boundaries->{'mRNA'}->{'start'} || $Start == $Ref_to_Boundaries->{'UTR_left'}->{'end'} + 1) {
				if ($Strand == -1) {
					$Sub_type = 'Terminal';
				} else {
					$Sub_type = 'Initial';
				}
			} elsif ($End == $Ref_to_Boundaries->{'mRNA'}->{'end'} || $End == $Ref_to_Boundaries->{'UTR_right'}->{'start'} - 1) {
				if ($Strand == -1) {
					$Sub_type = 'Initial';
				} else {
					$Sub_type = 'Terminal';
				}
			} else {
				$Sub_type = 'Internal';
			}
		}
	}

	# Get ontology
	if ($Sub_type eq '') {
		$Ontology = $self->getSOTermId($Feature_type);
	} else {
		$Ontology = $self->getSOTermId($Feature_type, $Sub_type);
	}

	# Add Ontology and subtype to the current feature
	$Feature_to_update->add_tag_value('Ontology_term', $Ontology) if ($Ontology ne '');
	$Feature_to_update->add_tag_value($Feature_type . '_type', $Sub_type) if ($Sub_type ne '');

	return $Feature_to_update;
}


#######################
# Overridden methods
#######################

sub getSoftList {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my @Soft_list = ();

	# SIMsearch is included in TriAnnot so its version is equal to Triannot version
	push(@Soft_list, $self->{'programName'} . '(TriAnnot ' . $TRIANNOT_CONF{'VERSION'} . ')');

	return \@Soft_list;
}

1;
