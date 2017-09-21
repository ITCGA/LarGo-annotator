#!/usr/bin/env perl

package TriAnnot::Programs::FuncAnnot;

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

# CPAN modules
use File::Basename;

## Bioperl modules
use Bio::SearchIO;
use Bio::Tools::GFF;
use Bio::SeqIO;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Programs::Programs;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Programs::Programs);


##################################################
## Methods
##################################################
=head1 TriAnnot::Programs::FuncAnnot - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, $attrs_ref) = @_;

	# Check the type of the second argument
	if (ref($attrs_ref) ne 'HASH') {
		$logger->logdie('Error: FuncAnnot.pm constructor is expecting a hash reference as second argument !');
	}

	# Call the constructor of the parent class (TriAnnot::Programs::Programs)
	my $self = $class->SUPER::new($attrs_ref);

	# Allow the use of Multi-fasta sequence file
	$self->{'allowMultiFasta'} = 'yes';

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

	# Store some path and names in the current object for easier access
	$self->_managePathsAndNames();
}


sub _managePathsAndNames {

	# Recovers parameters
	my $self = shift;

	$self->{'annotationResults'}  = {}; # Each key is a step name and each value is the result of an annotation step
	$self->{'commandLines'}       = {}; # Each key is a step name and each value is the complete command line executed for this step

	$self->{'outFile'} = 'Functional_annotation_results.txt';

	if ($self->{'isSubAnnotation'} eq 'yes') {
		$self->{'needParsing'} = 'no' if ($self->{'isSubAnnotation'} eq 'yes');
	} else {
		$self->{'gffDirFullPath'} = $self->{'directory'} . '/' . $TRIANNOT_CONF{'DIRNAME'}->{'GFF_files'};
		$self->{'gffToAnnotateOriginalDirectory'} = dirname($self->{'gff_to_annotate'});
		$self->{'gffToAnnotateStandardFullPath'} = $self->{'gffDirFullPath'} . '/' . basename($self->{'gff_to_annotate'});
	}
}


#######################################
# Parameters check related methods
#######################################

