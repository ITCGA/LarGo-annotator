#!/usr/bin/env perl

package TriAnnot::Programs::SIMsearch;

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

# CPAN modules
use File::Basename;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Programs::Programs;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Programs::Programs);

##################################################
## Methods
##################################################
=head1 TriAnnot::Programs::SIMsearch - Methods
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


################################
# Parameters and Databases check related methods
################################

sub _checkInputFiles {

	# Recovers parameters
	my $self = shift;

	$self->_checkFileExistence('ab initio gene model GFF', $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'GFF_files'} . '/' . $self->{'abinitioGff'});
}


#####################
## Method _execute() #
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Prepare the three configuration file required for a correct SIMsearch execution
	$self->_prepareFilesBeforeExec();

	# Log some useful information
	$logger->info('The selected proteinDb is: ' . $self->{'proteinDb'});
	$logger->info('The selected transcriptsDb is: ' . $self->{'transcriptsDb'});

	# Building of the command line
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{$self->{programName}}->{'bin'} . ' -c ' . $self->{'autoAnnotFileName'};

	# Log the newly build command line
	$logger->debug($self->{programName} . ' will be executed (on ' . $self->{'hostname'} . ') with the following command line:');
	$logger->debug($cmd);

	# Execute command
	my $cmdOutput = `$cmd 2>&1`;
	$logger->debug(">>>>>>>> Start of execution output <<<<<<<<");
	$logger->debug($cmdOutput);
	$logger->debug(">>>>>>>>  End of execution output  <<<<<<<<");

	my $blastFileName = $self->{sequenceName} . "/" . $self->{sequenceName} . '.b';

	if ($self->{keepBlastResult} eq 'no' && -e $blastFileName) {
		$logger->info('Removing intermediate blast result file: ' . $blastFileName);
		unlink($blastFileName);
	}

	## Renaming of the final SIMsearch output file
	my $brutOutputFile = 'for_annotation_' . $self->{'autoannot.CATEGORY'} . '.gff';

	if (-e $brutOutputFile) {
		$logger->info('');
		$logger->info('Renaming SIMsearch brut GFF file (' . $brutOutputFile . ' -> ' . $self->{'outFile'} . ')');
		rename ($brutOutputFile,  $self->{'outFile'});
	} else {
		$logger->debug('SIMsearch brut GFF file ' . $brutOutputFile . ' does not exist !');
	}
}

###############################
## Configuration file preparation related methods
###############################

sub _prepareFilesBeforeExec {

	# Recovers parameters
	my $self = shift;

	# Launch a specific method to create each of the mandatory configuration file
	$self->_prepareAutoAnnotFile();
	$self->_prepareMapFile();
	$self->_prepareOrfFile();

	return 1; # true operation successfull
}

sub _prepareAutoAnnotFile {

	# Recovers parameters
	my $self = shift;

	# Write AUTOANNOT file
	open(AUTOANNOT, '>' . $self->{'autoAnnotFileName'}) || $logger->logdie('Error: Cannot create/open file: ' . $self->{'autoAnnotFileName'});

	print AUTOANNOT "WORKING_DIR=" . $self->{'directory'} . '/' . $self->{'tmpFolder'} . ";\n"; # Working directory
	print AUTOANNOT "INPUT_SEQUENCE=" . $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'sequence'} . ";\n"; # Input Sequence

	print AUTOANNOT "MAP_CONFIG_FILE=" . $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'mapFileName'} . ";\n"; # MAP config file
	print AUTOANNOT "ORF_CONFIG_FILE=" . $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'orfFileName'} . ";\n"; # ORF config file

	print AUTOANNOT "MAP_PROGRAM=" . $TRIANNOT_CONF{PATHS}->{soft}->{'map'}->{'bin'} . ";\n"; # bl2fna_exonerate.pl
	print AUTOANNOT "ORF_PROGRAM=" . $TRIANNOT_CONF{PATHS}->{soft}->{'orf'}->{'bin'} . ";\n"; # fna2orf.pl
	print AUTOANNOT "EXT_PROGRAM=" . $TRIANNOT_CONF{PATHS}->{soft}->{'ext'}->{'bin'} . ";\n"; # Extended_gff_start_stop.pl
	print AUTOANNOT "EIJ_PROGRAM=" . $TRIANNOT_CONF{PATHS}->{soft}->{'eij'}->{'bin'} . ";\n"; # compEIjunction.pl
	print AUTOANNOT "MODORF_PROGRAM=" . $TRIANNOT_CONF{PATHS}->{soft}->{'modo'}->{'bin'} . ";\n"; # modifyORF.pl
	print AUTOANNOT "MODGFF_PROGRAM=" . $TRIANNOT_CONF{PATHS}->{soft}->{'modg'}->{'bin'} . ";\n"; # modifyGFF.pl

	print AUTOANNOT "ABINITIO_GFF=" . $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'GFF_files'} . '/' . $self->{'abinitioGff'} . ";\n"; # Already computed gene prediction from another tool like Augustus, FgeneSH, etc.

	# Add some parameters from the SIMSearch.xml file to the AUTOANNOT config file
	foreach my $key (keys %{$self}) {
		if ($key =~ /^autoannot\.(.+)$/) {
			print AUTOANNOT $1 . "=" . $self->{$key} . ";\n";
		}
	}

	close(AUTOANNOT);
}

