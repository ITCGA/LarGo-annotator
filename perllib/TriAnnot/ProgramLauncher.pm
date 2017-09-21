#!/usr/bin/env perl

package TriAnnot::ProgramLauncher;

use strict;
use warnings;
use diagnostics;

## Perl modules
use File::Basename;
use Getopt::Long;
use Data::Dumper;
use XML::Twig;
use Cwd;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Launcher;
use TriAnnot::Programs::Programs;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Launcher);

#################
# Constructor
#################
sub new {
	my $class = shift;
	my $self  = $class->SUPER::new();
	$self->{launcherTitle} = "TriAnnot Pipeline Program Launcher";
	$self->{usageExample} = basename($0) . ' -stagelist my_stagelist.xml -sequence my_seq.tfa -conf ~/my_conf_file.xml -pid 1 -workdir ~/analysis/my_new_directory';
	return $self;
}

sub getOptions {
	my $self = shift;
	my @specificOptions = ();
	$self->SUPER::getOptions(\@specificOptions);
}

sub checkSpecificOptionsToHandleBeforeLoadingConfigurationFiles {
	my $self = shift;
}

sub checkSpecificOptionsToHandleAfterLoadingConfigurationFiles {
	my $self = shift;
}

sub displaySpecificParameters {
	my $self = shift;
}

sub displaySpecificHelpMessage {
	my $self = shift;
}

sub createSpecificSubDirectories {
	my $self = shift;
	$self->{sequence_repository} = $self->{Working_directory} . '/' . $TRIANNOT_CONF{DIRNAME}->{'sequence_files'};
	if (!-e $self->{sequence_repository}) { mkdir($self->{sequence_repository}, 0755); }
}

sub _createComponentObject {
	my $self = shift;
	# Create a new program object via TriAnnot::Programs::Programs factory method
	$self->{componentObject} = TriAnnot::Programs::Programs->factory(
			'programName'  => $self->{programName},
			'programID'    => $self->{Program_id},
			'step'         => $self->{step},
			'stepSequence' => $self->{stepSequence},
			'directory'    => $self->{Working_directory});
}

sub _doTreatment {
	my $self = shift;
	# Check database's files and other input files existence before execution
	$self->{componentObject}->_checkInputFiles();

	# Execution of the selected programs
	$self->{componentObject}->execute();

}


sub _addSpecificContentToAbstractFile {

	# Recovers parameters
	my ($self, $TwigRoot) = @_;

	# Initializations
	my $Output_file_fullpath = $self->{'Working_directory'} . '/' . $self->{'componentObject'}->{'tmpFolder'} . '/' . $self->{'componentObject'}->{'outFile'};

	# Add generic content for execution modules
	# Execution skipped
	if (defined($self->{'componentObject'}->{'Execution_skipped'}) && $self->{'componentObject'}->{'Execution_skipped'} eq 'yes') {
		$TwigRoot->insert_new_elt('last_child', 'exit_status', 'SKIP');
		$TwigRoot->insert_new_elt('last_child', 'explanation', $self->{'componentObject'}->{'Skip_reason'}) if (defined($self->{'componentObject'}->{'Skip_reason'}));
		$TwigRoot->insert_new_elt('last_child', 'output_file', $Output_file_fullpath);
		$TwigRoot->insert_new_elt('last_child', 'output_file_size', '0');

	# Execution successful
	} elsif (-f $Output_file_fullpath) {
		$TwigRoot->insert_new_elt('last_child', 'exit_status', 'OK');
		$TwigRoot->insert_new_elt('last_child', 'analysis_folder', $self->{'componentObject'}->{'tmpFolder'});
		$TwigRoot->insert_new_elt('last_child', 'output_file', $Output_file_fullpath);
		$TwigRoot->insert_new_elt('last_child', 'output_file_size', (stat($Output_file_fullpath))[7]);

		# Benchmark
		if (defined($self->{'componentObject'}->{'benchmark'}->{'exec'})) {
			my $benchmark = $TwigRoot->insert_new_elt('last_child', 'benchmark');
			my $times = $benchmark->insert_new_elt('last_child', 'times');

			$times->insert_new_elt('real', $self->{'componentObject'}->{'benchmark'}->{'exec'}->[0]);
			$times->insert_new_elt('cpu', ($self->{'componentObject'}->{'benchmark'}->{'exec'}->[1] + $self->{'componentObject'}->{'benchmark'}->{'exec'}->[2] + $self->{'componentObject'}->{'benchmark'}->{'exec'}->[3] + $self->{'componentObject'}->{'benchmark'}->{'exec'}->[4]));
		}

	# Execution failed
	} else {
		$TwigRoot->insert_new_elt('last_child', 'exit_status', 'ERROR');
		$TwigRoot->insert_new_elt('last_child', 'explanation', 'Output file does not exists');
		$TwigRoot->insert_new_elt('last_child', 'expected_output_file', $Output_file_fullpath);
	}

	$TwigRoot->insert_new_elt('last_child', 'need_parsing', $self->{'componentObject'}->{'needParsing'}) if (defined($self->{'componentObject'}->{'needParsing'}));

	# Sequence masking statistics (Particular case for SequenceMasker module)
	if ($self->{'programName'} =~ /SequenceMasker/) {
		$TwigRoot->insert_new_elt('last_child', 'sequence_file', $self->{'componentObject'}->{'outFile'});
		my $maskingElement = $TwigRoot->insert_new_elt('last_child', 'masking_statistics');

		$self->_addDataFromInfoFile($maskingElement);

	# Protein creation statistics (Particular case for ProteinMaker module)
	} elsif ($self->{'programName'} =~ /ProteinMaker/) {
		$TwigRoot->insert_new_elt('last_child', 'sequence_file', $self->{'sequence_repository'} . '/' . $self->{'componentObject'}->{'outFile'});
		my $proteinElement = $TwigRoot->insert_new_elt('last_child', 'protein_creation_statistics');

		$self->_addDataFromInfoFile($proteinElement);
	}

	return 0; # SUCCESS
}

1;