sub _checkInputFiles {

	# Recovers parameters
	my $self = shift;

	# If we are not in a sub FuncAnnot we have to check the existence of the GFF file to annotate
	# This GFF input file is only used in parsing mode and there is no parsing step for a sub FuncAnnot
	# The check is made here to avoid running FuncAnnot in execution mode for nothing (ie. if the parsing will fail because the required input file is missing)
	if ($self->{'isSubAnnotation'} eq 'no') {
		# Special case: the value of the "gff_to_annotate" parameter is an external full path instead of just a filename
		if (($self->{'gffToAnnotateOriginalDirectory'} ne '.') && ($self->{'gffToAnnotateOriginalDirectory'} ne $self->{'gffDirFullPath'})) {
			# Check the existance of the external file
			$self->_checkFileExistence('external GFF ', $self->{'gff_to_annotate'});

			# Check if the symlink destination is available
			$self->_checkSymlinkDestination($self->{'gffToAnnotateStandardFullPath'}, $self->{'gff_to_annotate'});

			# Create a symlink to the existing external GFF file in the default GFF subfolder
			if (! -e $self->{'gffToAnnotateStandardFullPath'}) {
				$logger->debug('Creation of a symlink pointing to the external GFF input file in the default GFF subfolder');
				symlink($self->{'gff_to_annotate'}, $self->{'gffToAnnotateStandardFullPath'}) or $logger->logdie('Error: Cannot create a symlink to the external GFF input file in the default GFF subfolder ! (External file is: ' . $self->{'geneModelGffFile'} . ')');
			}
		} else {
			# Standard case: the GFF file to annotate is located in the default GFF subfolder
			$self->_checkFileExistence('GFF', $self->{'gffToAnnotateStandardFullPath'});
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
## Method execute() #
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Check if the protein sequence file contains at least one sequence
	if (-z $self->{'fullSequencePath'}) {
		$logger->logwarn('WARNING: Trying to run the Functional annotation procedure on an empty protein sequence file (' . $self->{'sequence'} . '). Execution is skipped.');

		# Creation of an empty output file
		$logger->debug('');
		$logger->debug('Note: Creation of an empty result file (' . $self->{'outFile'} . ')');
		open(EMPTY_OUT, '>' . $self->{'outFile'}) or $logger->logdie('Error: Cannot create the empty output file: ' . $self->{'outFile'});
		close(EMPTY_OUT);

		# Mark the execution procedure as SKIP
		$self->{'Execution_skipped'} = 'yes';
		$self->{'Skip_reason'} = 'Empty protein sequence file';

		return;
	}

	# Determine if the selected multi-fasta input file contains more than 1 sequence
	$self->_analyzeMultiFastaInputFile();

	# Simple or parallel execution of the functional annotation procedure
	if ($self->{'Number_of_sequence'} > 1) {

		# Prepare all files required for a parallel execution of the functional annotation procedure
		$self->_prepareFilesBeforeExec();

		# Launch sub FuncAnnots
		$self->_launchSubTriAnnotUnit();

		# Merge all .in files that contains the command line of each failed analysis
		# TODO

		# Merge all annotation files (.annot) located in the Sub common tmp folder
		$self->_mergeAnnotationFiles();

	} else {
		# Execute the functional annotation on the simple fasta file


		# Execute the functional annotation on the simple fasta file
		$logger->debug('');
		$logger->debug('The Functional Annotation procedure will be executed (on ' . $self->{'hostname'} . '):');

		$self->_executeAnnotationSteps();

		$logger->debug('');
		$logger->debug('End of the functionnal annotation at ' . localtime());

		# Write the annotation result into the file $self->{outFile}
		$self->_writeAnnotationToFile();
	}
}


######################
## Abstract methods
######################

sub _executeAnnotationSteps {

	# Recovers parameters
	my $self = shift;

	$logger->logdie('Error: No _executeAnnotationSteps method implemented for class ' . ref($self));

	return 0;
}


sub _createXMLStageList {

	# Recovers parameters
	my $self = shift;

	$logger->logdie('Error: No _createXMLStageList method implemented for class ' . ref($self));

	return 0;
}


####################################
## Multi fasta related methods
####################################

sub _analyzeMultiFastaInputFile {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my $Sequence_counter = 0;

	$logger->info('');
	$logger->info('Analysis of the selected multi-fasta input file:');

	# Analyze the multi-fasta input file to determine the number of sequence it contains
	my $SeqIO_input_object  = Bio::SeqIO->new ( '-file' => $self->{'fullSequencePath'}, '-format' => 'FASTA' );

	while (my $currentSequence = $SeqIO_input_object->next_seq) {
		$Sequence_counter++;
		$self->{'Sequence_ID'} = $currentSequence->display_id(); # TODO: Remove this after blast related methods refactoring
	}

	$logger->info("\tThe file " . $self->{'sequence'} . " contains " . $Sequence_counter . " sequence(s) !");

	# Store the number of sequence as an object attribute
	$self->{'Number_of_sequence'} = $Sequence_counter;

	return 0; # Success
}


sub _prepareFilesBeforeExec {

	# Recovers parameters
	my $self = shift;

	# Split the multifasta file
	$self->_splitMultiFasta();

	# Create mandatory stage list (XML file) for all Program_Launcher executions (list of the internal steps of the functionnal annotation)
	$self->_createXMLStageList();

	return 0; # Success
}


sub _splitMultiFasta {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my $SequenceCounter = 0;
	my ($Splitted_fasta_file, $Current_ID, $Protein_sequence) = ('', '', '');

	# Create a sub directory to store all splitted fasta files
	if (!-d $TRIANNOT_CONF{DIRNAME}->{'sequence_files'}) {
		mkdir($TRIANNOT_CONF{DIRNAME}->{'sequence_files'}, 0775) or $logger->logdie('Error: Cannot create directory: ' . $TRIANNOT_CONF{DIRNAME}->{'sequence_files'});
	}

	$logger->debug('');
	$logger->debug('Splitting of the multiple fasta file:');

	# Analyze the protein sequence file and split it sequence by sequence if needed
	my $SeqIO_input_object = Bio::SeqIO->new( '-file' => $self->{'fullSequencePath'}, '-format' => 'FASTA' );

	while (my $currentSequence = $SeqIO_input_object->next_seq) {
		# Initializations

		my $singleFastaFile = $TRIANNOT_CONF{DIRNAME}->{'sequence_files'} . '/' . 'sequence_' . ++$SequenceCounter . '.seq';

		# Create a fasta output stream
		my $outputStream = Bio::SeqIO->new(-file => '>' . $singleFastaFile, -format => 'FASTA');

		# Write translated sequence on the output stream
		$outputStream->write_seq($currentSequence);
	}

	$logger->debug('End of the splitting procedure');

	return $SequenceCounter;
}


###############################################
## Annotation file creation related methods
###############################################

sub _mergeAnnotationFiles {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my $Directory_to_browse = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'tmp_files'};
	my $Global_annotation_file_fullpath = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'outFile'};
	my (@All_files, @filesToMerge) = ((), ());

	$logger->debug('');
	$logger->debug('Global Annotation file creation - Start at ' . localtime());

	# Lists file of the Sub common tmp folder
	opendir(ANNOT_DIR, $Directory_to_browse) or $logger->logdie('Error: Cannot open/read directory: ' . $Directory_to_browse);
	@All_files = readdir(ANNOT_DIR);
	closedir(ANNOT_DIR);

	# Select annotation files to merge
	foreach my $file (@All_files) {
		if ($file =~ /\.annot$/) {
			push(@filesToMerge, $Directory_to_browse . '/' . $file);
		}
	}

	if (scalar(@filesToMerge) < $self->{'Number_of_sequence'}) {
		$logger->logwarn('Unlikely event: the number of annotation result is lower than the number of protein sequence to annotate ! Something might have gone wrong during the annotation process...');
		$logger->logwarn('=> Global annotation result file will not be created and the <exit_status> tag of the main XML abstract file will be equal to ERROR !');

	} else {
		# Creation of the global annotation file
		open(MERGE, '>' . $Global_annotation_file_fullpath) or $logger->logdie('Error: Cannot create/open file: ' . $Global_annotation_file_fullpath);
		foreach my $fileToMerge (@filesToMerge) {
			$logger->debug("\tMerging " . basename($fileToMerge) . " into " . basename($Global_annotation_file_fullpath));

			open(TEMPO, '<' . $fileToMerge) or $logger->logdie('Error: Cannot open/read file: ' . $fileToMerge);
			while (<TEMPO>) { print MERGE $_; }
			close(TEMPO);
		}
		close(MERGE);
	}

	$logger->debug('Global Annotation file creation - Stop at ' . localtime());

	return 0; # Success
}


