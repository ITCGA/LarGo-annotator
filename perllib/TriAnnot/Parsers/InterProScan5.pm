#!/usr/bin/env perl

package TriAnnot::Parsers::InterProScan5;

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
use XML::Twig;

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
=head1 TriAnnot::Parsers::InterProScan5 - Methods
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
		$logger->logwarn('InterProScan5 output file is missing (' . $self->{'fullFileToParsePath'} . '). Parse method will return an empty feature array.');
		return @IPSres;
	}

	$logger->info('');
	# Parse the GeneModel file to collect CDS/polypeptide features
	if (defined($self->{'useGeneModelData'}) && $self->{'useGeneModelData'} eq 'yes') {
		$logger->info('Parsing of the InterProScan5 output file (Gene model mode) in progress..');
		$usefulFeaturesHashReference = $self->_ExtractUsefulFeaturesFromGeneModelFile();
	} else {
		$logger->info('Parsing of the InterProScan5 output file (Stand alone mode) in progress..');
	}
	$logger->info('');

	# Create new XML::Twig object to parse InterProScan5 XML output file
	my $twig = new XML::Twig();

	# Parse the InterProScan5 XML output file
	$twig->parsefile($self->{'fullFileToParsePath'});
	my $twigRoot = $twig->root();

	# Analyse the results for each protein
	foreach my $proteinElt ($twigRoot->children('protein')) {
		# Get the xref elements (that contains sequence names)
		# Note: There could be more than one xref by protein block if two proteins of the fasta file have the exact same sequence)
		foreach my $xrefElt ($proteinElt->children('xref')) {
			# Initializations
			my $geneNumber = 0;

			# Store some data in the main object
			$self->{'Current_mRNA'} = $xrefElt->{'att'}->{'id'};

			# Get the current gene/match number from the mRNA name
			if ($self->{'Current_mRNA'} =~ /\w+?_(Gene|Match)_(\d+)_.*/i) {
				$geneNumber = int($2);
			} else {
				$logger->logdie('Error: Gene/Match number cannot be extracted from the mRNA identifier !');
			}

			print "Current mRNA: " . $self->{'Current_mRNA'} . "\n";

			# Get all the matches for the current protein/mRNA
			foreach my $matchesElt ($proteinElt->children('matches')) {
				foreach my $matchElt ($matchesElt->children()) {
					# Initializations
					my %matchContent = ();
					my $subDomainCounter = 0;

					# Get global evalue (that can be overwritten by the evalue attribute of the xxx-location tag)
					$matchContent{'Evalue'} = (eltHasAtt($matchElt, 'evalue')) ? $matchElt->{att}->{'evalue'} : undef;

					# Extract useful content from the signature tag
					$self->analyseSignatureElement($matchElt, \%matchContent) if ($matchElt->has_child('signature'));

					# Extract useful content from the locations tag
					$self->analyseLocationsElement($matchElt, \%matchContent) if ($matchElt->has_child('locations'));

					# Count the number of result for the current analysis type (Ex: HMMPfam) on the current protein sequence (Ex: Synth09_FGENESH_41954_44924_Gene_0008_mRNA_0001)
					$self->_updateResultCounters($geneNumber, $matchContent{'Analysis_Type'});

					# Build the main feature
					my $PolypeptideDomainFeature = $self->_generatePolypeptideDomainFeature($geneNumber, \%matchContent);
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
			}
		}
	}

	return @IPSres;
}


########################################
# XML tags analysis related methods
########################################

sub analyseSignatureElement {

	# Recovers parameters
	my ($self, $matchElt, $matchContentRef) = @_;

	# Get Signature element and analyze its content
	my $signatureElt = $matchElt->first_child('signature');
	$matchContentRef->{'Signature_Accession'} = $signatureElt->{att}->{'ac'};
	$matchContentRef->{'Signature_Description'} = (eltHasAtt($signatureElt, 'desc')) ? _removeUnauthorizedCharacters($signatureElt->{att}->{'desc'}) : 'No annotation available for this InterProScan application';

	if ($signatureElt->has_child('entry')) {
		# Manage InterPro annotation
		my $entryElt = $signatureElt->first_child('entry');
		$matchContentRef->{'InterPro_Annotation'} = $entryElt->{att}->{'type'} . ' # ' . _removeUnauthorizedCharacters($entryElt->{att}->{'desc'}) . ' (' . $entryElt->{att}->{'ac'} . ')';

		# Manage GO
		my @goElements = $entryElt->children('go-xref');

		foreach my $goElt (@goElements) {
			$matchContentRef->{'GO_terms'} = () if (! defined($matchContentRef->{'GO_terms'}));
			push(@{$matchContentRef->{'GO_terms'}}, $goElt->{att}->{'category'} . ' # ' . _removeUnauthorizedCharacters($goElt->{att}->{'name'}) . ' (' . $goElt->{att}->{'id'} . ')');
		}

		# Manage Pathway
		my @pathwayElements = $entryElt->children('pathway-xref');

		foreach my $patwayElt (@pathwayElements) {
			$matchContentRef->{'Pathways'} = () if (! defined($matchContentRef->{'Pathways'}));
			push(@{$matchContentRef->{'Pathways'}}, $patwayElt->{att}->{'db'} . ' # ' . _removeUnauthorizedCharacters($patwayElt->{att}->{'name'}) . ' (' . $patwayElt->{att}->{'id'} . ')');

		}
	}

	$matchContentRef->{'Analysis_Type'} = uc($signatureElt->first_child('signature-library-release')->{att}->{'library'});
}


