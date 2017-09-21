#!/usr/bin/env perl

package TriAnnot::Parsers::InterProScan;

##################################################
## Documentation POD
##################################################

##################################################
## Modules
##################################################
##  Basic Perl modules
use strict;
use warnings;
use diagnostics;

## Perl modules
use File::Basename;

# Bioperl
use Bio::SeqFeature::Generic;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Parsers::Parsers;
use TriAnnot::Tools::Logger;

# Debug
use Data::Dumper;

## Inherits
our @ISA = qw(TriAnnot::Parsers::Parsers);

##################################################
## Methods
##################################################
=head1 TriAnnot::Parsers::InterProScan - Methods
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


#############################################
## Parameters/variables initializations
#############################################

sub setParameters {

	# Recovers parameters
	my ($self, $parameters) = @_;

	# Call parent class method (See Programs.pm module for more information)
	$self->SUPER::setParameters($parameters);

	# Check tool specific parameters
	$self->_checkCustomParameters();

	# Store some path and names in the current object for easier access
	$self->_managePathsAndNames();
}


sub _managePathsAndNames {

	# Recovers parameters
	my $self = shift;

	if (defined($self->{'geneModelGffFile'}) && $self->{'geneModelGffFile'} ne '') {
		$self->{'gffDirFullPath'} = $self->{'directory'} . '/' . $TRIANNOT_CONF{'DIRNAME'}->{'GFF_files'};
		$self->{'geneModelFileFullPath'} = $self->{'gffDirFullPath'} . '/' . $self->{'geneModelGffFile'};
	}
}


#######################################
# Parameters check related methods
#######################################

sub _checkCustomParameters {

	# Recovers parameters
	my $self = shift;

	# Check specific parameters
	if (defined($self->{'useGeneModelData'}) && $self->{'useGeneModelData'} eq 'yes') {
		if (!defined($self->{'geneModelGffFile'}) || $self->{'geneModelGffFile'} eq '') {
			$logger->logdie('Error: Gene Model data must be used (useGeneModelData parameter set to yes) but there is no Gene Model GFF file defined (with the geneModelGffFile parameter)');
		}
	}

	if (defined($self->{'geneModelGffFile'}) && $self->{'geneModelGffFile'} ne '') {
		if (!defined($self->{'useGeneModelData'}) || $self->{'useGeneModelData'} eq 'no') {
			$logger->logdie('Error: A Gene Model GFF file has been selected but the useGeneModelData switch is set to no (or not defined) !');
		}
	}

	return 0; # SUCCESS
}


sub _checkInputFiles {

	# Recovers parameters
	my $self = shift;

	# Check the input Gene Model file if needed
	if (defined($self->{'geneModelGffFile'}) && $self->{'geneModelGffFile'} ne '') {
		$self->_checkFileExistence('Gene Model', $self->{'geneModelFileFullPath'});
	}
}


##################
# Method parse() #
##################

