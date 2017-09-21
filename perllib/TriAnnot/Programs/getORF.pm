#!/usr/bin/env perl

package TriAnnot::Programs::getORF;

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
=head1 TriAnnot::Programs::getORF - Methods
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
	my ($self, $parameters) = @_;

	# Call parent class method (See Programs.pm module for more information)
	$self->SUPER::setParameters($parameters);

	# Store some path and names in the current object for easier access
	$self->_managePathsAndNames();
}


sub _managePathsAndNames {

	# Recovers parameters
	my $self = shift;

	# Directories and files - Full paths
	$self->{'outFileFullPath'} = $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' .$self->{'outFile'};
}


#####################
## Method execute() #
######################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Log
	$logger->info('The selected genetic code is: ' . $TRIANNOT_CONF{'getORF'}->{'geneticCodeDescriptions'}->{$self->{'geneticCode'}});
	$logger->info('The selected find mode is: ' . $TRIANNOT_CONF{'getORF'}->{'findModeDescriptions'}->{$self->{'findMode'}});

	# Building of the command line
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'};

	$cmd .= ' -sequence ' . $self->{'sequence'};
	$cmd .= ' -outseq ' . $self->{'outFile'};
	$cmd .= ' -table ' . $self->{'geneticCode'};
	$cmd .= ' -minsize ' . $self->{'minSize'};
	$cmd .= ' -maxsize ' . $self->{'maxSize'};
	$cmd .= ' -find ' . $self->{'findMode'};
	if ($self->{'startWithMethionine'} eq "yes") { $cmd .= ' -methionine'; } else { $cmd .= ' -nomethionine'; }
	if ($self->{'searchOnReverseStrand'} eq "yes") { $cmd .= ' -reverse'; } else { $cmd .= ' -noreverse'; }

	# Log the newly build command line
	$logger->debug('getORF will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	my $cmdOutput = `$cmd 2>&1`;
	$logger->debug(">>>>>>>> Start of execution output <<<<<<<<");
	$logger->debug($cmdOutput);
	$logger->debug(">>>>>>>>  End of execution output  <<<<<<<<");
}

1;
