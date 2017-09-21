#!/usr/bin/env perl

package TriAnnot::Programs::ProteinMaker;

##################################################
## Included modules
##################################################
##  Basic Perl modules
use strict;
use warnings;
use diagnostics;

## Perl modules
use File::Basename;
use File::Copy;

## TriAnnot modules
use TriAnnot::Programs::Programs;
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::Logger;

# BioPerl modules
use Bio::Tools::GFF;
use Bio::SeqIO;
use Bio::DB::Fasta;

# Debug
use Data::Dumper;

## Inherits
use base ("TriAnnot::Programs::Programs");

##################################################
## Methods
##################################################
=head1 TriAnnot::Programs::ProteinMaker - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call parent class constructor (See Programs.pm module for more information)
	my $self = $class->SUPER::new(\%attrs);

	# Set specific object attributes
	$self->{'needParsing'} = 'no';
	$self->{'allowMultiFasta'} = 'yes';

	# Define $self as a $class type object
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

	# Files and directories names
	$self->{'gffDirName'} = $TRIANNOT_CONF{'DIRNAME'}->{'GFF_files'};

	$self->{'infoFileName'} = $self->{'programID'} . '_' . $self->{'programName'} . '.info';

	$self->{'cdsSequenceFileName'} = basename($self->{'cds_sequence_file'});
	$self->{'proteinSequenceFileName'} = basename($self->{'protein_sequence_file'});

	$self->{'rejectedCdsSequenceFileName'} = basename($self->{'cds_sequence_file'}) . '.rejected';
	$self->{'rejectedProteinSequenceFileName'} = basename($self->{'protein_sequence_file'}) . '.rejected';

	$self->{'outFile'} = $self->{'proteinSequenceFileName'};

	# Full paths
	$self->{'gffDirPath'} = $self->{'directory'} . '/' . $self->{'gffDirName'};

	$self->{'geneModelGffFileOriginalDirectory'} = dirname($self->{'geneModelGffFile'});
	$self->{'geneModelGffFileBasename'} = basename($self->{'geneModelGffFile'});
	$self->{'geneModelGffFileStandardFullPath'} = $self->{'gffDirPath'} . '/' . $self->{'geneModelGffFileBasename'};

	$self->{'infoFileFullPath'} = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' .$self->{'infoFileName'};

	$self->{'proteinSequenceFileFullPath'} = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'proteinSequenceFileName'};
	$self->{'cdsSequenceFileFullPath'} = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'cdsSequenceFileName'};

	$self->{'rejectedCdsSequenceFileFullPath'} = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'rejectedCdsSequenceFileName'};
	$self->{'rejectedProteinSequenceFileFullPath'} = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'rejectedProteinSequenceFileName'};
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

	# Check the GFF input file
	if (defined($self->{'geneModelGffFile'}) && $self->{'geneModelGffFile'} ne '') {
		# Special case: the value of the "geneModelGffFile" parameter is an external full path instead of just a filename
		if (($self->{'geneModelGffFileOriginalDirectory'} ne '.') && ($self->{'geneModelGffFileOriginalDirectory'} ne $self->{'gffDirPath'})) {
			# Check the existance of the external file
			$self->_checkFileExistence('external Gene Model GFF ', $self->{'geneModelGffFile'});

			# Check if the symlink destination is available
			$self->_checkSymlinkDestination($self->{'geneModelGffFileStandardFullPath'}, $self->{'geneModelGffFile'});

			# Create a symlink to the existing external GFF file in the default GFF subfolder
			if (! -e $self->{'geneModelGffFileStandardFullPath'} ) {
				$logger->debug('Creation of a symlink pointing to the external GFF input file in the default GFF subfolder');
				symlink($self->{'geneModelGffFile'}, $self->{'geneModelGffFileStandardFullPath'}) or $logger->logdie('Error: Cannot create a symlink to the external GFF input file in the default GFF subfolder ! (External file is: ' . $self->{'geneModelGffFile'} . ')');
			}
		} else {
			# Standard case: the GFF file to annotate is located in the default GFF subfolder
			$self->_checkFileExistence('Gene Model GFF', $self->{'geneModelGffFileStandardFullPath'});
		}
	}
}