sub _writeAnnotationToFile {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my $Annotation_file_fullpath = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'outFile'};

	# Add the annotation of the current protein sequence to the annotation result file
	open (FINAL_ANNOT, '>' . $Annotation_file_fullpath) or $logger->logdie('Error: Cannot create/open file: ' . $Annotation_file_fullpath);
	print FINAL_ANNOT $self->{'Sequence_ID'} . "\t" . $self->{'annotationResults'}->{'Final'} . "\n";
	close (FINAL_ANNOT);

	# Creation of a symlink to the new annotation file into the Sub common tmp folder (for Sub FuncAnnot only)
	if ($self->{'isSubAnnotation'} eq 'yes') {
		symlink($Annotation_file_fullpath, $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'tmp_files'} . '/Program_' . $self->{'programID'} . '.annot')
			or $logger->logdie('Error: Cannot create a symlink in the Sub common tmp folder for file: ' . $self->{'outFile'});
	}

	return 0; # Success
}


#####################################################
## Parallel annotation launching related methods
#####################################################

sub _launchSubTriAnnotUnit {

	# Recovers parameters
	my $self = shift;

	# Check if the mandatory XML stagelist for Program Launcher exists and is not empty
	if (!-e $self->{'program_launcher_stagelist'} || -z $self->{'program_launcher_stagelist'}) {
		$logger->logdie('Error: The XML stagelist (' . $self->{'program_launcher_stagelist'} . ') required to execute TAP_Program_Launcher does not exists in the current folder');
	}

	# Building of the TriAnnotPipeline command line
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{'TriAnnotUnit'}->{'bin'};

	$cmd .= ' --sequence ' .  $self->{'fullSequencePath'};
	$cmd .= ' --tasks ' .  $self->{'program_launcher_stagelist'};
	$cmd .= ' --config ' .  $TRIANNOT_CONF{'Runtime'}->{'configFile'};
	$cmd .= ' --clean c'; # disable the removal of the common folder
	$cmd .= ' --runner ' . $self->{'taskJobRunnerName'};
	$cmd .= ($TRIANNOT_CONF_VERBOSITY == 3) ? ' --debug' : '';

	# Log the newly build command line
	$logger->debug('');
	$logger->debug('Sub TriAnnot Unit (for the Functional Annotation procedure) will be executed (from ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);
	$logger->debug('');

	# Execute command
	my $subTriAnnotOutput = `$cmd 2>&1`;
	$logger->debug('## Sub TriAnnot Pipeline log - START ##');
	$logger->debug($subTriAnnotOutput);
	$logger->debug('## Sub TriAnnot Pipeline log - END ##');

	return 0; # Success
}


################################
## HMMscan related methods
################################

sub hmmscanAnnotation {

	# Recovers parameters
	my ($self, $Current_step) = @_;

	# Initializations
	my $Annotation_result = '-';
	my $HMMscan_result_file = 'Results_for_' . $Current_step . '_HMMscan.res';

	# Log
	$logger->debug('');
	$logger->debug("\t" . $Current_step . ': ' . $self->buildStepDescriptionString($Current_step) . ' (Start at ' . localtime() . ')');

	# Command line building
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{'HMMscan'}->{'bin'} . ' --acc --noali --qformat fasta';

	$cmd .= ' --cpu ' . $self->{'nbCore'};
	$cmd .= ' -E ' . $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{$Current_step}->{'evalue'};
	$cmd .= ' -o std_temp_output.res';
	$cmd .= ' --tblout ' . $HMMscan_result_file;
	$cmd .= ' ' . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'database_' . $Current_step}}->{'path'} . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'database_' . $Current_step}}->{'HMMExtension'};
	$cmd .= ' ' . $self->{'fullSequencePath'};

	# Save the newly build command line and execute it
	$self->{'commandLines'}->{$Current_step} = $cmd;

	# Execute command
	my $cmdOutput = `$cmd 2>&1`;
	$logger->debug(">>>>>>>> Start of execution output <<<<<<<<");
	$logger->debug($cmdOutput);
	$logger->debug(">>>>>>>>  End of execution output  <<<<<<<<");

	# Parse Hmmscan output file if it exists
	if (-e $HMMscan_result_file){
		$Annotation_result = $self->_parseHmmscan($HMMscan_result_file, $Current_step);
	} else {
		$logger->logwarn('HMMscan (' . $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{'annotationProcedureName'} . ' annotation - ' . $Current_step . ') output file is missing (' . $HMMscan_result_file . ').');
	}

	# Log annotation result
	if ($Annotation_result ne '-') {
		$logger->debug("\t\t" . '=> ' . $Annotation_result . ' => ' . $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{$Current_step}->{'annotation_class'});
	} else{
		$logger->debug("\t\t" . '=> No result => Next annotation stage will begin soon..');
	}

	# Store annotation result for the current step in a hash table
	$self->{'annotationResults'}->{$Current_step} = $Annotation_result;

	return 0; # Success
}

