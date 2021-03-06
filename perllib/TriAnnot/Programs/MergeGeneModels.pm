#!/usr/bin/env perl

package TriAnnot::Programs::MergeGeneModels;

## Perl modules
use strict;
use warnings;
use diagnostics;

# CPAN modules
use File::Basename;
use File::Copy;
use File::Copy::Recursive;
use Data::Dumper;
use Clone;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Programs::Programs;
use TriAnnot::Tools::Logger;

## BioPerl modules
use Bio::Tools::GFF;
use Bio::SeqIO;
use Bio::SearchIO;

## Inherits
our @ISA = qw(TriAnnot::Programs::Programs);


##################################################
## Methods
##################################################

=head1 TriAnnot::Programs::MergeGeneModels - Methods
This module aim to select the best gene model for one given locus.
Input is a list of GFF file and output a GFF file with only one CDS per locus.
=cut

###################
# Constructor
###################

=head2 new

=cut

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class (TriAnnot::Programs::Programs)
	my $self = $class->SUPER::new(\%attrs);

	bless $self => $class;

	return $self;
}


#############################################
## Parameters/variables initializations
#############################################

=head2 setParameters
Retrieve the parent parameters.
=cut

sub setParameters {
	my ($self, $parameters) = @_;

	# Call parent class method (See Programs.pm module for more information)
	$self->SUPER::setParameters($parameters);

	# Additional parameters
	$self->{'evidenceParameterNames'} = ['proteicEvidences', 'highQualityNucleicEvidences', 'otherNucleicEvidences'];

	# Specific parameter check
	if($self->{validationRange}%3 != 0){
		$logger->logdie('ERROR: The validationRange option must be a multiple of 3.');
	}

	# Store some path and names in the current object for easier access
	$self->_managePathsAndNames();
}


sub _managePathsAndNames {

	# Recovers parameters
	my $self = shift;

	# Files and directories names
	$self->{'gffDirName'} = $TRIANNOT_CONF{'DIRNAME'}->{'GFF_files'};
	$self->{'emblDirName'} = $TRIANNOT_CONF{'DIRNAME'}->{'EMBL_files'};
	$self->{'commonsDirName'} = $TRIANNOT_CONF{'DIRNAME'}->{'tmp_files'};

	# Full paths
	$self->{'fastaDirPath'} = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'emblSubDirectoryForFastaFiles'}; # sub directory of the execution directory
	$self->{'blastpDirPath'} = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'emblSubDirectoryForBlastFiles'}; # sub directory of the execution directory

	$self->{'gffDirPath'} = $self->{'directory'} . '/' . $self->{'gffDirName'};
	$self->{'emblDirPath'} = $self->{'directory'} . '/' . $self->{'emblDirName'};
	$self->{'commonsDirPath'} = $self->{'directory'} . '/' . $self->{'commonsDirName'};

	$self->{'emblFastaSubDirPath'} = $self->{'emblDirPath'} . '/' . $self->{'emblSubDirectoryForFastaFiles'}; # sub directory of the EMBL directory
	$self->{'emblBlastSubDirPath'} = $self->{'emblDirPath'} . '/' . $self->{'emblSubDirectoryForBlastFiles'}; # sub directory of the EMBL directory

	$self->{'gffTranspoFilePath'} = $self->{'gffDirPath'} . '/' . $self->{'gffForTranspoLikeGeneModels'};
	$self->{'outputFilePath'} = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' .$self->{'outFile'};
}


###################################
## Parameters and files check
###################################

=head2 _checkInputFiles
Check the existence of all the input files given in the step.xml file.
Check the existence of the Blast database given in the step.xml file.
=cut

sub _checkInputFiles {

	# Recovers parameters
	my $self = shift;

	# Define list of category to check
	my @categoryToCheck = @{$self->{'evidenceParameterNames'}};
	push (@categoryToCheck, 'automaticPredictions');

	# Check GFF file containing manually curated predictions if needed
	if (defined($self->{'manuallyCuratedPrediction'})) {
		$logger->debug('Checking the existence of file ' . $self->{'manuallyCuratedPrediction'} . ' (manually curated)');
		$self->_checkFileExistence('GFF', $self->{'gffDirPath'} . '/' . $self->{'manuallyCuratedPrediction'});
	}

	# Check all other GFF input files
	foreach my $category (@categoryToCheck) {
		foreach my $fileToCheck (@{$self->{$category}}) {
			$logger->debug('Checking the existence of file ' . $fileToCheck . ' from category ' . $category);
			$self->_checkFileExistence('GFF', $self->{'gffDirPath'} . '/' . $fileToCheck);
		}
	}
}


##################################
## Execution related methods
##################################

=head2 _prepareFilesBeforeExec
Create all the symlink of the given files.
Create the fasta and blastp folders.
=cut

#sub _prepareFilesBeforeExec {
sub	_beforeExec {

	# Recovers parameters
	my $self = shift;

	# Initialization
	$self->{'fileList'} = ();
	my $index = 1;

	# Call parent class method
	$self->SUPER::_beforeExec();

	# Deal with manually curated predictions
	if (defined($self->{'manuallyCuratedPrediction'})) {
		symlink($self->{'gffDirPath'} . '/' . $self->{'manuallyCuratedPrediction'}, '00.gff');
		$logger->debug('Selected manually curated prediction file: ' . $self->{'manuallyCuratedPrediction'});
	} else {
		open(MANUAL,'>00.gff') or $logger->logdie('Cannot create file 00.gff');
		close MANUAL;
	}
	push(@{$self->{fileList}},'00.gff');

	# Deal with in silico predictions
	foreach my $automaticPrediction (@{$self->{'automaticPredictions'}}) {
		$logger->debug('Selected automatic prediction file: ' . $automaticPrediction);
		my $symlinkName = ($index < 10) ? '0' . $index . '.gff' :  $index . '.gff';
		symlink($self->{'gffDirPath'} . '/' . $automaticPrediction, $symlinkName);
		push(@{$self->{fileList}}, $symlinkName);
		$index++;
	}

	# Generate needed sub directories
	mkdir $self->{'fastaDirPath'} if (! -e $self->{'fastaDirPath'});
	mkdir $self->{'blastpDirPath'} if (! -e $self->{'blastpDirPath'});
}


=head2 _execute
This method is called by the parent object to launch the execution.
Steps are:
=over 3
=item 1.
Prepare GFF files for merging.
=item 2.
Retrieve biological evidences from exonerate alignments.
=item 3.
Foreach GFF file to merge, build CDSs and filter them out.
=item 4.
Select the best gene model contained in each file.
=item 5.
Generate the final GFF file.
=cut

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Retrieve the sequence as an Bio::Seq object for futher use.
	$self->{'sequenceObject'} = $self->_retrieveSequence($self->{'fullSequencePath'});

	# Some log
	$logger->info('The selected database for blastp analysis is: ' . $self->{'database'});
	if (defined($self->{'databaseNamesForExpressionCheck'}) && scalar($self->{'databaseNamesForExpressionCheck'}) > 0) {
		$logger->info('The selected database(s) for expression check is/are: ' . join(',', @{$self->{'databaseNamesForExpressionCheck'}}));
	}
	$logger->info('');

	# Deal with biological evidence files
	$self->_retrieveBiologicalEvidences();

	# Build and Validate macro CDS features
	$logger->info('Building macro CDS features from prediction files..');

	for(my $i=0; $i<=$#{$self->{fileList}};$i++){

		$self->{_currentFileLevel} = $i ;

		if (-z $self->{fileList}[$self->{_currentFileLevel}] ) { next ; }

		$self->_buildCdsFromGff();

		$self->_validateAndFilterCds();
	}

	# Delete the evidences hash from self because it won't be used anymore
	delete $self->{evidences};

	# Choose best Gene Models
	$self->_selectGeneModel();

	# Generate the final GFF file
	if(defined($self->{finalCDSList})){
		$self->_seekForTransposases();
		$self->_generateOutputFiles();
	} else{
		open(EMPTY,">" . $self->{'outFile'}) or $logger->logdie('Cannot create an empty output file');
		close EMPTY;
	}
}


#################################################################
## Biological evidences extraction/recovery related methods
#################################################################

=head2 _retrieveBiologicalEvidences
=cut

sub _retrieveBiologicalEvidences {

	# Recovers parameters
	my $self = shift;

	$logger->info('Retrieving Biological evidences..');

	# Collect High Quality Nucleic evidences
	foreach my $fileCategory (@{$self->{'evidenceParameterNames'}}) {
		foreach my $evidenceFile (@{$self->{$fileCategory}}) {
			$logger->info('  -> Loading evidences (' . $fileCategory . ') from the following file: ' . $evidenceFile);

			if ($evidenceFile =~ /^(\d+)_([^_]+)_(.+)\..+$/) { # Step number, tool name and database name should be catched by the capture groups
				$self->{'evidences'}->{$fileCategory}->{$3}->{features} = $self->_retrieveExonerateFeatures($self->{'gffDirPath'} . '/' . $evidenceFile);
			} else {
				$logger->logdie('Error: Database name cannot be extracted from the name of the evidence file (' . $evidenceFile . ')..');
			}
		}
	}
}


=head2 _retrieveExonerateFeatures
=cut

sub _retrieveExonerateFeatures{
	my ($self,$file) = @_;
	my @return;
	my $gffIO = Bio::Tools::GFF->new(-file => $file, -gff_version => 3, -verbose => -1);
	my $feature;
	my $hashFeatures;

	while($feature = $gffIO->next_feature()){
		my $parentId = $self->_getParentID($feature);
		if($parentId ne '0'){
			push(@{$hashFeatures->{$parentId}},$feature);
		}
	}

	foreach my $pId (keys(%{$hashFeatures})){
		foreach my $ft (sort {$a->start <=> $b->end} (@{$hashFeatures->{$pId}})){
			if(defined($self->{_locations}->{$pId})){
				$self->{_locations}->{$pId}->add_sub_Location( Bio::Location::Simple->new ('-start' => $ft->start, '-end' => $ft->end, '-strand' => $ft->strand));
			} else {
				$self->{_locations}->{$pId} = Bio::Location::Split->new;
				$self->{_locations}->{$pId}->add_sub_Location( Bio::Location::Simple->new ('-start' => $ft->start, '-end' => $ft->end, '-strand' => $ft->strand));
			}
		}
		my $newObj = new Bio::SeqFeature::Generic ( -location	=> $self->{_locations}->{$pId});
		push(@return,$newObj);
	}
	$self->{_locations}=undef;
	return \@return;
}


