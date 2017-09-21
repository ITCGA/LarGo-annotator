#!/usr/bin/env perl

package TriAnnot::Parsers::Parsers;

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
use File::Path;
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
use TriAnnot::Tools::EMBL_writer;


## Inherits
our @ISA = qw(TriAnnot::Component);
#################
# Constructor
#################

sub new {
	my ($class, $attrs_ref) = @_;

	# Check the type of the second argument
	if (ref($attrs_ref) ne 'HASH') {
		$logger->logdie('Error: Parsers.pm constructor is expecting a hash reference as second argument !');
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

	if (!defined($attrs_ref->{fileToParse})) {
		$logger->logdie('Error: No fileToParse passed to ' . $class . ' constructor');
	}
	if (!-e $attrs_ref->{fileToParse}) {
		$logger->logdie('Error: fileToParse passed to ' . $class . ' constructor does not exists: ' . $attrs_ref->{fileToParse});
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
		fullFileToParsePath   => Cwd::realpath($attrs_ref->{'fileToParse'}),
		allowMultiFasta       => 'no',
		allFeatures           => []
	};
	$self->{fileToParse} = basename($self->{'fullFileToParsePath'});

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
		$self->{'tmpFolder'} = sprintf("%03s", $self->{'programID'}) . '_' . $self->{'programName'} . '_parsing';
	}

	# Define the parameters that stores the full path of the GFF and EMBL files
	$self->{gffFileFullPath} = $self->{directory} . '/' . $TRIANNOT_CONF{DIRNAME}->{'GFF_files'} . '/' . $self->{'gffFile'};
	$self->{emblFileFullPath} = $self->{directory} . '/' . $TRIANNOT_CONF{DIRNAME}->{'EMBL_files'} . '/' . $self->{'emblFile'};
}


#####################
# Parsing related methods
#####################

sub _parse {

	# Recovers parameters
	my $self = shift;

	$logger->logdie('Error: The _parse method need to be implemented in module ' . ref($self));
}

sub _beforeParsing {

	# Recovers parameters
	my $self = shift;

	# Temporary execution folder creation
	if (!-e $self->{'tmpFolder'}) {
		mkdir($self->{'tmpFolder'}, 0755);
	}

	# Jump to the new temporary folder
	chdir($self->{'tmpFolder'});
}

sub parse {

	# Recovers parameters
	my $self = shift;

	$logger->info('');
	$logger->info('Beginning of the parsing procedure at ' . localtime());
	$logger->info('');

	$logger->info('Module used: ' . ref($self));
	$logger->info('The selected file to parse is: ' . $self->{'fileToParse'});

	# Benchmark initialization
	my $timeStart = Benchmark->new();

	# Main parsing process
	$self->_beforeParsing();
	$self->{allFeatures} = [$self->_parse()];
	$self->_afterParsing();

	$logger->debug('');
	$logger->debug('Number of BioPerl features: ' . scalar(@{$self->{allFeatures}}));

	$logger->info('');
	$logger->info('End of the parsing procedure at ' . localtime());
	$logger->info('');

	# Collect benchmark information
	my $timeEnd = Benchmark->new();
	my $timeDiff = Benchmark::timediff($timeEnd, $timeStart);
	$self->{'benchmark'}->{'parsing'} = $timeDiff;
}

sub _afterParsing {

	# Recovers parameters
	my $self = shift;

	# Management of generated files that will be used in other step of the pipeline
	$self->_generatedFilesManagement();

	# Go back to parent folder
	chdir('..');
}


###############
#  All Get methods
###############

sub getSoftList {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my @Soft_list = ();

	# General case: one software used and a version clearly defined in the global configuration file
	push(@Soft_list, $self->{'programName'} . '(' . $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'}}->{'version'} . ')');

	return \@Soft_list;
}

