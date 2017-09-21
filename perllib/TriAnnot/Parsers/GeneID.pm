#!/usr/bin/env perl

package TriAnnot::Parsers::GeneID;

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
use Bio::Tools::Geneid;
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
=head1 TriAnnot::Parsers::GeneID - Methods
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
	my @GeneIDres = ();

	# Display a warning message when the file to parse is missing
	if (! -e $self->{'fullFileToParsePath'}) {
		$logger->logwarn('GeneID output file is missing (' . $self->{'fullFileToParsePath'} . '). Parse method will return an empty feature array.');
		return @GeneIDres;
	}

	# Creation of a Bioperl parser for GeneID results
	my $gid = Bio::Tools::Geneid->new(-file => $self->{'fullFileToParsePath'});

	# Parses the result file ( browse each prediction results one by one )
	while (my $gene = $gid->next_prediction()) {

		# Initializations
		my ($geneTag, $rnaTag) = ({}, {});
		my $nbExons = 0;
		my @pepFeats = ();

		# Gets all exons for the current gene prediction
		my @exons = $gene->exons();

		# Increases and formats the number of genes
		$nbGenes++;
		$nbGenes = sprintf("%04d", $nbGenes);

		# Get gene start and stop
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
								-strand      => $exons[0]->strand(),
								-tag         => $geneTag
								 );

		push(@GeneIDres, $geneFeat); # Adds the new gene feature to feature table

		# Creates the mRNA feature (GeneID doesn't provides informations on mRNA so we create a fictive mRNA feature with valid coordinates)
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
								-strand      => $exons[0]->strand(),
							    -tag         => $rnaTag);

		push(@GeneIDres, $rnaFeat);

		# Create all real exon feature and virtual CDS/polypeptide features
		foreach my $exon (@exons) {

			# Get exon start, end and type
			my $exon_start = $exon->start();
			my $exon_end = $exon->end();
			my $exon_type = $exon->primary_tag();

			# Increases the number of exon
			$nbExons++;
			$nbExons = sprintf("%04d", $nbExons);

			# Creates the Exon feature
			my $exonTag = {};
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
									-score       => $exon->score(),
									-strand      => $exon->strand(),
									-frame       => $exon->frame(),
									-tag         => $exonTag
									);

			push(@GeneIDres, $exonFeat);

			# Creates the Hypothetical polypeptide/CDS feature - take this informations with caution
			my $pepTag = {};
			$pepTag->{'Name'} = $self->getSourceTag() . '_' . $exon_start . '_' . $exon_end . '_Gene_' . $nbGenes . '_mRNA_0001_' . $cds_or_poly . '_' . $nbExons;
			$pepTag->{'ID'} = $self->{'sequenceName'} . '_' . $pepTag->{'Name'};
			$pepTag->{'Derives_from'} = $rnaTag->{'ID'};
			$pepTag->{$cds_or_poly . '_type'} = $exon_type;

			# Get Ontology term ( It will be used in Eugene module (Sensor.AnnotaStruct and Sensor.EST))
			$pepTag->{'Ontology_term'} = $self->getSOTermId($cds_or_poly, $exon_type);

			my $pepFeat = Bio::SeqFeature::Generic->new(
								-seq_id      => $self->{'sequenceName'},
								-source_tag  => $self->getSourceTag(),
								-primary_tag => $cds_or_poly,
								-start       => $exon_start,
								-end         => $exon_end,
								-strand      => $exon->strand(),
								-tag         => $pepTag
								);

			push(@pepFeats, $pepFeat);
		}

		# Adds all CDS/polypeptide features after all the exons features for the current gene
		push(@GeneIDres,@pepFeats);
	}

	# Closing of the file opened by the parser
	$gid->close();

	return @GeneIDres;
}

1;
