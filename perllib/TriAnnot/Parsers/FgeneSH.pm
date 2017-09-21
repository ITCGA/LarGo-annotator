#!/usr/bin/env perl

package TriAnnot::Parsers::FgeneSH;

##################################################
## Documentation POD
##################################################

##################################################
## Modules
##################################################
## Perl modules
use strict;
use warnings;

## BioPerl modules
use Bio::Tools::Fgenesh;

## TriAnnot modules
use TriAnnot::Parsers::Parsers;
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Parsers::Parsers);

##################################################
## Methods
##################################################
=head1 TriAnnot::Parsers::FgeneSH - Methods
=cut


#################
# Constructor
#################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class
	my $self = $class->SUPER::new(\%attrs);
	$self->{allFeats} = [];
	$self->{nbGenes} = 0;
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

	# Display a warning message when the file to parse is missing
	if (! -e $self->{'fullFileToParsePath'}) {
		$logger->logwarn('FGenesh output file is missing (' . $self->{'fullFileToParsePath'} . '). Parse method will return an empty feature array.');
		return @{$self->{allFeats}};
	}
	
	### Modification made by P. Leroy on April 19th, 2016 to overcome the problem of new FGeneSH output file
	my $tmp = $self->{'fullFileToParsePath'} . 'tmp';
	system ("cp $self->{'fullFileToParsePath'} $tmp");
	unlink $self->{'fullFileToParsePath'};
	$logger->logwarn('Modify FGeneSH output file (' . $tmp . '). ');

	open (OUT, "> $self->{'fullFileToParsePath'}") || $logger->logwarn('not possible to create ' . $self->{'fullFileToParsePath'} . "\n"); 
	open (FILE, $tmp) || $logger->logwarn('no file ' . $tmp . "\n");
		while (my $line = <FILE>) {
			chomp $line;
			if ($line =~ /^\/\/$/) {
				next;
			} else {
				print OUT $line . "\n";
			}
		}
	close FILE;	
	close OUT;
	unlink $tmp;
	#############################################################################################################
		
	my $fgenesh = Bio::Tools::Fgenesh->new(-file => $self->{'fullFileToParsePath'});

	# Read FGenesh results
	while (my $gene = $fgenesh->next_prediction()) {  # $gene <=> Bio::Tools::Prediction::Gene

		# Initializations
		my ($geneTag, $rnaTag) = ({}, {});
		my $nbExons = 0;
		my @pepFeats = ();
		my $firstUtrFeat = undef;
		my $secondUtrFeat = undef;

		# Gets all exons for the current gene prediction
		my @exons = $gene->exons();

		# Increases and formats the number of genes
		$self->{nbGenes} = $self->{nbGenes} + 1;
		my $nbGenes = sprintf("%04d", $self->{nbGenes});

		# Get gene start and end position
		my $gene_start = $gene->start();
		my $gene_end = $gene->end();

		# Creation of the Gene Feature
		$geneTag->{'Name'} = $self->getSourceTag() . '_' . $gene_start . '_' . $gene_end . '_Gene_' . $nbGenes;
		$geneTag->{'ID'} = $self->{'sequenceName'} . '_' . $geneTag->{'Name'};

		my $geneFeat = Bio::SeqFeature::Generic->new(
								-seq_id      => $self->{'sequenceName'},
								-source_tag  => $self->getSourceTag(),
								-primary_tag => 'gene',
								-start       => $gene_start,
								-end         => $gene_end,
								-strand      => $gene->strand(),
								-tag         => $geneTag
								);

		push(@{$self->{allFeats}}, $geneFeat);

		# Creates the mRNA feature
		$rnaTag->{'Name'} = $self->getSourceTag() . '_' . $gene_start . '_' . $gene_end . '_Gene_' . $nbGenes . '_mRNA_0001';
		$rnaTag->{'ID'} = $self->{'sequenceName'} . '_' . $rnaTag->{'Name'};
		$rnaTag->{'Parent'} = $geneTag->{'ID'};

		my $rnaFeat = Bio::SeqFeature::Generic->new(
									-seq_id      => $self->{'sequenceName'},
									-source_tag  => $self->getSourceTag(),
									-primary_tag => 'mRNA',
									-start       => $gene_start,
									-end         => $gene_end,
									-strand      => $gene->strand(),
									-tag         => $rnaTag
									);

		push(@{$self->{allFeats}}, $rnaFeat);

		# Create all real exon feature and virtual CDS/polypeptide features
		foreach my $exon (@exons) {

			# Get exon start, end and type
			my $exon_start= $exon->start();
			my $exon_end= $exon->end();
			my $exon_type = $exon->primary_tag();

			# Increases the number of exon feature
			$nbExons++;
			$nbExons = sprintf("%04d", $nbExons);

			# Creation of the exon feature according to strand (FgeneSH inverse start and end position when strand is negative)
			my $exonTag = {};
			$exonTag->{'Name'} = $self->getSourceTag() . '_' . $exon_start . '_' . $exon_end . '_Gene_' . $nbGenes . '_mRNA_0001_exon_' . $nbExons;
			$exonTag->{'ID'} = $self->{'sequenceName'} . '_' . $exonTag->{'Name'};
			$exonTag->{'Parent'} = $rnaTag->{'ID'};

			# Get Ontology term ( It will be used in Eugene module (Sensor.AnnotaStruct and Sensor.EST))
			if ($exon_type =~ /(Initial|Internal|Terminal|Single).*/i) {
				$exonTag->{'exon_type'} = $1;
				$exonTag->{'Ontology_term'} = $self->getSOTermId('exon', $1);
			}

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

			push(@{$self->{allFeats}}, $exonFeat);

			# Creation of the Hypothetical polypeptide/CDS feature - take this informations with caution
			my $pepTag = {};
			$pepTag->{'Name'} = $self->getSourceTag() . '_' . $exon_start . '_' . $exon_end . '_Gene_' . $nbGenes . '_mRNA_0001_' . $cds_or_poly . '_' . $nbExons;
			$pepTag->{'ID'} = $self->{'sequenceName'} . '_' . $pepTag->{'Name'};
			$pepTag->{'Derives_from'} = $rnaTag->{'ID'};

			# Get Ontology term ( It will be used in Eugene module (Sensor.AnnotaStruct and Sensor.EST))
			if ($exon_type =~ /(Initial|Internal|Terminal|Single).*/i) {
				$pepTag->{$cds_or_poly . '_type'} = $1;
				$pepTag->{'Ontology_term'} = $self->getSOTermId($cds_or_poly, $1);
			}

			my $pepFeat = Bio::SeqFeature::Generic->new(
								-seq_id      => $self->{'sequenceName'},
								-source_tag  => $self->getSourceTag(),
								-primary_tag => $cds_or_poly,
								-start       => $exon_start,
								-end         => $exon_end,
								-strand      => $exon->strand(),
								-tag         => $pepTag
								);

			if ($exon_type =~ /^(Initial|Single)/i && $exon->strand() == 1) {
				$firstUtrFeat = $self->_addFivePrimeUtrFeature($gene, $exon, $rnaTag->{'ID'});
			}
			if ($exon_type =~ /^(Terminal|Single)/i && $exon->strand() == -1) {
				$firstUtrFeat = $self->_addThreePrimeUtrFeature($gene, $exon, $rnaTag->{'ID'});
			}
			if ($exon_type =~ /^(Terminal|Single)/i && $exon->strand() == 1) {
				$secondUtrFeat = $self->_addThreePrimeUtrFeature($gene, $exon, $rnaTag->{'ID'});
			}
			if ($exon_type =~ /^(Initial|Single)/i && $exon->strand() == -1) {
				$secondUtrFeat = $self->_addFivePrimeUtrFeature($gene, $exon, $rnaTag->{'ID'});
			}
			push(@pepFeats, $pepFeat);
		}

		if (defined($firstUtrFeat)) {
			push(@{$self->{allFeats}}, $firstUtrFeat);
		}
		# Adds all CDS/polypeptide features after all the exons features for the current gene
		push(@{$self->{allFeats}}, @pepFeats);
		if (defined($secondUtrFeat)) {
			push(@{$self->{allFeats}}, $secondUtrFeat);
		}
	}

	$fgenesh->close();
	return @{$self->{allFeats}};
}

