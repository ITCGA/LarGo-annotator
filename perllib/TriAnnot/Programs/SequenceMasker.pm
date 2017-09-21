#!/usr/bin/env perl

package TriAnnot::Programs::SequenceMasker;

##################################################
## Documentation POD
##################################################

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
use Bio::Tools::RepeatMasker;

## Inherits
our @ISA = qw(TriAnnot::Programs::Programs);

##################################################
## Methods
##################################################
=head1 TriAnnot::Programs::SequenceMasker - Methods
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
	$self->{'input_file'}     = defined($attrs{'input_file'}) ? $attrs{'input_file'} : undef();
	$self->{'regionsToMask'}  = undef();
	$self->{'needParsing'}    = 'no';

	# Define $self as a $class type object
	bless $self => $class;

	return $self;
}


#############################################
## Parameters/variables initializations
#############################################

sub setParameters {
	my ($self, $parameters) = @_;

	# Call parent class method (See Programs.pm module for more information)
	$self->SUPER::setParameters($parameters);

	# Ouput related object attributes
	if (!defined($self->{'outFile'})) {
		$self->{'outFile'} = $self->{'masked_sequence'}
	};

	# Store some path and names in the current object for easier access
	$self->_managePathsAndNames();

	# Checks
	if (!defined($self->{'input_file'})) {
		$logger->logdie('Error: input_file parameter is not defined !');
	}
}


sub _managePathsAndNames {

	# Recovers parameters
	my $self = shift;

	# The main output file is actually the masked sequence file
	$self->{'outFile'} = $self->{'masked_sequence'};
	$self->{'outFileFullPath'} = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' .$self->{'outFile'};

	# Directories and files - Names
	$self->{'gffDirName'} = $TRIANNOT_CONF{'DIRNAME'}->{'GFF_files'};
	$self->{'extraFilesDirName'} = $TRIANNOT_CONF{'DIRNAME'}->{'keep_files'};
	$self->{'commonsDirName'} = $TRIANNOT_CONF{'DIRNAME'}->{'tmp_files'};
	$self->{'sequenceDirName'} = $TRIANNOT_CONF{'DIRNAME'}->{'sequence_files'};

	my ($OutFileNameWithoutExtension, $base, $ext) = fileparse($self->{'outFile'}, qr/\.[^.]*/);
	$self->{'infoFileName'} = $OutFileNameWithoutExtension . '.info';
	$self->{'igFileName'} = $OutFileNameWithoutExtension . '.ig';
	$self->{'globalXmFileName'} = 'Global_XM_for_' . $OutFileNameWithoutExtension . '.xm';

	# Directories and files - Full paths
	$self->{'gffDirPath'} = $self->{'directory'} . '/' . $self->{'gffDirName'};
	$self->{'extraFilesDirPath'} = $self->{'directory'} . '/' . $self->{'extraFilesDirName'};
	$self->{'commonsDirPath'} = $self->{'directory'} . '/' . $self->{'commonsDirName'};
	$self->{'sequenceDirPath'} = $self->{'directory'} . '/' . $self->{'sequenceDirName'};

	$self->{'infoFileFullPath'} = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' .$self->{'infoFileName'};
	$self->{'igFileFullPath'} = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' .$self->{'igFileName'};
	$self->{'globalXmFileFullPath'} = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' .$self->{'globalXmFileName'};
}


###############################
# File check related methods
###############################

sub _checkInputFiles {

	# Recovers parameters
	my $self = shift;

	# Check the existence of the input files defined with the input_file parameter
	foreach my $inputFile (@{$self->{'input_file'}}) {
		if ($self->{'input_type'} eq 'Tallymer') {
			$self->_checkFileExistence('Tallymer', $self->{'extraFilesDirPath'} . '/' . $inputFile);
		} elsif ($self->{'input_type'} eq 'XM') {
			$self->_checkFileExistence('XM', $self->{'commonsDirPath'} . '/' . $inputFile);
		} else {
			$self->_checkFileExistence('GFF', $self->{'gffDirPath'} . '/' . $inputFile);
		}
	}
}


