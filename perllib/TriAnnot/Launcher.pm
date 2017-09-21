#!/usr/bin/env perl

package TriAnnot::Launcher;

##################################################
## Modules
##################################################
## Basic Perl modules
use strict;
use warnings;
use diagnostics;

## Perl modules
use File::Basename;
use Getopt::Long;
use Data::Dumper;
use XML::Twig;
use Cwd;
use Log::Log4perl::Level;

## CPAN modules
use Capture::Tiny 'capture';

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Programs::Programs;
use TriAnnot::Tools::Logger;


#################
# Constructor
#################

sub new {
	my $class = shift;
	my $self = {
		usageExample      => undef,
		Working_directory => undef,
		Stage_list        => undef,
		Config_file       => undef,
		Sequence_file     => undef,
		Program_id        => undef,
		ProgramName       => undef,
		step              => undef,
		help              => undef,
		verbosity         => undef,
		checkList         => undef
	};
	bless $self => $class;
	return $self;
}


#######################
# Options management
#######################

sub getOptions {
	my $self = shift;
	my $specificOptionsArrayRef = shift;

	if (!defined($specificOptionsArrayRef)) {
		$specificOptionsArrayRef = [];
	}

	# Get options from command line
	my @options = (
		'help|h'             => \$self->{help},
		'progid|pid=i'       => \$self->{Program_id},
		'stagelist|step=s'   => \$self->{Stage_list},
		'sequence|seq=s'     => \$self->{Sequence_file},
		'workdir|wd=s'       => \$self->{Working_directory},
		'configfile|conf=s'  => \$self->{Config_file},
		'verbose|v=i'        => \$self->{verbosity},
		'check=s@'           => \$self->{checkList}
	);

	push(@options, @$specificOptionsArrayRef);
	GetOptions (@options);
}


sub checkOptions {
	my $self = shift;
	$self->checkOptionsToHandleBeforeLoadingConfigurationFiles();
	$self->checkSpecificOptionsToHandleBeforeLoadingConfigurationFiles();
	$self->readConfigurationFiles();
	$self->checkOptionsToHandleAfterLoadingConfigurationFiles();
	$self->checkSpecificOptionsToHandleAfterLoadingConfigurationFiles();

	$self->displayParameters();
}


sub checkOptionsToHandleBeforeLoadingConfigurationFiles {
	my $self = shift;
	$logger->info('');

	# Display help message if needed
	if (defined($self->{help})) {
		$self->displayHelpMessage();
	}

	# Deal with verbose option
	if (!defined($self->{verbosity})) {
		$self->{verbosity} = 0;
	}
	elsif ($self->{verbosity} < 0 || $self->{verbosity} > 3) {
		$logger->info('Error: The selected verbosity level (' . $self->{verbosity} . ') is not valid !');
		$logger->info('');
		$self->displayHelpMessage();
	}
	$TRIANNOT_CONF_VERBOSITY = $self->{verbosity};
	if ($self->{verbosity} == 3) {
		$logger->level($DEBUG);
	}

	if (!defined($self->{Config_file})) {
		$logger->info('Error: No config file defined through the -configfile/-conf option !');
		$logger->info('');
		$self->displayHelpMessage();
	} else {
		if(!-e $self->{Config_file}) {
			$logger->info('Error: Selected configuration file does not exists !');
			$logger->info('');
			$self->displayHelpMessage();
		}
	}

	# Deal with progid option
	if (!defined($self->{Program_id})) {
		$logger->info('Error: No program identifier defined !');
		$logger->info('');
		$self->displayHelpMessage();
	}

	# Deal with stagelist option
	if (!defined($self->{Stage_list}) || $self->{Stage_list} eq '') {
		$logger->info('No stage list defined !');
		$logger->info('Default stage list step.xml will be used...');
		$logger->info('');

		$self->{Stage_list} = 'step.xml';
	}

	if(!-e $self->{Stage_list}) {
		$logger->info('Error: Selected stage list does not exists !');
		$logger->info('This program cannot run without a valid stage list... Exiting...');
		$logger->info('');
		$self->displayHelpMessage();
	}

	$self->{Stage_list} = Cwd::realpath($self->{Stage_list});

	# Deal with sequence option
	if (!defined($self->{Sequence_file}) || $self->{Sequence_file} eq '') {
		$logger->info('No sequence file defined !');
		$logger->info('Default sequence file seq.tfa will be used...');
		$logger->info('');

		$self->{Sequence_file} = 'seq.tfa';
	}

	if(!-e $self->{Sequence_file} || -z $self->{Sequence_file}) {
		$logger->info('Error: Selected sequence file does not exists (or is empty)!');
		$logger->info('This program cannot run without a valid sequence file... Exiting...');
		$logger->info('');
		$self->displayHelpMessage();
	}

	$self->{Sequence_file} = Cwd::realpath($self->{Sequence_file});

	$self->checkSpecificOptionsToHandleBeforeLoadingConfigurationFiles();
}


