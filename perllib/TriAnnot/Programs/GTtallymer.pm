#!/usr/bin/env perl

package TriAnnot::Programs::GTtallymer;

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
=head1 TriAnnot::Programs::GTtallymer - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class (TriAnnot::Programs::Programs)
	my $self = $class->SUPER::new(\%attrs);

	$self->{needParsing} = 'no';

	bless $self => $class;

	return $self;
}


#####################
## Method execute() #
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	$logger->info('The selected tallymer-index is: ' . $self->{'tallymerIndex'});

	# Creation of the command line and execution
	my $cmd= $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'bin'} . ' tallymer search -tyr ' . $TRIANNOT_CONF{PATHS}->{index}->{$self->{programName}}->{$self->{'tallymerIndex'}}->{'path'} . ' -q ' . $self->{'sequence'} . ' -strand ' . $self->{'strand'};

	# Add verbosity option if needed
	if ($TRIANNOT_CONF_VERBOSITY >= 1) { $cmd .= ' -v'; }

	# Build GT Tallymer Search output option, some explanations:
	# - 4 columns can be printed in GT Tallymer Search output file: qseqnum (identifier (0, 1, etc)  of the query sequence), qpos (Start postion of the k-mer in the query sequence), counts (Number of times the current mer occurs in the indexed sequences), sequence (sequence of the current k-mer)
	# - In TriAnnot, the "qseqnum" column is uselss in GT Tallymer Search output because GT Tallymer Search is always launched on a single query sequence file (the BAC)
	# - To avoid problems during the highly recurrent k-mers masking procedure the "qpos" and "counts" columns are mandatory
	if ($self->{'display_sequence'} eq 'yes') {
		$cmd .= ' -output qpos counts sequence';
	} else {
		$cmd .= ' -output qpos counts';
	}

	$cmd .= ' 1> ' . $self->{'outFile'} . ' 2> ' . $self->{'errorFile'};

	# Log the newly build command line
	$logger->debug('Genome Tools Tallymer Search will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	system($cmd);

	if (-e $self->{'outFile'} && $self->{'create_plot_file'} eq 'yes') {
		$self->_generatePlotFile();
	}
}

###########################
## Artemis plot file creation related methods
###########################

sub _generatePlotFile {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my %Hash_MDR;
	my $Exec_folder = $self->{'directory'} . '/' . $self->{'tmpFolder'};

	# Parse Tallymer brut output file
	open(MDR, '<' . $Exec_folder . '/' . $self->{'outFile'}) || $logger->logdie('Error: Cannot open/read file: ' . $Exec_folder . '/' . $self->{'outFile'});
	while (my $MDR_line = <MDR>) {

		# Treat non nomment and non empty lines only
		if ($MDR_line =~ /^#|^$/) {
			next;
		} else {
			# Initializations
			my ($strandqpos, $counts, $sequence, $strand, $qpos) = ('', '', '', '', '');

			# Split result line to extract the various field (
			if ($self->{'display_sequence'} eq 'yes') {
				($strandqpos, $counts, $sequence) = split(/\t/, $MDR_line);
			} else {
				($strandqpos, $counts) = split(/\t/, $MDR_line);
			}

			# Disband the stand from the position
			if ($strandqpos =~/^([\+\-])(\d+)$/) {
				($strand, $qpos) = ($1, $2);
			}

			# Take the log of the tallymer occurence counter
			my $log10 = sprintf("%.5f", (log($counts)/log(10)));

			# Add extracted informations in a hash table (Strands are separated and at the second level each key is a query position and each value is a MDR score)
			$Hash_MDR{$strand}->{$qpos} = $log10;
		}
	}
	close(MDR);

	# Write the plot file for Artemis
	$logger->debug('');
	$logger->debug('Note: Creation of the plot files (forward and/or reverse strand) for mer distribution viewing under Artemis');
	$self->_writePlotFile(\%Hash_MDR);

	return 0; # Success
}

sub _writePlotFile {

	# Recovers parameters
	my ($self, $Ref_to_Hash_MDR) = @_;

	# Browse the MDR hash table and write the  plot file
	foreach my $Current_strand ( keys %{$Ref_to_Hash_MDR}) {

		# Open the right file depending of the current strand
		if ($Current_strand eq '+') {
			open(PLOT, '>' . $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'forwardPlotFile'}) || $logger->logdie('Error: Cannot create/open file: ' . $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'forwardPlotFile'});
		} else {
			open(PLOT, '>' . $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'reversePlotFile'}) || $logger->logdie('Error: Cannot create/open file: ' . $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'reversePlotFile'});
		}

		# Note: if at a given position, the occurence counter stay at 0 GTtallymer does not write the line in its output file
		# However, for the artemis plot file we need to have a line for each position
		# Therefore we automatically add a line containing a 0 when there is no tallymer score for a given query position
		for (my $position = 0 ; $position < ($self->{'sequenceLength'} - 16) ; $position += 1) {
			if (defined($Ref_to_Hash_MDR->{$Current_strand}->{$position})) {
				print PLOT $Ref_to_Hash_MDR->{$Current_strand}->{$position} . "\n";
			} else {
				print PLOT -0.1 . "\n";
			}
		}

		close(PLOT);
	}

	return 0; # Success
}

#####################
## New Files management
#####################

sub _generatedFilesManagement {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my $tmp_folder = $self->{'directory'} . '/' . $self->{'tmpFolder'};

	# Copy the new GTtallymer result file in the the long term conservation directory (Copy instead of Move because the result file is also the GTtallymer outFile and have to be present in the execution folder to avoid an ERROR status in the abstract file)
	if (-e $tmp_folder . '/' . $self->{'outFile'}) {
		$logger->debug('');
		$logger->debug('Note: Copying of the newly generated GTtallymer result file into into the ' . $TRIANNOT_CONF{DIRNAME}->{'keep_files'} . ' folder for long term conservation');
		copy($tmp_folder . '/' . $self->{'outFile'}, $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'keep_files'} . '/' . $self->{'outFile'}) or $logger->logdie('Error: Cannot copy the newly generated GTtallymer result file: ' . $self->{'outFile'});
	}

	# Move the new GTtallymer fplot file in the the long term conservation directory
	if (-e $tmp_folder . '/' . $self->{'forwardPlotFile'}) {
		$logger->debug('');
		$logger->debug('Note: Moving of the newly generated GTtallymer foward plot file into into the ' . $TRIANNOT_CONF{DIRNAME}->{'keep_files'} . ' folder for long term conservation');
		move($tmp_folder . '/' . $self->{'forwardPlotFile'}, $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'keep_files'} . '/' . $self->{'forwardPlotFile'}) or $logger->logdie('Error: Cannot move the newly generated GTtallymer foward plot file: ' . $self->{'forwardPlotFile'});
	}

	# Move the new GTtallymer rplot file in the the long term conservation directory
	if (-e $tmp_folder . '/' . $self->{'reversePlotFile'}) {
		$logger->debug('');
		$logger->debug('Note: Moving of the newly generated GTtallymer reverse plot file into into the ' . $TRIANNOT_CONF{DIRNAME}->{'keep_files'} . ' folder for long term conservation');
		move($tmp_folder . '/' . $self->{'reversePlotFile'}, $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'keep_files'} . '/' . $self->{'reversePlotFile'}) or $logger->logdie('Error: Cannot move the newly generated GTtallymer reverse plot file: ' . $self->{'reversePlotFile'});
	}
}

1;
