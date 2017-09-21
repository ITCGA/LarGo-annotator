#!/usr/bin/env perl

package TriAnnot::Programs::ssrFinder;

##################################################
## Documentation POD
##################################################

##################################################
## Modules
##################################################
## Basic Perl modules
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
=head1 TriAnnot::Programs::ssrFinder - Methods
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
	my $ssrFinderStdErrorFile = 'ssrFinder.err';

	# Prepare the custom configuration file before execution
	$self->_prepareCustomConfigFile();

	# Building of the command line
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'};
	$cmd .= ' --directory ' . $self->{'executionDirectory'};
	$cmd .= ' --config ' . $self->{'configFile'};
	$cmd .= ' --lowercase ' if ($self->{'useLowercase'} ne 'yes');
	$cmd .= ' --debug ' if ($TRIANNOT_CONF_VERBOSITY >= 1);
	$cmd .=  ' ' . $self->{'sequence'};
	$cmd .= ' 1> /dev/null 2> ' . $ssrFinderStdErrorFile;

	# Log the newly build command line
	$logger->debug($self->{'programName'} . ' will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);
	$logger->debug('Note: ' . $self->{'programName'} . ' use log4perl to generate its own log & debug files. Please have a look at the execution directory.');

	# Execute command
	system($cmd);

	# Determine the full name of the main result file (depends on the sequence file name and the name of the sequence)
	my ($sequenceFileBaseName, $sequenceFilePath, $sequenceFileExtension) = fileparse($self->{'sequence'}, qr/\.[^.]*/);
	my $outputFileDirectory = $self->{'executionDirectory'} . '/' . $sequenceFileBaseName . '/' . $self->{'sequenceName'};
	my $outputFileName = $sequenceFileBaseName . '_' . $self->{'sequenceName'} . '.gff';

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

	# Creation of the twig object
	my $twig = XML::Twig->new();
	$twig->set_xml_version('1.0');
	$twig->set_encoding('ISO-8859-1');
	$twig->set_pretty_print('record');

	# Creation of the XML root
	my $XML_root = XML::Twig::Elt->new('ssrFinder', {'version' => $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'version'}});
	$twig->set_root($XML_root);

	# Basic parameters
	my $basicSection = XML::Twig::Elt->new('section' => {name => 'Basic'});
	$basicSection->paste($twig->root);
	$basicSection->insert_new_elt('entry' => {key => 'outputFormat'}, 'gff');
	$basicSection->insert_new_elt('entry' => {key => 'primer3ExecutablePath'}, $TRIANNOT_CONF{PATHS}->{soft}->{'Primer3'}->{'bin'});

	# Advanced parameters
	my $advancedSection = XML::Twig::Elt->new('section' => {name => 'Advanced'});
	$advancedSection->paste('last_child', $twig->root);
	$advancedSection->insert_new_elt('entry' => {key => 'exclusionZoneSize'}, $self->{'exclusionZoneSize'});
	$advancedSection->insert_new_elt('entry' => {key => 'ssrFlankingRegionSize'}, $self->{'ssrFlankingRegionSize'});
	$advancedSection->insert_new_elt('entry' => {key => 'minPrimerProductSize'}, $self->{'minPrimerProductSize'});
	$advancedSection->insert_new_elt('entry' => {key => 'maxPrimerProductSize'}, $self->{'maxPrimerProductSize'});
	$advancedSection->insert_new_elt('entry' => {key => 'numberOfPrediction'}, $self->{'numberOfPrediction'});

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
		if ($logLine =~ /no SSR or Amplicon/i) {
			$status = 'ok';
			last;
		}
	}
	close (LOG);

	# Return execution status
	return $status;
}

1;
