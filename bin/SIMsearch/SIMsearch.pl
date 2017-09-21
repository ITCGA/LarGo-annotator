#!/usr/bin/env perl

###################
#     Imports     #
###################

# Basic perl modules
use strict;
use warnings;
use diagnostics;

# Perl/CPAN modules
use File::Basename;
use Getopt::Long;

# SIMsearch modules
use SIMsearch::mapping::MAP;

# Debug
use Data::Dumper;


#############################
#     Globals variables     #
#############################

# Initializations
my $Start_time_hr = humanReadableDate();
my $programName = basename($0);

my ($configurationFile, $help) = (undef(), undef());


##########################
#     Manage options     #
##########################

GetOptions('config|c=s' => \$configurationFile, 'help|h' => \$help);

# Display help message if needed
if (defined($help) || (!defined($help) && !defined($configurationFile))) {
	displayHelpMessage();
}

# Check parameters
if (!defined($configurationFile)) {
	print STDERR 'ERROR: No configuration file specified with the -config/-c command line parameter !' . "\n";
	die 'ERROR:' . $!;
} else {
	if (! -e $configurationFile || -z $configurationFile) {
		print STDERR 'ERROR: The selected configuration file does not exists or is empty: ' . $configurationFile . "\n";
		die 'ERROR:' . $!;
	}
}


########################
#     Main program     #
########################

# Welcome message
print "#################################################\n";
print "#            Welcome in SIMsearch.pl            #\n";
print "#################################################\n";
print "Start time: " . $Start_time_hr . "\n\n";

# Load configuration file
my $configuration = {};
SIMsearch::mapping::MAP::read_option($configurationFile, $configuration);

# Execute bl2fna_exonerate
execute_bl2fna($configuration);
check_bl2fna_outputs($configuration);

# Execute fna2orf
execute_fna2orf($configuration);
check_fna2orf_outputs($configuration);

# Execute Extended_gff_start_stop
execute_Extended_gff_start_stop($configuration);
check_Extended_gff_start_stop_outputs($configuration);

# Execute compEIjunction
execute_compEIjunction($configuration);
check_compEIjunction_outputs($configuration);

# Execute modifyORF
execute_modifyORF($configuration);
check_modifyORF_outputs($configuration);

# Determine representative sequences within the GFF file
$configuration->{'REP_GFF'} = dirname($configuration->{'MODORF_GFF'}) . '/' . $configuration->{'CATEGORY'} . '_rep.gff';
my $makeRepResult = SIMsearch::mapping::MAP::makeRep($configuration->{'MODORF_GFF'}, $configuration->{'MAP_INF'}, $configuration->{'ORF_DAT'}, $configuration->{'MODORF_ORF_INF'}, $configuration->{'MAP_FNA'}, $configuration->{'MODORF_FNA'}, $configuration->{'MODORF_FAA'}, $configuration->{'PRIORITY'}, $configuration->{'CATEGORY'});
check_makeRep_outputs($configuration);

# Create an empty final outpu file or adapt the GFF to TriAnnot requirements
if ($makeRepResult == 0) {
	# Execute modifyGFF
	execute_modifyGFF($configuration);
	check_modifyGFF_outputs($configuration);
} else {
	createEmptyOutputfile($configuration, 'There is no representative sequence within the intermediate GFF file !');
}

print "\nStop time: " . humanReadableDate() . "\n";
print "#################################################\n";
print "#               End of execution                #\n";
print "#################################################\n";


#############################
#     Execute Functions     #
#############################

sub execute_bl2fna {

	# Recovers parameters
	my $configuration = shift;

	# Initializations
	$configuration->{'bl2fna_output'} = $configuration->{'WORKING_DIR'} . '/' . 'bl2fna_output_list.txt';

	# Build command line
	my $cmd = $configuration->{'MAP_PROGRAM'} . ' -c ' . $configuration->{'MAP_CONFIG_FILE'} . ' -o ' . $configuration->{'bl2fna_output'};

	# LOG
	print '[' . $programName . ']: bl2fna_exonerate.pl will be executed with the following command line: ' . $cmd . "\n";

	# Execute
	system($cmd);
}