sub getDbList {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my @Db_list = ();

	# General case: one databank used and a version clearly defined in the global configuration file
	if (defined($self->{'database'})) {
		if (defined($TRIANNOT_CONF{PATHS}->{db}->{$self->{'database'}})) {
			push(@Db_list, $self->{'database'} . '(' . $TRIANNOT_CONF{PATHS}->{db}->{$self->{'database'}}->{'version'} . ')');
		} else {
			push(@Db_list, $self->{'database'} . '(Unknown_version)');
		}
	}

	return \@Db_list;
}

# Recover the Sequence Ontology identifier of some features types (Gene prediction programs only) - Use ine Eugene module (Sensor.AnnotaStruct, Sensor.EST, etc.)
# For more information about the Sequence Ontology, please visit: http://www.sequenceontology.org/browser/obob.cgi
sub getSOTermId {

	# Recovers parameters
	my ($class, $primary_tag, $sub_type) = @_;

	# Get the correct SO term ID depending on the feature type
	if (defined($sub_type)) {
		if ($primary_tag eq 'exon') {
			switch ($sub_type) {
				case /external/i	{ return "SO:0000198"; } # non_coding_exon
				case /internal/i	{ return "SO:0000004"; } # Interior_coding_exon
				case /initial/i		{ return "SO:0000200"; } # Five_prime_coding_exon
				case /terminal/i	{ return "SO:0000202"; } # Three_prime_coding_exon
				else	            { return "SO:0000147"; } # General Exon
			}
		} elsif ($primary_tag eq 'CDS') {
			switch ($sub_type) {
				case /internal/i	{ return "SO:0001215"; } # coding_region_of_exon
				case /initial/i		{ return "SO:0000196"; } # Five_prime_coding_exon_region
				case /terminal/i	{ return "SO:0000197"; } # Three_prime_coding_exon_region
				else                { return "SO:0000316"; } # General CDS
			}
		} elsif ($primary_tag eq 'polypeptide') {
			switch ($sub_type) {
				case /internal/i	{ return "SO:0001215"; } # coding_region_of_exon
				case /initial/i		{ return "SO:0000196"; } # Five_prime_coding_exon_region
				case /terminal/i	{ return "SO:0000197"; } # Three_prime_coding_exon_region
				else                { return "SO:0000104"; } # General polypeptide
			}
		} elsif ($primary_tag =~ 'intron') {
			switch ($sub_type) {
				case /internal/i	{ return "SO:0000191"; } # Interior_intron
				case /initial/i		{ return "SO:0000190"; } # Five_prime_intron
				case /terminal/i	{ return "SO:0000192"; } # Three_prime_intron
				else	            { return "SO:0000188"; } # General intron
			}
		} else {
			return "SO:0000001"; # Region
		}

	} else {
		switch ($primary_tag) {
			case 'gene' { return "SO:0000704"; }
			case 'mRNA' { return "SO:0000234"; }
			case 'start_codon' { return "SO:0000318"; }
			case 'stop_codon' { return "SO:0000319"; }
			case 'five_prime_UTR' {	return "SO:0000204"; }
			case 'three_prime_UTR' { return "SO:0000205"; }
			case 'acceptor' { return "SO:0000164"; }
			case 'donor' { return "SO:0000163";	}
			case 'transcription_start_site' { return "SO:0000315"; }
			case 'transcription_end_site' { return "SO:0000616"; }
			case 'insertion_site' {	return "SO:0000366"; }
			case 'deletion_junction' { return "SO:0000687"; }
			case 'ncRNA' { return "SO:0000655"; }
			case 'tRNA' { return "SO:0000253"; }
			case 'rRNA' { return "SO:0000252"; }
			case 'ORF' { return "SO:0000236"; }
			case 'repeat_region' { return "SO:0000657"; }
			case 'nested_repeat' { return "SO:0001649"; }
			case 'repeat_fragment' { return "SO:0001050"; }
			else { return "SO:0000001"; } # Region
		}
	}
}