sub _parseHmmscan {

	# Recovers parameters
	my ($self, $outFile, $current_step)= @_;

	# Initializations
	my $Final_HMMscan_annotation = '-';

	# Gets usefull information for the annotation from the hmmpfam resul file (read line by line)
	open(HMMSCAN, '<' . $outFile) || $logger->logdie('Error: Cannot create/open file: ' . $outFile);

	while (<HMMSCAN>){

		chomp;
		if ($_ =~ /^#/){
			next;
		} else {
			# Split table name
			my ($Target_name, $Domain_ID, $Query_name, $Unknown_acc, $fullseq_evalue, $fullseq_score, $fullseq_bias, $best1domain_evalue, $best1domain_score, $best1domain_bias, $dne_exp, $dne_reg, $dne_clu, $dne_ov, $dne_env, $dne_dom, $dne_rep, $dne_inc, $Target_description) = split(/\s+/, $_, 19);

			# Clean Target description
			$Target_description =~ s/[^\w\-\(\)\|]/ /g;
			$Target_description =~ tr/ //s;

			# Build annotation string
			if ($Final_HMMscan_annotation eq '-') {
				$Final_HMMscan_annotation = 'Note=HMMScan - ' . $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{$current_step}->{'annotation_class'} . ' --> ' . $Domain_ID . ' - ' . $Target_description . ' (' . $fullseq_evalue . ')';
			} else {
				$Final_HMMscan_annotation .= ',' . $Domain_ID . ' - ' . $Target_description . ' (' . $fullseq_evalue .')';
			}
		}
	}

	close(HMMSCAN);

	return $Final_HMMscan_annotation;
}


#############################
## Blast related methods
#############################

