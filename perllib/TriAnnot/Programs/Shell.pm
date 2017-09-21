#!/usr/bin/env perl

package TriAnnot::Programs::Shell;

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
use Data::Dumper;
use File::Copy;

## TriAnnot modules
use TriAnnot::Programs::Programs;
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Programs::Programs);


##################################################
## Methods
##################################################
=head1 TriAnnot::Programs::Shell - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class (TriAnnot::Programs::Programs)
	my $self = $class->SUPER::new(\%attrs);

	$self->{needParsing}    = 'no';

	bless $self => $class;

	return $self;
}

sub setParameters {
	my ($self, $parameters) = @_;

	# Call parent class method (See Programs.pm module for more information)
	$self->SUPER::setParameters($parameters);

	if ($self->{'moveOutFileToKeepFilesFolder'} eq 'yes' && !defined($self->{'outFile'})) {
		$logger->logdie("'moveOutFileToKeepFilesFolder' is set to 'yes', this setting is only valid when an outFile is spevified. Either set the 'outFile' parameter or set 'moveOutFileToKeepFilesFolder' to 'no'");
	}

	$self->{'generateEmptyOutFile'} = 0;
	if (!defined($self->{'outFile'})) {
		$self->{'outFile'} = $self->{'step'} . '_' . $self->{'programID'} . '_SHELL.res';
		$self->{'generateEmptyOutFile'} = 1;
	}
}


#####################
## Method execute() #
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Building of the command line

	# Log the newly build command line
	$logger->debug('Shell module will be executed with the following command line' . (scalar(@{$self->{'cmd'}}) > 1 ? 's':'') . ':');
	$logger->debug(join("\n", @{$self->{'cmd'}}));

	# Execute command
	foreach my $cmd (@{$self->{'cmd'}}) {
		system($cmd);
	}

	if ($self->{generateEmptyOutFile}) {
		open(OUTFILE, '>' . $self->{outFile})  or $logger->logdie('Error: Cannot create outFile: ' . $self->{outFile});
		close(OUTFILE);
	}


}


sub _generatedFilesManagement {

	# Recovers parameters
	my $self = shift;

	my $tmp_folder = $self->{'directory'} . '/' . $self->{'tmpFolder'};
	
	# Move outFile to keep files folder if needed
	if ($self->{'moveOutFileToKeepFilesFolder'} eq 'yes') {
		$logger->debug('');
		$logger->debug('Note: Moving of the newly generated file into the ' . $TRIANNOT_CONF{DIRNAME}->{'keep_files'} . ' folder');
		copy($tmp_folder . '/' . $self->{'outFile'}, $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'keep_files'}  . '/' . $self->{'outFile'}) or $logger->logdie('Error: Cannot move the newly generated file: ' . $self->{'outFile'});
	}
}

1;
