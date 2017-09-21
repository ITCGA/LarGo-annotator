#!/usr/bin/env perl

package TriAnnot::Parsers::GeneMarkHMM;

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
use Bio::Tools::Genemark;
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
=head1 TriAnnot::Parsers::GeneMarkHMM - Methods
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
	my $cds_or_poly = $TRIANNOT_CONF{Global}->{'CDS_or_POLY'};
	my $nbGenes = 0;
	my @GMHMMres;

	# Display a warning message when the file to parse is missing
	if (! -e $self->{'fullFileToParsePath'}) {
		$logger->logwarn('GeneMarkHMM output file is missing (' . $self->{'fullFileToParsePath'} . '). Parse method will return an empty feature array.');
		return @GMHMMres;
	}

	# Creation of a Bioperl parser for GeneMarkHMM results
	my $genemark = Bio::Tools::Genemark->new(-file => $self->{'fullFileToParsePath'});

	# If we use GeneMarkHMM3 (i.e we use a matrix *.mod), we force analysis_method to GeneMark.hmm to avoid an undefined value warning in Bioperl parser
	if ($TRIANNOT_CONF{PATHS}->{matrices}->{$self->{programName}}->{$self->{'matrix'}}->{'path'} =~ /mod$/) {
		$genemark->analysis_method('GeneMark.hmm');
		$self->{version} = '3'
	}
	else {
		$self->{version} = '2'
	}

	# Parses the result file ( browse each prediction results one by one )
	while (my $gene = $genemark->next_prediction()){  # $gene <=> Bio::Tools::Prediction::Gene

		# Initializations
		my ($geneTag, $rnaTag) = ({}, {});
		my $nbExons = 0;
		my @pepFeats = ();

		# Gets all exons for the current gene prediction
		my @exons = $gene->exons();

		# Increases and formats the number of genes
		$nbGenes++;
		$nbGenes = sprintf("%04d", $nbGenes);

		# Get gene start and end
		my $gene_start = $gene->start();
		my $gene_end = $gene->end();

		# Creates the gene feature
		$geneTag->{'Name'} = $self->getSourceTag() . '_' . $gene_start . '_' . $gene_end . '_Gene_' . $nbGenes;
		$geneTag->{'ID'} = $self->{'sequenceName'} . '_' . $geneTag->{'Name'};

		my $geneFeat = Bio::SeqFeature::Generic->new(
								-seq_id      => $self->{'sequenceName'},
								-source_tag  => $self->getSourceTag(),
								-primary_tag => 'gene',
								-start       => $gene_start,
								-end         => $gene_end,
								-strand      => $gene->strand(),
								-frame       => $gene->frame(),
								-tag         => $geneTag
								 );

		push(@GMHMMres, $geneFeat);

		# Creates the mRNA feature (GMHMM doesn't provides informations on mRNA so we create a fictive mRNA feature feature with valid coordinates)
		my ($Real_mRNA_start, $Real_mRNA_end) = ($exons[0]->start(), $exons[$#exons]->end());

		$rnaTag->{'Name'} = $self->getSourceTag() . '_' . $Real_mRNA_start . '_' . $Real_mRNA_end . '_Gene_' . $nbGenes . '_mRNA_0001';
		$rnaTag->{'ID'} = $self->{'sequenceName'} . '_' . $rnaTag->{'Name'};
		$rnaTag->{'Parent'} = $geneTag->{'ID'};

		my $rnaFeat = Bio::SeqFeature::Generic->new(
								-seq_id      => $self->{'sequenceName'},
							    -source_tag  => $self->getSourceTag(),
							    -primary_tag => 'mRNA',
							    -start       => $Real_mRNA_start,
							    -end         => $Real_mRNA_end,
							    -strand      => $gene->strand(),
							    -frame       => $gene->frame(),
							    -tag         => $rnaTag
								);

		push(@GMHMMres, $rnaFeat);

		# Create all real exon feature and virtual CDS/polypeptide features
		foreach my $exon (@exons){ # $exon <=> Bio::Tools::Prediction::Exon

			# Initializations
		    my ($exonTag, $polyTag) = ({}, {});

			# Get exon start, end and type
			my $exon_start = $exon->start();
			my $exon_end = $exon->end();
			my $exon_type = $exon->primary_tag();

			# Note: GMHMM Bioperl parser (method primary_tag) return "exon" instead of "single" for an exon of a single exon gene => we correct it
			if ($exon_type =~ /Exon/) {
				$exon_type = 'Single';
			}

			# Increase and format the number of genes
			$nbExons++;
			$nbExons = sprintf("%04d", $nbExons);

			# Create the Exon feature
			$exonTag->{'Name'} = $self->getSourceTag() . '_' . $exon_start . '_' . $exon_end . '_Gene_' . $nbGenes . '_mRNA_0001_exon_' . $nbExons;
		    $exonTag->{'ID'} = $self->{'sequenceName'} . '_' . $exonTag->{'Name'};
		    $exonTag->{'Parent'} = $rnaTag->{'ID'};
		    $exonTag->{'exon_type'} = $exon_type;

			# Get Ontology term ( It will be used in Eugene module (Sensor.AnnotaStruct and Sensor.EST))
			$exonTag->{'Ontology_term'} = $self->getSOTermId('exon', $exon_type);

		    my $exonFeat = Bio::SeqFeature::Generic->new(
								-seq_id      => $self->{'sequenceName'},
								-source_tag  => $self->getSourceTag(),
								-primary_tag => 'exon',
								-start       => $exon_start,
								-end         => $exon_end,
								-strand      => $exon->strand(),
								-frame       => $exon->frame(),
								-tag         => $exonTag
								);

		    push(@GMHMMres, $exonFeat);

			# Create the Hypothetical CDS/polypeptide feature
			$polyTag->{'Name'} = $self->getSourceTag() . '_' . $exon_start . '_' . $exon_end . '_Gene_' . $nbGenes . '_mRNA_0001_' . $cds_or_poly . '_' . $nbExons;
			$polyTag->{'ID'} = $self->{'sequenceName'} . '_' . $polyTag->{'Name'};
			$polyTag->{'Derives_from'} = $rnaTag->{'ID'};
			$polyTag->{$cds_or_poly . '_type'} = $exon_type;

			# Get Ontology term ( It will be used in Eugene module (Sensor.AnnotaStruct and Sensor.EST))
			$polyTag->{'Ontology_term'} = $self->getSOTermId($cds_or_poly, $exon_type);

			my $pepFeat = Bio::SeqFeature::Generic->new(
								-seq_id      => $self->{'sequenceName'},
								-source_tag  => $self->getSourceTag(),
								-primary_tag => $cds_or_poly,
								-start       => $exon_start,
								-end         => $exon_end,
								-strand      => $exon->strand(),
								-tag         => $polyTag
								);

			push(@pepFeats, $pepFeat);
		}

		# Adds all CDS/polypeptide features after all the exons features for the current gene
		push(@GMHMMres, @pepFeats);
	}

	# Closing of the file opened by the parser
	$genemark->close();

	return @GMHMMres;
}

sub getSoftList {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my @Soft_list = ();

	push(@Soft_list, $self->{'programName'} . '(' . $TRIANNOT_CONF{PATHS}->{soft}->{$self->{'programName'} . $self->{version}}->{'version'} . ')');

	return \@Soft_list;
}
1;