sub getGenericFeatureOrder {

	# Recovers parameters
	my ($self, $Strand) = @_;

	# Initializations
	my ($UTR_1, $UTR_2) = ('', '');

	# Deal with strand
	if ($Strand == -1) {
		$UTR_1 = 'three_prime_UTR';
		$UTR_2 = 'five_prime_UTR';
	} else {
		$UTR_1 = 'five_prime_UTR';
		$UTR_2 = 'three_prime_UTR';
	}

	# Build list
	my @Feature_order = ('gene', 'mRNA');

	foreach my $key (sort {$a <=> $b} keys %{$TRIANNOT_CONF{SubFeaturesOrder}}) {
		my $Feature_name = $TRIANNOT_CONF{SubFeaturesOrder}->{$key};

		if (($Feature_name eq 'CDS' && $TRIANNOT_CONF{Global}->{'CDS_or_POLY'} eq 'CDS') || ($Feature_name eq 'polypeptide' && $TRIANNOT_CONF{Global}->{'CDS_or_POLY'} eq 'polypeptide')) {
			push(@Feature_order, ($UTR_1, $Feature_name, $UTR_2));
		} else {
			push(@Feature_order, $Feature_name);
		}
	}

	return \@Feature_order;
}


sub getSourceTag {
	my $self = shift;

	if (!defined($self->{sourceTag})) {
		$logger->logdie('Error: No sourceTag defined for task ' . $self->{programID});
	}

	if (defined($self->{_sourceTagParsed})) {
		return $self->{sourceTag};
	}

	my $sourceTag = $self->{sourceTag};
	my $pattern1 = '(\{(.+?)\})';
	while ($sourceTag =~ m/$pattern1/g) {
		if (!defined($self->{$2})) {
			$logger->logdie("Error: Invalid sourceTag pattern for task " . $self->{programID});
		}
		else {
			my $newValue = $self->{$2};
			$sourceTag =~ s/\Q$1/$newValue/g;
		}
	}

	$self->{sourceTag} = $sourceTag;
	$self->{_sourceTagParsed} = 1;
	return $self->{sourceTag};
}

sub fromFeaturesToFiles {
	# Recovers parameters
	my $self = shift;
	my $outputFormat = shift;

	# Output files writing
	if (scalar(@{$self->{allFeatures}}) > 0) {
		if ($outputFormat eq 'gff' || $outputFormat eq 'both') {
			# Write all Bio::SeqFeature::Generic features into a GFF3 File
			$self->_writeGFF3File();
			if (-e $self->{'gffFileFullPath'} && -s $self->{'gffFileFullPath'}) {
				$logger->info("\tCreation of file " . $self->{'gffFile'} . " => Done !");
			} else {
				$logger->info("\tError: creation of the file " . $self->{'gffFileFullPath'} . " failed !");
			}
		}

		if ($outputFormat eq 'embl' || $outputFormat eq 'both') {
			# Write all Bio::SeqFeature::Generic features into an EMBL File
			$self->_writeEMBLFile();
			if (-e $self->{'emblFileFullPath'} && -s $self->{'emblFileFullPath'}) {
				$logger->info("\tCreation of file " . $self->{'emblFile'} . " => Done !");
			} else {
				$logger->info("\tError: creation of the file " . $self->{'emblFileFullPath'} . " failed !");
			}
		}
	} else {
		# Empty files creation
		if ($outputFormat eq 'gff' || $outputFormat eq 'both') {
			$logger->info('There are no ' . ucfirst($self->{'programName'}) . ' results, creation of an empty GFF3 file: ' . $self->{'gffFile'});
			open(EMPTY_GFF, '>' . $self->{'gffFileFullPath'}) or $logger->logdie('Error: Can not create/open file ' . $self->{'gffFileFullPath'});
			close(EMPTY_GFF);
		}
		if ($outputFormat eq 'embl' || $outputFormat eq 'both') {
			$logger->info('There are no ' . ucfirst($self->{'programName'}) . ' results, creation of an empty EMBL file: ' . $self->{'emblFile'});
			open(EMPTY_EMBL, '>' . $self->{'emblFileFullPath'}) or $logger->logdie('Error: Can not create/open file ' . $self->{'emblFileFullPath'});
			close(EMPTY_EMBL);
		}
	}
}