sub blastAnnotation {

	# Recovers parameters
	my ($self, $Current_step) = @_;

	# Initializations
	my $Annotation_result = '-';
	my $Blast_result_file = 'Results_for_' . $Current_step . '_Blast.res';

	# Log
	$logger->debug('');
	$logger->debug("\t" . $Current_step . ': ' . $self->buildStepDescriptionString($Current_step) . ' (Start at ' . localtime() . ')');

	# Build command line
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{'Blast'}->{'bin'} .
		' -p ' . $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{$Current_step}->{'type'} .
		' -d ' . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'database_' . $Current_step}}->{'path'} .
		' -i ' . $self->{'fullSequencePath'} .
		' -e ' . $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{$Current_step}->{'evalue'} .
		' -o ' . $Blast_result_file .
		' -b ' . $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{$Current_step}->{'concatQueries'} .
		' -v ' . $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{$Current_step}->{'concatDb'} .
		' -g ' . $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{$Current_step}->{'performAlign'} .
		' -F ' . $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{$Current_step}->{'filterSeq'} .
		' -a ' . $self->{'nbCore'};

	# Save the newly build command line and execute it
	$self->{'commandLines'}->{$Current_step} = $cmd;

	# Execute command
	my $cmdOutput = `$cmd 2>&1`;
	$logger->debug(">>>>>>>> Start of execution output <<<<<<<<");
	$logger->debug($cmdOutput);
	$logger->debug(">>>>>>>>  End of execution output  <<<<<<<<");

	# Parse Blast results if it exists
	if (-e $Blast_result_file){
		$Annotation_result = $self->_parseBlast($Blast_result_file,
				 $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{$Current_step}->{'coverageCutOff'},
				 $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{$Current_step}->{'identityCutOff'},
				 $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{$Current_step}->{'annotation_class'},
				 $self->{'Sequence_ID'});
	} else {
		$logger->logwarn('Blast (' . $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{'annotationProcedureName'} . ' annotation - ' . $Current_step . ') output file is missing (' . $Blast_result_file . ').');
	}

	# Log annotation result
	if ($Annotation_result ne '-') {
		$logger->debug("\t\t" . '=> ' . $Annotation_result . ' => ' . $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{$Current_step}->{'annotation_class'});
	} else{
		$logger->debug("\t\t" . '=> No result => Next annotation stage will begin soon..');
	}

	# Store annotation result for the current step in a hash table
	$self->{'annotationResults'}->{$Current_step} = $Annotation_result;

	return 0; # Success
}


