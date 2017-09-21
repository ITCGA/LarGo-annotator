package SIMsearch::orf::ORF;

# Perl modules
use strict;
use warnings;
use diagnostics;

use Carp;

# BioPerl modules
use Bio::SearchIO;
use Bio::SeqIO;


sub new {
	my $caller = shift;
	my $class = ref($caller) || $caller;
	my $self = {};
	bless $self, $class;
	$self->_init(@_);
	return $self;
}

sub identity_cutoff {
	my ($self, $identity) = @_;
	return unless defined $identity;
	$self->{'identity_cutoff'} = $identity;
}

sub length_cutoff {
	my ($self, $length) = @_;
	return unless defined $length;
	$self->{'length_cutoff'} = $length;
}

sub find {
	my $self = shift;
	$self->_read_blast;
	$self->_read_seq;
	$self->_find_orf;
}

sub write_nuc {
	my $self = shift;
	$self->_write('nuc', @_);
}

sub write_ami {
	my $self = shift;
	$self->_write('ami', @_);
}

sub _init {
	my $self = shift;
	my %args = @_;
	$self->{'blast_file'} = $args{'-blast'};
	$self->{'seq_file'} = $args{'-seq'};
	$self->{'identity_cutoff'} = 0.5;
	$self->{'length_cutoff'} = 100;
}

sub _read_blast {
	my $self = shift;
	my $hits = {};
	my $blast = Bio::SearchIO->new(-file => $self->{'blast_file'});
	while (my $result = $blast->next_result) {
		next if $result->num_hits == 0;
		my $hit = $result->next_hit;
		my $hsp = $hit->next_hsp;
		my $evalue = $hsp->evalue;
		my $identity = $hsp->frac_identical;
		next if $hsp->frac_identical < $self->{'identity_cutoff'};
		$hits->{$result->query_name} = {
		  start  => $hsp->start('query'),
		  end	=> $hsp->end('query'),
		  strand => $hsp->strand('query'),
		  evalue => $evalue,
		  identity => $identity,
		};
	}
	$self->{blast} = $hits;
}

sub _read_seq {
	my $self = shift;
	my $seqs = {};
	my $fasta = Bio::SeqIO->new(-file => $self->{'seq_file'});
	while (my $seq = $fasta->next_seq) {
		$seqs->{$seq->display_id} = $seq;
	}
	$self->{seq} = $seqs;
}

sub _find_orf {
	my $self = shift;
	my $orfs = {};
	foreach my $id (keys %{$self->{blast}}) {
		my $start = $self->{blast}->{$id}->{start};
		my $end = $self->{blast}->{$id}->{end};
		my $strand = $self->{blast}->{$id}->{strand};
		my $evalue = $self->{blast}->{$id}->{evalue};
		my $identity = $self->{blast}->{$id}->{identity};
		my $seq = $self->{seq}->{$id};

		unless (defined $seq) {
			carp "Sequence of $id was not found." if $^W;
			next;
		}

		($start, $end, $seq) = _revcom($start, $end, $seq) if $strand == -1;
		$start = _find_start($start, $seq);
		$end = _find_stop($end, $seq);
		#next if _contains_stop($start, $end, $seq);
		next if _too_short($start, $end, $self->{'length_cutoff'});
		($start, $end, $seq) = _revcom($start, $end, $seq) if $strand == -1;

		($start, $end) = ($end, $start) if $strand == -1;
		$orfs->{$id} = { start => $start, end => $end, evalue => $evalue, identity => $identity};
	}
	$self->{orf} = $orfs;
}

sub _classify {
	my ($start, $end, $seq) = @_;
	($start, $end, $seq) = _revcom($end, $start, $seq) if $end < $start;
	my $first_codon = $seq->trunc($start, $start + 2)->translate->seq;
	my $last_codon = $seq->trunc($end - 2, $end)->translate->seq;
	my $class;
	if ($first_codon eq 'M' && $last_codon eq '*') {
		$class = 'complete';
	} elsif ($first_codon ne 'M' && $last_codon eq '*') {
		$class = "5'partial";
	} elsif ($first_codon eq 'M' && $last_codon ne '*') {
		$class = "3'partial";
	} else {
		$class = "5'3'partial";
	}
	return $class;
}

sub _revcom {
	my ($start, $end, $seq) = @_;
	($start, $end) = ($end, $start);
	return ($seq->length - $start + 1, $seq->length - $end + 1, $seq->revcom);
}

sub _find_start {
	my ($hit_start, $seq) = @_;
	my $up_end = $hit_start + 2;
	my $up_start = 1 + $up_end % 3;
	my $aa_seq = reverse($seq->trunc($up_start, $up_end)->translate->seq);
	my ($start, $met) = (0, 0);
	foreach my $aa (split '', $aa_seq) {
		last if $aa eq '*';
		$start++;
		$met = $start if $aa eq 'M';
	}

	my $pos = ($met == 0) ? $start : $met;
	$pos = length($aa_seq) - $pos + 1;
	return ($pos * 3 - 2) + ($up_start - 1);
}

sub _find_stop {
	my ($hit_end, $seq) = @_;
	my $down_start = $hit_end - 2;
	my $down_end = $seq->length - ($seq->length - $down_start + 1) % 3;
	my $aa_seq = $seq->trunc($down_start, $down_end)->translate->seq;
	my $pos = 0;
	foreach my $aa (split '', $aa_seq) {
		$pos++;
		last if $aa eq '*';
	}

	return ($pos * 3) + ($down_start - 1);
}

sub _contains_stop {
	my ($start, $end, $seq) = @_;
	my $orf = $seq->trunc($start, $end - 3)->translate->seq;
	return ($orf =~ /\*/) ? 1 : 0;
}

sub _too_short {
	my ($start, $end, $cutoff) = @_;
	my $length = (($end - $start + 1) - 3) / 3;
	return ($length < $cutoff) ? 1 : 0;
}

sub _write {
	my $self = shift;
	my $seq = shift;
	my %args = @_;
	my $file = $args{'-file'};
	my $out = (defined $file) ? Bio::SeqIO->new(-format => 'fasta', -file => ">$file") : Bio::SeqIO->new(-format => 'fasta', -fh => \*STDOUT);
	foreach my $id (keys %{$self->{orf}}) {
		my $start = $self->{orf}->{$id}->{start};
		my $end = $self->{orf}->{$id}->{end};
		my $evalue = $self->{orf}->{$id}->{evalue};
		my $identity = $self->{orf}->{$id}->{identity};
		my $seqobj = ($start < $end) ? $self->{seq}->{$id}->trunc($start, $end) : $self->{seq}->{$id}->trunc($end, $start)->revcom;
		my $length = $seqobj->length;
		my $seqstr = ($seq eq 'nuc') ? $seqobj->seq : $seqobj->translate->seq;
		my $note = _classify($start, $end, $self->{seq}->{$id});
		my $stop_codon = _contains_stop(1, $length, $seqobj) ? 'true' : 'false';
		$stop_codon = "inframe_stop_codon:$stop_codon";
		my $desc = join(' ', "start:$start", "end:$end", "orf:$note", $stop_codon, $evalue, $identity);
		$out->write_seq(Bio::Seq->new(-id => $id, -desc => $desc, -seq => $seqstr));
	}
}

1;