sub execute_fna2orf {

	# Recovers parameters
	my $configuration = shift;

	# Initializations
	$configuration->{'ORF_DAT'} = $configuration->{'WORKING_DIR'} . '/' . 'orf.dat';

	# Build command line
	my $cmd = $configuration->{'ORF_PROGRAM'} . ' -i ' . $configuration->{'MAP_FNA'} . ' -g ' . $configuration->{'MAP_GFF'} . ' -c ' . $configuration->{'ORF_CONFIG_FILE'};

	# LOG
	print '[' . $programName . ']: fna2orf.pl will be executed with the following command line: ' . $cmd . "\n";

	# Execute
	system($cmd);
}


sub execute_Extended_gff_start_stop {

	# Recovers parameters
	my $configuration = shift;

	# Initializations
	my ($fileWithoutExt, $base, $ext) = fileparse($configuration->{'MAP_GFF'}, qr/\.[^.]*/);
	$configuration->{'EXT_output_prefix'} = $fileWithoutExt . '_53ext';
	$configuration->{'EXT_FNA'} = $configuration->{'WORKING_DIR'} . '/' . $configuration->{'EXT_output_prefix'} . '.fna';
	$configuration->{'EXT_FAA'} = $configuration->{'WORKING_DIR'} . '/' . $configuration->{'EXT_output_prefix'} . '.faa';
	$configuration->{'EXT_ORF_INF'} = $configuration->{'WORKING_DIR'} . '/' . $configuration->{'EXT_output_prefix'} . '_orf.inf';
	$configuration->{'EXT_GFF'} = $configuration->{'WORKING_DIR'} . '/' . $configuration->{'EXT_output_prefix'} . '.gff';

	# Build command line
	my $cmd = $configuration->{'EXT_PROGRAM'} . ' -b ' . $configuration->{'INPUT_SEQUENCE'} . ' -g ' . $configuration->{'MAP_GFF'} . ' -o ' . $configuration->{'EXT_output_prefix'} . ' ' . $configuration->{'EXT_OPT'};

	# LOG
	print '[' . $programName . ']: Extended_gff_start_stop.pl will be executed with the following command line: ' . $cmd . "\n";

	# Execute
	system($cmd);
}


sub execute_compEIjunction {

	# Recovers parameters
	my $configuration = shift;

	# Initializations
	$configuration->{'EIJ_OUT'} = $configuration->{'WORKING_DIR'} . '/compEIjunction.inf';

	# Build command line
	my $cmd = $configuration->{'EIJ_PROGRAM'} . ' -gff1 ' . $configuration->{'EXT_GFF'} . ' -gff2 ' . $configuration->{'ABINITIO_GFF'} . ' -inf ' . $configuration->{'EXT_ORF_INF'} . ' > ' . $configuration->{'EIJ_OUT'};

	# LOG
	print '[' . $programName . ']: compEIjunction.pl will be executed with the following command line: ' . $cmd . "\n";

	# Execute
	system($cmd);
}


sub execute_modifyORF {

	# Recovers parameters
	my $configuration = shift;

	# Initializations
	$configuration->{'MODORF_GFF'} = $configuration->{'WORKING_DIR'} . '/modified.gff';
	$configuration->{'MODORF_ORF_INF'} = $configuration->{'WORKING_DIR'} . '/modified.inf';
	$configuration->{'MODORF_FNA'} = $configuration->{'WORKING_DIR'} . '/modified.fna';
	$configuration->{'MODORF_FAA'} = $configuration->{'WORKING_DIR'} . '/modified.faa';

	# Build command line
	my $cmd = $configuration->{'MODORF_PROGRAM'} . ' -gff ' . $configuration->{'EXT_GFF'} . ' -inf ' . $configuration->{'EIJ_OUT'} . ' -fna ' . $configuration->{'EXT_FNA'} . ' -genome ' . $configuration->{'INPUT_SEQUENCE'} . ' -dir ' . $configuration->{'WORKING_DIR'};

	# LOG
	print '[' . $programName . ']: modifyORF.pl will be executed with the following command line: ' . $cmd . "\n";

	# Execute
	system($cmd);
}