sub _parse {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my @IPSres = ();
	my $usefulFeaturesHashReference = {};
	$self->{'Results_by_tool'} = ();

	# Check if the file to parse exist or not
	if (! -e $self->{'fullFileToParsePath'}) {
		$logger->logwarn('InterproScan output file is missing (' . $self->{'fullFileToParsePath'} . '). Parse method will return an empty feature array.');
		return @IPSres;
	}

	$logger->info('');
	# Parse the GeneModel file to collect CDS/polypeptide features
	if (defined($self->{'useGeneModelData'}) && $self->{'useGeneModelData'} eq 'yes') {
		$logger->info('Parsing of the InterProScan output file (GFF mode) in progress..');
		$usefulFeaturesHashReference = $self->_ExtractUsefulFeaturesFromGeneModelFile();
	} else {
		$logger->info('Parsing of the InterProScan output file (Stand alone mode) in progress..');
	}
	$logger->info('');

	# Load the ID correspondence from the text file (Short_ID to Long_ID)
	my $Ref_to_ID_correspondence = $self->_load_ID_correspondence();

	# Open & Parse the InterproScan output file
	open(IPS_OUT, '<' . $self->{'fullFileToParsePath'}) or $logger->logdie('Error: Cannot open/read file: ' . $self->{'fullFileToParsePath'});
	while (my $resultLine = <IPS_OUT>){

		# Initializations
		my $geneNumber = 0;
		my $subDomainCounter = 0;

		# Cleaning
		chomp($resultLine);
		$resultLine =~ s/[;,]//g; # Eliminate all "," and ";" character that sometimes appears in various field

		# Partial split of the result line
		my ($input_sequence_id, $crc64_checksum, $input_sequence_length, $analysis_type, $resultLineEnd) = split('\t', $resultLine, 5);

		# Store some data in the main object
		$self->{'Current_mRNA'} = $Ref_to_ID_correspondence->{$input_sequence_id};
		$self->{'Analysis_type'} = uc($analysis_type);

		# Get the current gene/match number from the mRNA name
		if ($self->{'Current_mRNA'} =~ /\w+?_(Gene|Match)_(\d+)_.*/i) {
			$geneNumber = int($2);
		} else {
			$logger->logdie('Error: Gene/Match number cannot be extracted from the mRNA identifier !');
		}

		# Count the number of result for the current analysis type (Ex: HMMPfam) on the current protein sequence (Ex: Synth09_FGENESH_41954_44924_Gene_0008_mRNA_0001)
		$self->_updateResultCounters($geneNumber);

		# Build the main feature
		my $PolypeptideDomainFeature = $self->_generatePolypeptideDomainFeature($geneNumber, $resultLineEnd);

		push(@IPSres, $PolypeptideDomainFeature);

		# Generate sub-domain features if needed
		if (defined($usefulFeaturesHashReference->{$self->{'sequenceName'}}->{$self->{'Current_mRNA'}})) {
			# Collect coordinates
			my $refToCoordinates = $self->_determineSubDomainsCoordinates($usefulFeaturesHashReference->{$self->{'sequenceName'}}->{$self->{'Current_mRNA'}}, $PolypeptideDomainFeature);

			# Update the coordinates of the parent feature
			$self->_updateParentFeatureCoordinates($refToCoordinates, $PolypeptideDomainFeature);

			# Build sub-domain features
			foreach my $coordinates (@{$refToCoordinates}) {
				push(@IPSres, $self->_generatePolypeptideDomainPartFeature($coordinates, ++$subDomainCounter, $PolypeptideDomainFeature));
			}
		}
	}

	# Closes the REPET output file
	close(IPS_OUT);

	return @IPSres;
}


#####################################################
# Sub-domains coordinates recovery related methods
#####################################################

sub _determineSubDomainsCoordinates {

	# Recovers parameters
	my ($self, $polypeptideFeatures, $parentFeature) = @_;

	# Initializations
	my ($polypeptideCounter, $domainSizeDecrementCounter) = (0, -1);
	my @subDomainsCoordinates = ();

	# Collect domain data
	my ($Target_ID, $proteicDomainStart, $proteicDomainEnd) = $parentFeature->get_tag_values('Target');
	my $nucleicDomainSize = (($proteicDomainEnd - $proteicDomainStart + 1) * 3);
	my $nbNucleotideBeforeDomain = ($proteicDomainStart -1) * 3;

	# Get the strand from one of the CDS/polypeptide feature and Update the parent feature
	my $strand = $polypeptideFeatures->[0]->strand();
	$parentFeature->strand($strand);

	# Determine coordinates depending on the strand
	# Forward strand
	if ($strand == 1) {
		# Determine on which polypeptide/CDS feature begins the domain
		foreach my $polypeptideFeature (@{$polypeptideFeatures}) {
			if ($polypeptideFeature->length() <= $nbNucleotideBeforeDomain) {
				$nbNucleotideBeforeDomain -= $polypeptideFeature->length();
				$polypeptideCounter++;
			} else {
				last;
			}
		}

		# Compute the real start position of the domain on the input DNA sequence
		my $nucleicStartposition = $polypeptideFeatures->[$polypeptideCounter]->start() + $nbNucleotideBeforeDomain;

		# Get coordinates
		my $coordinatesRef = $self->_getForwardStrandSubDomains($polypeptideFeatures, $polypeptideCounter, $nucleicDomainSize, $nucleicStartposition);

		push(@subDomainsCoordinates, @{$coordinatesRef});

	# Reverse strand
	} else {
		my @reverseList = reverse @{$polypeptideFeatures};

		# Determine on which polypeptide/CDS feature begins the domain
		foreach my $polypeptideFeature (@reverseList) {
			if ($polypeptideFeature->length() <= $nbNucleotideBeforeDomain) {
				$nbNucleotideBeforeDomain -= $polypeptideFeature->length();
				$polypeptideCounter++;
			} else {
				last;
			}
		}

		# Compute the real start position of the domain on the input DNA sequence
		my $nucleicStartposition = $reverseList[$polypeptideCounter]->end() - $nbNucleotideBeforeDomain;

		# Get coordinates
		my $coordinatesRef = $self->_getReverseStrandSubDomains(\@reverseList, $polypeptideCounter, $nucleicDomainSize, $nucleicStartposition);

		push(@subDomainsCoordinates, reverse @{$coordinatesRef});
	}

	# Check
	if (scalar(@subDomainsCoordinates) == 0) {
		$logger->logdie('Error: The array containing the sub-domains coordinates is empty !');
	}

	return \@subDomainsCoordinates;
}


