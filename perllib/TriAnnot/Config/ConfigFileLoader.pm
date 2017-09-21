#!/usr/bin/env perl

package TriAnnot::Config::ConfigFileLoader;

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
use File::Basename;
use Cwd;
use Data::Dumper;
use XML::Twig;
use FindBin;
require Exporter;

## TriAnnot modules
use TriAnnot::Tools::Logger;
use TriAnnot::TriAnnotVersion;


our %TRIANNOT_CONF = ('VERSION'=> $TriAnnot::TriAnnotVersion::TRIANNOT_VERSION);
our $TRIANNOT_CONF_VERBOSITY = 0;
our @ISA = qw(Exporter);
our @EXPORT = qw(%TRIANNOT_CONF $TRIANNOT_CONF_VERBOSITY);


#################
# Constructor
#################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Initialize specific object attributes
	my $self = {
		config_file_path   => $attrs{'config_file'},
		config_file_name   => basename($attrs{'config_file'}),
		requiredVersion    => defined($attrs{'requiredVersion'}) ? $attrs{'requiredVersion'} : undef,
		#bypassValidation   => !TriAnnot::Config::ConfigFileLoader->isXmllintAvailable(),
		CONF               => \%TRIANNOT_CONF
	};

	bless $self => $class;

	return $self;
}


#########################
# XML parsing - Configuration loading
#########################

sub loadConfigurationFile {

	# Recovers parameters
	my $self = shift;

	my $twigObject = XML::Twig->new();
	$TriAnnot::Tools::Logger::logger->debug('Analysis of XML configuration file: ' . $self->{'config_file_name'});

	$twigObject->parsefile($self->{'config_file_path'});
	if (defined($self->{requiredVersion}) && $twigObject->root->{att}->{triannot_version} ne $self->{CONF}->{VERSION}) {
		$TriAnnot::Tools::Logger::logger->logdie($self->{'config_file_name'} . ' configuration file version is ' . $twigObject->root->{att}->{triannot_version} . '. It does not match TriAnnot version: ' . $self->{CONF}->{VERSION});
	}

	my @sections= $twigObject->root->children('section');
	foreach my $section (@sections) {
		$self->readSection($section, $self->{CONF})
	}
	$twigObject->purge();

	$TriAnnot::Tools::Logger::logger->debug('All data have been successfully loaded !');
	$TriAnnot::Tools::Logger::logger->debug('');

	# Return all collected data
	return $self->{CONF};
}


sub readSection() {
	my ($self, $sectionXml, $hashDestination) = @_;
	my $entriesCpt = 0;

	my $sectionName = trim($sectionXml->{'att'}->{'name'});
	my $clear = 0; #false
	if ($sectionXml->att_exists('clear')) {
		$clear = 1; #true
	}

	if (!defined($sectionName) || trim($sectionName) eq '') {
		$TriAnnot::Tools::Logger::logger->logdie("Invalid section found. All sections must have a name attribute:\n" . $sectionXml->start_tag())
	}

	if (defined($hashDestination->{$sectionName})) {
		$TriAnnot::Tools::Logger::logger->info("Overriding section [$sectionName]");
	}
	if (!defined($hashDestination->{$sectionName}) ||
		(defined($hashDestination->{$sectionName}) && $clear)) {
		$hashDestination->{$sectionName} = {};
	}
	$entriesCpt = scalar(keys(%{$hashDestination->{$sectionName}}));
	foreach my $entry ($sectionXml->children('entry')) {
		$self->readEntry($entry, $hashDestination->{$sectionName}, $sectionName, $entriesCpt++);
	}
}


sub readEntry() {
	my ($self, $entryXml, $hashDestination, $sectionName, $entryNumber) = @_;

	my $key = $entryNumber;
	if (defined($entryXml->{'att'}->{'key'})) {
		$key = trim($entryXml->{'att'}->{'key'});
		if ($key eq '') {
			$TriAnnot::Tools::Logger::logger->logdie("Invalid empty entry key found in section [$sectionName]");
		}
	}
	my $value = trim($entryXml->text_only());
	if (#($value eq '' and !$entryXml->has_child('entry')) or
		($value ne '' and $entryXml->has_child('entry'))) {
		$TriAnnot::Tools::Logger::logger->logdie("Invalid entry [$key] found in section [$sectionName]");
	}
	if (defined($hashDestination->{$key})) {
		$TriAnnot::Tools::Logger::logger->info("Overriding value of entry [$key] in section [$sectionName]");
	}
	if (!$entryXml->has_child('entry')) { # scalar value
		$hashDestination->{$key} = $value;
	}
	else {
		my $subEntriesCpt = 0;
		my $clear = 0; #false
		if ($entryXml->att_exists('clear')) {
			$clear = 1; #true
		}

		if (!defined($hashDestination->{$key}) ||
			(defined($hashDestination->{$key}) && $clear)) {
			$hashDestination->{$key} = {};
		}

		$subEntriesCpt = scalar(keys(%{$hashDestination->{$key}}));
		foreach my $entry ($entryXml->children('entry')) {
			$self->readEntry($entry, $hashDestination->{$key}, $sectionName, $subEntriesCpt++);
		}
	}
}


# Static methods

sub loadThisConfigurationFile {
	my ($configFilePath, $requiredVersion) = @_;
	# Creation of a new ConfigFileLoader object (XML parser)
	my $ConfigFileLoader_object = TriAnnot::Config::ConfigFileLoader->new('config_file' => $configFilePath, 'requiredVersion' => $requiredVersion);

	# Load TriAnnot global configuration from the selected XML configuration file
	$ConfigFileLoader_object->loadConfigurationFile();
}


sub isConfigValueDefined {
	my $valuePath = shift;
	my @chunks = split(/\|/, $valuePath);
	my $hashRef = \%TRIANNOT_CONF;
	while (scalar(@chunks) > 0) {
		if (!defined($hashRef->{$chunks[0]})) {
			return 0; #False
		}
		$hashRef = $hashRef->{shift(@chunks)};
	}

	return 1; #True
}


sub getConfigValue {
	my $valuePath = shift;
	my @chunks = split(/\|/, $valuePath);
	my $hashRef = \%TRIANNOT_CONF;
	while (scalar(@chunks) > 0) {
		if (!defined($hashRef->{$chunks[0]})) {
			$TriAnnot::Tools::Logger::logger->logdie("Trying to get a config value that is not defined: $valuePath");
		}
		if (scalar(@chunks) == 1) {
			last;
		}
		$hashRef = $hashRef->{shift(@chunks)};
	}
	my $retrievedValue = $hashRef->{shift(@chunks)};

	return $retrievedValue;
}


sub trim($) {
	my $string = shift;
	if (defined($string)) {
		$string =~ s/^\s+//;
		$string =~ s/\s+$//;
	}
	return $string;
}

1;