sub execute_modifyGFF {

	# Recovers parameters
	my $configuration = shift;

	# Initializations
	$configuration->{'MODGFF_OUTPUT'} = $configuration->{'WORKING_DIR'} . '/for_annotation_' . $configuration->{'CATEGORY'} . '.gff';

	# Build command line
	my $cmd = $configuration->{'MODGFF_PROGRAM'} . ' -seq ' . $configuration->{'INPUT_SEQUENCE'} . ' -gff ' . $configuration->{'REP_GFF'} . ' -category ' . $configuration->{'CATEGORY'} . ' -dir ' . $configuration->{'WORKING_DIR'};

	# LOG
	print '[' . $programName . ']: modifyGFF.pl will be executed with the following command line: ' . $cmd . "\n";

	# Execute
	system($cmd);
}


#####################################
#     Output checking functions     #
#####################################

sub check_bl2fna_outputs {

	# Recovers parameters
	my $configuration = shift;

	# Read the main output file to update the configuration hash table
	if (-f $configuration->{'bl2fna_output'} && !-z $configuration->{'bl2fna_output'}) {
		SIMsearch::mapping::MAP::read_option($configuration->{'bl2fna_output'}, $configuration);
	} else {
		print STDERR '[' . $programName . '] ERROR: The file (' . basename($configuration->{'bl2fna_output'}) . ') that contains the complete list of file normally generated by ' . basename ($configuration->{'MAP_PROGRAM'}) . ' is missing or empty..' . "\n";
		die '[' . $programName . '] ERROR: ' . $! . "\n";
	}

	# Check the existence of every other output files
	checkOutputFileExistence($configuration->{'MAP_FNA'}, 'Fasta', basename($configuration->{'MAP_PROGRAM'}));
	checkOutputFileExistence($configuration->{'MAP_GFF'}, 'GFF', basename($configuration->{'MAP_PROGRAM'}));
	checkOutputFileExistence($configuration->{'MAP_INF'}, 'INF', basename($configuration->{'MAP_PROGRAM'}));
	checkOutputFileExistence($configuration->{'MAP_ABS'}, 'Abstract', basename($configuration->{'MAP_PROGRAM'}));

	# Halt the execution if the number of validated gene models is equal to 0
	my $validatedGeneCounter = getSpecificValueFromAbstractFile($configuration->{'MAP_ABS'}, 'Nb_validated_genes');
	createEmptyOutputfile($configuration, 'There is no validated gene model !') if ($validatedGeneCounter == 0);

	# Halt the execution if either the Fasta file or the INF file is empty
	if (-z $configuration->{'MAP_FNA'} || -z $configuration->{'MAP_INF'}) {
		createEmptyOutputfile($configuration, 'At least one of the ' . basename($configuration->{'MAP_PROGRAM'}) . ' output file is empty !');
	}

	return 0;
}


sub check_fna2orf_outputs {

	# Recovers parameters
	my $configuration = shift;

	# Check the existence of the output file
	checkOutputFileExistence($configuration->{'ORF_DAT'}, 'DAT', basename($configuration->{'ORF_PROGRAM'}));

	# Halt the execution if the dat output file is empty
	createEmptyOutputfile($configuration, 'No ORF found by ' . basename($configuration->{'ORF_PROGRAM'}) . ' !') if (-z $configuration->{'ORF_DAT'});

	return 0;
}


sub check_Extended_gff_start_stop_outputs {

	# Recovers parameters
	my $configuration = shift;

	checkOutputFileExistence($configuration->{'EXT_FNA'}, 'Nucleic Fasta', basename($configuration->{'EXT_PROGRAM'}));
	checkOutputFileExistence($configuration->{'EXT_FAA'}, 'Proteic Fasta', basename($configuration->{'EXT_PROGRAM'}));
	checkOutputFileExistence($configuration->{'EXT_ORF_INF'}, 'INF', basename($configuration->{'EXT_PROGRAM'}));
	checkOutputFileExistence($configuration->{'EXT_GFF'}, 'GFF', basename($configuration->{'EXT_PROGRAM'}));

	return 0;
}


sub check_compEIjunction_outputs {

	# Recovers parameters
	my $configuration = shift;

	checkOutputFileExistence($configuration->{'EIJ_OUT'}, 'INF', basename($configuration->{'EIJ_PROGRAM'}));

	return 0;
}