#############################
## Counter management
#############################

sub _resetSuccesiveUnmaskedCounter {

	# Recovers parameterd
	my $self = shift;

	# Counter reset
	if ($self->{'_cptSuccessiveUnmasked'} > $self->{'maxSuccessiveUnmasked'}) {
		$self->{'maxSuccessiveUnmasked'} = $self->{'_cptSuccessiveUnmasked'};
	}
	$self->{'_cptSuccessiveUnmasked'} = 0;
}


sub _initCounters {

	# Recovers parameters
	my $self = shift;

	# Initialize some counters (Object attributes)
	$self->{sequenceLength} = 0;
	$self->{cptNewlyMasked} = 0;
	$self->{cptAlreadyMasked} = 0;
	$self->{maxSuccessiveUnmasked} = 0;
	$self->{_currentPositon} = 0;
	$self->{_firstRegionIndex} = 0;
	$self->{_cptSuccessiveUnmasked} = 0;
}


#####################
## Method execute() #
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	$self->_initCounters();

	# Initializations
	my $Common_tmp_folder = $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'tmp_files'};

	# Log
	$logger->info('');
	$logger->info('Regions to mask will be collected in at least one ' . $self->{'input_type'} . ' file');
	$logger->info('Masking mode is set to: ' . $self->{'masking_mode'});
	$logger->info('Masking letter will be: ' . $self->{'masking_letter'}) if ($self->{'masking_mode'} eq 'use_masking_letter');
	$logger->info('');

	# Define regions to mask
	if ($self->{'input_type'} eq 'XM') {
		# Fusion of all XM input files if needed
		$self->createGlobalXMFile() if ($self->{'generate_global_XM_file'} eq 'yes');

		# Define the regions to mask on the input sequence from the content of the global XM file
		$self->setRegionsToMaskFromXmFiles();

		# Remove the simple XM files after usage if requested
		$self->removeSimpleXmFiles() if ($self->{'remove_simple_XM_files'} eq 'yes');

	} elsif ($self->{'input_type'} eq 'GFF') {
		# Define the regions to mask on the input sequence from the coordinates of all feature of type $self->{'feature_type'} of the input GFF file
		$self->setRegionsToMaskFromGffFiles($self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'GFF_files'} . '/' . $self->{'input_file'}, $self->{'feature_type'});

	} elsif ($self->{'input_type'} eq 'Tallymer') {
		# Define the regions to mask on the input sequence from the coordinates of all k-mers of the input tallymer file that are over a given threshold
		$self->setRegionsToMaskFromTallymerFiles();
	}

	# Masking procedure
	$self->writeMaskedSequenceToFile();

	# Creation of a temporary file that contains informations about the masked sequence
	$self->saveMaskingInformations();

	# Creation of an optionnal file for Eugene execution if needed
	if ($self->{'generate_IG_file'} eq 'yes' && !-e $Common_tmp_folder . '/' . $self->{'igFileName'}) {
		$self->CreateIgFileForEugene();
	}
}


########################
## XM file management
########################

sub createGlobalXMFile {

	# Recovers parameters
	my $self = shift;

	$logger->info('Global XM file creation:');

	# Creation of the fusion file
	open(MERGE, '>' . $self->{'globalXmFileFullPath'}) || $logger->logdie('Error: Cannot create/open file: ' . $self->{'globalXmFileFullPath'});

	foreach my $inputXmFile (@{$self->{'input_file'}}) {
		$logger->debug("\t" . 'Merging ' . $inputXmFile . ' into ' . $self->{'globalXmFileName'});

		# Add the content of the current simple XM file to the global XM file
		open(TEMPO, '<' . $self->{'commonsDirPath'} . '/' . $inputXmFile) || $logger->logdie('Error: Cannot open/read file: ' . $self->{'commonsDirPath'} . '/' . $inputXmFile);
		while (<TEMPO>) { print MERGE $_; }
		close(TEMPO);
	}

	close(MERGE);
}


