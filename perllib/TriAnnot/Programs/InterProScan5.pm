#!/usr/bin/env perl

package TriAnnot::Programs::InterProScan5;

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

# CPAN modules
use File::Copy;
use Capture::Tiny 'capture';

## BioPerl modules
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
=head1 TriAnnot::Programs::InterproScan5 - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class (TriAnnot::Programs::Programs)
	my $self = $class->SUPER::new(\%attrs);

	$self->{'allowMultiFasta'} = 'yes';

	bless $self => $class;

	return $self;
}

sub setParameters {
	my ($self, $parameters) = @_;

	# Call parent class method (See Programs.pm module for more information)
	$self->SUPER::setParameters($parameters);

	$self->{'modifiedFastaFile'} = 'Protein_sequences_without_final_asterik.faa';
	$self->{'outputFilesPrefix'} = $self->{'programName'} . '_results';
}


#####################
## Method execute() #
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Check if the protein sequence file contains at least one sequence
	if (-z $self->{'fullSequencePath'}) {
		$logger->logwarn('WARNING: Trying to run InterproScan5 on an empty protein sequence file (' . $self->{'sequence'} . '). Execution is skipped.');

		# Creation of an empty output file
		$logger->debug('Note: Creation of an empty InterproScan5 output file (' . $self->{'outFile'} . ')');
		open(EMPTY_OUT, '>' . $self->{'outFile'}) or $logger->logdie('Error: Cannot create the empty output file: ' . $self->{'outFile'});
		close(EMPTY_OUT);

		# Mark the execution procedure as SKIP
		$self->{'Execution_skipped'} = 'yes';
		$self->{'Skip_reason'} = 'Empty protein sequence file';

		return;
	}

	# Convert long sequence ID into short ID to avoid InterproScan5 execution (and parsing) malfunctions
	$self->_build_Fasta_without_final_asterisk();

	# Building of the command line (Current parse method can parse InterproScan5 results in tsv format only)
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'};

	$cmd .= ' -i ' . $self->{'modifiedFastaFile'} . ' -b ' . $self->{'outputFilesPrefix'} . ' -f XML, svg';
	if ($self->{'desactivateMatchLookup'} eq "yes") { $cmd .= ' --disable-precalc'; }
	if ($self->{'activateOptionalLookups'} eq "yes") { $cmd .= ' --iprlookup --goterms --pathways'; }

	# Application list
	# Important Note: if the list of application to execute is empty then InterproScan5 will be launched on all programs/applications and the "-appl" option is useless
	if (defined($self->{'applications'})) {
		foreach my $application (@{$self->{'applications'}}) {
			$cmd .= ' -appl ' . $application;
		}
	}

	# Execution of the command line
	$logger->debug('InterProScan5 will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	my ($stdout, $stderr, $exitCode) = capture { system($cmd); };

	# Avoid "uninitialized value" warning with outdated versions of the Capture::Tiny module
	if (!defined($exitCode) or $exitCode eq '') {
		$exitCode = 'undefined (Please upgrade your "Capture::Tiny" CPAN module to version 0.24 or greater)';
	}

	# Log the result
	$logger->debug('');
	$logger->debug('InterProScan5 exit code is: ' . $exitCode);

	$logger->debug("####################################");
	$logger->debug("##  External Tool Output - START  ##");
	$logger->debug("####################################");
	$logger->debug($stdout);
	$logger->debug("##################################");
	$logger->debug("##  External Tool Output - END  ##");
	$logger->debug("##################################");

	# Renaming of the output files
	if (-e $self->{'outputFilesPrefix'} . '.xml') {
		# Renaming of the main output file
		rename ($self->{'outputFilesPrefix'} . '.xml',  $self->{'outFile'});
	}

	if (-e $self->{'outputFilesPrefix'} . '.svg.tar.gz') {
		# Renaming of the SVG tarball
		rename ($self->{'outputFilesPrefix'} . '.svg.tar.gz',  $self->{'svgTarball'});
	}
}

###################
## Internal Methods
###################

sub _build_Fasta_without_final_asterisk {

	# Recovers parameters
	my ($self, $protein_sequence_file) = @_;

	# Initializations
	my $Sequence_counter = 0;

	# Create a fasta input stream to read the input fasta file with long IDs
	my $inputStream = Bio::SeqIO->new(-format => 'FASTA', -file => $self->{'fullSequencePath'});

	# Create a fasta output stream to write the modified sequences
	my $outputStream = Bio::SeqIO->new(-file => '>' . $self->{'modifiedFastaFile'}, -format => 'FASTA');

	# Browse the original fasta file and remove the final */stop amino acid
	while (my $inputSequence = $inputStream->next_seq()) {
		# Remove the final character if it's an asterisk
		my $finalCharacter = substr($inputSequence->seq(), -1);
		my $newSequenceObject = '';

		if ($finalCharacter eq '*') {
			$newSequenceObject = Bio::Seq->new( -id => $inputSequence->display_name() , -seq => substr($inputSequence->seq(), 0, -1), -desc => 'length=' . $inputSequence->length() );
		} else {
			$newSequenceObject = Bio::Seq->new( -id => $inputSequence->display_name() , -seq => $inputSequence->seq(), -desc => 'length=' . $inputSequence->length() );
		}

		# Write the new sequence object
		$outputStream->write_seq($newSequenceObject);
	}
}


#####################
## New Files management
#####################

sub _generatedFilesManagement {

	# Recovers parameters
	my $self = shift;

	# Move the new InterProScan5 SVG tarball in the the long term conservation directory
	if (-e $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'svgTarball'}) {
		$logger->debug('');
		$logger->debug('Note: Moving of the newly generated InterProScan5 SVG tarball into into the ' . $TRIANNOT_CONF{DIRNAME}->{'keep_files'} . ' folder for long term conservation');
		move($self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'svgTarball'}, $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'keep_files'} . '/' . $self->{'svgTarball'}) or $logger->logdie('Error: Cannot move the newly generated InterProScan5 SVG tarball: ' . $self->{'svgTarball'});
	}
}

1;
