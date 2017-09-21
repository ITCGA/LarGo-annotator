#!/usr/bin/env perl

package TriAnnot::Programs::InterProScan;

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
=head1 TriAnnot::Programs::InterProScan - Methods
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

	$self->{New_fasta_File}   = 'Protein_sequence_with_short_ID.faa';
}


#####################
## Method execute() #
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Check if the protein sequence file contains at least one sequence
	if (-z $self->{'fullSequencePath'}) {
		$logger->logwarn('WARNING: Trying to run InterProScan on an empty protein sequence file (' . $self->{'sequence'} . '). Execution is skipped.');

		# Creation of an empty output file
		$logger->debug('Note: Creation of an empty InterProScan output file (' . $self->{'outFile'} . ')');
		open(EMPTY_OUT, '>' . $self->{'outFile'}) or $logger->logdie('Error: Cannot create the empty output file: ' . $self->{'outFile'});
		close(EMPTY_OUT);

		# Mark the execution procedure as SKIP
		$self->{'Execution_skipped'} = 'yes';
		$self->{'Skip_reason'} = 'Empty protein sequence file';

		return;
	}

	# Convert long sequence ID into short ID to avoid Interproscan execution (and parsing) malfunctions
	$self->_build_Fasta_with_short_ID();

	# Building of the command line (Current parse method can parse InterproScan results in raw format only)
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'} . ' -cli' .
		' -iprlookup -goterms' .
		' -format raw' .
		' -i ' . $self->{'New_fasta_File'} .
		' -o ' . $self->{'outFile'};

	# Application list
	# Important Note: if the list of application to execute is empty then InterproScan will be launched on all programs/applications and the "-appl" option is useless
	if (defined($self->{'applications'})) {
		foreach my $application (@{$self->{'applications'}}) {
			print "Added application: " . $application . "\n";
			$cmd .= ' -appl ' . $application;
		}
	}

	# Verbosity
	if ($TRIANNOT_CONF_VERBOSITY >= 1) { $cmd .= ' -v'; }

	# Execution of the command line
	$logger->debug('InterProScan will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	my $cmdOutput = `$cmd 2>&1`;
	$logger->debug(">>>>>>>> Start of execution output <<<<<<<<");
	$logger->debug($cmdOutput);
	$logger->debug(">>>>>>>>  End of execution output  <<<<<<<<");
}

###################
## Internal Methods
###################

sub _build_Fasta_with_short_ID {

	# Recovers parameters
	my ($self, $protein_sequence_file) = @_;

	# Initializations
	my $Sequence_counter = 0;

	# Create a fasta input stream to read the input fasta file with long IDs
	my $inputStream = Bio::SeqIO->new(-format => 'FASTA', -file => $self->{'fullSequencePath'});

	# Create a fasta output stream to write the output fasta file with short IDs
	my $outputStream = Bio::SeqIO->new(-file => '>' . $self->{'New_fasta_File'}, -format => 'FASTA');

	# Browse the original fasta file and write ID correspondence (short ID to Long ID) into a formated text file
	open(CORRESPONDENCE, '>' . $self->{'sequenceIDsFile'}) or $logger->logdie('Error: Cannot create/open file: ' . $self->{'sequenceIDsFile'}); # Writing mode

	while (my $inputSequence = $inputStream->next_seq()) {
		# Build and write the new sequence
		my $shortID = 'Seq_' . sprintf("%05d", ++$Sequence_counter);
		my $newSequenceObject = Bio::Seq->new( -id => $shortID , -seq => $inputSequence->seq(), -desc => 'length=' . $inputSequence->length() );
		$outputStream->write_seq($newSequenceObject);

		# Store ID correspondence
		print CORRESPONDENCE $shortID . ";" . $inputSequence->display_name() . "\n";
	}

	close(CORRESPONDENCE);
}


#####################
## New Files management
#####################

sub _generatedFilesManagement {

	# Recovers parameters
	my $self = shift;

	# Create a symlink to the ID correspondence file in the common tmp folder
	if (-e $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'sequenceIDsFile'}) {
		$logger->debug('');
		$logger->debug('Note: Creation of a symlink to the newly generated ID correspondence file (short ID to long ID) in the common tmp folder');
		symlink($self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'sequenceIDsFile'}, $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'tmp_files'} . '/' . $self->{'sequenceIDsFile'})
			or $logger->logdie('Error: Cannot create a symlink to file: ' . $self->{'sequenceIDsFile'});
	}
}

1;