sub _prepareMapFile {

	# Recovers parameters
	my $self = shift;

	$logger->debug('Exonerate will be launched in serial mode (1 by 1)');

	# Write MAP file
	open(MAP, '>' . $self->{'mapFileName'}) || $logger->logdie('Error: Cannot create/open file: ' . $self->{'mapFileName'});

	print MAP "WD=" . $self->{'directory'} . '/' . $self->{'tmpFolder'} . ";\n"; # Working directory
	print MAP "G_SEQ=" . $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'sequence'} . ";\n"; # Input Sequence
	print MAP "T_SEQ=" . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'transcriptsDb'}}->{'path'} . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'transcriptsDb'}}->{'FastaExtension'} . ";\n"; # Databank in fasta format
	print MAP "T_DB=" . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'transcriptsDb'}}->{'path'} . ";\n"; # Databank in blast format (no extension)

	print MAP "BLAST_EXE=" . $TRIANNOT_CONF{SIMsearch}->{'BLAST_EXE'} . ";\n"; # Blast bin path (Could be different from the common blast defined in TriAnnotConfig_PATHS.xml)
	print MAP "EXONERATE_EXE=" . $TRIANNOT_CONF{PATHS}->{soft}->{'Exonerate'}->{'bin'} . ";\n"; # Exonerate bin path
	print MAP "FORMATDB_EXE=" . $TRIANNOT_CONF{PATHS}->{soft}->{'formatdb'}->{'bin'} . ";\n"; # Formatdb bin path
	print MAP "FASTACMD_EXE=" . $TRIANNOT_CONF{PATHS}->{soft}->{'fastacmd'}->{'bin'} . ";\n"; # fastacmd bin path

	#print MAP "SGE_EXE=" . $TRIANNOT_CONF{SIMsearch}->{'SGE_EXE'} . ";\n"; # Not used in TAP mode

	foreach my $key (keys %{$self}) {
		if ($key =~ /^map\.(.+)$/) {
			if ($1 eq 'BLAST_OPT') {
				print MAP $1 . "=" . $self->{$key} . " -a " . $self->{nbCore} . ";\n";
			} else {
				print MAP $1 . "=" . $self->{$key} . ";\n";
			}
		}
	}

	close(MAP);
}

sub _prepareOrfFile {

	# Recovers parameters
	my $self = shift;

	# Write ORF file
	open(ORF, '>' . $self->{'orfFileName'}) || $logger->logdie('Could not open ' . $self->{'orfFileName'} . ' in writing mode');

	print ORF "WD=" . $self->{'directory'} . '/' . $self->{'tmpFolder'} . ";\n"; # Working directory
	print ORF "DB=" . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'proteinDb'}}->{'path'} . ";\n"; # Databank in Blast format or fasta format (do not put the file extension at the end of the db name) - If formatdb is not already done (fasta database) it will be perform before Blast execution

	print ORF "BLAST_EXE=" . $TRIANNOT_CONF{SIMsearch}->{'BLAST_EXE'} . ";\n"; # Blast bin path (Could be different from the common blast defined in TriAnnotConfig_PATHS.xml)
	print ORF "FORMATDB_EXE=" . $TRIANNOT_CONF{PATHS}->{soft}->{'formatdb'}->{'bin'} . ";\n"; # Formatdb bin path

	#print ORF "SGE_EXE=" . $TRIANNOT_CONF{SIMsearch}->{'SGE_EXE'} . ";\n"; # Not used in TAP mode

	foreach my $key (keys %{$self}) {
		if ($key =~ /^orf\.(.+)$/) {
			if ($1 eq 'BLAST_OPT') {
				print ORF $1 . "=" . $self->{$key} . " -a " . $self->{nbCore} . ";\n";
			} else {
				print ORF $1 . "=" . $self->{$key} . ";\n";
			}
		}
	}

	close(ORF);
}

1;