sub _addFivePrimeUtrFeature {
	my ($self, $gene, $exon, $parentId) = @_;

	if (defined($gene->promoters()) && scalar($gene->promoters()) > 0) {
		if (scalar($gene->promoters()) > 1) {
			die("FgeneSH predicted multiple 5'UTRs for the following gene and this case is not treated: " . $parentId . "\n");
		}
		my $utrStart;
		my $utrEnd;

		if ($gene->strand() == -1) {
			$utrStart = ($exon->end() + 1);
			$utrEnd = ($gene->promoters())[0]->start();
		}
		else {
			$utrStart = ($gene->promoters())[0]->start();
			$utrEnd = ($exon->start() - 1);
		}
		my $fivePrimeUtrTag = {};
		$fivePrimeUtrTag->{'Name'} = $self->getSourceTag() . '_' . $utrStart . '_' .  $utrEnd . '_Gene_' . sprintf("%04d", $self->{nbGenes}) . '_mRNA_0001_five_prime_UTR_0001';
		$fivePrimeUtrTag->{'ID'} = $self->{'sequenceName'} . '_' . $fivePrimeUtrTag->{'Name'};
		$fivePrimeUtrTag->{'Parent'} = $parentId;
		$fivePrimeUtrTag->{'Ontology_term'} = $self->getSOTermId('five_prime_UTR');
		my $fivePrimeUtrFeat = Bio::SeqFeature::Generic->new(
												-seq_id      => $self->{'sequenceName'},
												-source_tag  => $self->getSourceTag(),
												-primary_tag => 'five_prime_UTR',
												-start       => $utrStart,
												-end         => $utrEnd,
												-score       => ($gene->promoters())[0]->score(),
												-strand      => $gene->strand(),
												-tag         => $fivePrimeUtrTag
												);
		return $fivePrimeUtrFeat;
	}
	return undef;
}

