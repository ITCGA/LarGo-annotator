#!/usr/bin/env perl

package TriAnnot::ParserLauncher;

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
use TriAnnot::Parsers::Parsers;
use TriAnnot::Tools::Logger;
use TriAnnot::Tools::EMBL_writer;

## Inherits
our @ISA = qw(TriAnnot::Launcher);

#################
# Constructor
#################
sub new {
	my $class = shift;
	my $self  = $class->SUPER::new();
	$self->{File_to_parse} = undef;
	$self->{Output_format} = undef;
	$self->{launcherTitle} = "TriAnnot Pipeline Parser Launcher";
	$self->{usageExample} = basename($0) . ' -stagelist my_stagelist.xml -conf ~/my_conf_file.xml -ftp ~/RepeatMasker/0_REPEATMASKER_TREP_plus.out -seq my_seq.tfa -pid 1 -workdir ~/analysis/my_new_directory';
	return $self;
}

sub getOptions {
	my $self = shift;
	my @specificOptions = ('filetoparse|ftp=s' => \$self->{File_to_parse}, 'outputformat|out=s' => \$self->{Output_format});
	$self->SUPER::getOptions(\@specificOptions);
}

sub checkSpecificOptionsToHandleBeforeLoadingConfigurationFiles {
	my $self = shift;
	# Deal with Output format option
	if (!defined($self->{Output_format})) {
		$logger->info('No output format defined !');
		$logger->info('Both GFF3 file and EMBL file will be created...');
		$logger->info('');

		$self->{Output_format} = 'both';
	}

	if ($self->{Output_format} !~ /^(gff|embl|both)$/) {
		$logger->info('Error: The selected output format (' . $self->{Output_format} . ') is not valid !');
		$logger->info('');
		$self->displayHelpMessage();
	}

	# Deal with filetoparse option
	if (!defined($self->{File_to_parse}) || $self->{File_to_parse} eq '') {
		$logger->info('Error: No file to parse defined !');
		$logger->info('TAP_Parser_Launcher cannot run without a valid file to parse... Exiting...');
		$logger->info('');
		$self->displayHelpMessage();
	}

	if(!-e $self->{File_to_parse}) {
		$logger->info('Error: Selected file to parse does not exists !');
		$logger->info('TAP_Program_Launcher cannot run without a valid file to parse... Exiting...');
		$logger->info('');
		$self->displayHelpMessage();
	}

	$self->{File_to_parse} = Cwd::realpath($self->{File_to_parse});

}

sub checkSpecificOptionsToHandleAfterLoadingConfigurationFiles {
	my $self = shift;
}

sub displaySpecificParameters {
	my $self = shift;
	$logger->debug('File to parse: ' . $self->{File_to_parse});
	$logger->debug('Output format: ' . $self->{Output_format});
}

sub displaySpecificHelpMessage {
	my $self = shift;
	$logger->info('   -filetoparse/-ftp file => Brut output file to parse and convert into GFF3 and EMBL (Mandatory)');
	$logger->info('');

	$logger->info('   -outputformat/-out string => Parsing output format - Possible values are: [gff|embl|both] (Optional)');
	$logger->info('       By default, both GFF3 file and EMBL file will be created');
	$logger->info('');
}

sub createSpecificSubDirectories {
	my $self = shift;
	$self->{gff_repository} = $self->{Working_directory} . '/' . $TRIANNOT_CONF{DIRNAME}->{'GFF_files'};
	$self->{embl_repository} = $self->{Working_directory}  . '/' . $TRIANNOT_CONF{DIRNAME}->{'EMBL_files'};
	if (!-e $self->{gff_repository} && $self->{Output_format} ne 'embl') { mkdir($self->{gff_repository}, 0755); }
	if (!-e $self->{embl_repository} && $self->{Output_format} ne 'gff') { mkdir($self->{embl_repository}, 0755); }
}