sub check_modifyORF_outputs {

	# Recovers parameters
	my $configuration = shift;

	checkOutputFileExistence($configuration->{'MODORF_FNA'}, 'Nucleic Fasta', basename($configuration->{'MODORF_PROGRAM'}));
	checkOutputFileExistence($configuration->{'MODORF_FAA'}, 'Proteic Fasta', basename($configuration->{'MODORF_PROGRAM'}));
	checkOutputFileExistence($configuration->{'MODORF_ORF_INF'}, 'INF', basename($configuration->{'MODORF_PROGRAM'}));
	checkOutputFileExistence($configuration->{'MODORF_GFF'}, 'GFF', basename($configuration->{'MODORF_PROGRAM'}));

	return 0;
}


sub check_makeRep_outputs {

	# Recovers parameters
	my $configuration = shift;

	# Check the existence of the makeRep outfile
	checkOutputFileExistence($configuration->{'REP_GFF'}, 'GFF', 'the SIMsearch::mapping::MAP::makeREP function');

	return 0;
}


sub check_modifyGFF_outputs {

	# Recovers parameters
	my $configuration = shift;

	checkOutputFileExistence($configuration->{'MODGFF_OUTPUT'}, 'GFF', basename($configuration->{'MODGFF_PROGRAM'}));

	return 0;
}


sub checkOutputFileExistence {

	# Recovers parameters
	my ($fileToCheck, $fileType, $fileCreator) = @_;

	# Check if the selected file exists
	if (!-e $fileToCheck) {
		print STDERR '[' . $programName . '] ERROR: The ' . $fileType . ' file (' . basename($fileToCheck) . ') file generated by ' . $fileCreator . ' is missing..' . "\n";
		die '[' . $programName . '] ERROR: ' . $! . "\n";
	}
}


###########################
#     Other Functions     #
###########################

sub humanReadableDate {

	# Recovers parameters
	my $time = shift || time;

	# Split time string
	my ($seconde, $minute, $heure, $jour, $mois, $annee, $jour_semaine, $jour_annee, $heure_hiver_ou_ete) = localtime($time);
	$mois  += 1;
	$annee += 1900;

	# On rajoute 0 si le chiffre est compris entre 1 et 9
	foreach ( $seconde, $minute, $heure, $jour, $mois, $annee ) { s/^(\d)$/0$1/; }

	return "$jour-$mois-$annee" . '_' . "$heure:$minute:$seconde";
}


sub displayHelpMessage {

	print ('###########################################################' . "\n");
	print ('#               ' . $programName . ' - Help section               #' . "\n");
	print ('###########################################################' . "\n\n");

	print 'Usage example:' . "\n\n";
	print '   ' . 'SIMsearch.pl -c My_configuration_file.ctl' . "\n\n\n";

	print 'Parameters :' . "\n\n";

	print '   ' . '-help => Display this help message.' . "\n\n";
	print '   ' . '-config/-c file => Full path of the configuration file to use (mandatory).' . "\n\n";

	print ("\n" . '###########################################################' . "\n");
	print ('#            ' . $programName . ' - Help section - END            #' . "\n");
	print ('###########################################################' . "\n");

	exit (1);
}


sub createEmptyOutputfile {

	# Recovers parameters
	my ($configuration, $message) = @_;

	# Initializations
	$configuration->{'EMPTY_OUTPUT_FILE'} = $configuration->{'WORKING_DIR'} . '/for_annotation_' . $configuration->{'CATEGORY'} . '.gff';

	# Create the empty output file
	print '[' . $programName . ']: ' . $message . ' Creating an empty final output file..' . "\n";

	open (EMPTY_OUT, '>' . $configuration->{'EMPTY_OUTPUT_FILE'}) or die('Error: Cannot create/open file: ' . $configuration->{'EMPTY_OUTPUT_FILE'});
	close (EMPTY_OUT);

	# Stop the execution after the creation of the empty output file
	exit();
}


sub getSpecificValueFromAbstractFile {

	# Recovers parameters
	my ($abstractFile, $searchedValue) = @_;

	# Initializations
	my %abstract = ();

	# read Abstract file
	open (ABSTRACT, '<' . $abstractFile) or die('Error: Cannot open/read file: ' . $abstractFile);

	while (my $abstractLine = <ABSTRACT>) {
		my ($tag, $value) = split ('=', $abstractLine);

		$abstract{$tag} = $value;
	}

	close(ABSTRACT);

	# Return requested value
	if (defined($abstract{$searchedValue}) && $abstract{$searchedValue} ne "") {
		return $abstract{$searchedValue};
	} else {
		return 0;
	}
}
