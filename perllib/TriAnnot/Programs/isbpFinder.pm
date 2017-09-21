#!/usr/bin/env perl

package TriAnnot::Programs::isbpFinder;

##################################################
## Documentation POD
##################################################

##################################################
## Modules
##################################################
## Perl modules
use strict;
use warnings;
use diagnostics;

## Perl modules
use XML::Twig;
use File::Basename;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Programs::Programs;
use TriAnnot::Tools::Logger;

## Debug module
use Data::Dumper;

## Inherits
our @ISA = qw(TriAnnot::Programs::Programs);

##################################################
## Methods
##################################################
=head1 TriAnnot::Programs::isbpFinder - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class (TriAnnot::Programs::Programs)
	my $self = $class->SUPER::new(\%attrs);

	bless $self => $class;

	return $self;
}


#####################
## Method execute()
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my $isbpFinderStdErrorFile = 'isbpFinder.err';
	my $RepeatMasker_result = $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'tmp_files'} . '/' . $self->{'RepeatMasker_output_file'};

	# Prepare the custom configuration file before execution
	$self->_prepareCustomConfigFile();

	# Building of the command line
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'};
	$cmd .= ' --directory ' . $self->{'executionDirectory'};
	$cmd .= ' --format ' . 'gff';

	$cmd .= ' --rm ' . $RepeatMasker_result;
	$cmd .= ' --lib ' . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'database'}}->{'path'} . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'database'}}->{'FastaExtension'};

	$cmd .= ' --min_amplicon_length ' . $self->{'minPrimerProductSize'};
	$cmd .= ' --max_amplicon_length ' . $self->{'maxPrimerProductSize'};

	if (defined($self->{'confidenceFilterLevels'})) {
		foreach my $level (@{$self->{'confidenceFilterLevels'}}) {
			$cmd .= ' --filter_by_confidence ' . $level;
		}
	}

	if (defined($self->{'junctionFilterList'})) {
		foreach my $junction (@{$self->{'junctionFilterList'}}) {
			$cmd .= ' --filter_by_confidence ' . $junction;
		}
	}

	$cmd .= ' --reject_uncomplete ' . $self->{'descriptionFilterSwitch'};
	$cmd .= ' --reject_identical ' . $self->{'identicalFilterSwitch'};
	$cmd .= ' --reject_unknown ' . $self->{'unknownFilterSwitch'};

	$cmd .= ' --config ' . $self->{'configFile'};
	$cmd .= ' --debug ' if ($TRIANNOT_CONF_VERBOSITY >= 1);
	$cmd .=  ' ' . $self->{'sequence'};
	$cmd .= ' 1> /dev/null 2> ' . $isbpFinderStdErrorFile;

	# Log the newly build command line
	$logger->debug($self->{'programName'} . ' will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);
	$logger->debug('Note: ' . $self->{'programName'} . ' use log4perl to generate its own log & debug files. Please have a look at the execution directory.');

	# Execute command
	system($cmd);

	# Determine the full name of the main result file (depends on the sequence file name and the name of the sequence)
	my ($sequenceFileBaseName, $sequenceFilePath, $sequenceFileExtension) = fileparse($self->{'sequence'}, qr/\.[^.]*/);
	my $outputFileDirectory = $self->{'executionDirectory'} . '/' . $sequenceFileBaseName . '/' . $self->{'sequenceName'};
	my $outputFileName = $sequenceFileBaseName . '_' . $self->{'sequenceName'} . '.filtered_isbp.gff';

	# Management of the output file
	# Case 1: ssrFinder has not produced any output file => we have to check if an error happened or if there was no results for the analyzed sequence
	# Case 2: ssrFinder has produced a valid output file in its own execution directory => we have to create a symlink to it in the main execution directory
	if (! -f $outputFileDirectory . '/' . $outputFileName) {
		# Get the status of the execution
		my $status = _getExecutionStatus($self->{'executionDirectory'} . '/' . $self->{'programName'} . '.log');

		# Create empty outFile
		if ($status eq 'ok') {
			$logger->debug('There was no result for the analyzed sequence => Creation of an empty output file');
			open (EMPTY, '>' . $self->{'outFile'}) or $logger->logdie('Error: Cannot create/open file: ' . $self->{'outFile'});
			close (EMPTY);
		}
	} else {
		# Create a symlink to the main output file in the current folder
		symlink ($outputFileDirectory . '/' . $outputFileName, $self->{'outFile'})
			or $logger->logdie('Error: Cannot create a symlink to ' . $self->{'programName'} . ' brut output file in the execution folder');
	}
}


