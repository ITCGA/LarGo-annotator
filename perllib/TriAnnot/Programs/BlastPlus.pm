#!/usr/bin/env perl

package TriAnnot::Programs::BlastPlus;

##################################################
## Documentation POD
##################################################

##################################################
## Modules
##################################################
## Perl modules
use strict;
use warnings;
use diagnostics;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::Logger;

## Inherits
use base ("TriAnnot::Programs::Programs");


##################################################
## Methods
##################################################
=head1 TriAnnot::Programs::BlastPlus - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, $attrs_ref) = @_;

	# Check the type of the second argument
	if (ref($attrs_ref) ne 'HASH') {
		$logger->logdie('Error: BlastPlus.pm constructor is expecting a hash reference as second argument !');
	}

	# Call the constructor of the parent class (TriAnnot::Programs::Programs)
	my $self = $class->SUPER::new($attrs_ref);

	bless $self => $class;

	return $self;
}


#########################
## Method _execute()
#########################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my ($cmd, $cmd_base) = ('', '');

	# Building of the command line
	$cmd_base .= $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'};

	# Always defined parameters
	$cmd_base .= ' -query ' . $self->{'sequence'};
	$cmd_base .= ' -db ' . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'database'}}->{'path'};
	$cmd_base .= ' -outfmt 5 '; # Hard coded output format: 5 = XML
	$cmd_base .= ' -evalue ' . $self->{'evalue'};
	$cmd_base .= ' -max_target_seqs ' . $self->{'maxTargetSeqs'};
	$cmd_base .= ' -num_threads ' . $self->{'nbCore'};

	# Optional parameters
	if (defined($self->{'wordSize'})) { $cmd_base .= ' -word_size ' . $self->{'wordSize'}; }
	if (defined($self->{'gapOpeningCost'})) { $cmd_base .= ' -gapopen ' . $self->{'gapOpeningCost'}; }
	if (defined($self->{'gapExtensionCost'})) { $cmd_base .= ' -gapextend ' . $self->{'gapextend'}; }
	if (defined($self->{'windowSize'})) { $cmd_base .= ' -window_size ' . $self->{'windowSize'}; }

	# Parameters without value (presence/absence)
	if (defined($self->{'lowerCaseFilter'}) && $self->{'lowerCaseFilter'} eq 'true') { $cmd_base .= ' -lcase_masking '; }

	# Mutually incompatible parameters
	if (defined($self->{'cullingLimit'})) {
		$cmd_base .= ' -culling_limit ' . $self->{'cullingLimit'};
	} else {
		if (defined($self->{'bestHitOverhang'})) { $cmd_base .= ' -best_hit_overhang ' . $self->{'bestHitOverhang'}; }
		if (defined($self->{'bestHitScoreEdge'})) { $cmd_base .= ' -best_hit_score_edge ' . $self->{'bestHitScoreEdge'}; }
	}

	# Add command line addon (*Blast* specific parameters) if it exists
	if (defined($self->{'Command_addon'}) && $self->{'Command_addon'} ne '') {
		$cmd = $cmd_base . $self->{'Command_addon'};
	} else {
		$cmd = $cmd_base;
	}

	# Log the newly build command line
	$logger->info('The selected database is: ' . $self->{'database'});
	if (defined($self->{'task'}) && $self->{'task'} ne '') {
		$logger->info('The selected ' . $self->{'programName'} . ' sub-type is: ' . $self->{'task'});
	}

	$logger->debug($self->{'programName'} . ' will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	my $cmdOutput = `$cmd 2>&1`;
	$logger->debug(">>>>>>>> Start of execution output <<<<<<<<");
	$logger->debug($cmdOutput);
	$logger->debug(">>>>>>>>  End of execution output  <<<<<<<<");
}

1;
