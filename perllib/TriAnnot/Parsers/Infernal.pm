#!/usr/bin/env perl

package TriAnnot::Parsers::Infernal;

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

## BioPerl modules
use Bio::SeqFeature::Generic;

## TriAnnot modules
use TriAnnot::Parsers::Parsers;
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Parsers::Parsers);


##################################################
## Methods
##################################################
=head1 TriAnnot::Parsers::Infernal - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class
	my $self = $class->SUPER::new(\%attrs);

	bless $self => $class;

	return $self;
}


##################
# Method parse() #
##################

sub _parse {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my $resultCounter = 0;
	my @InfernalFeatures = ();

	# Display a warning message when the file to parse is missing
	if (! -e $self->{'fullFileToParsePath'}) {
		$logger->logwarn('Infernal output file is missing (' . $self->{'fullFileToParsePath'} . '). Parse method will return an empty feature array.');
		return @InfernalFeatures;
	}

	# Open GMAP brut output file
	open(INFERNAL_OUT, '<' . $self->{'fullFileToParsePath'}) or $logger->logdie('Error: Cannot open/read file: ' . $self->{'fullFileToParsePath'});

	while(my $rawLine = <INFERNAL_OUT>){
		# If the current line ins't a comment line we analyse it
		if ($rawLine =~ /^[^#]/) {
			# Initialization and incrementation
			my $newFeatureTags = {};
			$resultCounter++;

			# Eliminate redundant spaces and the carriage return
			chomp $rawLine;
			$rawLine =~ tr/ //s;

			my ($targetName, $targetAcc, $queryName, $queryAcc, $model, $targetFrom, $targetTo, $queryFrom, $queryTo, $strand, $truncated, $pass, $gcPercent, $bias, $score, $evalue, $inc, $desc) = split (' ', $rawLine, 18);

			# Creation of the new Feature
			$newFeatureTags->{'Name'} = $self->getSourceTag() . '_' . $queryFrom . '_' . $queryTo . '_ncRNA_' . $resultCounter;
			$newFeatureTags->{'ID'} = $self->{'sequenceName'} . '_' . $newFeatureTags->{'Name'};

			$newFeatureTags->{'Target'} = [$targetAcc, $targetFrom, $targetTo]; # Target Tag must be a reference to a table (anonymous or not)
			$newFeatureTags->{'Note'} = $targetName . ' - ' . $desc;
			$newFeatureTags->{'evalue'} = $evalue;
			$newFeatureTags->{'target_gc_percent'} = $gcPercent;
			$newFeatureTags->{'truncated_hit'} = $truncated;

			my $newFeature = Bio::SeqFeature::Generic->new(
								-seq_id      => $self->{'sequenceName'},
								-source_tag  => $self->getSourceTag(),
								-primary_tag => 'ncRNA',
								-start       => $queryFrom,
								-end         => $queryTo,
								-strand      => $strand,
								-score       => $score,
								-tag         => $newFeatureTags
								);

			push(@InfernalFeatures, $newFeature);
		}
	}

	close(INFERNAL_OUT);

	return @InfernalFeatures;
}

1;