sub checkOptionsToHandleAfterLoadingConfigurationFiles {
	my $self = shift;
	# Deal with workdir option
	if (!defined($self->{Working_directory})) {
		$self->{Working_directory} = getcwd();
		$logger->info('No custom work directory defined !');
		$logger->info('This program will be executed in current directory...');
		$logger->info('');
	}
	$self->createWorkingDirectoryIfNeeded();
}


############################
# Directories management
############################

sub createWorkingDirectoryIfNeeded {
	my $self = shift;

	if (!-e $self->{Working_directory}) {
		# Note: This situation should not happen if TAP_Program_Launcher is launched througth TriAnnot main python program
		$logger->info('Creation of the selected work directory: ' . $self->{Working_directory});
		$logger->info('');
		mkdir($self->{Working_directory}, 0755) or $logger->logdie('Error: Cannot create directory ' . $self->{Working_directory});
	}

	$self->{Working_directory} = Cwd::realpath($self->{Working_directory});

}


sub createAllSubDirectories {
	my $self = shift;
	$self->{log_repository} = $self->{Working_directory} . '/' . $TRIANNOT_CONF{DIRNAME}->{'log_files'};
	$self->{abstract_repository} = $self->{Working_directory} . '/' . $TRIANNOT_CONF{DIRNAME}->{'summary_files'};
	$self->{common_tmp_repository} = $self->{Working_directory} . '/' . $TRIANNOT_CONF{DIRNAME}->{'tmp_files'};
	$self->{Other_files_repository} = $self->{Working_directory} . '/' . $TRIANNOT_CONF{DIRNAME}->{'keep_files'};

	# Directory creation
	if (!-e $self->{log_repository}) { mkdir($self->{log_repository}, 0755); }
	if (!-e $self->{abstract_repository}) { mkdir($self->{abstract_repository}, 0755); }
	if (!-e $self->{common_tmp_repository}) { mkdir($self->{common_tmp_repository}, 0755); }
	if (!-e $self->{Other_files_repository}) { mkdir($self->{Other_files_repository}, 0755); }
	$self->createSpecificSubDirectories();
}


################################################
# CheckConfiguration.py execution and parsing
################################################

sub checkConfigurationInPython {

	# Recovers parameters
	my ($self, $logFilesSuffix) = @_;

	# Execute The Python configuration checker if needed (CheckConfiguration.py in TAP 4.4)
	if (defined($self->{'checkList'})) {
		$logger->info('The Python configuration checker will now be used to check the full configuration file');

		my $configurationCheckerErrors = $self->executePythonConfigurationChecker($logFilesSuffix);

		# If the error file is not empty then all errors will be displayed before exiting the program
		if ($configurationCheckerErrors ne "") {
			$logger->info('The following errors have been detected by the Python configuration checker:');
			$logger->logdie($configurationCheckerErrors);
		} else {
			$logger->info('No error has been detected by the Python configuration checker.');
		}
	}
}