sub _createComponentObject {
	my $self = shift;
	# Create a new program object via TriAnnot::Parsers::Parsers factory method
	$self->{componentObject} = TriAnnot::Parsers::Parsers->factory(
			'programName'  => $self->{programName},
			'programID'    => $self->{Program_id},
			'step'         => $self->{step},
			'stepSequence' => $self->{stepSequence},
			'fileToParse'  => $self->{File_to_parse},
			'directory'    => $self->{Working_directory});
}

sub _doTreatment {
	my $self = shift;

	# Check possible input files
	$self->{componentObject}->_checkInputFiles();

	# Do parsing for the selected program
	$self->{componentObject}->parse();

	# Create GFF/EMBL/etc files from the table of BioPerl features returned by the execution procedure
	$self->{componentObject}->fromFeaturesToFiles($self->{Output_format});
	delete($self->{componentObject}->{allFeature});
}


sub _addSpecificContentToAbstractFile {

	# Recovers parameters
	my ($self, $TwigRoot) = @_;

	# Real parsing result
	my $parsing = $TwigRoot->insert_new_elt('last_child', 'parsing');

	if (scalar(@{$self->{componentObject}->{allFeatures}}) > 0) {
		$parsing->insert_new_elt('last_child', 'exit_status', 'OK');
		$parsing->insert_new_elt('last_child', 'number_of_feature', scalar(@{$self->{componentObject}->{allFeatures}}));
	} else {
		$parsing->insert_new_elt('last_child', 'exit_status', 'SKIP');
		$parsing->insert_new_elt('last_child', 'explanation', 'No feature');
	}

	if (defined($self->{'componentObject'}->{'benchmark'}->{'parsing'})) {
		my $benchmark = $parsing->insert_new_elt('last_child', 'benchmark');
		my $times = $benchmark->insert_new_elt('last_child', 'times');

		$times->insert_new_elt('last_child', 'real', $self->{'componentObject'}->{'benchmark'}->{'parsing'}->[0]);
		$times->insert_new_elt('last_child', 'cpu', ($self->{'componentObject'}->{'benchmark'}->{'parsing'}->[1] + $self->{'componentObject'}->{'benchmark'}->{'parsing'}->[2] + $self->{'componentObject'}->{'benchmark'}->{'parsing'}->[3] + $self->{'componentObject'}->{'benchmark'}->{'parsing'}->[4]));
	}

	# Conversion results
	my $conversion = $TwigRoot->insert_new_elt('last_child', 'conversion');

	if ($self->{'Output_format'} eq 'gff' || $self->{'Output_format'} eq 'both') {
		if (-e $self->{'componentObject'}->{'gffFileFullPath'}) {
			$conversion->insert_new_elt('last_child', 'GFF_creation', 'OK');
			$conversion->insert_new_elt('last_child', 'GFF_file', $self->{'componentObject'}->{'gffFileFullPath'});
		} else {
			$conversion->insert_new_elt('last_child', 'GFF_creation', 'ERROR - GFF3 file does not exists');
		}
	}

	if ($self->{'Output_format'} eq 'embl' || $self->{'Output_format'} eq 'both') {
		if (-e $self->{'componentObject'}->{'emblFileFullPath'}) {
			$conversion->insert_new_elt('last_child', 'EMBL_creation', 'OK');
			$conversion->insert_new_elt('last_child', 'EMBL_file', $self->{'componentObject'}->{'emblFileFullPath'});
		} else {
			$conversion->insert_new_elt('last_child', 'EMBL_creation', 'ERROR - EMBL file does not exists');
		}
	}

	# Particular case for getORF module
	if ($self->{'programName'} =~ /getORF/) {
		$TwigRoot->insert_new_elt('last_child', 'sequence_file', $self->{'Working_directory'} . '/' . $TRIANNOT_CONF{'DIRNAME'}->{'sequence_files'} . '/' . $self->{'componentObject'}->{'orfFile'});
		my $orfDiscoveryElement = $TwigRoot->insert_new_elt('last_child', 'orf_discovery_statistics');

		$self->_addDataFromInfoFile($orfDiscoveryElement);
	}

	return 0; # SUCCESS
}

1;
