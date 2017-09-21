#!/usr/bin/env perl

package TriAnnot::Programs::Programs;

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
use integer;
use Switch;
use Cwd;
use File::Basename;
use Benchmark;
use Tie::IxHash;
use Sys::Hostname;

## Debug
use Data::Dumper;

## TriAnnot modules
use TriAnnot::Component;
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::Logger;


## Inherits
our @ISA = qw(TriAnnot::Component);

#################
# Constructor
#################
sub new {
	my ($class, $attrs_ref) = @_;

	# Check the type of the second argument
	if (ref($attrs_ref) ne 'HASH') {
		$logger->logdie('Error: Programs.pm constructor is expecting a hash reference as second argument !');
	}

	if (!defined($attrs_ref->{step})) {
		$logger->logdie('Error: No step passed to ' . $class . ' constructor');
	}
	if ($attrs_ref->{step} !~ /^[0-9]+$/) {
		$logger->logdie('Error: Step passed to ' . $class . ' constructor is not a numeric value');
	}

	if (!defined($attrs_ref->{programID})) {
		$logger->logdie('Error: No programID passed to ' . $class . ' constructor');
	}
	if ($attrs_ref->{programID} !~ /^[0-9]+$/) {
		$logger->logdie('Error: programID passed to ' . $class . ' constructor is not a numeric value');
	}

	if (!defined($attrs_ref->{directory})) {
		$logger->logdie('Error: No directory passed to ' . $class . ' constructor');
	}
	if (!-e $attrs_ref->{directory}) {
		$logger->logdie('Error: Directory passed to ' . $class . ' constructor does not exists: ' . $attrs_ref->{directory});
	}
	if (!-w $attrs_ref->{directory}) {
		$logger->logdie('Error: Directory passed to ' . $class . ' constructor is not writable: ' . $attrs_ref->{directory});
	}

	# Set object's attributes
	my $self = {
		step                  => $attrs_ref->{'step'},
		stepSequence          => $attrs_ref->{'stepSequence'},
		programName           => $attrs_ref->{'programName'},
		programID             => $attrs_ref->{'programID'},
		directory             => $attrs_ref->{'directory'},
		parametersDefinitions => undef,
		hostname              => hostname(),
		benchmark             => {},
		startTime             => time(),
		needParsing           => 'yes',
		allowMultiFasta       => 'no',
		outFile               => undef
	};

	tie %{$self->{'benchmark'}}, "Tie::IxHash";

	bless $self => $class;
	return $self;
}


sub setParameters {
	# Recovers parameters
	my ($self, $parameters) = @_;

	# Convert the parameters collected form the step/task file into attribute of the current object
	foreach my $parameterName (keys(%{$parameters})) {
		$self->{$parameterName} = $parameters->{$parameterName};
	}

	# Define temporary execution folder name
	if (!defined($self->{'tmpFolder'})) {
		$self->{'tmpFolder'} = sprintf("%03s", $self->{'programID'}) . '_' . $self->{'programName'} . '_execution';
	}
}


#####################
# Execution related methods
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	$logger->logdie('Error: The _execute method need to be implemented in ' . ref($self));
}

sub _beforeExec {

	# Recovers parameters
	my $self = shift;

	# Temporary execution folder creation
	if (!-e $self->{'tmpFolder'}) {
		mkdir($self->{'tmpFolder'}, 0755);
	}

	# Jump to the new temporary folder
	chdir($self->{'tmpFolder'});

	# Create a symbolic link to sequence file in tmpFolder
	symlink($self->{'fullSequencePath'}, $self->{'sequence'});
}

sub execute {

	# Recovers parameters
	my $self = shift;

	$logger->info('');
	$logger->info('Beginning of the execution procedure at ' . localtime());
	$logger->info('');

	$logger->info('Module used: ' . ref($self));
	$logger->info('The selected sequence file is: ' . $self->{'sequence'});

	# Benchmark initialization
	my $timeStart = Benchmark->new();

	# Main execution process
	$self->_beforeExec();
	$self->_execute();
	$self->_afterExec();

	$logger->info('');
	$logger->info('End of the execution procedure at ' . localtime());
	$logger->info('');

	# Collect benchmark information
	my $timeEnd = Benchmark->new();
	my $timeDiff = Benchmark::timediff($timeEnd, $timeStart);
	$self->{'benchmark'}->{'exec'} = $timeDiff;
}

sub _afterExec {

	# Recovers parameters
	my $self = shift;

	# Management of generated files that will be used in other step of the pipeline
	$self->_generatedFilesManagement();

	# Go back to parent folder
	chdir('..');
}

1;