sub executePythonConfigurationChecker {

	# Recovers parameters
	my ($self, $logFilesSuffix) = @_;

	# Initializations
	my $checkerName = basename($TRIANNOT_CONF{'PATHS'}->{'soft'}->{'CheckConfiguration'}->{'bin'});
	my $errorFileName = 'CheckConfiguration' . $logFilesSuffix . '.err';

	# Building of the command line
	my $cmd = $TRIANNOT_CONF{'PATHS'}->{'soft'}->{'CheckConfiguration'}->{'bin'};
	$cmd .= ' --config ' . $self->{'Config_file'};
	$cmd .= ' --debug ' if ($self->{'verbosity'} > 2);
	$cmd .= ' --check ' . join(' ', @{$self->{'checkList'}});
	$cmd .= ' --suffix ' . $logFilesSuffix;
	$cmd .= ' --nolog';

	# Log the newly build command line
	$logger->debug($checkerName . ' command line:');
	$logger->debug($cmd);

	# Execute command
	my ($stdout, $stderr, $exitCode) = capture { system($cmd); };

	# Avoid "uninitialized value" warning with outdated versions of the Capture::Tiny module
	if (!defined($exitCode) or $exitCode eq '') {
		$exitCode = 'undefined (Please upgrade your "Capture::Tiny" CPAN module to version 0.24 or greater)';
	}

	# Log the result
	$logger->debug($checkerName . ' exit code is: ' . $exitCode);

	$logger->debug("####################################");
	$logger->debug("##  External Tool Output - START  ##");
	$logger->debug("####################################");
	$logger->debug($stdout);
	$logger->debug("##################################");
	$logger->debug("##  External Tool Output - END  ##");
	$logger->debug("##################################");

	# Return the potential errors
	return $stderr;
}


###########################
# Configuration loading
###########################

sub readConfigurationFiles {
	my $self = shift;

	# Deal with config file option
	if (defined($self->{Config_file})) {
		$self->{Config_file} = Cwd::realpath($self->{Config_file});
		$TRIANNOT_CONF{Runtime}->{'configFile'} = $self->{Config_file};

		# Load TriAnnot Pipeline command line configuration file
		TriAnnot::Config::ConfigFileLoader::loadThisConfigurationFile($self->{Config_file}, $TRIANNOT_CONF{VERSION});
	}
}


sub displayParameters{
	my $self = shift;
	if ($logger->level() >= $DEBUG) {
		$logger->debug('Here is the list of input parameters :');

		$logger->debug('Working directory: ' . $self->{Working_directory});
		$logger->debug('Stage list: ' . $self->{Stage_list});
		if (defined($self->{Config_file})) {
			$logger->debug('Configuration file: ' . $self->{Config_file});
		}
		$logger->debug('Sequence file: ' . $self->{Sequence_file});
		$logger->debug('Program identifier: ' . $self->{Program_id});

		if (defined($self->{checkList})) {
			$logger->debug('List of configuration checks that must be re-executed on the execution node: ' . join(', ', @{$self->{checkList}}));
		}

		$self->displaySpecificParameters();
		$logger->debug('');
	}
}


###########################
# Logger creation
###########################

sub initFileLoggers {
	my $self = shift;
	my $normalLogFilePath = shift;
	my $debugLogFilePath = shift;
	TriAnnot::Tools::Logger::initFileLoggers($self->{log_repository}, $normalLogFilePath, $debugLogFilePath);
}


#######################################
# Load Step/Task/StageList XML file
#######################################

sub _processStageListWithTwig {
	my $self = shift;

	# Creates the Twig object
	my $Twig_object = XML::Twig->new(twig_handlers => {'program[@id="' . $self->{Program_id} . '"]' =>  sub { $self->_loadProgramParameters(@_) } });

	# "twig-ish" parse of the file
	$logger->info('Analysis of the stage list to collect parameters for the selected program (PID: ' . $self->{Program_id} . ')');

	$Twig_object->parsefile($self->{Stage_list});
	if (!defined($self->{programName})) {
		$logger->logdie('Error: There is no program with this ID in the stage list file');
	}

	$logger->info('All parameters have been successfully collected !');
	$logger->info('');
}


