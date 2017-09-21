#!/usr/bin/env perl

package TriAnnot::Parsers::getORF;

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
use File::Copy;
use File::Basename;

## BioPerl modules
use Bio::SeqFeature::Generic;
use Bio::Tools::GFF;

## TriAnnot modules
use TriAnnot::Parsers::Parsers;
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Parsers::Parsers);

##################################################
## Methods
##################################################
=head1 TriAnnot::Parsers::getORF - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class
	my $self = $class->SUPER::new(\%attrs);

	bless $self => $class;

	return $self;
}


#############################################
## Parameters/variables initializations
#############################################

sub setParameters {
	my ($self, $parameters) = @_;

	# Call parent class method (See Programs.pm module for more information)
	$self->SUPER::setParameters($parameters);

	# Store some path and names in the current object for easier access
	$self->_managePathsAndNames();
}


sub _managePathsAndNames {

	# Recovers parameters
	my $self = shift;

	# Directories and files - Names
	my ($orfFileWithoutExt, $base, $ext) = fileparse($self->{'orfFile'}, qr/\.[^.]*/);
	$self->{'infoFileName'} = $orfFileWithoutExt . '.info';
	$self->{'sequenceDirName'} = $TRIANNOT_CONF{'DIRNAME'}->{'sequence_files'};

	# Directories and files - Full paths
	$self->{'sequenceDirPath'} = $self->{'directory'} . '/' . $self->{'sequenceDirName'};
	$self->{'orfFileFullPath'} = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' .$self->{'orfFile'};
	$self->{'infoFileFullPath'} = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' .$self->{'infoFileName'};
}


##################
# Method parse() #
##################

sub _parse {

	# Recovers parameters
	my $self = shift;

	# Initializations
	$self->{'numberOfOrf'} = 0;
	my @getOrfFeatures = ();

	# Display a warning message when the file to parse is missing
	if (! -e $self->{'fullFileToParsePath'}) {
		$logger->logwarn('getORF output file is missing (' . $self->{'fullFileToParsePath'} . '). Parse method will return an empty feature array.');
		return @getOrfFeatures;
	}

	# Browse the ORF file and collect the start and stop position of the ORFs
	my $SeqIO_input_object  = Bio::SeqIO->new(-file => $self->{'fullFileToParsePath'}, -format => 'FASTA');

	# Create a fasta output stream for renamed ORFs
	my $outputStream = Bio::SeqIO->new(-file => '>' . $self->{'orfFileFullPath'}, -format => 'FASTA');

	while (my $Current_ORF = $SeqIO_input_object->next_seq) {
		# Increment feature counter
		$self->{'numberOfOrf'}++;

		# Initializations
		my ($start, $end) = (-1, -1);
		my $orfTags = {};

		# Collect basic datas
		my $orfDescription = $Current_ORF->description();

		# Get the strand
		my $strand = ($orfDescription =~ /REVERSE SENSE/) ? -1 : 1;

		# Split the ORF description to get start and stop positions
		if ($orfDescription =~ /\[(\d+)\s-\s(\d+)\]/) {
			if ($strand == 1) {
				$start = $1;
				$end = $2;
			} else {
				$start = $2;
				$end = $1;
			}
		} else {
			$logger->logdie('Error: TriAnnot did not managed to parse the description of the following ORF: ' . $Current_ORF->display_id() . ' ' . $orfDescription);
		}

		# Creation of the ORF feature
		$orfTags->{'Name'} = $self->getSourceTag() . '_' . $start . '_' . $end . '_ORF_' . $self->{'numberOfOrf'};
		$orfTags->{'ID'} = $self->{'sequenceName'} . '_' . $orfTags->{'Name'};
		$orfTags->{'length'} = $Current_ORF->length();
		$orfTags->{'Ontology_term'} = $self->getSOTermId('ORF');

		my $orfFeature = Bio::SeqFeature::Generic->new(
								-seq_id      => $self->{'sequenceName'},
								-source_tag  => $self->getSourceTag(),
								-primary_tag => 'ORF',
								-start       => $start,
								-end         => $end,
								-strand      => $strand,
								-tag         => $orfTags
								 );

		# Store the updated feature
		push(@getOrfFeatures, $orfFeature);

		# Change the name of the current ORF and write it
		$Current_ORF->display_id($orfTags->{'ID'});
		$outputStream->write_seq($Current_ORF);
	}

	# Write an informative file in csv format (it will be parsed to build a section of the Abstract file)
	$self->_writeInfoFile();

	return @getOrfFeatures;
}


######################
# Writing methods
######################

sub _writeInfoFile {

	# Recovers parameters
	my $self = shift;

	# Log
	$logger->debug('');
	$logger->debug('Writing informative data about the discovered ORF in the following file: ' . $self->{'infoFileName'});

	# Writing data
	open(INFO, '>' . $self->{'infoFileFullPath'}) or $logger->logdie('Error: Cannot create/open file: ' . $self->{'infoFileName'});
	print INFO 'number_of_discovered_ORF=' . $self->{'numberOfOrf'} . ';';
	close(INFO);
}


#####################
## New Files management
#####################

sub _generatedFilesManagement {

	# Recovers parameters
	my $self = shift;

	# Create a symlink to the new informative file in the common tmp folder
	if (-e $self->{'infoFileFullPath'}) {
		$logger->debug('');
		$logger->debug('Note: Creation of a symlink to the newly generated informative file concerning the Open Reading Frame search (' . $self->{'infoFileName'} . ') in the common tmp folder');
		symlink($self->{'infoFileFullPath'}, $self->{'directory'} . '/' . $TRIANNOT_CONF{'DIRNAME'}->{'tmp_files'} . '/' . $self->{'infoFileName'}) or $logger->logdie('Error: Cannot create a symlink to file: ' . $self->{'infoFileName'});
	}

	# Copy the new ORF file to the sequence folder (Copy instead of symlink because we want to keep it in the Sequences folder )
	if (-e $self->{'orfFileFullPath'}) {
		$logger->debug('');
		$logger->debug('Note: Copy of the newly generated ORF file (in Fasta format) into the default sequence folder');
		copy($self->{'orfFileFullPath'}, $self->{'sequenceDirPath'} . '/' . $self->{'orfFile'}) or $logger->logdie('Error: Cannot copy the newly generated ORF file: ' . $self->{'orfFile'});
	}
}

1;
