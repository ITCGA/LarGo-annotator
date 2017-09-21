#!/usr/bin/env perl

package TriAnnot::Programs::Eugene;

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

## Other Perl modules
use Storable;
use File::Basename;

## Debug module
use Data::Dumper;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Programs::Programs;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Programs::Programs);

##################################################
## Methods
##################################################

=head1 TriAnnot::Programs::Eugene - Methods
=cut

#################
# Methode new() #
#################

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

	# Files and directories names
	$self->{'gffDirName'} = $TRIANNOT_CONF{'DIRNAME'}->{'GFF_files'};
	$self->{'commonsDirName'} = $TRIANNOT_CONF{'DIRNAME'}->{'tmp_files'};
	$self->{'igFileName'} = basename($self->{'igFile'}) if (defined($self->{'igFile'}));

	$self->{'genericSequenceName'} = 'Eugene_input_sequence';

	# Files and directories paths
	$self->{'gffDirPath'} = $self->{'directory'} . '/' . $self->{'gffDirName'};
	$self->{'commonsDirPath'} = $self->{'directory'} . '/' . $self->{'commonsDirName'};
	$self->{'igFileFullPath'} = $self->{'commonsDirPath'} . '/' . $self->{'igFileName'} if (defined($self->{'igFile'}));
}


####################
##  Check methods  #
####################

sub _checkInputFiles {

	# Recovers parameters
	my $self = shift;

	# Check the existence of the eugene parameter file (should have already been done in python)
	$self->_checkFileExistence('.par', $self->{'eugeneParFileFullPath'});

	# Check the IG file if needed
	if (defined($self->{'igFileFullPath'})) {
		$self->_checkFileExistence('IG', $self->{'igFileFullPath'});
	}

	# Check evidence files existence if needed
	if (defined($self->{'evidenceFile'})) {
		$self->checkEvidenceFilesExistence();
	}
}

sub checkEvidenceFilesExistence {

	# Recovers parameters
	my $self = shift;

	# Initialization
	$self->{'evidenceFilesCorrespondance'} = {};

	# Loop through the list of
	if (ref($self->{'evidenceFile'}) eq 'ARRAY') {
		foreach my $evidenceFile (@{$self->{'evidenceFile'}}) {
			# Separate the input GFF file name from the extension to use during the renaming step (Format is already checked in the Python code)
			my ($gffFileName, $eugeneExtension) = split(/\|/, $evidenceFile);

			# Check existence of the GFF input file
			my $gffFileFullPath = $self->{'gffDirPath'} . '/' . $gffFileName;
			$self->_checkFileExistence('GFF input', $gffFileFullPath);

			# Store the correspondance between the reall input file (GFF) and the name it should have in the Eugene execution directory
			$self->{'evidenceFilesCorrespondance'}->{$gffFileName} = { 'gffFileFullPath' => $gffFileFullPath, 'eugeneCompatibleName' => $self->{'genericSequenceName'} . '.' . $eugeneExtension };
		}
	} else {
		$logger->logdie('Error: The type of the evidenceFile parameter should always be ARRAY ! (Current value: ' . ref($self->{'evidenceFile'}) . ')');
	}
}

#####################
## Method execute() #
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Initialization of some environment variables before execution
	$self->_prepareEnvBeforeExec();

	# Prepare Eugene parameter file before execution
	$self->_prepareFilesBeforeExec();

	# Building of the command line (-pg to generate gff3 file, -A for eugene config file)
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'} . ' -pg -A ' . $self->{'eugeneParFileFullPath'} . ' ' . $self->{'genericSequenceName'};

	# Log the newly build command line
	$logger->debug('Eugene will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	my $cmdOutput = `$cmd 2>&1`;
	$logger->debug(">>>>>>>> Start of execution output <<<<<<<<");
	$logger->debug($cmdOutput);
	$logger->debug(">>>>>>>>  End of execution output  <<<<<<<<");

	# Renaming of the main output file
	rename ($self->{'genericSequenceName'} . '.gff3',  $self->{'outFile'}) or $logger->logdie('Error: Cannot rename Eugene brut output file (' . $self->{'genericSequenceName'} . '.gff3) into ' . $self->{'outFile'});
}


#########################################
## Environment and configuration files preparation related methods
#########################################

sub _prepareEnvBeforeExec {

	# Recovers parameters
	my $self = shift;

	# Define some mandatory environment variables
	$ENV{'EUGENEDIR'} = $TRIANNOT_CONF{PATHS}->{config}->{$self->{'programName'}}->{'path'};

	return 0; # Success
}


sub _prepareFilesBeforeExec {

	# Recovers parameters
	my $self = shift;

	# There is no output option for Eugene, therefore the name of the output file is always the name of the input sequence plus the .gff3 extension (Example: if the sequence name is my_seq.seq the output file will be my_seq.seq.gff3)
	# Hovewer if the sequence name contains some particular extensions (.fasta, .fsa, .tfa, .txt) this extension is removed (Example: if the sequence name is seq.tfa the output file will be seq.gff3)
	# The best way to avoid those particular cases is to rename the input sequence with a generic name before the execution
	rename($self->{'sequence'}, $self->{'genericSequenceName'});

	# Renaming of the IG file (that contains the positions of the repeats identified by RepeatMasker) in the Eugene execution directory
	if (defined($self->{'igFileFullPath'})) {
		$logger->info('The selected .ig file is: ' . $self->{'igFileName'});
		symlink($self->{'igFileFullPath'}, $self->{'genericSequenceName'} . '.ig') or $logger->logdie('Error: Cannot create a symlink to file: ' . $self->{'igFileFullPath'});
	}

	# Creation of edited ('polypeptide' becomes 'CDS') and renamed copies of the input GFF evidence files
	$self->_prepareEvidenceFiles();

	return 0; # SUCCESS
}


sub _prepareEvidenceFiles {

	# Recovers parameters
	my $self = shift;

	# Log
	$logger->info('The selected evidence files are: ' . join(', ', keys %{$self->{'evidenceFilesCorrespondance'}}));

	# Creation of the edited copies of the input evidence files
	foreach my $evidenceFileName (keys %{$self->{'evidenceFilesCorrespondance'}}) {
		# Open both input and output file
		open(SRC_FILE, '<' . $self->{'evidenceFilesCorrespondance'}->{$evidenceFileName}->{'gffFileFullPath'}) or $logger->logdie('Error: Cannot open/read file: ' . $self->{'evidenceFilesCorrespondance'}->{$evidenceFileName}->{'gffFileFullPath'});
		open(DEST_FILE, '>' . $self->{'evidenceFilesCorrespondance'}->{$evidenceFileName}->{'eugeneCompatibleName'}) or $logger->logdie('Error: Cannot create/open file: ' . $self->{'evidenceFilesCorrespondance'}->{$evidenceFileName}->{'eugeneCompatibleName'});

		# Edition
		while (my $originalLine = <SRC_FILE>) {
			$originalLine =~ s/\tpolypeptide\t/\tCDS\t/;
			print DEST_FILE $originalLine;
		}

		close(DEST_FILE);
		close(SRC_FILE);
	}

	return 0; # SUCCESS
}

1;
