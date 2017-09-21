#!/usr/bin/env perl

package TriAnnot::Programs::ClariTE;

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

## TriAnnot modules
use TriAnnot::Programs::Programs;
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Programs::Programs);

##################################################
## Methods
##################################################
=head1 TriAnnot::Programs::ClariTE - Methods
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

#############################################
## Parameters/variables initializations
#############################################

sub setParameters {

	# Recovers parameters
	my ($self, $parameters) = @_;

	# Call parent class method (See Programs.pm module for more information)
	$self->SUPER::setParameters($parameters);

	# Check tool specific parameters
	$self->_checkCustomParameters();

	# Store some path and names in the current object for easier access
	$self->_managePathsAndNames();
}


sub _managePathsAndNames {

	# Recovers parameters
	my $self = shift;

	# Path for the input GFF file
	if (defined($self->{'geneModelEmblFile'}) && $self->{'geneModelEmblFile'} ne '') {
		$self->{'emblDirFullPath'} = $self->{'directory'} . '/' . $TRIANNOT_CONF{'DIRNAME'}->{'EMBL_files'};
		$self->{'geneModelFileFullPath'} = $self->{'emblDirFullPath'} . '/' . $self->{'geneModelEmblFile'};
	}

	# Path for the input XM file
	$self->{'commonsDirFullPath'} = $self->{'directory'} . '/' . $TRIANNOT_CONF{'DIRNAME'}->{'tmp_files'};
	$self->{'RepeatMaskerXmFileFullPath'} = $self->{'commonsDirFullPath'} . '/' . $self->{'RepeatMaskerXmFile'};

	# Path of the main output file
	$self->{'outFileFullPath'} = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' .$self->{'outFile'};

	# Path of the classification and LTR_position file
	$self->{'classificationFileFullPath'} = $TRIANNOT_CONF{PATHS}->{'db'}->{$self->{'database'}}->{'path'} . '.classification';
	$self->{'ltrPositionFileFullPath'} = $TRIANNOT_CONF{PATHS}->{'db'}->{$self->{'database'}}->{'path'} . '.LTR_position';
}


#######################################
# Parameters check related methods
#######################################

sub _checkCustomParameters {

	# Recovers parameters
	my $self = shift;

	# Check specific parameters
	if (defined($self->{'useGeneModelData'}) && $self->{'useGeneModelData'} eq 'yes') {
		if (!defined($self->{'geneModelEmblFile'}) || $self->{'geneModelEmblFile'} eq '') {
			$logger->logdie('Error: Gene Model data must be used (useGeneModelData parameter set to yes) but there is no Gene Model GFF file defined (with the geneModelEmblFile parameter)');
		}
	}

	if (defined($self->{'geneModelEmblFile'}) && $self->{'geneModelEmblFile'} ne '') {
		if (!defined($self->{'useGeneModelData'}) || $self->{'useGeneModelData'} eq 'no') {
			$logger->logdie('Error: A Gene Model GFF file has been selected but the useGeneModelData switch is set to no (or not defined) !');
		}
	}

	return 0; # SUCCESS
}


sub _checkInputFiles {

	# Recovers parameters
	my $self = shift;

	# Check the input Gene Model file if needed
	if (defined($self->{'geneModelEmblFile'}) && $self->{'geneModelEmblFile'} ne '') {
		$self->_checkFileExistence('Gene Model', $self->{'geneModelFileFullPath'});
	}

	# Check if the RepeatMasker XM file exists in the Commons folder
	$self->_checkFileExistence('RepeatMasker XM', $self->{'RepeatMaskerXmFileFullPath'});
}


#####################
## Method execute() #
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Log
	if ($self->{'useGeneModelData'} eq 'yes') {
		$logger->info('The selected Gene Model EMBL file is: ' . basename($self->{'geneModelEmblFile'}));
	}
	$logger->info('The selected RepeatMasker XM file is: ' . basename($self->{'RepeatMaskerXmFile'}));

	# Building of the command line
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'};

	$cmd .= ' -fasta ' . $self->{'sequence'};
	$cmd .= ' -LTR ' . $self->{'ltrPositionFileFullPath'};
	$cmd .= ' -classi ' . $self->{'classificationFileFullPath'};
	if ($self->{'useGeneModelData'} eq 'yes') { $cmd .= ' -gene ' . $self->{'geneModelFileFullPath'}; }
	$cmd .= ' -v 4';
	$cmd .= ' ' . $self->{'RepeatMaskerXmFileFullPath'};

	# Log the newly build command line
	$logger->debug($self->{'programName'} . ' will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	my $cmdOutput = `$cmd 2>&1`;
	$logger->debug(">>>>>>>> Start of execution output <<<<<<<<");
	$logger->debug($cmdOutput);
	$logger->debug(">>>>>>>>  End of execution output  <<<<<<<<");

	# Renaming of the output files
	my ($xmFileWithoutExt, $base, $ext) = fileparse($self->{'RepeatMaskerXmFile'}, qr/\.[^.]*/);
	my $clariteMainOutputFileName = $xmFileWithoutExt . '_anno.embl';
	rename ($clariteMainOutputFileName,  $self->{'outFile'}) or die ('Cannot rename file');
}

1;