sub _addThreePrimeUtrFeature {
	my ($self, $gene, $exon, $parentId) = @_;

	if (defined($gene->poly_A_site())) {
		my $utrStart;
		my $utrEnd;

		if ($gene->strand() == -1) {
			$utrStart = $gene->poly_A_site()->start();
			$utrEnd = ($exon->start() - 1);
		}
		else {
			$utrStart = ($exon->end() + 1);
			$utrEnd = $gene->poly_A_site()->start();
		}
		my $threePrimeUtrTag = {};
		$threePrimeUtrTag->{'Name'} = $self->getSourceTag() . '_' . $utrStart . '_' . $utrEnd . '_Gene_' . sprintf("%04d", $self->{nbGenes}) . '_mRNA_0001_three_prime_UTR_0001';
		$threePrimeUtrTag->{'ID'} = $self->{'sequenceName'} . '_' . $threePrimeUtrTag->{'Name'};
		$threePrimeUtrTag->{'Parent'} = $parentId;
		$threePrimeUtrTag->{'Ontology_term'} = $self->getSOTermId('three_prime_UTR');
		my $threePrimeUtrFeat = Bio::SeqFeature::Generic->new(
												-seq_id      => $self->{'sequenceName'},
												-source_tag  => $self->getSourceTag(),
												-primary_tag => 'three_prime_UTR',
												-start       => $utrStart,
												-end         => $utrEnd,
												-score       => $gene->poly_A_site()->score(),
												-strand      => $gene->strand(),
												-tag         => $threePrimeUtrTag
												);
		return $threePrimeUtrFeat;
	}
	return undef;
}
1;