sub removeSimpleXmFiles {

	# Recovers parameters
	my $self = shift;

	# Unlink XM input files from the common tmp folder
	foreach my $inputXmFile (@{$self->{'input_file'}}) {
		unlink($self->{'commonsDirPath'} . '/' . $inputXmFile) or $logger->logdie('Error: Cannot delete the following file: ' . $self->{'commonsDirPath'} . '/' . $inputXmFile);
	}

	return 0; # SUCCESS
}


#############################
## Get/Set regions to mask
#############################

sub setRegionsToMaskFromXmFiles {

	# Recovers parameters
	my $self = shift;

	# Initializations
	$self->{'regionsToMask'} = [];

	# Log
	$logger->info('');
	$logger->info('Setting regions to mask from the selected RepeatMasker XM files');

	# Loop through the list of XM files
	foreach my $inputXmFile (@{$self->{'input_file'}}) {
		$logger->info('   -> Extracting regions from file ' . $inputXmFile);

		# Creation of a new BioPerl object for RepeatMasker results parsing
		my $repeatmasker = Bio::Tools::RepeatMasker->new(-file => $self->{'commonsDirPath'} . '/' . $inputXmFile);

		# Extract region to masking from the global XM file
		while (my $parserRes = $repeatmasker->next_result()) {
			my $queryInfo = $parserRes->feature1;

			if ($queryInfo->end() < $queryInfo->start()) {
				push(@{$self->{'regionsToMask'}}, {start => $queryInfo->end(), end => $queryInfo->start()});
			} else {
				push(@{$self->{'regionsToMask'}}, {start => $queryInfo->start(), end => $queryInfo->end()});
			}
		}
	}

	$self->_sortRegionsToMask();
	$self->_mergeOverlappingRegionsToMask();
}