sub _loadProgramParameters {
	my ($self, $twigObject, $programTwig) = @_;

	# Initializations
	my ($parameterName, $parameterValue) = (undef, undef);

	# Get program name and identifier
	$self->{'programName'} = $programTwig->att('type');
	$self->{'step'} = $programTwig->att('step');
	$self->{'stepSequence'} = $programTwig->att('sequence');

	# Analyse all <parameter> XML tag
	foreach my $parameterTwig ($programTwig->children('parameter')) {
		$parameterName = $parameterTwig->att('name');
		$parameterValue = $parameterTwig->text();

		# Analyse the current parameter tag/block and store it's value in memory (programParameters hash)
		# There are 2 cases here:
		# 1) The parameter can have multiple values (isArray parameter)
		# 2) The parameter can only have one value
		if ($parameterTwig->att_exists('isArray')) {
			if ($parameterTwig->att('isArray') eq 'yes') {
				if (!defined($self->{'programParameters'}->{$parameterName})) {
					# Deal with first value of the isArray parameter
					$self->{'programParameters'}->{$parameterName} = [$parameterValue];
				} else {
					# Deal with other values
					push(@{$self->{'programParameters'}->{$parameterName}}, $parameterValue);
				}
			}
		} else {
			if (defined($self->{'programParameters'}->{$parameterName})) {
				$logger->logdie('Parameter ' . $parameterName . ' is not an isAray parameter but yet have multiple values. This should never happen !')
			}
			$self->{'programParameters'}->{$parameterName} = $parameterValue;
		}
	}

	# Debug log
	$logger->debug('List of parameters for the selected program :');
	$logger->debug(Dumper($self->{'programParameters'}));
	$logger->debug('');

	$programTwig->purge();
}


############################
# Abstract file creation
############################

sub prepareAbstractFile {

	# Recovers parameters
	my ($self, $abstractFileName) = @_;

	# Initializations
	my $Abstract_file_fullpath = $self->{'abstract_repository'} . '/' . $abstractFileName;

	# Creation of the twig object
	my $twig = XML::Twig->new();
	$twig->set_xml_version('1.0');
	$twig->set_encoding('ISO-8859-1');
	$twig->set_pretty_print('record');

	# Creation of the XML root
	my $XML_root = XML::Twig::Elt->new('program', {'id' => $self->{'Program_id'}});
	$twig->set_root($XML_root);

	# Get the content of the file from the child class (as an XML::Twig::Elt object)
	$self->_addSpecificContentToAbstractFile($twig->root());

	# Write the twig to generate the custom XML file
	$twig->print_to_file($Abstract_file_fullpath);
}


sub _addDataFromInfoFile {

	# Recovers parameters
	my ($self, $twigParentElement) = @_;

	# Read the info file and build xml element
	open(INFO, '<' . $self->{'common_tmp_repository'} . '/' . $self->{'componentObject'}->{'infoFileName'}) or $logger->logdie('Error: Cannot open/read file: ' . $self->{'componentObject'}->{'infoFileName'});
	while (my $currentLine = <INFO>) {
		my @dataCouples = split(';', $currentLine);

		foreach my $currentCouple (@dataCouples) {
			my ($attribute, $value) = split('=', $currentCouple);
			$twigParentElement->insert_new_elt('last_child', $attribute, $value);
		}
	}
	close(INFO);

	return 0; # SUCCESS
}


##################################
# Help display related methods
##################################

sub displayHelpMessage {
	my $self = shift;

	$logger->info('######################################################');
	$logger->info('# ' . $self->{launcherTitle} . ' - Help section #');
	$logger->info('######################################################');
	$logger->info('');

	$logger->info('Here is the list of authorized parameters :');
	$logger->info('');

	$logger->info('   -progid/-pid integer => Identifier of the program to execute (Mandatory)');
	$logger->info('');

	$logger->info('   -configfile/-conf file => Path and name of a global XML configuration file generated by TriAnnotPipeline.py (Mandatory)');
	$logger->info('');

	$logger->info('   -workdir/-wd file => Path and name of the main analysis directory (Optional)');
	$logger->info('       By default, the current directory will be used');
	$logger->info('');

	$logger->info('   -stagelist/-step file => XML file which contains all parameters for the program to execute (Optional)');
	$logger->info('       By default, the reference file step.xml will be used');
	$logger->info('');

	$logger->info('   -sequence/-seq file => Fasta sequence file which contains the sequence to use for the selected program (Optional)');
	$logger->info('       By default, the reference file seq.tfa will be used');
	$logger->info('');

	$logger->info('   -check string => List of configuration checks that will be done at the beginning of the execution procedure (Optional)');
	$logger->info('       When this option is not used, no check will be made');
	$logger->info('');
	$logger->info('       Possible checks are:');
	$logger->info('         - xml  -> Check XML configuration files syntax with XMLlint');
	$logger->info('         - sect -> Check mandatory configuration section existence');
	$logger->info('         - entr -> Check mandatory configuration entries existence');
	$logger->info('         - dep  -> Check dependencies between configuration files');
	$logger->info('         - def  -> Check the definitions of all tool\'s parameters');
	$logger->info('         - path -> Check the existence of the files/directories referenced in the TriAnnotConfig* XML configuration files');
	$logger->info('');
	$logger->info('       Example:');
	$logger->info('         Use \'-check xml -check entr\' to check both xml syntax and mandatory configuration entries existence');
	$logger->info('');

	$self->displaySpecificHelpMessage();

	$logger->info('   -verbose/-v integer => Level of verbosity. Possible values are 0, 1, 2, 3.');
	$logger->info('       0 will produce minimal output and 3 enables debug output. Default is 0.');
	$logger->info('');

	$logger->info('   -help => Display this help message');
	$logger->info('');
	$logger->info('');

	if (defined($self->{usageExample})) {
		$logger->info('Usage example :');
		$logger->info('');

		$logger->info($self->{usageExample});
		$logger->info('');
	}

	exit();
}


