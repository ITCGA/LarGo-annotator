#!/usr/bin/env perl

package TriAnnot::Programs::MinibankBuilder;

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
=head1 TriAnnot::Programs::MinibankBuilder - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call parent class constructor (See Programs.pm module for more information)
	my $self = $class->SUPER::new(\%attrs);
	$self->{needParsing}       = 'no';

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

	$self->{outFile} = $self->{'minibank_name'}
}

sub _checkInputFiles {

	# Recovers parameters
	my $self = shift;

	# Check if the Minibank hit list file exists or not
	$self->_checkFileExistence('minibank hit list', $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'tmp_files'} . '/' . $self->{'hitListFile'});
}

#####################
## Method execute() #
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my $mb_hit_list_fullpath = $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'tmp_files'} . '/' . $self->{'hitListFile'};

	# Log and Warning
	$logger->info('The selected database is: ' . $self->{'database'});
	$logger->info('The selected minibank hit list is: ' . $self->{'hitListFile'});

	# Check if the minibank hit list contains at least one ID
	if (-z $mb_hit_list_fullpath) {
		$logger->logwarn('Trying to run MinibankBuilder (fastacmd) with an empty minibank hit list (' . $self->{'hitListFile'} . '). Execution is skipped.');

		# Creation of an empty output file
		$logger->debug('');
		$logger->debug('Note: Creation of an empty minibank (' . $self->{'outFile'} . ')');
		open(EMPTY_OUT, '>' . $self->{'outFile'}) or $logger->logdie('Error: Cannot create the empty output file: ' . $self->{'outFile'});
		close(EMPTY_OUT);

		# Mark the execution procedure as SKIP
		$self->{'Execution_skipped'} = 'yes';
		$self->{'Skip_reason'} = 'Empty minibank hit list file';

		return;
	}

	# Build fastacmd command line and execute it
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{'fastacmd'}->{'bin'} .
		' -i ' . $mb_hit_list_fullpath .
		' -d ' . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'database'}}->{'path'} .
		' -o ' . $self->{'outFile'};

	# Log the newly build command line
	$logger->debug('MinibankBuilder (fastacmd) will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	my $cmdOutput = `$cmd 2>&1`;
	$logger->debug(">>>>>>>> Start of execution output <<<<<<<<");
	$logger->debug($cmdOutput);
	$logger->debug(">>>>>>>>  End of execution output  <<<<<<<<");
}

#####################
## New Files management
#####################

sub _generatedFilesManagement {

	# Recovers parameters
	my $self = shift;

	# Create a symlink to the new minibank in the common tmp folder
	if (-e $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'outFile'}) {
		$logger->debug('');
		$logger->debug('Note: Creation of a symlink to the newly generated minibank (' . $self->{'outFile'} . ') in the common tmp folder');
		symlink($self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'outFile'}, $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'tmp_files'} . '/' . $self->{'outFile'})
			or $logger->logdie('Error: Cannot create a symlink to file: ' . $self->{'outFile'});
	}
}

1;