sub _getForwardStrandSubDomains {

	# Recovers parameters
	my ($self, $polypeptideFeatures, $polypeptideCounter, $nucleicDomainSize, $nucleicStartposition) = @_;

	# Initializations
	my $subDomainStart = -1;
	my $currentPosition = $nucleicStartposition;
	my @coordinates = ();

	# Determine coordinates
	while ($nucleicDomainSize > 1) {

		my $currentPolypeptide = $polypeptideFeatures->[$polypeptideCounter];

		$subDomainStart = ($currentPolypeptide->start() > $nucleicStartposition) ? $currentPolypeptide->start() : $nucleicStartposition;

		if ($currentPosition == $currentPolypeptide->end()) {
			push(@coordinates, { 'start' => $subDomainStart, 'end' => $currentPosition });
			$polypeptideCounter++;
		}

		if ($currentPolypeptide->start() <= $currentPosition && $currentPosition <= $currentPolypeptide->end()) {
			$nucleicDomainSize--;
		}

		$currentPosition++;
	}

	push(@coordinates, { 'start' => $subDomainStart, 'end' => $currentPosition });

	return \@coordinates;
}


sub _getReverseStrandSubDomains {

	# Recovers parameters
	my ($self, $polypeptideFeaturesReverseList, $polypeptideCounter, $nucleicDomainSize, $nucleicStartposition) = @_;

	# Initializations
	my $subDomainEnd = -1;
	my $currentPosition = $nucleicStartposition;
	my @coordinates = ();

	# Determine coordinates
	while ($nucleicDomainSize > 1) {

		my $currentPolypeptide = $polypeptideFeaturesReverseList->[$polypeptideCounter];

		$subDomainEnd = ($currentPolypeptide->end() < $nucleicStartposition) ? $currentPolypeptide->end() : $nucleicStartposition;

		if ($currentPosition == $currentPolypeptide->start()) {
			push(@coordinates, { 'start' => $currentPosition, 'end' => $subDomainEnd });
			$polypeptideCounter++;
		}

		if ($currentPolypeptide->start() <= $currentPosition && $currentPosition <= $currentPolypeptide->end()) {
			$nucleicDomainSize--;
		}

		$currentPosition--;
	}

	push(@coordinates, { 'start' => $currentPosition, 'end' => $subDomainEnd });

	return \@coordinates;
}


##############################################
# Feature creation/Update related methods
##############################################