# WARNING: very old blast parser, not up to date at all
# TODO:  Use TriAnnot V3 (or greater) generic blast parser of module Blast_parser.pm insted of this method
sub _parseBlast {
	my ($self, $outFile, $cutCoverage, $cutPid, $annot, $query_name) = @_;
	my $in;
	my $result;
	my $hit;
	my $nom;
	my $hitAcc;
	my $description="";
	my $hitLength;
	my $debut;
	my $fin;
	my $longueur;
	my $hsp;
	my $id; # identity
	my $ligne;
	my $flag01=0;
	#my $query_name;
	my $value;
	my %hash=();
	my (%res_blast)=();
	my $res_annot;
	$in = new Bio::SearchIO (-format =>'blast', -file =>$outFile);
	while($result=$in->next_result) {
		#$query_name=$result->query_name;
		while($hit = $result->next_hit) {
			$hitAcc=$hit->name;
			$hitAcc=~ s/[^\w\-\(\)\|]/ /g;
			$flag01=1;
			while($hsp = $hit->next_hsp) {

				#($hitAcc) = ($hitAcc=~ /\S+\|\S+\|(\S+)/);
				$nom=$hit->accession;
				$description=$hit->description;
				$hitLength=$hit->length;
				$debut=$hsp->start('query');
				$fin=$hsp->end('query');
				$longueur=$hsp->length;
				$id=$hsp->num_identical;
				unless ($hitAcc) {$hitAcc="-"}
				unless ($description) {$description="-";}
				$ligne=$fin.';'.$hitAcc.';'.$nom.';'.$longueur.';'.$hitLength.';'.$id.';'.$description;
				$hash{$debut}=$ligne ;
			}
		}
	}
	if ($flag01==1) {
		# Joindre les HSP pour chaque hit
		my $borne;
		my $count;
		my $longSum;
		my $coverage;
		my $idSum;
		my $idp;
		my $descriptOld="";
		my $nomOld;
		my $hitAccOld;
		my $countOld;
		my $join;
		my $flag02=0;

		foreach my $key (sort {$a<=>$b} keys %hash) {
			$value=$hash{$key};
			my @tableau01=split (';',$value);
			$debut=$key;
			$fin=$tableau01[0];
			$borne=$debut."..".$fin;
			$hitAcc=$tableau01[1];
			$nom=$tableau01[2];
			$longueur=$tableau01[3];
			$hitLength=$tableau01[4];
			$id=$tableau01[5];
			$description=$tableau01[6];
			$count=1;
			if ($hitAcc eq "") {$hitAcc="-";}
			if ($description eq "") {$description="-";}
			if ($flag02==0) {
				$join="$borne,";
				$nomOld=$nom;
				$hitAccOld=$hitAcc;
				$countOld=$count;
				$longSum=$longueur;
				$idSum=$id;
				$descriptOld=$description;
				$flag02=1;
				next;
			}

			if (($nom eq $nomOld) && ($count>$countOld)) {
				$join=$join."$borne,";
				$countOld=$count;
				$longSum=$longueur+$longSum;
				$idSum=$id+$idSum;
				$descriptOld=$description;
				$hitAccOld=$hitAcc;
			}

			else {
				($join)=($join=~ /(.+)\,$/);
				$idp=(($idSum/$longSum)*100);
				$idp= sprintf ("%4.2f",$idp);
				$coverage=(($longSum/$hitLength)*100);
				$coverage= sprintf ("%4.2f",$coverage);
				$join="$borne,";
				$nomOld=$nom;
				$countOld=$count;
				$longSum=$longueur;
				$idSum=$id;
				$descriptOld=$description;
				$hitAccOld=$hitAcc;
				$value = $join.';'.$nomOld.';'.$coverage.';'.$idp.';'.$descriptOld;
				$res_blast{$query_name}= $value;
			}
		}
		($join)=($join=~ /(.+)\,$/);
		$idp=(($idSum/$longSum)*100);
		$idp= sprintf ("%4.2f",$idp);
		$coverage=(($longSum/$hitLength)*100);
		$coverage= sprintf ("%4.2f",$coverage);
		$value = $join.';'.$nomOld.';'.$coverage.';'.$idp.';'.$descriptOld;
		$res_blast{$query_name}= $value;
		## Trie sur taux de recouvrement et le % d'identite
		foreach my $cle (keys %res_blast){
			$value=$res_blast{$cle};
			my @tableau02=split (';',$value);
			$join=$tableau02[0];
			#$hitAcc=$tableau[1];
			$nom=$tableau02[1];
			$coverage=$tableau02[2];
			$idp=$tableau02[3];
			$description=$tableau02[4];
			#if ($hitAcc eq "") {$hitAcc="-";}
			if ($description eq "") {$description="-";}
			if (($coverage > $cutCoverage) && ($idp > $cutPid)){ ## Test of coverage and identity
				my ($coord_start,$coord_stop) = split (/\.\./, $join);
				# $logger->debug("-- $coord_start $coord_stop --");
				# Eliminate unauthorized characters
				$description =~ s/[^\w\-\(\)\|]/ /g;
				# Eliminate redundant spaces
				$description =~ tr/ //s;
				$res_annot= 'Note='.$annot.' - '.$description.';function_target='.$hitAcc.' '.$coord_start.' '.$coord_stop.';function_coverage='.$coverage.';function_identity='.$idp;
			}
			else { ## Test failled... the annotation procedure must continue
				$res_annot='-';
			}
		}
	}
	else { ## If No Hit Found !!
		$res_annot="-";
	}

	return ($res_annot);
} ## END parseBlast sub


#############################
## Other methods
#############################

sub buildStepDescriptionString {

	# Recovers parameters
	my ($self, $Current_step) = @_;

	# Initializations
	my $stepData = $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{$Current_step};
	my $description = $stepData->{'programName'};
	my @details = ();

	if ($stepData->{'programName'} =~ /Blast/i) {
		$description .= ' (' . $stepData->{'type'} . ')';
	}

	$description .= ' on ' . $self->{'database_' . $Current_step} . ' [With ';

	if (defined($stepData->{'evalue'})) {
		push(@details, 'evalue < ' . $stepData->{'evalue'});
	}

	if (defined($stepData->{'identityCutOff'})) {
		push(@details, 'ID > ' . $stepData->{'identityCutOff'});
	}

	if (defined($stepData->{'coverageCutOff'})) {
		push(@details, 'Coverage > ' . $stepData->{'coverageCutOff'});
	}

	$description .= join(', ', @details) . ']';

	return $description;
}

1;