sub _checkSymlinkDestination {

	# Recovers parameters
	my ($self, $symlinkFileFullPath, $expectedSymlinkDestination) = @_;

	# Stop the execution of the tool if needed
	if ( -e $symlinkFileFullPath ) {
		# Case where a regular file (ie. not a symlink) already exists in the destination folder
		if (! -l $symlinkFileFullPath) {
			$logger->logdie('Error: The external GFF input file will not be able to be symlinked in the default GFF subfolder because a regular file with the same name already exists in the destination folder !');

		# Case where a symlink file already exists in the destination folder but points to another external file than the expected one
		} elsif (readlink($symlinkFileFullPath) ne $expectedSymlinkDestination) {
			$logger->logdie('Error: The external GFF input file will not be able to be symlinked in the default GFF subfolder because a symlink with the same name already exists in the destination folder but points to another external file !');
		}
	}
}


#####################
## Execution
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	if (defined($self->{'useGeneModelData'}) && $self->{'useGeneModelData'} eq 'yes') {
		# Gene predictions contained in the GFF file will be used to extract the coding sequence of each gene
		$self->_gffBasedTranslation();
	} else {
		# All fasta sequences will be fully translated
		$self->_simpleTranslation();
	}

	# Write an informative file in csv format (it will be parsed to build a section of the Abstract file)
	$self->_writeInfoFile();
}


sub _gffBasedTranslation {

	# Recovers parameters
	my $self = shift;

	$logger->info('The selected GFF input file is: ' . $self->{'geneModelGffFileBasename'});
	$logger->info('');

	# Parse the GFF input file to collect CDS/polypeptide features
	$self->_ExtractUsefulFeaturesFromGff();

	# Indexation of the (multi-)fasta file vith BioPerl
	$logger->info('');
	$logger->info('Indexing of the fasta input file..');

	$self->{'fastaDatabase'} = Bio::DB::Fasta->new($self->{'sequence'});

	# Get the coding sequence for each gene
	$self->_buildCodingSequenceObjects();

	# Write sequence files
	$self->_writeCdsSequences();
	$self->_writeProteinSequences();
}


sub _simpleTranslation {

	# Recovers parameters
	my $self = shift;

	# Initializations
	$self->{'numberOfProteinSequence'} = 0;

	# Log
	$logger->info('');
	$logger->info('All fasta sequences will now be fully translated into amino acids and written in the main output file:');

	# Create a fasta input stream
	my $inputStream = Bio::SeqIO->new(-format => 'FASTA', -file => $self->{'fullSequencePath'});

	# Create a fasta output stream
	my $outputStream = Bio::SeqIO->new(-file => '>' . $self->{'proteinSequenceFileFullPath'}, -format => 'FASTA');

	# Translate sequences to amino acids
	while (my $currentSequence = $inputStream->next_seq()) {
		$logger->info('  -> Translating sequence ' . $currentSequence->display_name());

		# Build sequence object
		my $translatedSequence = $currentSequence->translate->seq();
		my $proteinSequenceObject = Bio::Seq->new( -id => $currentSequence->display_id() ,-alphabet => 'protein', -seq => $translatedSequence, -desc => 'length=' . length($translatedSequence) );

		# Write translated sequence on the output stream
		$outputStream->write_seq($proteinSequenceObject);

		$self->{'numberOfProteinSequence'}++;
	}

	$logger->info('');
	$logger->info('Number of sequence written in the protein sequence file: ' . $self->{'numberOfProteinSequence'});

	return 0; # Success
}


##########################################
# GFF based Tranlation related methods
##########################################

