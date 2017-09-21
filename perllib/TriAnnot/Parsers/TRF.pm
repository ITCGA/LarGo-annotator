#!/usr/bin/env perl

package TriAnnot::Parsers::TRF;

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

# BioPerl modules
use Bio::Tools::TandemRepeatsFinder;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Parsers::Parsers;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Parsers::Parsers);

##################################################
## Methods
##################################################
=head1 TriAnnot::Parsers::TRF - Methods
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
	my @TRFfeatures;
	my $nbTRepeat = 0;

	# Display a warning message when the file to parse is missing
	if (! -e $self->{'fullFileToParsePath'}) {
		$logger->logwarn('TRF output file is missing (' . $self->{'fullFileToParsePath'} . '). Parse method will return an empty feature array.');
		return @TRFfeatures;
	}

	# Creation of a parser of TRF results
	my $trf = Bio::Tools::TandemRepeatsFinder->new(-file => $self->{'fullFileToParsePath'});

	# Parses the result file
	while(my $result = $trf->next_result()){

		# Increases the number of tandem repeats
		$nbTRepeat++;
		$nbTRepeat = sprintf("%04d", $nbTRepeat);

		# Initializations
		my @number_of_repeat = $result->get_tag_values('copy_number');
		my @pattern = $result->get_tag_values('consensus_sequence');
		my @size = $result->get_tag_values('consensus_size');
		my $result_start = $result->start();
		my $result_end = $result->end();

		# Ninth column build
		my $repeatTag = {};

		$repeatTag->{'Name'} = 'TRF_' . $result_start . '_' . $result_end . '_Tandem_Repeat_' . $nbTRepeat;
		$repeatTag->{'ID'} = $self->{'sequenceName'} . '_' . $repeatTag->{'Name'};
		$repeatTag->{'motif_sequence'} = $pattern[0];
		$repeatTag->{'motif_size'} = $size[0];
		$repeatTag->{'number_of_repeat'} = $number_of_repeat[0];

		# Creation of a real match_part feature
		my $repeatFeat = Bio::SeqFeature::Generic->new(
									-seq_id      => $self->{'sequenceName'},
									-source_tag  => $self->getSourceTag(),
									-primary_tag => 'tandem_repeat',
									-start       => $result_start,
									-end         => $result_end,
									-tag         => $repeatTag
									);

		# Storage of the new feature in a table (It will be used to build GFF files)
		push (@TRFfeatures, $repeatFeat);
	}

	# Closing of the file opened by the parser
	$trf->close();

	return @TRFfeatures;
}


1;