####################################################################################
## In Silico Predictions loading & Macro CDS features building related methods
####################################################################################

=head2 _buildCdsFromGff
This sub builds the CDS feature from the structure of originalFeatureObjects using polypeptides subfeatures.
=cut

sub _buildCdsFromGff {
	my ($self) = @_;

	$self->_retrieveAnnotationFromGff();

	foreach my $geneID (keys(%{$self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}})){
		foreach my $mRnaID (keys(%{$self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}})){
			if($mRnaID eq 'gene'){next;}

			#~ Check what type of feature to use to construct the CDS.
			my $ftType='';

			if(defined($self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}->{$mRnaID}->{polypeptide})){
				$ftType = 'polypeptide';
				$logger->debug('Building CDS with ' . $ftType . ' subfeatures.' );
			}
			elsif(defined($self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}->{$mRnaID}->{match_part})){
				$ftType = 'match_part';
				$logger->debug('Building CDS with ' . $ftType . ' subfeatures.' );
			}
			else{
				$logger->warn('This feature with id: ' . $mRnaID . ' neither have polypeptide nor match_part subfeatures. Next...' );
				next;
			}

			# Sorting polypeptide features (the match_part case should not happen but the if statement is kept by security)
			@{$self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}->{$mRnaID}->{$ftType}} = (sort { $a->start <=> $b->start} (@{$self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}->{$mRnaID}->{$ftType}}));

			# Exon features must also be reordered to avoid errors in the method that update the feature coordinates when a new start or stop codon is found
			if(defined($self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}->{$mRnaID}->{'exon'})){
				@{$self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}->{$mRnaID}->{'exon'}} = (sort { $a->start <=> $b->start} (@{$self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}->{$mRnaID}->{'exon'}}));
			}

			for(my $i=0; $i<=$#{$self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}->{$mRnaID}->{$ftType}}; $i++){
				if(defined($self->{_locations}->{$mRnaID})){
					$self->{_locations}->{$mRnaID}->add_sub_Location( Bio::Location::Simple->new ( 	'-start' => ($self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}->{$mRnaID}->{$ftType}[$i])->start,
																											'-end' => ($self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}->{$mRnaID}->{$ftType}[$i])->end,
																											'-strand' => ($self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}->{$mRnaID}->{$ftType}[$i])->strand ) );
				}
				else{
					$self->{_locations}->{$mRnaID} = Bio::Location::Split->new ;
					$self->{_locations}->{$mRnaID}->add_sub_Location( Bio::Location::Simple->new ( 	'-start' => ($self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}->{$mRnaID}->{$ftType}[$i])->start,
																											'-end' => ($self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}->{$mRnaID}->{$ftType}[$i])->end,
																											'-strand' => ($self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}->{$mRnaID}->{$ftType}[$i])->strand ) );
				}
			}
			foreach my $id (keys(%{$self->{_locations}})){
				my $locus_tag = $id . '_CDS' ;
				$self->{predictions}->{$self->{_currentFileLevel}}->{cds}->{$id} = new Bio::SeqFeature::Generic ( -location	=> $self->{_locations}->{$id},
																	-primary => 'CDS',
																	-tag	=> { 	'locus_tag' => $locus_tag,
																					'Derives_from'	=>	$id,
																					}
																	);
				$self->{predictions}->{$self->{_currentFileLevel}}->{cds}->{$id}->{geneid} = $geneID;
				$self->{predictions}->{$self->{_currentFileLevel}}->{cds}->{$id}->{mrnaid} = $mRnaID;
				$self->{predictions}->{$self->{_currentFileLevel}}->{cds}->{$id}->{fileLevel} = $self->{_currentFileLevel};
			}

			delete $self->{_locations};
		}
	}
}


=head2 _retrieveAnnotationFromGff
This sub is able to read a GFF file pass as argument to MergeGeneModels.pm. Build a structure to store the original information
until the end of the script (_generateOutputFiles).
$self->{ fileLevel }->{ originalFeatureObjects }->{ geneID }->{gene}		=> the gene feature.
$self->{ fileLevel }->{ originalFeatureObjects }->{ geneID }->{mRnaID}->{mRNA}		=> the mRNA feature.
$self->{ fileLevel }->{ originalFeatureObjects }->{ geneID }->{mRnaID}->{exon}		=> the array of exons features.
$self->{ fileLevel }->{ originalFeatureObjects }->{ geneID }->{mRnaID}->{polypeptide}		=> the array of polypeptides features.
This structure migth be able to store multiple mRNA for one gene (alternative splicing) but hasn't been tested since TriAnnot is not
able to predict them. Also the sub _selectGeneModel is made to select only one CDS per locus.
=cut

sub _retrieveAnnotationFromGff {
	my ($self) = @_ ;

	$logger->debug('Retrieving predictions from file: ' . $self->{fileList}[$self->{_currentFileLevel}]);

	my $gffIO = Bio::Tools::GFF->new(-file => $self->{fileList}[$self->{_currentFileLevel}], -gff_version => 3, -verbose => -1);
	my $feature;
	my $geneID='';
	my $mRnaID='';

	#~ Run through all the features contained in the file.
	while($feature = $gffIO->next_feature()){
		if($feature->primary_tag() =~ /^gene$/){
			if($feature->has_tag('ID')){
				$geneID = ($feature->get_tag_values('ID'))[0];
				$self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}->{$feature->primary_tag()} = $feature;
			}
			else{
				$logger->error('This gene do not have any ID tag.');
			}
		}

		elsif($feature->primary_tag() =~ /^(CDS|polypeptide|three_prime_UTR|exon|five_prime_UTR)$/){
			my $parentID = $self->_getParentID($feature);
			$logger->debug('Inserting feature ' . $feature->primary_tag() . ' in the gene ' . $geneID . ' and mRNA ' . $mRnaID . '.');
			push(@{$self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}->{$mRnaID}->{$feature->primary_tag()}},$feature);
		}

		elsif($feature->primary_tag() =~ /^mRNA$/){
			$mRnaID = ($feature->get_tag_values('ID'))[0];
			$logger->debug('Inserting feature ' . $feature->primary_tag() . ' in the gene ' . $geneID . ' and mRNA ' . $mRnaID . '.');
			#~ Storing mRNA in a tab because there can be splicing variants.
			$self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneID}->{$mRnaID}->{$feature->primary_tag()} = $feature;
		}

		elsif($feature->primary_tag() =~ /^match$/){
			($geneID, $mRnaID) = $self->convertMatchFeature($feature);
		}

		elsif($feature->primary_tag() =~ /^match_part$/){
			$self->convertMatchPartFeature($feature, $geneID, $mRnaID);
		}

		else{
			$logger->debug('This primary_tag is not handle for the creation of the feature tree: ' . $feature->primary_tag() . '.');
		}
	}

	$gffIO->close();
}


sub convertMatchFeature {

	# Recovers parameters
	my ($self, $matchFeature) = @_ ;

	# Collect data on the original feature
	if (! $matchFeature->has_tag('ID')) {
		$logger->logdie('A match feature without ID tag/attribute has been found in the following prediction file: ' . $self->{fileList}[$self->{_currentFileLevel}]);
	}

	my $originalId = ($matchFeature->get_tag_values('ID'))[0];
	my $originalName = ($matchFeature->get_tag_values('Name'))[0];

	# Creation of the gene feature
	my $geneFeatureAttributes = {};
	$geneFeatureAttributes->{'ID'} = $originalId;
	$geneFeatureAttributes->{'Name'} = $originalName;

	my $geneFeature = Bio::SeqFeature::Generic->new(
		 -seq_id      => $matchFeature->seq_id(),
		 -source_tag  => $matchFeature->source_tag(),
		 -primary_tag => 'gene',
		 -start       => $matchFeature->start(),
		 -end         => $matchFeature->end(),
		 -strand      => $matchFeature->strand(),
		 -tag         => $geneFeatureAttributes
	);

	# Creation of the mRNA feature
	my $mRNAFeatureAttributes = {};
	$mRNAFeatureAttributes->{'ID'} = $originalId . '_mRNA_0001';
	$mRNAFeatureAttributes->{'Name'} = $originalName . '_mRNA_0001';
	$mRNAFeatureAttributes->{'Parent'} = $geneFeatureAttributes->{'ID'};
	$mRNAFeatureAttributes->{'generated_from'} = $originalId;

	my $mRNAFeature = Bio::SeqFeature::Generic->new(
		 -seq_id      => $matchFeature->seq_id(),
		 -source_tag  => $matchFeature->source_tag(),
		 -primary_tag => 'mRNA',
		 -start       => $matchFeature->start(),
		 -end         => $matchFeature->end(),
		 -strand      => $matchFeature->strand(),
		 -tag         => $mRNAFeatureAttributes
	);

	# Store the newly created features
	$logger->debug('Match feature "' . $originalId . '" has been converted into a gene+mRNA feature couple.');
	$self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneFeatureAttributes->{'ID'}}->{gene} = $geneFeature;
	$self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$geneFeatureAttributes->{'ID'}}->{$mRNAFeatureAttributes->{'ID'}}->{mRNA} = $mRNAFeature;

	return ($geneFeatureAttributes->{'ID'}, $mRNAFeatureAttributes->{'ID'});
}