sub _ExtractUsefulFeaturesFromGff {

	# Recovers parameters
	my $self = shift;

	# Initializations
	$self->{'usefulFeatures'} = {};
	$self->{'geneModelsStatus'} = {};

	# Log
	$logger->info('Retrieving CDS/polypeptide features from file ' . $self->{'geneModelGffFileBasename'});
	$logger->info('');

	# Use BioPerl to parse the input GFF file
	my $gffObject = Bio::Tools::GFF->new(-file => $self->{'geneModelGffFileStandardFullPath'} , -gff_version => 3);

	while (my $currentFeature = $gffObject->next_feature()) {
		# Check if the current gene model must be conserved or rejected
		if ($currentFeature->primary_tag() eq 'mRNA') {
			$self->flagGeneModel($currentFeature);

		# Extract CDS/polypeptide features and split them
		} elsif ($currentFeature->primary_tag() =~ /^(CDS|polypeptide)$/) {
			# Get data from the current feature
			my $parentIdentifier = $self->_getParentIdentifier($currentFeature);
			my $sequenceIdentifier = $currentFeature->seq_id();

			if (!defined($self->{'geneModelsStatus'}->{$parentIdentifier})) {
				$logger->logdie('The parent of the feature named ' . ($currentFeature->get_tag_values('Name'))[0] . ' does not exists in the input Gene Model GFF file !');
			}

			# Hash and array initializations
			$self->{'usefulFeatures'}->{$sequenceIdentifier} = {} if (!defined($self->{'usefulFeatures'}->{$sequenceIdentifier}));
			$self->{'usefulFeatures'}->{$sequenceIdentifier}->{$parentIdentifier} = [] if (!defined($self->{'usefulFeatures'}->{$sequenceIdentifier}->{$parentIdentifier}));

			# Add the current CDS/polypeptide feature in the hash entry attached to the current parent name
			$logger->debug('Adding feature ' . ($currentFeature->get_tag_values('Name'))[0] . ' for parent ' . $parentIdentifier);
			push(@{$self->{'usefulFeatures'}->{$sequenceIdentifier}->{$parentIdentifier}}, $currentFeature);
		}
	}

	return 0; # SUCCESS
}


sub flagGeneModel {

	# Recovers parameters
	my ($self, $mRnaFeature) = @_;

	# Initializations
	my $featureId = ($mRnaFeature->get_tag_values('ID'))[0];
	$self->{'geneModelsStatus'}->{$featureId} = 'conserved';

	# Check if the current mRNA feature possess at least one of the non authorized tag/attribute and flag it as "rejected" if that's the case
	foreach my $rejectedTag (@{$self->{'rejectedTags'}}) {
		if ($mRnaFeature->has_tag($rejectedTag)) {
			$self->{'geneModelsStatus'}->{$featureId} = 'rejected';
			last;
		}
	}

	return 0; # SUCCESS
}


sub _getParentIdentifier {

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
		$logger->logdie('A feature of type ' . $feature->primary_tag() . ' named ' . ($feature->get_tag_values('Name'))[0] . ' has no parent attribute !');
	}

	return 0;
}


sub _buildCodingSequenceObjects {

	# Recovers parameters
	my $self = shift;

	# Initializations
	$self->{'codingSequenceObjects'} = ();
	$self->{'numberOfBuiltSequences'} = {'conserved' => 0, 'rejected' => 0};

	$logger->info('');
	$logger->info('Coding sequences extraction:');

	# Build features
	foreach my $sequenceName (keys(%{$self->{'usefulFeatures'}})) {
		my $featureBySequenceCounter = 0;

		# Deal with the case where the input GFF file contains features about sequences that are not present in the Fasta input file
		# Note: this case should only happened when the GeneModel GFF file is an external GFF file coming from an external previous analysis (ie. TriAnnot_Post)
		if (! defined($self->{'fastaDatabase'}->get_Seq_by_id($sequenceName))) {
			$logger->info('  -> ' . 'Sequence "' . $sequenceName . '" referenced in the Gene Model GFF file does not exists in the Fasta input file and will therefore be ignored');
			next;
		}

		foreach my $parentName (keys(%{$self->{'usefulFeatures'}->{$sequenceName}})) {

			# Initializations
			my $codingSequence = "";

			# Get CDS/polypeptide features for the current gene/parent
			my @cdsFeatures = sort {$a->start <=> $b->start} (@{$self->{'usefulFeatures'}->{$sequenceName}->{$parentName}});

			# Get the gene strand of the current gene
			my $geneStrand = $cdsFeatures[0]->strand();

			# Get the complete coding sequence depending on the strand of the parent/gene
			if ($geneStrand == 1) {
				foreach my $cdsFeature (@cdsFeatures) {
					$codingSequence .= $self->{'fastaDatabase'}->seq($sequenceName, $cdsFeature->start(), $cdsFeature->end());
				}
			} else {
				foreach my $cdsFeature (reverse @cdsFeatures) {
					$codingSequence .= $self->{'fastaDatabase'}->seq($sequenceName, $cdsFeature->end(), $cdsFeature->start());
				}
			}

			# Build a valid Bio::Seq object
			my $codingSequenceObject = Bio::Seq->new( -id => $parentName, -alphabet => 'dna', -seq => $codingSequence, -desc => 'length=' . length($codingSequence) );

			# Add a custom attribute to the Bio::Seq object and increase the counters
			if ($self->{'geneModelsStatus'}->{$parentName} eq 'rejected') {
				$codingSequenceObject->{'needToBeRejected'} = 'yes';
				$self->{'numberOfBuiltSequences'}->{'rejected'}++;
			} else {
				$codingSequenceObject->{'needToBeRejected'} = 'no';
				$self->{'numberOfBuiltSequences'}->{'conserved'}++;
			}

			# Store the newly built object in the appropriate array
			push(@{$self->{'codingSequenceObjects'}}, $codingSequenceObject);

			# Increase the total number of feature for the current sequence
			$featureBySequenceCounter++
		}
		$logger->info('  -> ' . $featureBySequenceCounter . ' coding sequence(s) has/have been extracted from sequence "' . ucfirst($sequenceName) . '"');
	}

	# Get the total number of built sequences
	$self->{'numberOfBuiltSequences'}->{'total'} = $self->{'numberOfBuiltSequences'}->{'conserved'} + $self->{'numberOfBuiltSequences'}->{'rejected'};

	return 0;
}