sub analyseLocationsElement {

	# Recovers parameters
	my ($self, $matchElt, $matchContentRef) = @_;

	# Initializations
	my $locationsElt = $matchElt->first_child('locations');

	# Get the start and stop locations
	$matchContentRef->{'Start_location'} = $locationsElt->first_child()->{att}->{'start'};
	$matchContentRef->{'Stop_location'} = $locationsElt->first_child()->{att}->{'end'};

	# Replace the global evalue if an evalue is present in this section
	$matchContentRef->{'Evalue'} = (eltHasAtt($locationsElt->first_child(), 'evalue')) ? $locationsElt->first_child()->{att}->{'evalue'} : $matchContentRef->{'Evalue'};
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
	my ($self, $geneNumber, $matchContentRef) = @_;

	# Building of the new feature tag
	my $IPRscan_Feature_Tag = {};

	$IPRscan_Feature_Tag->{'Name'} = 'InterProScan_Protein_' . sprintf("%04d", $geneNumber) . '_' . $matchContentRef->{'Analysis_Type'} . '_result_' . $self->_getDomainNumber($geneNumber, $matchContentRef->{'Analysis_Type'});
	$IPRscan_Feature_Tag->{'ID'} = $self->{'sequenceName'} . '_' . $IPRscan_Feature_Tag->{'Name'};
	$IPRscan_Feature_Tag->{'Target'} = [$matchContentRef->{'Signature_Accession'}, $matchContentRef->{'Start_location'}, $matchContentRef->{'Stop_location'}]; # Target Tag must be a reference to a table (anonymous or not)
	$IPRscan_Feature_Tag->{'Note'} = $matchContentRef->{'Signature_Description'};
	$IPRscan_Feature_Tag->{'protein_derived_from'} = $self->{'Current_mRNA'};

	if (defined($matchContentRef->{'Evalue'})) { $IPRscan_Feature_Tag->{'e_value'} = $matchContentRef->{'Evalue'}; }
	if (defined($matchContentRef->{'InterPro_Annotation'})) { $IPRscan_Feature_Tag->{'interpro_annotation'} = $matchContentRef->{'InterPro_Annotation'}; }
	if (defined($matchContentRef->{'GO_terms'})) { $IPRscan_Feature_Tag->{'go_annotations'} = $matchContentRef->{'GO_terms'}; }
	if (defined($matchContentRef->{'Pathways'})) { $IPRscan_Feature_Tag->{'pathways_annotations'} = $matchContentRef->{'Pathways'}; }

	# Creation of the new feature
	my $IPRscan_Feature = Bio::SeqFeature::Generic->new(
								-seq_id      => $self->{'sequenceName'},
								-source_tag  => $matchContentRef->{'Analysis_Type'},
								-primary_tag => 'polypeptide_domain',
								-start       => $matchContentRef->{'Start_location'},
								-end         => $matchContentRef->{'Stop_location'},
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
								-source_tag  => $parentFeature->source_tag(),
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

sub eltHasAtt {

	# Recovers parameters
	my ($twigElement, $attributeName) = @_;

	# Check the existence of the requested attribute
	if (defined($twigElement->{att}->{$attributeName}) && $twigElement->{att}->{$attributeName} ne "") {
		return 1; # Attribute exist
	} else {
		return 0;
	}
}


sub _updateResultCounters {

	# Recovers parameters
	my ($self, $currentGeneNumber, $analysisType) = @_;

	# Update result counters
	if (!defined ($self->{'Results_by_tool'}->{$analysisType})) { $self->{'Results_by_tool'}->{$analysisType} = (); }

	if (defined ($self->{'Results_by_tool'}->{$analysisType}->{'gene_' . $currentGeneNumber})) {
		$self->{'Results_by_tool'}->{$analysisType}->{'gene_' . $currentGeneNumber}++;
	} else {
		$self->{'Results_by_tool'}->{$analysisType}->{'gene_' . $currentGeneNumber} = 1;
	}

	return 0;
}


sub _getDomainNumber {

	# Recovers parameters
	my ($self, $currentGeneNumber, $analysisType) = @_;

	# Modify the number of decimal of the result number
	my $domainNumber = sprintf("%04d", $self->{'Results_by_tool'}->{$analysisType}->{'gene_' . $currentGeneNumber});

	return $domainNumber;
}


sub _removeUnauthorizedCharacters {
	# Recovers parameters
	my $description = shift;

	if ($description ne "") {
		# Eliminate unauthorized characters
		$description =~ s/[^\w\-\(\|\s\.]/ -/g;

		# Replace parenthesis
		$description =~ s/[\(]/- /g;

		# Eliminate redundant spaces
		$description =~ tr/ //s;
	}

	return $description;
}

1;