sub convertMatchPartFeature {

	# Recovers parameters
	my ($self, $matchPartFeature, $curentGeneId, $currentMrnaId) = @_ ;

	# Initializations
	my ($rootName, $matchPartNumber) = ('', '');

	# Collect data on the original feature
	my $originalId = ($matchPartFeature->get_tag_values('ID'))[0];
	my $originalName = ($matchPartFeature->get_tag_values('Name'))[0];

	if ($originalName =~ /(\w+)_Match_part_(\d+)/) {
		$rootName = $1;
		$matchPartNumber = $2;
	}

	# Creation of the exon feature
	my $exonFeatureAttributes = {};
	$exonFeatureAttributes->{'Name'} = $rootName . '_mRNA_0001_exon_' . $matchPartNumber;
	$exonFeatureAttributes->{'ID'} = $matchPartFeature->seq_id() . '_' . $exonFeatureAttributes->{'Name'};
	$exonFeatureAttributes->{'Parent'} = $currentMrnaId;
	$exonFeatureAttributes->{'generated_from'} = $originalId;

	my $exonFeature = Bio::SeqFeature::Generic->new(
		 -seq_id      => $matchPartFeature->seq_id(),
		 -source_tag  => $matchPartFeature->source_tag(),
		 -primary_tag => 'exon',
		 -start       => $matchPartFeature->start(),
		 -end         => $matchPartFeature->end(),
		 -strand      => $matchPartFeature->strand(),
		 -tag         => $exonFeatureAttributes
	);

	# Creation of the polypeptide feature
	my $polypeptideFeatureAttributes = {};
	$polypeptideFeatureAttributes->{'Name'} = $rootName . '_mRNA_0001_polypeptide_' . $matchPartNumber;
	$polypeptideFeatureAttributes->{'ID'} = $matchPartFeature->seq_id() . '_' . $polypeptideFeatureAttributes->{'Name'};
	$polypeptideFeatureAttributes->{'Derives_from'} = $currentMrnaId;
	$polypeptideFeatureAttributes->{'generated_from'} = $originalId;

	my $polypeptideFeature = Bio::SeqFeature::Generic->new(
		 -seq_id      => $matchPartFeature->seq_id(),
		 -source_tag  => $matchPartFeature->source_tag(),
		 -primary_tag => 'polypeptide',
		 -start       => $matchPartFeature->start(),
		 -end         => $matchPartFeature->end(),
		 -strand      => $matchPartFeature->strand(),
		 -tag         => $polypeptideFeatureAttributes
	);

	# Store the newly created features
	$logger->debug('Match_part feature "' . $originalId . '" has been converted into an exon+polypeptide feature couple.');
	push(@{$self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$curentGeneId}->{$currentMrnaId}->{'exon'}}, $exonFeature);
	push(@{$self->{predictions}->{$self->{_currentFileLevel}}->{originalFeatureObjects}->{$curentGeneId}->{$currentMrnaId}->{'polypeptide'}}, $polypeptideFeature);

	return 0;
}


#################################################
## CDS validation/filtering related methods
#################################################

=head2 _validateAndFilterCds
This method go through the hash "$self->{predictions}->{$self->{_currentFileLevel}}->{cds}->{id} = Bio::SeqFeature" and
annotate each CDS.
Steps are:
=over 2
=item 1.
Select biological evidences that overlaps the $self->{_currentCDS}.
Exclude those without any.
=item 2.
Blast the corresponding protein against the choosen database. Exclude those below threshold.
=item 3.
Do the validation step.
=item 4.
Annotate this $self->{_currentCDS}.
=back
=cut

sub _validateAndFilterCds {

	# Recovers parameters
	my $self = shift;

	# Loop through the list of CDS
	foreach my $cds (values(%{$self->{predictions}->{$self->{_currentFileLevel}}->{cds}})) {
		$self->{_currentCDS} = $cds ;
		$self->{_currentCDS}->{'belowAllCoverageThresholds'} = 0;
		$self->{_currentCDS}->{'identity'} = 0;
		$self->{_currentCDS}->{'hit_coverage'} = 0;
		$self->{_currentCDS}->{'query_coverage'} = 0;
		$self->{_currentCDS}->{'cdsName'} = ($self->{_currentCDS}->get_tag_values('locus_tag'))[0];

		$self->{_currentCDS}->{'pseudogene'} = [];
		$self->{_currentCDS}->{'partially_sequenced'} = [];
		$self->{_currentCDS}->{'expressed'} = [];
		$self->{_currentCDS}->{'wrong_splice'} = [];

		# Adding '_fileLevel' in the SeqFeature object for future use in _retrieveGeneAndMrna.
		$self->{_currentCDS}->{fileLevel} = $self->{_currentFileLevel};

		# Reinitialize variables
		$self->{_selectedOverlappingFeatures} = undef;
		$self->{_numberOfSelectedOverlappingFeatures} = 0;
		$self->{_numberOfSelectedOverlappingFeaturesType} = 0;
		$self->{_isBlastHit} = 0;

		$logger->info('');
		$logger->info('Treating CDS with locus tag : ' . $self->{_currentCDS}->{'cdsName'});

		# Retrieve overlappping biological evidences for this CDS.
		$self->_selectOverlappingFeatures();

		if ($self->{_numberOfSelectedOverlappingFeaturesType} == 0) {
			$logger->info('  ' . 'There is no overlapping biological evidence(s) for this gene model ! It will be excluded..');
			next;
		} else {
			$logger->info('  ' . 'There is ' . $self->{_numberOfSelectedOverlappingFeatures} . ' overlapping biological evidence(s) for this gene model');
		}

		# Extract the real nucleic and proteic sequences for the current CDS
		$self->extractCodingSequence();

		# Execute BlastP and parse its results
		$self->{_isBlastHit} = $self->_blastProt();

		if ($self->{_isBlastHit} == 0) {
			$logger->info('    ' . '=> There is no blastP hit for this gene model ! It will be excluded..');
			next;
		} else {
			$logger->info('    ' . '=> Some Blast hit has been found !');
		}

		# Try to search missing Methionine or stop codon
		$self->_searchForAlternativeStartAndStop();

		# Do a really basic annotation of the current gene model
		$self->_annotateGene();

		# Execute the start/stop and splicing sites validation methods
		$self->_validateGeneStructure();

		# Set the trust/confidence level and store the list of structure warnings (ie. unvalidated start/end/splice positions)
		$self->_setTrustLevel();

		# Save validated predictions
		$logger->debug('Pushing this object in ' . $self->{_currentFileLevel} . ' file level.');
		push(@{$self->{predictions}->{$self->{_currentFileLevel}}->{selectedCDS}},$cds);
	}
}


sub extractCodingSequence {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my $codingSequence = "";

	# Get all locations
	my @locations = $self->{_currentCDS}->location->each_Location();

	# Extract the nucleic coding sequence depending on the strand
	if ($self->{_currentCDS}->strand() == 1) {
		foreach my $location (@locations) {
			$codingSequence .= $self->{'sequenceObject'}->subseq($location->start(), $location->end());
		}
	} else {
		foreach my $location (reverse @locations) {
			$codingSequence .= $self->{'sequenceObject'}->trunc($location->start(), $location->end())->revcom()->seq();
		}
	}

	# Save the nucleic sequence
	$self->{_currentCDS}->{'nucleicSequence'} = $codingSequence;

	# Translate into amino acids
	my $codingSequenceObject = Bio::Seq->new( -id => $self->{_currentCDS}->{'cdsName'}, -alphabet => 'dna', -seq => $codingSequence, -desc => 'length=' . length($codingSequence) );
	$self->{_currentCDS}->{'proteicSequence'} = $codingSequenceObject->translate->seq();

	return 0;
}

######################################################
## Overlapping feature selection related methods
######################################################

=head2 _selectOverlappingFeatures
=cut

sub _selectOverlappingFeatures {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my $selectedFeatures;

	# Loop through the evidences hash table and search for evidences that overlap Macro CDS features
	foreach my $type (keys(%{$self->{evidences}})){
		foreach my $db (keys(%{$self->{evidences}->{$type}})){
			foreach my $feature (@{$self->{evidences}->{$type}->{$db}->{features}}) {
				if(($self->{_currentCDS}->start < $feature->end && $self->{_currentCDS}->end > $feature->start) && ($self->{_currentCDS}->strand == $feature->strand)){
					if($self->_isReallyOverlapping($feature)){
						push(@{$self->{_selectedOverlappingFeatures}->{$type}->{$db}}, $feature);
						$self->{_numberOfSelectedOverlappingFeatures}++;
					}
				}
			}
			if(defined($self->{_selectedOverlappingFeatures}->{$type}->{$db})){
				$logger->debug(scalar(@{$self->{_selectedOverlappingFeatures}->{$type}->{$db}}) . ' features of type ' . $type . ' has/have been selected from ' . $db . ' evidence file');
				$self->{_numberOfSelectedOverlappingFeaturesType}++ ;
			}
		}
	}
}


sub _isReallyOverlapping {
	my ($self,$feature) = @_;
	my @CDSlocations = $self->{_currentCDS}->location->each_Location;
	my @featureLocations = $feature->location->each_Location;
	foreach my $cdsLoc (@CDSlocations){
		foreach my $ftLoc (@featureLocations){
			if(($cdsLoc->start < $ftLoc->end && $cdsLoc->end > $ftLoc->start) && ($cdsLoc->strand == $ftLoc->strand)){
				return 1;
			}
		}
	}
	return 0;
}


##################################################
## Blast execution & parsing related methods
##################################################

=head2 _blastProt
	This method Blast the protein of the $self->{_currentCDS} against.
=cut

