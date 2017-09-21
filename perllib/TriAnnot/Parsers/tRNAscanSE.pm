#!/usr/bin/env perl

package TriAnnot::Parsers::tRNAscanSE;

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

## BioPerl modules
use Bio::SeqFeature::Generic;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Parsers::Parsers;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Parsers::Parsers);

##################################################
## Methods
##################################################
=head1 TriAnnot::Parsers::tRNAscanSE - Methods
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
	my @tRNA_list = ();
	my ($nb_tRNA, $strand) = (0, 1);

	if (! -e $self->{'fullFileToParsePath'}) {
		$logger->logwarn('tRNAscan-SE output file is missing (' . $self->{'fullFileToParsePath'} . '). Parse method will return an empty feature array.');
		return @tRNA_list;
	}

	# Parsing of the result file
	open(TRNA_res, '<' . $self->{'fullFileToParsePath'}) || $logger->logdie('Error: Cannot create/open file: ' . $self->{'fullFileToParsePath'});

	while(<TRNA_res>){

		# Increases the number of hit for the current result
		$nb_tRNA++;
		$nb_tRNA = sprintf("%04d", $nb_tRNA);

		# Splitting of the current line
		my ($seqid, $tRNAnum, $start, $end, $type, $codon, $intron_start, $intron_end, $score) = split(/\s+/, $_);
		my $Amino_name = defined($TRIANNOT_CONF{AminoNames}->{$type})?$TRIANNOT_CONF{AminoNames}->{$type}:$type;

		# Reverse tRNA start and stop if needed
	    if( $start > $end ) { ($start, $end, $strand) = ($end, $start, -1); }

		# Creation of the tRNA feature Tag
		my $tRNA_Tag = {};

		$tRNA_Tag->{'Name'} = $self->getSourceTag() . '_' . $start . '_' . $end . '_tRNA_' . $nb_tRNA;
		$tRNA_Tag->{'ID'} = $self->{'sequenceName'} . '_' . $tRNA_Tag->{'Name'};

		if ($codon eq '???') {
			$tRNA_Tag->{'anticodon'} = 'Unknow anticodon';
		} else {
			$tRNA_Tag->{'anticodon'} = $codon;
		}

		$tRNA_Tag->{'Note'} = $Amino_name;
		if($strand == -1) {
			$tRNA_Tag->{'Note'} = '(Reverse) ' . $Amino_name;
		}

		if ($intron_start != 0 && $intron_end != 0) {
			# Exchange intron start and end if needed
			if( $intron_start > $intron_end ){ ($intron_start, $intron_end) = ($intron_end, $intron_start); }
			$tRNA_Tag->{'intron_start'}= $intron_start;
			$tRNA_Tag->{'intron_end'}= $intron_end;
		}

		# Creation of the tRNA feature
		my $tRNA_Feat= Bio::SeqFeature::Generic->new(
								-seq_id      => $self->{'sequenceName'},
								-source_tag  => $self->getSourceTag(),
								-primary_tag => 'tRNA',
								-start       => $start,
								-end         => $end,
								-score       => $score,
								-strand      => $strand,
								-tag         => $tRNA_Tag
							   );

		# Storage of the new tRNA feature in the final table (It will be used to build GFF files)
		push(@tRNA_list, $tRNA_Feat);
	}

	return @tRNA_list;
}

1;