sub _writeCdsSequences {

	# Recovers parameters
	my $self = shift;

	# Create 2 Bio::SeqIO objects (output streams)
	my $outputStreamConserved = Bio::SeqIO->new(-file => '>' . $self->{'cdsSequenceFileFullPath'}, -format => 'FASTA');
	my $outputStreamRejected = Bio::SeqIO->new(-file => '>' . $self->{'rejectedCdsSequenceFileFullPath'}, -format => 'FASTA');

	$logger->info('');
	$logger->info('CDS sequence files creation:');

	if ($self->{'numberOfBuiltSequences'}->{'total'} > 0) {
		$logger->info('  -> ' . $self->{'numberOfBuiltSequences'}->{'conserved'} . ' valid CDS sequence(s) will be written in the following file: ' . $self->{'cdsSequenceFileName'});
		$logger->info('  -> ' . $self->{'numberOfBuiltSequences'}->{'rejected'} . ' rejected CDS sequence(s) will be written in the following file: ' . $self->{'rejectedCdsSequenceFileName'});

		foreach my $codingSequenceObject (@{$self->{'codingSequenceObjects'}}){
			if ($codingSequenceObject->{'needToBeRejected'} eq 'yes') {
				$outputStreamRejected->write_seq($codingSequenceObject);
			} else {
				$outputStreamConserved->write_seq($codingSequenceObject);
			}
		}
	} else {
		$logger->info('  -> There is no CDS sequence to write..');
	}
}


sub _writeProteinSequences {

	# Recovers parameters
	my $self = shift;

	# Create a Bio::SeqIO object (output stream)
	my $outputStreamConserved = Bio::SeqIO->new(-file => '>' . $self->{'proteinSequenceFileFullPath'}, -format => 'FASTA');
	my $outputStreamRejected = Bio::SeqIO->new(-file => '>' . $self->{'rejectedProteinSequenceFileFullPath'}, -format => 'FASTA');

	$logger->info('');
	$logger->info('Translation procedure and protein sequence files creation:');

	if ($self->{'numberOfBuiltSequences'}->{'total'} > 0) {
		$logger->info('  -> ' . $self->{'numberOfBuiltSequences'}->{'conserved'} . ' valid protein sequence(s) will be generated and written in the following file: ' . $self->{'proteinSequenceFileName'});
		$logger->info('  -> ' . $self->{'numberOfBuiltSequences'}->{'rejected'} . ' rejected protein sequence(s) will be generated and written in the following file: ' . $self->{'rejectedProteinSequenceFileName'});

		foreach my $codingSequenceObject (@{$self->{'codingSequenceObjects'}}){
			my $translatedSequence = $codingSequenceObject->translate->seq();

			my $proteinSequenceObject = Bio::Seq->new( -id => $codingSequenceObject->display_id(), -alphabet => 'protein', -seq => $translatedSequence, -desc => 'length=' . length($translatedSequence) );

			if ($codingSequenceObject->{'needToBeRejected'} eq 'yes') {
				$outputStreamRejected->write_seq($proteinSequenceObject);
			} else {
				$outputStreamConserved->write_seq($proteinSequenceObject);
			}
		}
	} else {
		$logger->info('  -> There is no protein sequence to write..');
	}
}