sub _blastProt {

	# recovers parameters
	my $self = shift;

	# Initializations
	my $id = ($self->{_currentCDS}->get_tag_values('locus_tag'))[0];
	$self->{_currentCDS}->{'blastp_file'} = $id . '.bltp';
	$self->{_currentCDS}->{'fasta_file'} = $id . '.faa';
	my $fastaFileFullPath = $self->{fastaDirPath} . '/' . $self->{_currentCDS}->{'fasta_file'};
	my $blastpFileFullPath = $self->{blastpDirPath} . '/' . $self->{_currentCDS}->{'blastp_file'};

	# Generate the protein sequence
	$logger->debug('Creating fasta file for ' . $id);
	$logger->debug('Fasta file fullpath will be ' . $fastaFileFullPath);

	# Write the protein sequence in fasta format
	open(FASTA,">" . $fastaFileFullPath) or $logger->logdie('Cannot create fasta file ' . $fastaFileFullPath . ' in _blastProt method');
	print FASTA ">" . $id . "\n";
	print FASTA $self->{_currentCDS}->{'proteicSequence'};
	close FASTA;

	# Prepare Blast command line
	my $blastCmd = $TRIANNOT_CONF{PATHS}->{soft}->{'Blast'}->{'bin'} . ' -p ' . $self->{type} . ' -i ' . $fastaFileFullPath . ' -d ' . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'database'}}->{'path'} . ' -o ' . $blastpFileFullPath . ' -e ' . $self->{'evalue'} . ' -F F -v 50 -b 50 -a ' . $self->{nbCore} ;
	$logger->debug("Launching blast with the following command line: ". $blastCmd);

	# Execute command
	system($blastCmd);

	return $self->_analyseBlastResults($blastpFileFullPath) ;
}


=head2 _analyseBlastResults
=cut

sub _analyseBlastResults {
	my ($self,$blastpFile) = @_ ;

	my $searchIo = Bio::SearchIO->new( -format => 'blast' , -file   => $blastpFile );
	my $overIdentityThreshold = 0;
	my $overCoverageThreshold = 0;
	my $inPseudoThreshold = 0;
	my $belowFragmentThreshold = 0;

	$logger->info('  ' . 'Analyzing Blast results file:');
	$logger->debug('Blastp result file: ' . $blastpFile);

	while( my $result = $searchIo->next_result ) {
		my $queryLength = $result->query_length();
		if($result->num_hits() > 0){
			my $numHit = 0;
			while( my $hit = $result->next_hit ) {
				$numHit++;
				my $desc = $hit->description();
				my $hitLength = $hit->length();

				#~ On base l'annotation des pseudo/fragment seulement sur les 10 premiers hits du Blast.
				if($numHit <= 10){
					my $identitySum = 0 ;
					my $hspLengthSum = 0 ;
					#~ Parcours de tous les hsps d'un même hit.
					while(my $hsp = $hit->next_hsp){
						$identitySum += $hsp->percent_identity;
						$hspLengthSum += $hsp->length('total');
					}
					#~ Calcul de l'identité cumulée et des couvertures.
					$self->{_currentCDS}->{'identity'} = $identitySum / $hit->hsps();
					$self->{_currentCDS}->{'hit_coverage'} = ($hspLengthSum / $hitLength) * 100;
					$self->{_currentCDS}->{'query_coverage'} = ($hspLengthSum / $queryLength) * 100;
					$logger->debug('realIdentity: ' . sprintf("%.2f",$self->{_currentCDS}->{'identity'}) . '; hitCoverage: ' . sprintf("%.2f",$self->{_currentCDS}->{'hit_coverage'}) . '; queryCoverage: ' . sprintf("%.2f",$self->{_currentCDS}->{'query_coverage'}));

					if($self->{_currentCDS}->{'identity'} >= 35){
						$overIdentityThreshold = 1;
						if($self->{_currentCDS}->{'hit_coverage'} >= 70 && $self->{_currentCDS}->{'query_coverage'} >= 60 && $overCoverageThreshold == 0){
							$logger->debug("Over thresholds.");
							$overCoverageThreshold = 1;
						}
						elsif(($self->{_currentCDS}->{'hit_coverage'} <= 70 && $self->{_currentCDS}->{'hit_coverage'} >= 50 && $self->{_currentCDS}->{'query_coverage'} >= 60) && ($overCoverageThreshold == 0 && $inPseudoThreshold == 0) ){
							$logger->debug("In pseudo thresholds.");
							$inPseudoThreshold = 1;
						}
						elsif(($self->{_currentCDS}->{'hit_coverage'} < 50 && $self->{_currentCDS}->{'query_coverage'} >= 60) && ($overCoverageThreshold == 0 && $inPseudoThreshold == 0)){
							$logger->debug("In fragment thresholds.");
							$belowFragmentThreshold = 1;
						}
					}
				}
				if($numHit == 1){
					$self->{_currentCDS}->{'bestBlastHit'} = {'Description' => $desc, 'Percent_identity' => sprintf("%.2f",$self->{_currentCDS}->{'identity'}), 'Hit_coverage' => sprintf("%.2f",$self->{_currentCDS}->{'hit_coverage'}), 'Query_coverage' => sprintf("%.2f",$self->{_currentCDS}->{'query_coverage'}) };
				}
			}
		}
	}

	if($overIdentityThreshold == 1){
		$logger->debug('KEEPED: over thresholds.');
		if($overCoverageThreshold == 1){
			return 1 ;
		}
		else{
			if($inPseudoThreshold == 1){
				$logger->debug('In pseudo thresholds (Current CDS will now be tagged "pseudogene" if it is not already tagged "partially_sequenced")');
				if (scalar(@{$self->{_currentCDS}->{'partially_sequenced'}}) == 0) {
					push(@{$self->{_currentCDS}->{'pseudogene'}}, 'Hit coverage between 50 and 70 percent');
				}
			}
			elsif($belowFragmentThreshold == 1 && $inPseudoThreshold == 0){
				$logger->debug('In fragment thresholds (Current CDS is now tagged "pseudogene")');
				push(@{$self->{_currentCDS}->{'pseudogene'}}, 'Hit coverage below 50 percent (fragment)');
			}
			else{
				$self->{_currentCDS}->{'belowAllCoverageThresholds'} = 1;
			}
			return 1;
		}
	}
	else{
		$logger->debug('Some hit but below identity threshold.');
		return 0;
	}
}


#########################################################
## Other Methionine and stop search related methods
#########################################################