sub _prepareCustomConfigFile {

	# Recovers parameters
	my $self = shift;

	# Note:
	# The generated configuration file will not contains parameters that are modified through the command line

	# Creation of the twig object
	my $twig = XML::Twig->new();
	$twig->set_xml_version('1.0');
	$twig->set_encoding('ISO-8859-1');
	$twig->set_pretty_print('record');

	# Creation of the XML root
	my $XML_root = XML::Twig::Elt->new('isbpFinder', {'version' => $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'version'}});
	$twig->set_root($XML_root);

	# Bin section
	my $binSection = XML::Twig::Elt->new('section' => {name => 'Bin'});
	$binSection->paste('last_child', $twig->root);
	$binSection->insert_new_elt('entry' => {key => 'primer3ExecutablePath'}, $TRIANNOT_CONF{PATHS}->{soft}->{'Primer3'}->{'bin'});

	# Commons section
	# This section is only created to avoid useless parameters on the command line and errors in isbpFinder.pl checkParameters function
	my $commonsSection = XML::Twig::Elt->new('section' => {name => 'Commons'});
	$commonsSection->paste('last_child', $twig->root);
	$commonsSection->insert_new_elt('entry' => {key => 'csvFieldDelimiter'}, ';');
	$commonsSection->insert_new_elt('entry' => {key => 'nbThread'}, '1');

	# RepeatMasker section
	my $rmSection = XML::Twig::Elt->new('section' => {name => 'RepeatMasker'});
	$rmSection->paste('last_child', $twig->root);
	$rmSection->insert_new_elt('entry' => {key => 'extremityAreaLength'}, $self->{'extremityAreaLength'});
	# This next entry is only created to avoid useless parameters on the command line and errors in isbpFinder.pl checkParameters function
	$rmSection->insert_new_elt('entry' => {key => 'useQuickSearch'}, 'yes');

	# Primer3 section
	my $primer3Section = XML::Twig::Elt->new('section' => {name => 'Primer3'});
	$primer3Section->paste('last_child', $twig->root);
	$primer3Section->insert_new_elt('entry' => {key => 'numberOfPrediction'}, $self->{'numberOfPrediction'});

	# Filters section
	# This section is not created because those parameters will be set through the command line

	# Transposable_elements section
	my $teSection = XML::Twig::Elt->new('section' => {name => 'Transposable_elements'});
	$teSection->paste('last_child', $twig->root);

	# TE_classification sub entry
	my $teClassification = XML::Twig::Elt->new('entry' => {key => 'TE_classification'});
	$teClassification->paste('last_child' => $teSection);

	foreach my $tag (keys %{$TRIANNOT_CONF{'isbpFinder'}->{'Transposable_elements'}->{'TE_classification'}}) {
		$teClassification->insert_new_elt('last_child', 'entry' => {key => $tag}, $TRIANNOT_CONF{'isbpFinder'}->{'Transposable_elements'}->{'TE_classification'}->{$tag});
	}

	# Keywords_Order sub entry
	my $keywordsOrder = XML::Twig::Elt->new('entry' => {key => 'Keywords_Order'});
	$keywordsOrder->paste('last_child' => $teSection);

	for (my $i = 0; $i < scalar(keys %{$TRIANNOT_CONF{'isbpFinder'}->{'Transposable_elements'}->{'Keywords_Order'}}); $i++) {
		$keywordsOrder->insert_new_elt('last_child', 'entry' => {}, $TRIANNOT_CONF{'isbpFinder'}->{'Transposable_elements'}->{'Keywords_Order'}->{$i});
	}

	# TE_keywords sub entry
	my $teKeywords = XML::Twig::Elt->new('entry' => {key => 'TE_keywords'});
	$teKeywords->paste('last_child' => $teSection);

	# Keywords categories sub sub entries
	for (my $i = 0; $i < scalar(keys %{$TRIANNOT_CONF{'isbpFinder'}->{'Transposable_elements'}->{'Keywords_Order'}}); $i++) {

		my $categoryName = $TRIANNOT_CONF{'isbpFinder'}->{'Transposable_elements'}->{'Keywords_Order'}->{$i};
		my $category = XML::Twig::Elt->new('entry' => {key => $categoryName});
		$category->paste('last_child' => $teKeywords);

		foreach my $keyword (keys %{$TRIANNOT_CONF{'isbpFinder'}->{'Transposable_elements'}->{'TE_keywords'}->{$categoryName}}) {
			$category->insert_new_elt('last_child', 'entry' => {key => $keyword}, $TRIANNOT_CONF{'isbpFinder'}->{'Transposable_elements'}->{'TE_keywords'}->{$categoryName}->{$keyword});
		}
	}

	# Write the twig to generate the custom XML file
	$twig->print_to_file($self->{'configFile'});

	return 0; # SUCCESS
}


sub _getExecutionStatus {

	# Recovers parameters
	my $logFile = shift;

	# Initialization
	my $status = 'error';

	# Scan the log file for the "no result line"
	open (LOG, '<' . $logFile) or $logger->logdie('Error: Cannot open/read file: ' . basename($logFile));
	while ( my $logLine = <LOG> ) {
		if ($logLine =~ /0 repeat/i || $logLine =~ /No ISBP could be designed/i || $logLine =~ /TE junction cannot be determinded/i || $logLine =~ /no raw amplicon/i || $logLine =~ /no amplicon feature to write/i || $logLine =~ /no filtered amplicon/i) {
			$status = 'ok';
			last;
		}
	}
	close (LOG);

	# Return execution status
	return $status;
}

1;