sub _writeGFF3File {
	my $self = shift;

	# Log
	$logger->info('');
	$logger->info('All ' . ucfirst($self->{'programName'}) . ' results will be written in the following GFF3 file: ' . $self->{'gffFile'});

	# Creation of a new GFF writer object
	my $gff_writer_object = Bio::Tools::GFF->new(-fh => \*GFF3, -gff_version => 3);

	# Creation of the first line of the GFF (with databank and software versions)
	my $Origin = $self->_buildGFF3FirstLine();

	# Write all features into the GFF3 file
	open(GFF3, '>' . $self->{'gffFileFullPath'}) or $logger->logdie('Error: Cannot create/open file: ' . $self->{'gffFileFullPath'});

	$gff_writer_object->write_feature($Origin);
	foreach my $current_feature (@{$self->{allFeatures}}) {
		$gff_writer_object->write_feature($current_feature);
	}

	close(GFF3);
}

sub _writeEMBLFile {
	# Recovers parameters
	my $self = shift;

	# Initializations
	my $emblFormatDescription = undef();

	# Log
	$logger->info('');
	$logger->info('All ' . ucfirst($self->{'programName'}) . ' results will be written in the following EMBL file: ' . $self->{'emblFile'});

	# Extract the description of the selected EMBL Format from the configuration (except for the default empty format "keepAllFeatures")
	if (defined($self->{'EMBLFormat'}) && $self->{'EMBLFormat'} ne "keepAllFeatures") {
		my $listOfValuesPath = TriAnnot::Config::ConfigFileLoader::getConfigValue($self->{'programName'} . '|parserParameters|EMBLFormat|listOfValuesPath');
		$emblFormatDescription = TriAnnot::Config::ConfigFileLoader::getConfigValue($listOfValuesPath . '|' . $self->{'EMBLFormat'});
	}

	# Creation of a new EMBL_writer object
	my $EMBL_writer_object = TriAnnot::Tools::EMBL_writer->new('emblFormatDescription' => $emblFormatDescription, 'Parser_object' => $self, 'sequence' => $self->{'fullSequencePath'}, 'All_features_ref'   => $self->{'allFeatures'} );

	# Check parameters before the format conversion
	$EMBL_writer_object->checkParameters();

	# Format conversion
	$EMBL_writer_object->fromFeaturesToFile();

	return 0; # success
}


sub _buildGFF3FirstLine {
	my $self = shift;

	# Creation of the first basic feature
	my $Origin_attribute = {};

	# Define the basic feature attributes
	$Origin_attribute->{'ID'} = $self->{'sequenceName'};
	$Origin_attribute->{'Name'} = $Origin_attribute->{'ID'};

	# Define custom attributes
	if (defined($self->{'annotation_type'})) {
		$Origin_attribute->{'annotation_type'} = $self->{'annotation_type'};
	}

	$Origin_attribute->{'triannot_version'} = $TRIANNOT_CONF{VERSION};

	# Create the feature itself
	my $Origin = Bio::SeqFeature::Generic->new(
						 -seq_id      => $self->{'sequenceName'},
						 -source_tag  => 'TriAnnotPipeline',
						 -primary_tag => $TRIANNOT_CONF{Global}->{'Main_feature_type'},
						 -start       => 1,
						 -end         => $self->{'sequenceLength'},
						 -tag         => $Origin_attribute
						);

	# Deal with the list of software used
	my $Ref_to_Soft_list = $self->getSoftList();

	foreach my $software_used (@{$Ref_to_Soft_list}) {
		$Origin->add_tag_value('software_used', $software_used);
	}

	# Deal with the list of databank used
	my $Ref_to_Db_list = $self->getDbList();

	foreach my $databank_used (@{$Ref_to_Db_list}) {
		$Origin->add_tag_value('databank_used', $databank_used);
	}

	# Add Sequence Ontology
	$Origin->add_tag_value('Ontology_term', $self->getSOTermId('region'));

	return $Origin;

}

1;