# Note about coordinates:
# Stand alone mode (No GFF input file): the polypeptide domain features will have proteic coordinates
# GFF mode: the polypeptide domain features will have nucleic coordinates (on the initial input sequence) computed from sub-domains coordinates
sub _generatePolypeptideDomainFeature {

	# Recovers parameters
	my ($self, $geneNumber, $resultLine) = @_;

	# Full split of the result line
	my ($database_member_entry, $database_member_desc, $domain_match_start, $domain_match_end, $match_evalue, $match_status, $run_date, $interpro_entry, $interpro_desc, $All_GO) = split('\t', $resultLine);

	# Building of the new feature tag
	my $IPRscan_Feature_Tag = {};

	$IPRscan_Feature_Tag->{'Name'} = $self->{'Analysis_type'} . '_Protein_' . sprintf("%04d", $geneNumber) . '_Domain_' . $self->_getDomainNumber($geneNumber);
	$IPRscan_Feature_Tag->{'ID'} = $self->{'sequenceName'} . '_' . $IPRscan_Feature_Tag->{'Name'};
	$IPRscan_Feature_Tag->{'Target'} = [$database_member_entry, $domain_match_start, $domain_match_end]; # Target Tag must be a reference to a table (anonymous or not)
	if ($self->{'Analysis_type'} eq 'SEG' || $self->{'Analysis_type'} eq 'COIL') {
		$IPRscan_Feature_Tag->{'Note'} = 'No annotation available for seg/coils program';
	} else {
		$IPRscan_Feature_Tag->{'Note'} = $database_member_desc;
	}
	$IPRscan_Feature_Tag->{'protein_derived_from'} = $self->{'Current_mRNA'};
	$IPRscan_Feature_Tag->{'e_value'} = $match_evalue;
	if ($interpro_entry ne "" && $interpro_entry ne "NULL") { $IPRscan_Feature_Tag->{'interpro_entry'} = $interpro_entry; }
	if ($interpro_desc ne "" && $interpro_desc ne "NULL") { $IPRscan_Feature_Tag->{'interpro_entry_description'} = $interpro_desc; }

	# Isolate all GO informations
	$self->_manage_GO_informations($All_GO, $IPRscan_Feature_Tag);

	# Creation of the new feature
	my $IPRscan_Feature = Bio::SeqFeature::Generic->new(
								-seq_id      => $self->{'sequenceName'},
								-source_tag  => $self->{'Analysis_type'},
								-primary_tag => 'polypeptide_domain',
								-start       => $domain_match_start,
								-end         => $domain_match_end,
								-tag         => $IPRscan_Feature_Tag
								);

	return $IPRscan_Feature;
}


sub _generatePolypeptideDomainPartFeature {

	# Recovers parameters
	my ($self, $coordinates, $currentSubDomainNumber, $parentFeature) = @_;

	# Initializations
	my $parentIdentifier = join(',', $parentFeature->get_tag_values('ID'));
	my $parentName = join(',', $parentFeature->get_tag_values('Name'));
	my $strand = $parentFeature->strand();

	# Modify the number of decimal of the result number
	$currentSubDomainNumber = sprintf "%04d", $currentSubDomainNumber;

	# Building of the new feature tag
	my $featureTag = {};

	$featureTag->{'Name'} = $parentName . '_SubDomain_' . $currentSubDomainNumber;
	$featureTag->{'ID'} = $self->{'sequenceName'} . '_' . $featureTag->{'Name'};
	$featureTag->{'Parent'} = $parentIdentifier;

	# Creation of the new feature
	my $IPRscan_SubFeature = Bio::SeqFeature::Generic->new(
								-seq_id      => $self->{'sequenceName'},
								-source_tag  => $self->{'Analysis_type'},
								-primary_tag => 'polypeptide_domain_part',
								-strand      => $strand,
								-start       => $coordinates->{'start'},
								-end         => $coordinates->{'end'},
								-tag         => $featureTag
								);

	return $IPRscan_SubFeature;
}