sub setRegionsToMaskFromTallymerFiles {

	# Recovers parameters
	my $self = shift;

	# Initializations
	$self->{'regionsToMask'} = [];

	# Log
	$logger->info('Setting regions to mask from the selected GT Tallymer files');

	# Loop through the list of Tallymer files
	foreach my $inputTallymerFile (@{$self->{'input_file'}}) {
		$logger->info('   -> Extracting regions from file ' . $inputTallymerFile);

		# Read each line of the tallymer output file to extract k-mers positions (Positions of a mer are collected if the number of occurence of a mer is over the defined threshold)
		open (MDR, '<' . $self->{'extraFilesDirPath'} . '/' . $inputTallymerFile) or $logger->logdie('Error: Cannot open/read file: ' . $self->{'extraFilesDirPath'} . '/' . $inputTallymerFile);
		while (my $line = <MDR>) {

			if ($line =~ /^$/ || $line =~ /^#/) { next;	}

			my ($start_position, $nb_occurrence , $mer_sequence) = split(/\t/, $line);

			if (($nb_occurrence >= $self->{'masking_threshold'}) && ($start_position > 0)){
				$start_position=~ s/\+//g;
				push(@{$self->{'regionsToMask'}}, {start => $start_position+1, end => $start_position+17});
			}
		}
		close (MDR);
	}

	$self->_sortRegionsToMask();
	$self->_mergeOverlappingRegionsToMask();
}


sub setRegionsToMaskFromGffFiles {

	# Recovers parameters
	my $self = shift;

	# Initializations
	$self->{'regionsToMask'} = [];

	# Log
	$logger->info('Setting regions to mask from the selected GFF files');

	# Loop through the list of Tallymer files
	foreach my $inputGffFile (@{$self->{'input_file'}}) {
		$logger->info('   -> Extracting regions from file ' . $inputGffFile);

		# Read each line of the selected GFF file and extract start/stop positions of each feature of a valid type (Valid types are defined with the "feature_type" parameter)
		open (GFF, '<' . $self->{'gffDirPath'} . '/' . $inputGffFile) or $logger->logdie('Error: Cannot open/read file: ' . $self->{'gffDirPath'} . '/' . $inputGffFile);
		while (my $line = <GFF>) {
			# Skip empty and comment lines
			if ($line =~ /^$/ || $line =~ /^#/) { next;	}

			my ($seqid, $source, $type, $start, $end, $score, $strand, $phase, $attributes) = split(/\t/, $line);

			if (grep {$type eq $_} @{$self->{'feature_type'}}) {
				# Current type is in the list of types to treat
				if ($start > $end){
					push(@{$self->{'regionsToMask'}}, {start => $end, end => $start});
				} else {
					push(@{$self->{'regionsToMask'}}, {start => $start, end => $end});
				}
			}
		}
		close (GFF);
	}

	$self->_sortRegionsToMask();
	$self->_mergeOverlappingRegionsToMask();
}


sub getRegionsToMask {

	# Recovers parameters
	my $self = shift;

	# Accessor to the regionsToMask object attribute
	return @{$self->{'regionsToMask'}};
}


################################################
## Sort and clean the list of regions to mask
################################################

sub _mergeOverlappingRegionsToMask {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my @tempRegionsToMask = ();
	my ($previousStart, $previousEnd) = (-100, -100);

	# Merging of overlapping regions
	foreach my $region (@{$self->{'regionsToMask'}}) {
		# If explanation:
		# Merging case:
		#   1: 1----108 et 109----200 --> fusion: 1----200
		#   2: 1----108 et 100----150 --> fusion: 1----150
		# New element case:
		#   1----108 et 500----700 --> Adding of 500----700 to the final table
		# Rejected case: (ignore region)
		#   1----1000 et 50----625 --> No merging because the second element is fully integrated in the first element
		if( ($region->{'start'} == $previousEnd + 1) ||
		    ( ($region->{'start'} <= $previousEnd) && ($region->{'end'} > $previousEnd) ) ) { # Merging case
			pop(@tempRegionsToMask); # Remove the last element of the final table
			push(@tempRegionsToMask, {start => $previousStart, end => $region->{'end'}}); # Add the new "fusion element" to the final table

			$previousEnd = $region->{'end'};
		} elsif ($region->{'start'} > $previousEnd + 1) { # New element case
			push(@tempRegionsToMask, $region); # Add the new "fusion element" to the final table

			$previousStart = $region->{'start'};
			$previousEnd = $region->{'end'};
		}
	}

	# Update the list of regions to mask
	$self->{'regionsToMask'} =  \@tempRegionsToMask;
}


sub _sortRegionsToMask {

	# Recovers parameters
	my $self = shift;

	# Sort region to mask with a custom sort rule (sort by start positions)
	my @sortedPositions = sort {$a->{'start'} <=> $b->{'start'}} @{$self->{'regionsToMask'}};

	# Update the list of regions to mask
	$self->{'regionsToMask'} = \@sortedPositions;
}


###################################################################
## Masked sequence file creation (+ IG file creation for Eugene)
###################################################################

sub writeMaskedSequenceToFile {

	# Recovers parameters
	my $self = shift;

	# Initializations
	$self->_initCounters();
	my $maskedSequenceAsString = '';

	$logger->info('');
	$logger->info('Writing of the masked sequence in the following file: ' . $self->{'outFile'});

	# Create a fasta input stream
	my $inputStream = Bio::SeqIO->new(-format => 'FASTA', -file => $self->{'fullSequencePath'});

	# Create a fasta output stream
	my $outputStream = Bio::SeqIO->new(-file => '>' . $self->{'outFile'}, -format => 'FASTA');

	# Building of the masked sequence from the input sequence
	my $currentSequence = $inputStream->next_seq();

	# Split the sequence and work on each base
	foreach my $base (split(//, $currentSequence->seq())) {
		$self->{'_currentPositon'}++;
		if ($self->_isBaseAlreadyMasked($base)) {
			$self->{'cptAlreadyMasked'}++;
			$base = $self->_getMaskedBase($base);
			$self->_resetSuccesiveUnmaskedCounter();
		} elsif ($self->_needToMaskBase()) {
			$self->{'cptNewlyMasked'}++;
			$base = $self->_getMaskedBase($base);
			$self->_resetSuccesiveUnmaskedCounter();
		} else {
			$self->{'_cptSuccessiveUnmasked'}++;
		}
		$maskedSequenceAsString .= $base;
	}

	# Build the new sequence object
	$self->{'sequenceLength'} = $self->{'_currentPositon'};
	my $description = 'length=' . $self->{'sequenceLength'} . ';already_masked=' . $self->{'cptAlreadyMasked'} . ';newly_masked=' . $self->{'cptNewlyMasked'};
	my $maskedSequenceObject = Bio::Seq->new( -id => $currentSequence->display_id(), -alphabet => 'dna', -seq => $maskedSequenceAsString, -desc => $description );

	# Write translated sequence on the output stream
	$outputStream->write_seq($maskedSequenceObject);

	# Reset counters
	$self->_resetSuccesiveUnmaskedCounter();

	return 0; # SUCCESS
}


sub _needToMaskBase {

	# Recovers parameters
	my $self = shift;

	# Determine if the current base must be masked or not
	for (my $i = $self->{'_firstRegionIndex'}; $i < scalar(@{$self->{'regionsToMask'}}); $i++) {
		if ($self->{'_currentPositon'} < $self->{'regionsToMask'}->[$i]->{'start'}) {
			# current position is below the start of region to mask
			return 0; # no need to mask
		}
		if ($self->{'_currentPositon'} > $self->{'regionsToMask'}->[$i]->{'end'}) {
			# current position is over the end of region to mask,
			# we can ignore this region for the rest of the algorithm
			$self->{'_firstRegionIndex'}++;
			next;
		}
		return 1; # Need to mask
	}

	return 0; # No need to mask
}


# Return true if the base is already masked (ie. lower case letter or masking_letter),
# false otherwise
sub _isBaseAlreadyMasked {

	# Recovers parameters
	my ($self, $base) = @_;

	# A given base is considered as already masked if it is equal to the masking_letter or written in lower case (depending on the masking mode)
	if ($self->{'masking_mode'} eq 'convert_to_lowercase' && $base eq lc($base)) {
		return 1; # Already masked
	} elsif ($self->{'masking_mode'} eq 'use_masking_letter' && $base eq $self->{'masking_letter'}) {
		return 1; # Already masked
	}

	return 0; # Not masked
}


# Return the character corresponding to the masked base according to mask mode
sub _getMaskedBase {

	# Recovers parameters
	my ($self, $base) = @_;

	# Depending on the masking mode a masked base can be a N character or the base letter in lower case
	if($self->{'masking_mode'} eq 'convert_to_lowercase') {
		return lc($base);
	} else {
		return $self->{'masking_letter'};
	}
}


sub CreateIgFileForEugene {

	# Recovers parameters
	my $self = shift;

	$logger->debug('Storing of the coordinates of masked regions of sequence ' . $self->{'sequence'} . ' in file ' . $self->{'igFileName'} . ' for future use in Eugene module');

	# File creation
	open(IG, '>' . $self->{'igFileFullPath'}) or $logger->logdie('Error: Cannot create/open file: ' . $self->{'igFileFullPath'});
	foreach my $region (@{$self->{'regionsToMask'}}) {
		print IG $region->{'start'} . "\t" . $region->{'end'} . "\n";
	}
	close(IG);

	return 0; # Success
}

##############################################################
## Collect and save information about the masking procedure
##############################################################

sub getMaskingInfo {

	# Recovers parameters
	my  $self = shift;

	return 'number_of_base=' . $self->{'sequenceLength'} . ';' .
	       'already_masked=' . $self->{'cptAlreadyMasked'} . ';' .
	       'newly_masked=' . $self->{'cptNewlyMasked'} . ';' .
	       'total_number_masked=' . ($self->{'cptAlreadyMasked'} + $self->{'cptNewlyMasked'}) . ';' .
	       'percent_mask=' . sprintf("%.2f", $self->getPercentMasked()) . ';' .
	       'max_successive_unmasked=' . $self->{'maxSuccessiveUnmasked'} . ';' .
	       'percent_already_masked=' . sprintf("%.2f", $self->getPercentAlreadyMasked());
}


sub saveMaskingInformations {

	# Recovers parameters
	my $self = shift;

	$logger->info('');
	$logger->info('Saving masking information for masked sequence ' . $self->{'outFile'} . ' into temporary file "' . $self->{'infoFileName'} . '"');

	open(MASK_INFO, '>' . $self->{'infoFileFullPath'}) or $logger->logdie('Error: Cannot create/open file: ' . $self->{'infoFileFullPath'});
	print MASK_INFO $self->getMaskingInfo();
	close(MASK_INFO);
}


sub getPercentAlreadyMasked {

	# Recovers parameters
	my $self = shift;

	# Compute and return the pourcentage of already masked bases before the masking procedure start
	return ($self->{'cptAlreadyMasked'} / $self->{'sequenceLength'}) * 100;
}


sub getPercentMasked {

	# Recovers parameters
	my $self = shift;

	# Compute and return the pourcentage of masked bases after the masking procedure
	return (($self->{'cptNewlyMasked'} + $self->{'cptAlreadyMasked'}) / $self->{'sequenceLength'}) * 100;
}


#####################
## New Files management
#####################

sub _generatedFilesManagement {

	# Recovers parameters
	my $self = shift;

	# Create a symlink to the new IG file in the common tmp folder
	if (-e $self->{'igFileFullPath'}) {
		$logger->debug('');
		$logger->debug('Note: Creation of a symlink to the newly generated IG file for Eugene (' . $self->{'igFileName'} . ') in the common tmp folder');
		symlink($self->{'igFileFullPath'}, $self->{'commonsDirPath'} . '/' . $self->{'igFileName'}) or $logger->logdie('Error: Cannot create a symlink to file: ' . $self->{'igFileName'});
	}

	# Create a symlink to the new informative file in the common tmp folder
	if (-e $self->{'infoFileFullPath'}) {
		$logger->debug('');
		$logger->debug('Note: Creation of a symlink to the newly generated informative file concerning the masking procedure (' . $self->{'infoFileName'} . ') in the common tmp folder');
		symlink($self->{'infoFileFullPath'}, $self->{'commonsDirPath'} . '/' . $self->{'infoFileName'}) or $logger->logdie('Error: Cannot create a symlink to file: ' . $self->{'infoFileName'});
	}

	# Copy the new masked sequence to the sequence folder (Copy instead of Move because the sequence file is also the SequenceMasker outFile and have to be present in the execution folder to avoid an ERROR status in the abstract file)
	if (-e $self->{'outFileFullPath'}) {
		$logger->debug('');
		$logger->debug('Note: Copying of the newly generated masked sequence (in Fasta format) into the default sequence folder');
		copy($self->{'outFileFullPath'}, $self->{'sequenceDirPath'} . '/' . $self->{'outFile'}) or $logger->logdie('Error: Cannot copy the newly generated masked sequence file: ' . $self->{'outFile'});
	}

	# Move the global XM file to the long term conservation directory if needed
	if (-e $self->{'globalXmFileFullPath'}) {
		$logger->debug('');
		$logger->debug('Note: Moving of the newly generated global XM file into the ' . $TRIANNOT_CONF{DIRNAME}->{'keep_files'} . ' folder for long term conservation');
		move($self->{'globalXmFileFullPath'}, $self->{'extraFilesDirPath'} . '/' . $self->{'globalXmFileName'}) or $logger->logdie('Error: Cannot move the newly generated global XM file: ' . $self->{'globalXmFileName'});
	}
}

1;
