#!/usr/bin/env perl

package TriAnnot::Component;

##################################################
## Documentation POD
##################################################

##################################################
## Included modules
##################################################
## Basic Perl modules
use strict;
use warnings;
use diagnostics;

## Perl modules
use File::Basename;

## BioPerl modules
use Bio::SeqIO;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::Logger;

##################################################
# Component object factory
##################################################

sub factory {

	# Recovers parameters
	my ($Factory_module, %All_attributes) = @_; # Note: $Factory_module is the name of the current module (TriAnnot::Programs::Programs or TriAnnot::Programs::Parsers)

	if (!defined($All_attributes{'programName'})) {
		$logger->logdie("Error: No programName passed to Programs factory method");
	}

	# Initializations
	my @Class_hierarchy = split(/::/, $Factory_module);
	my $Last_level = pop(@Class_hierarchy);
	my $New_object_class = join('::', @Class_hierarchy) . '::' . $All_attributes{'programName'};

	$logger->debug($Factory_module . ' factory is trying to create a new ' . $All_attributes{'programName'} . ' object using module ' . $New_object_class);

	# Test if the selected module exists or not
	eval "require $New_object_class";
	if ($@) {
		$logger->debug('   => Module ' . $New_object_class . ' cannot be used !');
		$logger->debug('');
		$logger->logdie($@);
	} else {
		$logger->debug('   => Module ' . $New_object_class . ' is ready to be used !');
		$logger->debug('');
	}

	return $New_object_class->new(%All_attributes);
}


sub setSequence {
	my ($self, $sequencePath) = @_;

	if (!-e $sequencePath) {
		$logger->logdie("Sequence file does not exists: $sequencePath");
	}
	$self->{fullSequencePath} = Cwd::realpath($sequencePath);
	$self->{sequence} = basename($self->{fullSequencePath});
	$self->_analyzeSequenceFile();
}


############################
#  Output files management related methods
############################

# Abstract method
sub _generatedFilesManagement {

	# Recovers parameters
	my $self = shift;

	# Display a debug message for module where this method is not redefined
	$logger->debug('');
	$logger->debug('Note: There are neither symlink to create nor files to move for this program');
}


###############
#  All Get methods
###############

sub getBenchmark {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my ($subName, $benchResult);
	my $strResult = '';

	# Building of the benchmark string
	while (($subName, $benchResult) = each(%{$self->{'benchmark'}})) {
		$strResult .= $self->{'step'} . "\t" . ref($self) . "\t";
		if (defined($self->{'database'})) {
			$strResult .= $self->{'database'};
		}
		$strResult .= "\t$subName\t" . Benchmark::timestr($benchResult) . "\n";
	}
	$strResult =~ s/\n+$//;

	return $strResult;
}


######################
# Check methods
######################

# Abstract method
sub _checkInputFiles {

	# Recovers parameters
	my $self = shift;

	# Display a debug message for module where this method is not redefined
	$logger->debug('');
	$logger->debug('Note: There are no specific input files to check for this program');
	$logger->debug('');
}


sub _checkFileExistence {
	my ($self, $file_type, $selected_file) = @_;

	# Check if the selected file exists in the appropriate folder
	if (! -e $selected_file) {
		$logger->logdie('Error: The ' . $file_type . ' file (' . basename($selected_file) . ') given to ' . ref($self) . ' constructor does not exists in the following folder: ' . dirname($selected_file));
	}
}


#############################################
# Input Sequence File Analysis
#############################################

sub _analyzeSequenceFile {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my ($sequenceCounter, $rejectedSequenceCounter) = (0, 0);
	my @sequenceMetadatas = ();

	# Check sequence path
	if (!defined($self->{'fullSequencePath'})) {
		$logger->logdie('The fullSequencePath attribute must have been set within the setSequence method before calling the _analyzeSequenceFile method');
	}

	# Create a Bio::SeqIO object
	my $inputStream = Bio::SeqIO->new(-file => $self->{'fullSequencePath'}, -format => 'fasta');

	# Analyze sequences
	while (my $seqObject = $inputStream->next_seq()) {
		# Is multi-fasta supported for current module ?
		if ($sequenceCounter == 1 && $self->{'allowMultiFasta'} eq 'no') {
			$logger->logdie('The selected sequence file appears to be a multi-fasta file but module ' . $self->{'programName'} . ' does not support them !! Execution aborted..');
		}

		# Check the sequence for non authorized characters (non IUPAC)
		if ($seqObject->seq() =~ /([^ARNDCQEGHILKMFPSTWYVBZXUQEILFPZ*]+)/i) {
			$logger->debug('Warning: Sequence "' . $seqObject->display_id() . '" contains non authorized characters (' . $1 . ') and will be rejected..');
			$rejectedSequenceCounter++;
		} else {
			# Save informations about the sequence
			push(@sequenceMetadatas, { 'name' => $seqObject->display_name(), 'alphabet' => $seqObject->alphabet(), 'length' => $seqObject->length() });
		}
		$sequenceCounter++;
	}

	# Some logs
	$logger->info('The input sequence file contains ' . $sequenceCounter . ' sequence(s) (' . $rejectedSequenceCounter . ' of them has/have been rejected)');

	# Controls
	if ($sequenceCounter == $rejectedSequenceCounter) {
		$logger->logdie('All sequences contained in the selected fasta file have been rejected !! Execution aborted..');
	}

	# Backward compatibility (TODO: remove the following instructions when the multi-fasta support will be applied in all modules)
	if ($self->{'allowMultiFasta'} eq 'no') {
		$self->{'sequenceName'} = $sequenceMetadatas[0]->{'name'};
		$self->{'sequenceLength'} = $sequenceMetadatas[0]->{'length'};
	}
}

1;