sub _updateParentFeatureCoordinates {

	# Recovers parameters
	my ($self, $coordinatesArrayRef, $featureToUpdate) = @_;

	# Update the feature
	$featureToUpdate->start($coordinatesArrayRef->[0]->{'start'});
	$featureToUpdate->end($coordinatesArrayRef->[$#{$coordinatesArrayRef}]->{'end'});
}


##############################################
# Gene Model data recovery related methods
##############################################

sub _ExtractUsefulFeaturesFromGeneModelFile {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my %usefulFeatures = ();

	# Log
	$logger->info('');
	$logger->info('Retrieving CDS/polypeptide features from file: ' . basename($self->{'geneModelGffFile'}));

	# Use BioPerl to parse the input GFF file
	my $gffObject = Bio::Tools::GFF->new(-file => $self->{'geneModelFileFullPath'} , -gff_version => 3);

	while (my $currentFeature = $gffObject->next_feature()) {
		# Extract CDS/polypeptide features
		if ($currentFeature->primary_tag() =~ /^(CDS|polypeptide)$/) {
			# Get data from the current feature
			my $parentName = $self->_getParentName($currentFeature);
			my $sequenceIdentifier = $currentFeature->seq_id();

			# Initializations
			$usefulFeatures{$sequenceIdentifier} = {} if (!defined($usefulFeatures{$sequenceIdentifier}));
			$usefulFeatures{$sequenceIdentifier}->{$parentName} = [] if (!defined($usefulFeatures{$sequenceIdentifier}->{$parentName}));

			# Add the current CDS/polypeptide feature in the hash entry attached to the current parent name
			#$logger->debug('Adding feature ' . ($currentFeature->get_tag_values('Name'))[0] . ' for parent ' . $parentName);
			push(@{$usefulFeatures{$sequenceIdentifier}->{$parentName}}, $currentFeature);
		}
	}

	return \%usefulFeatures;
}


sub _getParentName {

	# Recovers parameters
	my ($self, $feature) = @_;

	# Return the parent name if it exists, an error otherwise
	if ($feature->has_tag('Derives_from')) {
		my @derivesFromTagValues = $feature->get_tag_values('Derives_from');
		return $derivesFromTagValues[0];
	} elsif ($feature->has_tag('Parent')) {
		my @parentTagValues = $feature->get_tag_values('Parent');
		return $parentTagValues[0];
	} else {
		$logger->logdie('A feature of type ' . $feature->primary_tag() . ' named ' . ($feature->get_tag_values('Name'))[0] . ' has no parent !');
	}

	return 0;
}


###################
## Basic Methods
###################

sub _load_ID_correspondence {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my %ID_hash = ();
	my $sequenceIDsFileFullPath = $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'tmp_files'} . '/' . $self->{'sequenceIDsFile'};

	# Load the ID correspondence into a hash table
	open(CORRESPONDENCE, '<' . $sequenceIDsFileFullPath) or $logger->logdie('Cannot open/read ' . $sequenceIDsFileFullPath); # Reading mode
	while(<CORRESPONDENCE>){

		# Split line and fill the hash table
		chomp;
		my ($Short_ID, $Long_ID) = split(';', $_);
		$ID_hash{$Short_ID} = $Long_ID;
	}
	close(CORRESPONDENCE);

	# Return a reference to the hash table containing the ID correspondence
	return \%ID_hash;
}


sub _updateResultCounters {

	# Recovers parameters
	my ($self, $currentGeneNumber) = @_;

	# Update result counters
	if (!defined ($self->{'Results_by_tool'}->{$self->{'Analysis_type'}})) { $self->{'Results_by_tool'}->{$self->{'Analysis_type'}} = (); }

	if (defined ($self->{'Results_by_tool'}->{$self->{'Analysis_type'}}->{'gene_' . $currentGeneNumber})) {
		$self->{'Results_by_tool'}->{$self->{'Analysis_type'}}->{'gene_' . $currentGeneNumber}++;
	} else {
		$self->{'Results_by_tool'}->{$self->{'Analysis_type'}}->{'gene_' . $currentGeneNumber} = 1;
	}

	return 0;
}


sub _getDomainNumber {

	# Recovers parameters
	my ($self, $currentGeneNumber) = @_;

	# Modify the number of decimal of the result number
	my $domainNumber = sprintf("%04d", $self->{'Results_by_tool'}->{$self->{'Analysis_type'}}->{'gene_' . $currentGeneNumber});

	return $domainNumber;
}


sub _manage_GO_informations {

	# Recovers parameters
	my ($self, $All_GO_information, $Current_feature_TAG) = @_;

	# Initializations
	my ($Nb_Molecular_function, $Nb_Biological_process, $Nb_Cellular_Component) = (0, 0, 0);

	# Split GO information and update feature TAG
	if (defined($All_GO_information)) {
		if ($All_GO_information ne "") {
			while ($All_GO_information =~ /Molecular Function: (.+?\))/g) {
				$Nb_Molecular_function++;
				$Current_feature_TAG->{'molecular_function_' . $Nb_Molecular_function} = $1;
			}
			while ($All_GO_information =~ /Biological Process: (.+?\))/g) {
				$Nb_Biological_process++;
				$Current_feature_TAG->{'biological_process_' . $Nb_Biological_process} = $1;
			}
			while ($All_GO_information =~ /Cellular Component: (.+?\))/g) {
				$Nb_Cellular_Component++;
				$Current_feature_TAG->{'cellular_component_' . $Nb_Cellular_Component} = $1;
			}
		}
	}
}

1;
