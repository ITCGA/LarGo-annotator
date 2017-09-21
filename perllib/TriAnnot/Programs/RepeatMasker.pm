#!/usr/bin/env perl

package TriAnnot::Programs::RepeatMasker;

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

## TriAnnot modules
use TriAnnot::Programs::Programs;
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Programs::Programs);

##################################################
## Methods
##################################################
=head1 TriAnnot::Programs::RepeatMasker - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call parent class constructor (See Programs.pm module for more information)
	my $self = $class->SUPER::new(\%attrs);

	# Define $self as a $class type object
	bless $self => $class;

	return $self;
}

################################
# Parameters and Databases check related methods
################################

sub setParameters {
	my ($self, $parameters) = @_;

	# Call parent class method (See Programs.pm module for more information)
	$self->SUPER::setParameters($parameters);

	if ($self->{'nbCore'} > 1 && $self->{'sequenceLength'} < 50000) {
		$logger->logwarn('Warning: RepeatMasker multithread option cannot be used for sequence under 50kb !');
		$logger->logwarn('The number of CPU to use for the current analysis is forced to 1');
		$self->{'nbCore'} = 1;
	}
}


#####################
## Method execute() #
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Manage artificial speed value -d
	my $speed = '-' . $self->{'speed'};
	if ($speed eq '-d') { $speed = ''; }

	# Creation of the command line
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'};

	if ($self->{'database'} ne 'RMdb') { $cmd .= ' -lib ' . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'database'}}->{'path'} . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'database'}}->{'FastaExtension'}; }
	if ($self->{'species'} ne 'none') { $cmd .= ' -species ' . $self->{'species'}; }
	if ($self->{'mask_low_complexity'} eq 'no') { $cmd .= ' -nolow'; }
	if ($self->{'mask_small_rna'} eq 'no') { $cmd .= ' -norna'; }
	if ($self->{'skip_bacterial_insertion'} eq 'yes') { $cmd .= ' -no_is'; }

	$cmd .= ' -xm ' . $speed . ' -engine ' . $self->{'engine'} . ' -cutoff ' . $self->{'cutoff'} . ' -parallel ' . $self->{'nbCore'} . ' ' . $self->{'sequence'};

	# Log the newly build command line
	$logger->info('The selected database is: ' . $self->{'database'});
	$logger->debug('RepeatMasker (for masking and annotation) will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	my $cmdOutput = `$cmd 2>&1`;
	if (!defined($cmdOutput)) {
		$logger->logdie('Error: ' . $self->{'programName'} . ' command could not be executed. Check that ' . $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'} . ' is in your PATH.');
	}

	$logger->debug(">>>>>>>> Start of execution output <<<<<<<<");
	$logger->debug($cmdOutput);
	$logger->debug(">>>>>>>>  End of execution output  <<<<<<<<");

	# Renaming of the output files
	rename ($self->{'sequence'} . '.out',  $self->{'outFile'});
	if (-e $self->{'sequence'} . '.out.xm') {
		# Rename the .xm file if it exists (if there were repeats identified)
		rename ($self->{'sequence'} . '.out.xm',  $self->{'xmFile'});
	} else {
		# Create an empty XM file if there were no repeats identified
		open (EMPTY, '>' . $self->{'xmFile'}) or $logger->logdie('Error: Cannot create/open file: ' . $self->{'xmFile'});
		close (EMPTY);
	}
}

#####################
## New Files management
#####################

sub _generatedFilesManagement {

	# Recovers parameters
	my $self = shift;

	# Create a symlink to the new .xm file in the common tmp folder (Will be used in SequenceMasker.pm)
	if (-e $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'xmFile'}) {
		$logger->debug('');
		$logger->debug('Note: Creation of a symlink to the newly generated .xm file in the common tmp folder');
		symlink($self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'xmFile'}, $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'tmp_files'} . '/' . $self->{'xmFile'})
			or $logger->logdie('Error: Cannot create a symlink to file: ' . $self->{'xmFile'});
	}

	# Create a symlink to the newly generated .out file in the common tmp folder (Will be used in isbpFinder.pm)
	if (-e $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'outFile'}) {
		$logger->debug('');
		$logger->debug('Note: Creation of a symlink to the newly generated .out file in the common tmp folder');
		symlink($self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'outFile'}, $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'tmp_files'} . '/' . $self->{'outFile'})
			or $logger->logdie('Error: Cannot create a symlink to file: ' . $self->{'outFile'});
	}
}

1;