sub _searchForAlternativeStartAndStop {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my $mainSequenceLength = $self->{'sequenceObject'}->length();
	my $needToUpdateCoordinates = 0;

	# Split the protein sequence
	my @protSeq = split('', $self->{_currentCDS}->{'proteicSequence'});

	# Search for an alternative start if needed (on both sides of the current start position)
	if ($protSeq[0] ne 'M') {
		$logger->debug('No Methionine found for this gene model. Seeking for one...');

		# Start to search for the Methionine 12 nucleotides after current start position but make sure to not go beyond the end of the first exon
		my $initialSearchOffset = 12;
		if ($self->_getLengthOfFirstExonFromCurrentCDS() - 12 <= 6) {
			$initialSearchOffset = $self->_getLengthOfFirstExonFromCurrentCDS() - 6 > 0 ? $self->_getLengthOfFirstExonFromCurrentCDS() - 6 : 0;
		}
		for (my $i=-$initialSearchOffset; $i <= 600 ; $i+=3) {
			my $triplet='';
			my $newStart='0';

			# Get the current codon/triplet and the possible new start position
			if ($self->{_currentCDS}->strand == 1) {
				# Check that we will not try to get a subsequence that overlap the start of the main sequence (or is totally outside of the main sequence)
				if (($self->{_currentCDS}->start() - $i) < 1) {
					$logger->debug('The start of the sequence has been reached (Current CDS is now tagged "partially_sequenced")');
					push(@{$self->{_currentCDS}->{'partially_sequenced'}}, 'Left sequence end reached during start search');
					last;
				}
				# Get triplet and start position
				$triplet = $self->{'sequenceObject'}->subseq( ($self->{_currentCDS}->start() - $i) , ($self->{_currentCDS}->start()-1 - ($i-3)) );
				$newStart=($self->{_currentCDS}->start() - $i);
			} else {
				# Check that we will not try to get a subsequence that overlap the end of the main sequence (or is totally outside of the main sequence)
				if (($self->{_currentCDS}->end() + $i) > $mainSequenceLength) {
					$logger->debug('The end of the sequence has been reached (Current CDS is now tagged "partially_sequenced")');
					push(@{$self->{_currentCDS}->{'partially_sequenced'}}, 'Right sequence end reached during start search');
					last;
				}
				# Get triplet (reverse comp) and start position
				$triplet = $self->{'sequenceObject'}->subseq( ($self->{_currentCDS}->end()+1 + ($i-3)) , ($self->{_currentCDS}->end() + $i) );
				$triplet =~ tr/atcgATCG/tagcTAGC/;
				$triplet = reverse($triplet);
				$newStart=($self->{_currentCDS}->end() + $i);
			}

			if ($triplet =~ /N/gi) {
				push(@{$self->{_currentCDS}->{'partially_sequenced'}}, 'Unknown aa found during start search');
				next;
			}

			my $aa = $TRIANNOT_CONF{GeneticCode}->{uc($triplet)};
			if ($aa =~ /\*|\#|\+/) {
					$logger->debug('A stop codon has been found. Start position will not be changed and search is canceled.');
					last;
			} elsif($aa eq 'M') {
				$logger->debug('New in-phase methionine found. The new start position for the current CDS will be: ' . $newStart);
				$self->_updateCoordinateOnOriginalFeature('start',$newStart);
				my @locations = $self->{_currentCDS}->location->each_Location ;
				if ($self->{_currentCDS}->strand == 1) {
					$locations[0]->start($newStart);
				} else {
					$locations[$#locations]->end($newStart);
				}
				$needToUpdateCoordinates = 1;
				last;
			}
		}
	}

	# Search for an alternative stop/end if needed (on one side of the current stop/end position)
	if ($protSeq[$#protSeq] !~ /\*|\#|\+/) {
		$logger->debug('No Stop codon found for this gene model. Seeking for one...');

		for (my $i=3; $i <= 600 ; $i+=3) {
			my $triplet='';
			my $newStop='0';

			# Get the current codon/triplet and the possible new stop/end position
			if ($self->{_currentCDS}->strand == 1) {
				# Check that we will not try to get a subsequence that overlap the end of the main sequence (or is totally outside of the main sequence)
				if (($self->{_currentCDS}->end() + $i) > $mainSequenceLength) {
					$logger->debug('The end of the sequence has been reached (Current CDS is now tagged "partially_sequenced")');
					push(@{$self->{_currentCDS}->{'partially_sequenced'}}, 'Right sequence end reached during stop search');
					last;
				}
				# Get triplet and stop/end position
				$triplet = $self->{'sequenceObject'}->subseq( ($self->{_currentCDS}->end()+1 + ($i-3)) , ($self->{_currentCDS}->end() + $i) );
				$newStop=($self->{_currentCDS}->end() + ($i));
			} else {
				# Check that we will not try to get a subsequence that overlap the start of the main sequence (or is totally outside of the main sequence)
				if (($self->{_currentCDS}->start() - $i) < 1) {
					$logger->debug('The start of the main sequence has been reached (Current CDS is now tagged "partially_sequenced")');
					push(@{$self->{_currentCDS}->{'partially_sequenced'}}, 'Left sequence end reached during stop search');
					last;
				}
				# Get triplet and stop/end position
				$triplet = $self->{'sequenceObject'}->subseq( ($self->{_currentCDS}->start() - $i) , ($self->{_currentCDS}->start()-1 - ($i-3)) );
				$triplet =~ tr/atcgATCG/tagcTAGC/;
				$triplet = reverse($triplet);
				$newStop=($self->{_currentCDS}->start() - ($i));
			}

			if ($triplet =~ /N/gi) {
				push(@{$self->{_currentCDS}->{'partially_sequenced'}}, 'Unknown aa found during stop search');
				next;
			}

			my $aa = $TRIANNOT_CONF{GeneticCode}->{uc($triplet)};
			if ($aa =~ /\*|\#|\+/) {
				$logger->debug('New in-phase stop found. New end coordinate: ' . $newStop);
				$self->_updateCoordinateOnOriginalFeature('end',$newStop);
				my @locations = $self->{_currentCDS}->location->each_Location ;
				if ($self->{_currentCDS}->strand == 1) {
					$locations[$#locations]->end($newStop);
				} else {
					$locations[0]->start($newStop);
				}
				$needToUpdateCoordinates = 1;
				last;
			}
		}
	}

	# Update the nucleic and proteic sequences
	if ($needToUpdateCoordinates == 1) {
		$self->extractCodingSequence();
	}
}


sub _updateCoordinateOnOriginalFeature{
	my ($self,$pos,$coord) = @_;
	if($pos eq 'start'){
		if($self->{_currentCDS}->strand == 1){
			$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{gene}->start($coord);
			foreach my $mRnaId (keys(%{$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}})){
				if($mRnaId eq 'gene'){next;}
				$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{mRNA}->start($coord);
				if(defined($self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{exon})){
					$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{exon}->[0]->start($coord);
				}
				if(defined($self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{polypeptide})){
					$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{polypeptide}->[0]->start($coord);
				}
			}
		}
		else{
			$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{gene}->end($coord);
			foreach my $mRnaId (keys(%{$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}})){
				if($mRnaId eq 'gene'){next;}
				$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{mRNA}->end($coord);
				if(defined($self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{exon})){
					my @tab = @{$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{exon}};
					$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{exon}->[$#tab]->end($coord);
				}
				if(defined($self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{polypeptide})){
					my @tab = @{$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{polypeptide}};
					$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{polypeptide}->[$#tab]->end($coord);
				}
			}
		}
	}
	elsif($pos eq 'end'){
		if($self->{_currentCDS}->strand == 1){
			$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{gene}->end($coord);
			foreach my $mRnaId (keys(%{$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}})){
				if($mRnaId eq 'gene'){next;}
				$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{mRNA}->end($coord);
				if(defined($self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{exon})){
					my @tab = @{$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{exon}};
					$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{exon}->[$#tab]->end($coord);
				}
				if(defined($self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{polypeptide})){
					my @tab = @{$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{polypeptide}};
					$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{polypeptide}->[$#tab]->end($coord);
				}
			}
		}
		else{
			$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{gene}->start($coord);
			foreach my $mRnaId (keys(%{$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}})){
				if($mRnaId eq 'gene'){next;}
				$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{mRNA}->start($coord);
				if(defined($self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{exon})){
					$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{exon}->[0]->start($coord);
				}
				if(defined($self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{polypeptide})){
					$self->{predictions}->{$self->{_currentCDS}->{fileLevel}}->{originalFeatureObjects}->{$self->{_currentCDS}->{geneid}}->{$mRnaId}->{polypeptide}->[0]->start($coord);
				}
			}
		}
	}
}


########################################
## Gene annotation related methods
########################################

=head2 _annotateGene
This sub tries to annotate the _currentCDS. It makes different basic checks:
 		- presence/absence of the 'M' as the first amino acids.
 		- presence/absence of an stop codon (*|#) inside the protein sequence.
 		- presence/absence of NNNN in the CDS or around a splicing site.
 		- non-canonical splicing sites (G[T|C] ; AG) (Note: Intron often start with GT/GC (donnor) and end with AG (acceptor))
=cut

sub _annotateGene{

	my ($self) = @_;

	$self->_checkForExpression();

	$self->_checkForPseudo() ;

	$self->_checkForNs();

	$self->_checkForWrongSpliceSites();
}


=head2 _checkForExpression
=cut

# TODO: check overlapping length ?
sub _checkForExpression {

	# Recovers parameters
	my $self = shift;

	# Check if it exist at least one overlapping evidence from one of the user selected databases for the current CDS
	if (scalar(@{$self->{'databaseNamesForExpressionCheck'}}) > 0) {
		CHECKLOOP: foreach my $evidenceType (@{$self->{'evidenceParameterNames'}}) {
			foreach my $databaseName (@{$self->{'databaseNamesForExpressionCheck'}}) {
				if (defined($self->{_selectedOverlappingFeatures}->{$evidenceType}->{$databaseName})) {
					$logger->debug('Biological evidence found in database ' . $databaseName. ' (Current CDS is now tagged "expressed")');
					push(@{$self->{_currentCDS}->{'expressed'}}, 'Hit found against expressed transcript');
					last CHECKLOOP;
				}
			}
		}
	}

	return 0; # SUCCESS
}


=head2 _checkForPseudo
Make several checks on the protein sequence and tag it accordingly
It checkd if the current protein start with a methionine, if it end with a stop and if it contains internal stop codons
=cut

sub _checkForPseudo {

	# Recovers parameters
	my $self = shift;

	# Verify if any stop codons in the protein sequence.
	my @protSeq = split('', $self->{_currentCDS}->{'proteicSequence'});

	# Check if the proteic sequence begin by a Methionine
	if($protSeq[0] ne 'M'){
		$logger->debug('Methionine missing for the following CDS: ' . ($self->{_currentCDS}->get_tag_values('locus_tag'))[0] . ' (Current CDS is now tagged "pseudogene")');
		push(@{$self->{_currentCDS}->{'pseudogene'}}, 'No methionine');
	}

	# Check if the sequence contains internal stop codons
	for(my $i = 0; $i<=$#protSeq; $i++){
		if($protSeq[$i] =~ /\*|\#|\+/ && $i != $#protSeq){
			$logger->debug('Stop codon in phase for the following CDS: ' . ($self->{_currentCDS}->get_tag_values('locus_tag'))[0] . ' (Current CDS is now tagged "pseudogene")');
			push(@{$self->{_currentCDS}->{'pseudogene'}}, 'Internal stop');
		}
	}

	# Check if the proteic sequence end with a stop codon
	if($protSeq[$#protSeq] !~ /\*|\#|\+/){
		$logger->debug('Final stop codon missing for the following CDS: ' . ($self->{_currentCDS}->get_tag_values('locus_tag'))[0] . ' (Current CDS is now tagged "partially_sequenced")');
		push(@{$self->{_currentCDS}->{'partially_sequenced'}}, 'No final stop');
	}

	return 0; # SUCCESS
}


=head2 _checkForNs
=cut

sub _checkForNs {

	# Recovers parameters
	my $self = shift;

	# Verify if there is some N's in the spliced CDS sequence.
	if ($self->{_currentCDS}->{'nucleicSequence'} =~ /N/gi) {
		$logger->debug('N detected in coding sequence for the following CDS: ' . ($self->{_currentCDS}->get_tag_values('locus_tag'))[0] . ' (Current CDS is now tagged "partially_sequenced")');
		push(@{$self->{_currentCDS}->{'partially_sequenced'}}, 'N base in coding sequence');
	}

	return 0; # SUCCESS
}


=head2 _checkForWrongSpliceSites
=cut

sub _checkForWrongSpliceSites {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my $intronLength = 0;

	# Verify if spliced sites (donor/acceptor) are corrects (GT|C/AG).
	my @locations = $self->{_currentCDS}->location->each_Location ;

	if ($self->{_currentCDS}->strand == -1) {
		@locations = reverse @locations;
	}

	for (my $i=0; $i<$#locations ; $i++) {
		my $donor = '';
		my $acceptor = '';

		if ($locations[$i]->strand == -1) {
			$intronLength = ($locations[$i]->start) - ($locations[$i+1]->end+1);
			$donor = $self->{'sequenceObject'}->subseq(($locations[$i]->start - 2) , ($locations[$i]->start - 1));
			$donor =~ tr/atcgATCG/tagcTAGC/;
			$donor = reverse($donor);

			$acceptor = $self->{'sequenceObject'}->subseq(($locations[$i+1]->end + 1) , ($locations[$i+1]->end + 2));
			$acceptor =~ tr/atcgATCG/tagcTAGC/;
			$acceptor = reverse($acceptor);

		} else {
			$intronLength = ($locations[$i+1]->start) - ($locations[$i]->end+1);
			$donor = $self->{'sequenceObject'}->subseq(($locations[$i]->end+1),($locations[$i]->end + 2));
			$acceptor = $self->{'sequenceObject'}->subseq(($locations[$i+1]->start - 2) , ($locations[$i+1]->start-1));
		}

		if ($donor =~ /^G[T|C]$/ && $acceptor =~ /^AG$/) {
			$logger->trace('Good splice site - Correct donor/acceptor');
			next;

		} elsif ($donor =~ /N/g || $acceptor =~ /N/g) {
			$logger->debug('N detected in acceptor or donor site (Current CDS is now tagged "partially_sequenced")');
			push(@{$self->{_currentCDS}->{'partially_sequenced'}}, 'N base in donor or acceptor site');

		} else {
			$logger->debug('Wrong splice site: ' . $donor . " - " . $acceptor . ' (Current CDS is now tagged "wrong_splice")');
			push(@{$self->{_currentCDS}->{'wrong_splice'}}, 'Invalid Do/Ac sites');

			if ($intronLength <= $self->{'minimumIntronLength'}) {
				$logger->debug('Intron length is lower than ' . $self->{'minimumIntronLength'} . ' bp' . ' (Current CDS is now tagged "pseudogene")');
				push(@{$self->{_currentCDS}->{'pseudogene'}}, 'Too small intron (frameshift)');
			}
		}
	}

	return 0; # SUCCESS
}


########################################
## Gene validation related methods
########################################

=head2 _validateGeneStructure
=cut

sub _validateGeneStructure {
	my ($self) = @_;
	my $warning = '';

	$self->_startEndValidation() ;

	my @locations  = $self->{_currentCDS}->location->each_Location ;

	if(scalar(@locations)>1){
		for(my $i=0; $i<$#locations ; $i++) {
			$self->_spliceValidation( $locations[$i]->end(), $locations[$i+1]->start(), $i);
		}
	}
}


=head2 _startEndValidation
=cut

sub _startEndValidation {
	my ($self) = @_;
	$self->{_currentCDS}->{_annotLevel}->{_start} = -1;
	$self->{_currentCDS}->{_annotLevel}->{_end} = -1;
	if(!defined($self->{_selectedOverlappingFeatures}->{proteicEvidences})){
		return 0 ;
	}
	$logger->debug("_startEndValidation for coordinates: " . $self->{_currentCDS}->start . "\t" . $self->{_currentCDS}->end);
	foreach my $db (keys(%{$self->{_selectedOverlappingFeatures}->{proteicEvidences}})){
		foreach my $feature (@{$self->{_selectedOverlappingFeatures}->{proteicEvidences}->{$db}}) {
			for(my $range=-$self->{validationRange} ; $range<=$self->{validationRange} ; $range+=3){
				my $featStart = $feature->start + $range ;
				my $featEnd = $feature->end + $range ;
				if($self->{_currentCDS}->strand == -1){
					if($featStart == $self->{_currentCDS}->start){
						if($self->{_currentCDS}->{_annotLevel}->{_end} == -1){
							$logger->debug("End validated with " . $db . " database.");
							$self->{_currentCDS}->{_annotLevel}->{_end} = 1 ;
						}
					}
					if($featEnd == $self->{_currentCDS}->end){
						if($self->{_currentCDS}->{_annotLevel}->{_start} == -1){
							$logger->debug("Start validated with " . $db . " database.");
							$self->{_currentCDS}->{_annotLevel}->{_start} = 1 ;
						}
					}
				}
				else{
					if($featStart == $self->{_currentCDS}->start){
						if($self->{_currentCDS}->{_annotLevel}->{_start} == -1){
							$logger->debug("Start validated with " . $db . " database.");
							$self->{_currentCDS}->{_annotLevel}->{_start} = 1 ;
						}
					}
					if($featEnd == $self->{_currentCDS}->end){
						if($self->{_currentCDS}->{_annotLevel}->{_end} == -1){
							$logger->debug("End validated with " . $db . " database.");
							$self->{_currentCDS}->{_annotLevel}->{_end} = 1 ;
						}
					}
				}
			}
		}
	}
}


=head2 _spliceValidation
=cut

sub _spliceValidation {

	# Recovers parameters
	my ($self, $exonEnd, $exonStart,$indice) = @_;

	$logger->debug('Validation of splice ' . $indice . ' coordinates:' . $exonEnd . "\t" . $exonStart);

	$self->{_currentCDS}->{_annotLevel}->{_splice}->{sprintf("%02d",$indice+1)} = -1;

	# Try to validate splices
	foreach my $type (@{$self->{'evidenceParameterNames'}}) {
		next if($type eq 'misc');

		foreach my $db (keys(%{$self->{_selectedOverlappingFeatures}->{$type}})) {
			if (defined($self->{_selectedOverlappingFeatures}->{$type}->{$db})) {
				$logger->debug('Validation attempt with evidences from database ' . $db . ' (Number of features: ' . scalar(@{$self->{_selectedOverlappingFeatures}->{$type}->{$db}}) . ')');
				foreach my $feature (@{$self->{_selectedOverlappingFeatures}->{$type}->{$db}}) {
					my @locations  = $feature->location->each_Location ;
					for (my $i = 0; $i < $#locations; $i++) {
						$logger->trace('' . $locations[$i]->end() . "<=>" . $locations[$i+1]->start());
						if (($locations[$i]->end() == $exonEnd && $locations[$i+1]->start() == $exonStart) && ($self->{_currentCDS}->{_annotLevel}->{_splice}->{sprintf("%02d",$indice+1)} == -1)) {
							$logger->debug("Splice " . $indice . " validated with " . $db . " database.");
							$self->{_currentCDS}->{_annotLevel}->{_splice}->{sprintf("%02d",$indice+1)} = 1;
							return 0; # SUCCESS
						}
					}
				}
			}
		}
	}
}


sub _setTrustLevel {

	# Recovers parameters
	my $self = shift;

	# Build the array of structure warnings
	$self->_buildStructureWarningsArray();

	# Set the trust level depending on the annotation tags (pseudogene, partially_sequenced, etc) and the validation steps
	if (scalar(@{$self->{_currentCDS}->{'structure_warnings'}}) > 0) {
		$logger->debug('Structure warnings are: ' . join(', ', @{$self->{_currentCDS}->{'structure_warnings'}}));

		$logger->info('  ' . 'The gene model structure is not fully validated by biological evidences..');
		$logger->info('    ' . '=> Setting trust level to Low confidence');
		$self->{_currentCDS}->{'trustLevel'} = 'Low Confidence';
	} else {
		if (scalar(@{$self->{_currentCDS}->{pseudogene}}) > 0 || scalar(@{$self->{_currentCDS}->{partially_sequenced}}) > 0 || scalar(@{$self->{_currentCDS}->{wrong_splice}}) > 0) {
			$logger->info('  ' . 'The gene model structure is fully validated by biological evidences but the gene model correspond to a pseudogene or a partially sequenced gene and/or possess strange donor/acceptor site(s) !');
			$logger->info('    ' . '=> Setting trust level to Medium confidence');
			$self->{_currentCDS}->{'trustLevel'} = 'Medium Confidence';
		} else {
			$logger->info('  ' . 'The gene model structure is fully validated by biological evidences !');
			$logger->info('    ' . '=> Setting trust level to High confidence');
			$self->{_currentCDS}->{'trustLevel'} = 'High Confidence';
		}
	}
}


sub _buildStructureWarningsArray {

	# Recovers parameters
	my $self = shift;

	# Initializations
	$self->{_currentCDS}->{'structure_warnings'} = [];

	# Fill the array
	if($self->{_currentCDS}->{_annotLevel}->{_start} == -1){
		push(@{$self->{_currentCDS}->{'structure_warnings'}}, 'START');
	}

	if(defined($self->{_currentCDS}->{_annotLevel}->{_splice})){
		if($self->{_currentCDS}->strand == -1){
			my $i=0;
			foreach my $splice (reverse(sort(keys(%{$self->{_currentCDS}->{_annotLevel}->{_splice}})))){
				$i++;
				if($self->{_currentCDS}->{_annotLevel}->{_splice}->{$splice} == -1){
					push (@{$self->{_currentCDS}->{'structure_warnings'}}, sprintf("SPLICE_%02d",$i));
				}
			}
		}
		else{
			foreach my $splice (sort(keys(%{$self->{_currentCDS}->{_annotLevel}->{_splice}}))){
				if($self->{_currentCDS}->{_annotLevel}->{_splice}->{$splice} == -1){
					push (@{$self->{_currentCDS}->{'structure_warnings'}}, sprintf("SPLICE_%02d",$splice));
				}
			}
		}
	}

	if($self->{_currentCDS}->{_annotLevel}->{_end} == -1){
		push(@{$self->{_currentCDS}->{'structure_warnings'}}, 'END');
	}

	return 0;
}


############################################################
## Best gene model per locus selection related methods
############################################################

=head2 _selectGeneModel
This sub select the best model at each locus.
=cut

sub _selectGeneModel {
	my ($self) = @_;

	$logger->info('');
	$logger->info('Best gene models selection:');

	for(my $i=0; $i<=$#{$self->{fileList}};$i++){
		if(! defined($self->{predictions}->{$i}->{selectedCDS})){
			$logger->debug('No CDS selected from file level ' . $i . '.');
			next;
		}
		$logger->debug('Treating ' . scalar(@{$self->{predictions}->{$i}->{selectedCDS}}) . ' CDS from file ' . $i . '.');
		foreach my $cds (@{$self->{predictions}->{$i}->{selectedCDS}}){
			#~ If this CDS have been treated by a previous step.
			if(defined($cds->{alreadyTreated}) && $cds->{alreadyTreated} == 1){next;}

			$self->{_currentCDS} = $cds ;
			$self->{_currentCDS}->{alreadyTreated} = 1 ;
			$logger->debug('Try to find overlapping CDS for '. ($self->{_currentCDS}->get_tag_values('locus_tag'))[0] .' in other files.');

			$self->_searchForCDSInSameLocus($i);

			if(scalar(@{$self->{_CDSFromSameLocus}}) > 1){
				$logger->debug(scalar(@{$self->{_CDSFromSameLocus}}) . ' overlapping CDS have been found.');
				@{$self->{_CDSFromSameLocus}} = $self->_sortByHitCoverage($self->{_CDSFromSameLocus});

				$self->_evaluateScore();
				$logger->debug('Pushing ' . $self->{_CDSFromSameLocus}[$self->{_indexMaxScore}]->{'_gsf_tag_hash'}->{'locus_tag'}[0] . ' in the final tab.');
				$self->_markOverlappingCDS($self->{_CDSFromSameLocus}[$self->{_indexMaxScore}]);
				push(@{$self->{finalCDSList}},$self->{_CDSFromSameLocus}[$self->{_indexMaxScore}]);

			}
			else{
				$logger->debug('No other CDS on this locus. Add this locus to final annotation.');
				$self->_markOverlappingCDS($self->{_currentCDS});
				push(@{$self->{finalCDSList}},$self->{_currentCDS});
			}
		}
	}

	if (defined($self->{finalCDSList})) {
		$logger->info('  => ' . scalar(@{$self->{finalCDSList}}) . ' gene prediction(s) has/have been selected');
	} else {
		$logger->info('  ' . '=> No gene predictions has been selected');
	}
}


=head2 _searchForCDSInSameLocus
Retrieve the _CDSFromSameLocus array of overlapping CDS from different file level.
=cut

sub _searchForCDSInSameLocus{
	my ($self,$indiceFileList) = @_;
	$self->{_CDSFromSameLocus}=undef;
	push(@{$self->{_CDSFromSameLocus}},$self->{_currentCDS});

	for(my $i = $indiceFileList; $i<=$#{$self->{fileList}}; $i++){
		foreach my $cds (@{$self->{predictions}->{$i}->{selectedCDS}}){
			if(($self->{_currentCDS}->get_tag_values('locus_tag'))[0] eq ($cds->get_tag_values('locus_tag'))[0]){next;}
			if(defined ($cds->{alreadyTreated}) && $cds->{alreadyTreated} == 1){next;}
			if( $self->{_currentCDS}->start < $cds->end && $self->{_currentCDS}->end > $cds->start ){
				push(@{$self->{_CDSFromSameLocus}},$cds);
			}
		}
	}
}


=head2 _sortByHitCoverage
=cut

sub _sortByHitCoverage {
	my ($self,$tab) = @_;
	return sort {$b->{hit_coverage} <=> $a->{hit_coverage}} (@{$tab});
}


=head2 _markOverlappingCDS
=cut

sub _markOverlappingCDS {
	my ($self,$current) = @_;
	$current->{alreadyTreated} = 1;
	for(my $i = 0; $i<=$#{$self->{fileList}}; $i++){
		foreach my $cds (@{$self->{predictions}->{$i}->{selectedCDS}}){
			if(($current->get_tag_values('locus_tag'))[0] eq ($cds->get_tag_values('locus_tag'))[0]){next;}
			if( $current->start < $cds->end && $current->end > $cds->start ){
				$logger->debug('Marking CDS ' . (($cds->get_tag_values('locus_tag'))[0]) . ' as already treated.');
				$cds->{alreadyTreated} = 1;
			}
		}
	}
}


#####################################################
## Gene model score computation related methods
#####################################################

=head2 _evaluateScore
Compute a score for each _CDSFromSameLocus.
=cut

sub _evaluateScore{

	# recovers parameters
	my $self = shift;

	# Initializations
	my $oldScore = 0;
	$self->{_indexMaxScore} = 0;

	for (my $i=0;$i<@{$self->{_CDSFromSameLocus}};$i++){
		my $score = 0;
		$logger->debug('Evaluating score for ' . $self->{_CDSFromSameLocus}[$i]->{'_gsf_tag_hash'}->{'locus_tag'}[0] . '.');
		if ($self->{_CDSFromSameLocus}[$i]->{hit_coverage} > 100){
			$logger->debug('hit_coverage: 100.');
			$score += ($self->{_CDSFromSameLocus}[$i]->{hit_coverage} * 2) + $TRIANNOT_CONF{MergeGeneModels}->{bonusScore}->{hitCoverageOver100};
		}
		else{
			$logger->debug('hit_coverage: ' . $self->{_CDSFromSameLocus}[$i]->{hit_coverage} . '.');
			$score += ($self->{_CDSFromSameLocus}[$i]->{hit_coverage} * 2);
		}

		if ($self->{_CDSFromSameLocus}[$i]->{query_coverage} > 100){
			$logger->debug('query_coverage: 100.');
			$score += $TRIANNOT_CONF{MergeGeneModels}->{bonusScore}->{queryCoverageOver100};
		}
		elsif($self->{_CDSFromSameLocus}[$i]->{query_coverage} <= 70){
			$logger->debug('query_coverage: -100.');
			$score -= $TRIANNOT_CONF{MergeGeneModels}->{malusScore}->{queryCoverageBelow70};
		}
		else{
			$logger->debug('query_coverage: ' . $self->{_CDSFromSameLocus}[$i]->{query_coverage} . '.');
			$score += $self->{_CDSFromSameLocus}[$i]->{query_coverage};
		}

		$logger->debug('identity: ' . $self->{_CDSFromSameLocus}[$i]->{identity} . '.');
		$score += $self->{_CDSFromSameLocus}[$i]->{identity};


		$score += $self->_computeValidationScore($self->{_CDSFromSameLocus}[$i]);

		if (scalar(@{$self->{_CDSFromSameLocus}[$i]->{partially_sequenced}}) > 0){
			$logger->debug('partially_sequenced.');
			$score -= $TRIANNOT_CONF{MergeGeneModels}->{malusScore}->{taggedPartiallySequenced};
		}
		if (scalar(@{$self->{_CDSFromSameLocus}[$i]->{wrong_splice}}) > 0){
			$logger->debug('wrong_splice.');
			$score -= $TRIANNOT_CONF{MergeGeneModels}->{malusScore}->{taggedWrong_Splice};
		}
		if ($self->{_CDSFromSameLocus}[$i]->{fileLevel} == 0){
			$logger->debug('scoreManual.');
			$score += $TRIANNOT_CONF{MergeGeneModels}->{bonusScore}->{manuallyCurated};
		}

		$self->{_CDSFromSameLocus}[$i]->{score} = $score;
		$logger->debug('Score is: ' . $self->{_CDSFromSameLocus}[$i]->{score} . '.');

		# Update Max score if needed
		if ($oldScore < $score){
			$self->{_indexMaxScore} = $i;
			$oldScore = $score;
		}
	}
}


=head2 _computeValidationScore
Compute the validation score for one feature.
=cut

sub _computeValidationScore{
	my ($self,$f) = @_;
	my ($nValid,$nAll) = (0,0);
	foreach my $aF (keys(%{$f->{_annotLevel}})){
		if($aF eq '_splice'){
			foreach my $sN (keys(%{$f->{_annotLevel}->{$aF}})){
				$nAll++;
				if($f->{_annotLevel}->{$aF}->{$sN} != -1){
					$nValid++;
				}
			}
		}
		else{
			$nAll++;
			if($f->{_annotLevel}->{$aF} != -1){
				$nValid++;
			}
		}
	}
	my $ratio = $nValid/$nAll;
	my $score = $ratio * 100;
	if($score == 100){
		$score += $TRIANNOT_CONF{MergeGeneModels}->{bonusScore}->{allValidSplice};
	}
	$logger->debug('validationScore: ' . $score . '.');
	return $score;
}


#####################################################
## Tranpo-like gene execlusion related methods
#####################################################

sub _seekForTransposases{
	my ($self) = @_;

	$logger->info('');
	$logger->info('Eliminating gene predicted as transposase-like:');

	my @temp;
CDS:foreach my $cds (sort {$a->start <=> $b->start} (@{$self->{finalCDSList}})){
		my $searchIo = Bio::SearchIO->new( -format => 'blast' , -file   => $self->{blastpDirPath} . '/' . $cds->{'blastp_file'});
		my $transpo = 0;
		while( my $result = $searchIo->next_result ) {
			if($result->num_hits() > 0){
				my $numHit = 0;
				while( my $hit = $result->next_hit ) {
					my $desc = $hit->description();

					foreach my $Transpo_like_keyword (values %{$TRIANNOT_CONF{MergeGeneModels}->{Transposase_like_keywords}}) {
						if ($desc =~ /.*$Transpo_like_keyword.*/i) {
							$logger->debug('REJECTED: Predicted as transposase.') ;
							$logger->debug($desc);
							push(@{$self->{predictedTransposases}},$cds);
							next CDS;
						}
					}
				}
			}
		}
		push(@temp,$cds);
	}
	$self->{finalCDSList} = \@temp;

	if (defined($self->{predictedTransposases})) {
		$logger->info('  => ' . scalar(@{$self->{predictedTransposases}}) . ' gene prediction(s) has/have been rejected');
	} else {
		$logger->info('  ' . '=> No gene prediction has been rejected');
	}
}


############################################
## Output file writing related methods
############################################

=head2 _generateOutputFiles
Generate the final GFF from the $self->{finalCDSList}.
=cut

sub _generateOutputFiles {
	my ($self) = @_;

	$logger->info('');
	$logger->info('Writing GFF output files:');

	my $gffMerge = Bio::Tools::GFF->new ( '-file' => ">$self->{'outFile'}", '-gff_version' => "3" ) ;

	$self->{CDScounter}=0;

	foreach my $cds (sort {$a->start <=> $b->start} (@{$self->{finalCDSList}})){
		$self->{CDScounter}++;
		$self->_writeGeneModelInformations($cds,$gffMerge);
	}

	$logger->info('  => ' . scalar(@{$self->{finalCDSList}}) . ' gene prediction(s) written in file ' . basename($self->{'outFile'}));

	if(defined($self->{predictedTransposases})){
		my $gffTranspo = Bio::Tools::GFF->new ( '-file' => ">" . $self->{'gffForTranspoLikeGeneModels'}, '-gff_version' => "3" ) ;

		foreach my $transpo (sort {$a->start <=> $b->start} (@{$self->{predictedTransposases}})) {
			$self->_writeGeneModelInformations($transpo,$gffTranspo);
		}

		$logger->info('  => ' . scalar(@{$self->{predictedTransposases}}) . ' gene prediction(s) written in file ' . basename($self->{'gffForTranspoLikeGeneModels'}));
	}
}


sub _writeGeneModelInformations {
	my ($self,$geneModel,$gffIO) = @_;

	$self->_cleanTags($self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{gene});

	$gffIO->write_feature($self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{gene});

	foreach my $mRnaID (keys(%{$self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}})){

		if($mRnaID eq 'gene'){next;}

		if(! defined( $self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{$mRnaID}->{mRNA} )){
			$logger->debug('mRNA feature not defined for ' . $mRnaID . '. Creating it based on the gene feature.');
			my %Rna = %{$self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{gene}};
			my $mRna = \%Rna;
			bless($mRna,'Bio::SeqFeature::Generic');
			$mRna->primary_tag('mRNA');
			$mRna->add_tag_value('Parent',$geneModel->{geneid});
			$self->_cleanTags($mRna);
			$self->_addAnnotationInfo($mRna,$geneModel);
			$gffIO->write_feature($mRna);
		} else{
			$self->_addAnnotationInfo($self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{$mRnaID}->{mRNA},$geneModel);
			$gffIO->write_feature($self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{$mRnaID}->{mRNA});
		}

		if(defined($self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{$mRnaID}->{exon})){
			foreach my $e (@{$self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{$mRnaID}->{exon}}){
				$gffIO->write_feature($e);
			}
		}

		if($geneModel == -1){
			if(defined($self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{$mRnaID}->{three_prime_UTR})){
				$gffIO->write_feature($self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{$mRnaID}->{three_prime_UTR}[0]);
			}
		} else {
			if(defined($self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{$mRnaID}->{five_prime_UTR})){
				$gffIO->write_feature($self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{$mRnaID}->{five_prime_UTR}[0]);
			}
		}


		if(defined($self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{$mRnaID}->{polypeptide})){
			foreach my $p (@{$self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{$mRnaID}->{polypeptide}}){
				$gffIO->write_feature($p);
			}
		}

		if($geneModel == -1){
			if(defined($self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{$mRnaID}->{five_prime_UTR})){
				$gffIO->write_feature($self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{$mRnaID}->{five_prime_UTR}[0]);
			}
		} else {
			if(defined($self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{$mRnaID}->{three_prime_UTR})){
				$gffIO->write_feature($self->{predictions}->{$geneModel->{fileLevel}}->{originalFeatureObjects}->{$geneModel->{geneid}}->{$mRnaID}->{three_prime_UTR}[0]);
			}
		}
	}
}


sub _cleanTags{
	my ($self,$ft) = @_;
	my @allTags = $ft->get_all_tags();
	foreach my $tag (@allTags){
		if($tag !~ /^(ID|Parent|Name|Derives_from)$/){
			$ft->remove_tag($tag);
		}
	}
}


=head2 _addAnnotationInfo
Add annotation done on the CDS to the mRNA feature.
=cut

sub _addAnnotationInfo {
	my ($self,$gene,$cds) = @_;

	# Level of trust
	$gene->add_tag_value('trustLevel', $cds->{'trustLevel'}) if (defined($cds->{'trustLevel'}) && $cds->{'trustLevel'} ne '');

	# Gene model structure warnings
	if(defined($cds->{'structure_warnings'})){
		foreach my $structure_warning (@{$cds->{'structure_warnings'}}) {
			$gene->add_tag_value('structure_warnings', $structure_warning);
		}
	}

	# Add the name of the blastp file as a feature tag
	if($self->{'addBlastpFileTag'} eq 'yes' && defined($cds->{'blastp_file'})){
		$gene->add_tag_value('blastp_file', $cds->{'blastp_file'});
	}

	# Add the name of the proteic fasta file as a feature tag
	if($self->{'addFastaFileTag'} eq 'yes' && defined($cds->{'fasta_file'})){
		$gene->add_tag_value('fasta_file', $cds->{'fasta_file'});
	}

	# Best blast hit
	if($self->{'addBestBlastHitTags'} eq 'yes' && defined($cds->{'bestBlastHit'})){
		$gene->add_tag_value('best_blast_hit', $cds->{'bestBlastHit'}->{'Description'});
		$gene->add_tag_value('best_blast_hit_identity', $cds->{'bestBlastHit'}->{'Percent_identity'});
		$gene->add_tag_value('best_blast_hit_hit_coverage', $cds->{'bestBlastHit'}->{'Hit_coverage'});
		$gene->add_tag_value('best_blast_hit_query_coverage', $cds->{'bestBlastHit'}->{'Query_coverage'});
	}

	# Expressed tag
	foreach my $expressedTagValue (@{$cds->{'expressed'}}) {
		$gene->add_tag_value('expressed', $expressedTagValue);
	}

	# Wrong_splice tag
	foreach my $wrongSpliceTagValue (@{$cds->{'wrong_splice'}}) {
		$gene->add_tag_value('wrong_splice', $wrongSpliceTagValue);
	}

	# Partially_sequenced tag
	foreach my $partiallySequencedTagValue (@{$cds->{'partially_sequenced'}}) {
		$gene->add_tag_value('partially_sequenced', $partiallySequencedTagValue);
	}

	# Pseudogene tag
	foreach my $pseudogeneTagValue (@{$cds->{'pseudogene'}}) {
		$gene->add_tag_value('pseudogene', $pseudogeneTagValue);
	}
}


################################################
## Generated output file move/copy/symlink
################################################

=head2 _generatedFilesManagement
Move the generated blastp folder in the general EMBL folder for use with the annotation file.
=cut

sub _generatedFilesManagement {

	# Recovers parameters
	my $self = shift;

	# Move the fasta directory (with protein sequences) to the EMBL folder if requested
	if ($self->{'moveProteinFastaToEmblDirectory'} eq 'yes') {
		if(-e $self->{'fastaDirPath'}){
			$logger->debug('Moving the fasta directory into the ' . $self->{'emblDirName'} . ' directory for future use.');
			my $nbFilesAndDirs = File::Copy::Recursive::dirmove($self->{'fastaDirPath'}, $self->{'emblFastaSubDirPath'})
				or $logger->logdie('Error: Cannot copy the ' . $self->{'emblSubDirectoryForFastaFiles'} . ' directory to the ' . $self->{'emblDirName'} . ' directory');
			$logger->debug('Number of moved files and directories: ' . $nbFilesAndDirs);
		}
	}

	# Move the blastp directory to the EMBL folder if requested
	if ($self->{'moveBlastResultsToEmblDirectory'} eq 'yes') {
		if(-e $self->{'blastpDirPath'}){
			$logger->debug('Moving the blastp directory into the ' . $self->{'emblDirName'} . ' directory for future use.');
			my $nbFilesAndDirs = File::Copy::Recursive::dirmove($self->{'blastpDirPath'}, $self->{'emblBlastSubDirPath'})
				or $logger->logdie('Error: Cannot copy the ' . $self->{'emblSubDirectoryForBlastFiles'} . ' directory to the ' . $self->{'emblDirName'} . ' directory');
			$logger->debug('Number of moved files and directories: ' . $nbFilesAndDirs);
		}
	}

	# Create a symlink to the GFF output file in the Commons folder
	if(-e $self->{'outFile'}){
		$logger->debug('Creating symlink for the new output GFF file in the ' . $self->{'commonsDirName'} . ' folder.');
		symlink($self->{'outputFilePath'}, $self->{'commonsDirPath'} . '/' . $self->{'outFile'})
			or $logger->logdie('Error: Cannot create symlink in the ' . $self->{'commonsDirName'} . ' folder.');
	}

	# Move the secondary optional output GFF file in the GFF foler
	if(-e $self->{'gffForTranspoLikeGeneModels'} && !-z $self->{'gffForTranspoLikeGeneModels'}){
		$logger->debug('Moving the GFF file containing GeneModels identified as transposase-like into the GFF directory.');
		move($self->{'gffForTranspoLikeGeneModels'}, $self->{'gffTranspoFilePath'})
			or $logger->logdie('Error: Cannot move file ' . $self->{'gffForTranspoLikeGeneModels'} . ' in the ' . $self->{'gffDirName'} . ' directory');
	}
}


###########################
## Misc basic methods
###########################

=head2 _retrieveSequence

This sub reads a fasta file and returns a Bio::Seq object.

=cut

sub _retrieveSequence {
	my ($self, $file) = @_;
	my $seqIO_obj = Bio::SeqIO->new( -format => "FASTA", -file => $file, -verbose => -1);
	my $seqObj = $seqIO_obj->next_seq;
	return $seqObj;
}


=head2 _getParentID

This sub is made to retrieve the Parent ID of a feature regarless of the format in which it have been stored.
 e.i. Derives_from or Parent.

=cut

sub _getParentID {
	my ($self, $feature) = @_;
	if( defined ($feature->{'_gsf_tag_hash'}->{'Derives_from'}) ){
		return $feature->{'_gsf_tag_hash'}->{'Derives_from'}[0];
	}
	elsif(defined($feature->{'_gsf_tag_hash'}->{'Parent'})){
		return $feature->{'_gsf_tag_hash'}->{'Parent'}[0];
	}
	else{
		return 0;
	}
}

=head2 _getLengthOfFirstExonFromCurrentCDS

This sub returns the size in number of nucleotide of the first exon of $self->{_currentCDS} taking into account
the strand of $self->{_currentCDS}

=cut
sub _getLengthOfFirstExonFromCurrentCDS {
	my $self = shift;
	my $length = 0;
	my @locations = $self->{_currentCDS}->location->each_Location ;
	if ($self->{_currentCDS}->strand == 1) {
		$length = $locations[0]->end() -  $locations[0]->start() + 1;
	} else {
		$length = $locations[$#locations]->end() - $locations[$#locations]->start() + 1;
	}
	return $length;
}

1;