######################
# Writing methods
######################

sub _writeInfoFile {

	# Recovers parameters
	my $self = shift;

	$logger->debug('');
	$logger->debug('Writing informative data about the generated proteic sequences in the following file: ' . $self->{'infoFileName'});

	# Writing data
	open(INFO, '>' . $self->{'infoFileFullPath'}) or $logger->logdie('Error: Cannot create/open file: ' . $self->{'infoFileName'});
	print INFO 'number_of_conserved_sequence=' . $self->{'numberOfBuiltSequences'}->{'conserved'} . ';';
	print INFO 'number_of_rejected_sequence=' . $self->{'numberOfBuiltSequences'}->{'rejected'} . ';';
	close(INFO);
}


############################
## New Files management
############################

sub _generatedFilesManagement {

	# Recovers parameters
	my $self = shift;

	# Create a symlink to the new informative file in the common tmp folder
	if (-e $self->{'infoFileFullPath'}) {
		$logger->debug('');
		$logger->debug('Note: Creation of a symlink to the newly generated informative file concerning the protein creation (' . $self->{'infoFileName'} . ') in the common tmp folder');
		symlink($self->{'infoFileFullPath'}, $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'tmp_files'} . '/' . $self->{'infoFileName'}) or $logger->logdie('Error: Cannot create a symlink to file: ' . $self->{'infoFileName'});
	}

	# Copy the new protein sequence files to the sequence folder (Copy instead of Move because the protein sequence file is also the ProteinMaker outFile and have to be present in the execution folder to avoid an ERROR status in the abstract file + we want to conserve sequence files)
	if (-e $self->{'proteinSequenceFileFullPath'}) {
		$logger->debug('');
		$logger->debug('Note: Copying of the newly generated protein sequence file of conserved gene models (in Fasta format) into the default sequence folder');
		copy($self->{'proteinSequenceFileFullPath'}, $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'sequence_files'} . '/' . $self->{'outFile'}) or $logger->logdie('Error: Cannot copy the newly generated protein sequence file of conserved gene models: ' . $self->{'outFile'});
	}

	if (-e $self->{'rejectedProteinSequenceFileFullPath'}) {
		$logger->debug('');
		$logger->debug('Note: Copying of the newly generated protein sequence file of rejected gene models (in Fasta format) into the default sequence folder');
		copy($self->{'rejectedProteinSequenceFileFullPath'}, $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'sequence_files'} . '/' . $self->{'rejectedProteinSequenceFileName'}) or $logger->logdie('Error: Cannot copy the newly generated protein sequence file of rejected gene models: ' . $self->{'rejectedProteinSequenceFileName'});
	}

	# Copy the new CDS sequence files to the sequence folder
	if (-e $self->{'cdsSequenceFileFullPath'}) {
		$logger->debug('');
		$logger->debug('Note: Copying of the newly generated CDS sequence file of conserved gene models (in Fasta format) into the default sequence folder');
		copy($self->{'cdsSequenceFileFullPath'}, $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'sequence_files'} . '/' . $self->{'cdsSequenceFileName'}) or $logger->logdie('Error: Cannot copy the newly generated CDS sequence file of conserved gene models: ' . $self->{'cdsSequenceFileName'});
	}

	if (-e $self->{'rejectedCdsSequenceFileFullPath'}) {
		$logger->debug('');
		$logger->debug('Note: Copying of the newly generated CDS sequence file of rejected gene models (in Fasta format) into the default sequence folder');
		copy($self->{'rejectedCdsSequenceFileFullPath'}, $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'sequence_files'} . '/' . $self->{'rejectedCdsSequenceFileName'}) or $logger->logdie('Error: Cannot copy the newly generated CDS sequence file of conserved gene models: ' . $self->{'rejectedCdsSequenceFileName'});
	}
}

1;