######################
# Abstract methods
######################

# Note: All this methods must be overridden in the subclasses of the Launcher class

sub checkSpecificOptionsToHandleBeforeLoadingConfigurationFiles {
	my $self = shift;

	$logger->logdie("Method checkSpecificOptionsToHandleBeforeLoadingConfigurationFiles() must be overridden in each specialized sub-class");
}


sub checkSpecificOptionsToHandleAfterLoadingConfigurationFiles {
	my $self = shift;

	$logger->logdie("Method checkSpecificOptionsToHandleAfterLoadingConfigurationFiles() must be overridden in each specialized sub-class");
}


sub displaySpecificParameters {
	my $self = shift;

	$logger->logdie("Method displaySpecificParameters() must be overridden in each specialized sub-class");
}


sub displaySpecificHelpMessage {
	my $self = shift;

	$logger->logdie("Method displaySpecificHelpMessage() must be overridden in each specialized sub-class");
}


sub createSpecificSubDirectories {
	my $self = shift;

	$logger->logdie("Method createSpecificSubDirectories() must be overridden in each specialized sub-class");
}


sub _createComponentObject {
	my $self = shift;

	$logger->logdie("Method _createComponentObject() must be overridden in each specialized sub-class");
}


sub _doTreatment {
	my $self = shift;

	$logger->logdie("Method _doTreatment() must be overridden in each specialized sub-class");
}


sub _addSpecificContentToAbstractFile {
	my $self = shift;

	$logger->logdie("Method _getSpecificAbstractFileContent() must be overridden in each specialized sub-class");
}


##################
#      MAIN      #
##################

sub main {
	# Recovers parameters
	my $self = shift;

	# Jump to the execution directory
	chdir($self->{Working_directory}) or $logger->logdie('Error: Could not jump to the directory: ' . $self->{Working_directory});

	# Welcoming - Log
	$logger->info('#################################################');
	$logger->info('# Welcome in ' . $self->{launcherTitle} . ' #');
	$logger->info('#################################################');
	$logger->info('Start date: ' . localtime());
	$logger->info('');

	# Parse the stage list to collect all parameters for the selected program ID
	$self->_processStageListWithTwig();

	$self->{componentObject} = $self->_createComponentObject();
	$self->{componentObject}->setSequence($self->{Sequence_file});
	$self->{componentObject}->setParameters($self->{programParameters});

	$logger->trace('Dumper of the new program object :');
	$logger->trace(sub { Dumper($self->{componentObject}) });
	$logger->trace('');
	$self->_doTreatment();

	$logger->trace('Dumper of the new program object after treatment :');
	$logger->trace(sub {Dumper($self->{componentObject}) });
	$logger->trace('');

	# Exiting - Log
	$logger->info('');
	$logger->info('End date: ' . localtime());
	$logger->info('#################################################');
	$logger->info('#   End of ' . $self->{launcherTitle} . ' #');
	$logger->info('#################################################');
}

1;
