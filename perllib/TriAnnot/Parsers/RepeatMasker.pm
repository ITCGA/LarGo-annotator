#!/usr/bin/env perl

package TriAnnot::Parsers::RepeatMasker;

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

## TriAnnot modules
use TriAnnot::Parsers::Parsers;
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::MergeHits;
use TriAnnot::Tools::Logger;
use TriAnnot::Tools::GetInfo;

# BioPerl modules
use Bio::Tools::RepeatMasker;

## Inherits
our @ISA = qw(TriAnnot::Parsers::Parsers);

##################################################
## Methods
##################################################
=head1 TriAnnot::Parsers::RepeatMasker - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call parent class constructor
	my $self = $class->SUPER::new(\%attrs);

	# Define $self as a $class type object
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
	my ($Nb_repeat_region, $connexion_to_db) = (0, undef);
	my (@RM_results,@Coordinates) = ((), ());

	# Display a warning message when the file to parse is missing
	if (! -e $self->{'fullFileToParsePath'}) {
		$logger->logwarn('RepeatMasker output file is missing (' . $self->{'fullFileToParsePath'} . '). Parse method will return an empty feature array.');
		return @RM_results;
	}

	# Creation of a parser of RepeatMasker results
	my $RM_parser = Bio::Tools::RepeatMasker->new(-file => $self->{'fullFileToParsePath'});

	######################
	# First step: Analyse of each result lines
	while (my $parser_res = $RM_parser->next_result()) {

		# The number of match_part increase
		$Nb_repeat_region++;
		$Nb_repeat_region = sprintf("%04d", $Nb_repeat_region);

		# Initializations
		my $repeat_region_Tag = {};
		my ($hfeat_start, $hfeat_end);

		# Recovers query information
		my $qfeat = $parser_res->feature1();
		my $qfeat_start = $qfeat->start();
		my $qfeat_end = $qfeat->end();
		my $qfeat_primary_tag = $qfeat->primary_tag();

		# Recovers hit information
		my $hfeat = $parser_res->feature2();
		my $hfeat_seqid = $hfeat->seq_id();
		if ($qfeat->strand() eq '-1') {
			$hfeat_start = $hfeat->end();
			$hfeat_end = $hfeat->start();
		} else {
			$hfeat_start = $hfeat->start();
			$hfeat_end = $hfeat->end();
		}

		# Build the new feature tag (GFF field 9)
		$repeat_region_Tag->{'Name'} = $self->{sourceTag} . '_' . $qfeat_start . '_' . $qfeat_end . '_Repeat_region_' . $Nb_repeat_region;
		$repeat_region_Tag->{'ID'} = $self->{'sequenceName'} . '_' . $repeat_region_Tag->{'Name'};
		$repeat_region_Tag->{'Target'} = [$hfeat_seqid, $hfeat->start(), $hfeat->end()]; # Target Tag must be a reference to a table (anonymous or not)

		# GetInfo
		my $info = TriAnnot::Tools::GetInfo->new(database => $TRIANNOT_CONF{PATHS}->{db}->{$self->{database}}->{path}, type => 'F' , id => $hfeat_seqid);

		# Special treatment for the Note attribute: if the database is different than RMdb
		if ($self->{'database'} ne 'RMdb') {
			$repeat_region_Tag->{'Note'} = $info->{description};
		} else {
			$repeat_region_Tag->{'Note'} = $hfeat_seqid . ' (' . $qfeat_primary_tag . ')';
		}

		# Compute coverage
		if ($self->{'database'} ne 'RMdb') {
			$repeat_region_Tag->{'hit_full_size'} = $info->{length};
			if ($repeat_region_Tag->{'hit_full_size'} == 0) {
				$logger->logwarn("Could not get information for this hit. Can not determine hit coverage: $hfeat_seqid");
			} else {
				my $hit_coverage = (($hfeat_end - $hfeat_start) + 1) / $repeat_region_Tag->{'hit_full_size'};
				$repeat_region_Tag->{'coverage'} = sprintf("%.2f", $hit_coverage * 100);
			}
		}

		# Creation of a new repeat_region feature
		my $repeat_region = Bio::SeqFeature::Generic->new(
						 -seq_id      => $self->{'sequenceName'},
						 -source_tag  => $self->{sourceTag},
						 -primary_tag => 'repeat_region',
						 -start       => $qfeat_start,
						 -end         => $qfeat_end,
						 -score       => $qfeat->score(),
						 -strand      => $qfeat->strand(),
						 -frame       => '.',
						 -tag         => $repeat_region_Tag
						);

		# Storage of the new feature in a table (It will be used to build GFF files)
		push(@RM_results, $repeat_region);

		# Storage of the couple of coordinates (query start and query end) in a table to create the merged hit in the next step
		my $coord_couple = $qfeat_start . "\t" . $qfeat_end;
		push(@Coordinates, $coord_couple);
	}

	$RM_parser->close();

	####################
	# Second step: Merged hit creation
	if (scalar(@Coordinates) > 0) { # Only if there is at least one result
		my $All_merged_hit = TriAnnot::Tools::MergeHits::Merge_all_hit(\@Coordinates, $self->{'sequenceName'}, $self->{sourceTag});
		push(@RM_results, @{$All_merged_hit});
	}

	return (@RM_results);
}

1;
