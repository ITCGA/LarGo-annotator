#!/usr/bin/env perl

package TriAnnot::Programs::Exonerate;

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
=head1 TriAnnot::Programs::Exonerate - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class (TriAnnot::Programs::Programs)
	my $self = $class->SUPER::new(\%attrs);

	# Define $self as a $class type object
	bless $self => $class;

	return $self;
}

################################
# Parameters and Databases check related methods
################################

sub _checkInputFiles {
	my $self = shift;

	# Check the fasta database
	if (defined($self->{miniBankPrefix}) &&  $self->{miniBankPrefix} ne '') {
		$self->{databaseFullPath} = $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'tmp_files'} . '/' . $self->{miniBankPrefix} . $self->{'database'};
		$self->_checkFileExistence('minibank', $self->{databaseFullPath});
	} else {
		$self->{databaseFullPath} = $TRIANNOT_CONF{PATHS}->{db}->{$self->{database}}->{'path'} . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'database'}}->{'FastaExtension'};
	}
}


#####################
## Method execute() #
#####################

sub _execute {
	my $self = shift;

	# Check if the database contains at least one sequence
	if (-z $self->{databaseFullPath}) {
		$logger->logwarn('Trying to run Exonerate on an empty databank (' . $self->{'database'} . '). Execution is skipped.');

		# Creation of an empty output file
		$logger->debug('');
		$logger->debug('Note: Creation of an empty Exonerate brut output file (' . $self->{'outFile'} . ')');
		open(EMPTY_OUT, '>' . $self->{'outFile'}) or $logger->logdie('Error: Cannot create the empty output file: ' . $self->{'outFile'});
		close(EMPTY_OUT);

		# Mark the execution procedure as SKIP
		$self->{'Execution_skipped'} = 'yes';
		$self->{'Skip_reason'} = 'Empty databank';

		return;
	}

	# Building of the command line
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'} .
		' -Q ' . $self->{'queryType'} .
		' -q ' . $self->{databaseFullPath} .
		' -T ' . $self->{'targetType'} .
		' -t ' . $self->{'sequence'} .
		' --exhaustive ' . $self->{'exhaustive'} .
		' --model ' . $self->{'model'} .
		' --score ' . $self->{'score'} .
		' --percent ' . $self->{'percent'} .
		' --bestn ' . $self->{'bestn'} .
		' --showvulgar TRUE ' .
		' --showalignment TRUE ' .
		' --maxintron ' . $self->{'maxIntron'} .
		' --minintron ' . $self->{'minIntron'} .
		' --refine ' . $self->{'refine'} .
		' --softmasktarget ' . $self->{'softMaskTarget'};

	if ($self->{'model'} =~ /protein/) {
		$cmd .= ' --ryo "identity_percentage: %pi\nsimilarity_percentage: %ps\n"';
	} else {
		$cmd .= ' --ryo "identity_percentage: %pi\n" ';
	}

	$cmd .= ' > ' . $self->{'outFile'};

	# Log the newly build command line
	$logger->info('The selected database is: ' . $self->{'database'});
	$logger->debug('Exonerate will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	system($cmd);
}

1;
