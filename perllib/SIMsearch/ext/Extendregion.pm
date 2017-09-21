package SIMsearch::ext::Extendregion;

use strict;
use warnings;
use diagnostics;

use Exporter;
use vars qw(@ISA @EXPORT);

@ISA=qw(Exporter);

@EXPORT=qw(
			report_ORF
			make_gff_from_sen
			exon_start_end_ext
			length_5_UTR
			extend_start_stop
			CDS_start_end_check
			fastafile_to_seqhash
			take_id_val
			first_val
			ins_paren
			replace_gff_file
			general_convert_gff_to_line
			exon_make_by_di
			CDS_trans2
			cut_seq_di
			check_start_stop
			between_stop
			search_back_start
			get_start
			search_back_exon_stop
			check_stop_remain
			search_back_stop
			ATGC_check
			insert_startend_exon
			conv_CDS_to_exon2
			printfasta2
			translate
			codontable
);


my $debugflg=0;


sub report_ORF(){
	my ($id,$orf)=@_;

	my $len=length($orf);

	my $premature=0;

	for (my $i=0;$i<$len;$i++){
		my $ami=substr($orf,$i,1);

		if($ami eq '*'){
			if($i==($len-1)){

			} else {
				$premature=1;
			}
		}
	}

	my $premature_stop_codon="false";
	if($premature==1){
		$premature_stop_codon="true";
	}

	my $startcodon=substr($orf,0,1);
	my $stopcodon=substr($orf,$len-1,1);

	my $orflen;
	if($stopcodon eq "*"){
		$orflen=$len-1;
	} else {
		$orflen=$len;
	}

	my $status="";
	if($startcodon eq "M"){
		if($stopcodon eq "*"){
			$status="complete";
		} else {
			$status="3'partial";
		}
	} elsif($stopcodon eq "*"){
		$status="5'partial";
	} else {
		$status="5'3'partial";
	}

	my $resinf=join("\t",$id,$orflen,$status,$premature_stop_codon);

	return $resinf;
}


sub make_gff_from_sen(){
	my ($sen,$typecol,$infcol)=@_;

	my @items=split(/\t/,$sen);

	my $chr=$items[1];
	my $start=$items[2];
	my $end=$items[3];
	my $di=$items[4];
	my $exon=$items[5];
	my $type=$items[$typecol];
	my $exoninf=$items[$typecol+1];
	my $inf=$items[$infcol];

	my $gffver=3;
	my %symhash=('C' => 'polypeptide', '5' => 'five_prime_UTR', '3' => 'three_prime_UTR', 'U' => 'exon');

	my %tmphash;

	&take_id_val($inf,$gffver,\%tmphash);

	my $uniq_id=$items[0];
	if(defined $tmphash{ID}){
		$uniq_id=$tmphash{ID};
	}

	my $finres="";

	my $data_type="mRNA";
	my $kazu=".";
	my $phase=".";
	my $gene=join("\t",$chr,$type,$data_type,$start,$end,$kazu,$di,$phase,$inf);

	$finres.="$gene\n";

	my @data=split(/,/,$exon);
	for (my $i=0;$i<@data;$i++){
		my @tmp=split(/\|/,$data[$i]);

		my $frg_sym=$tmp[0];
		my $frg_start=$tmp[1];
		my $frg_end=$tmp[2];
		my $frg_type=$symhash{$frg_sym};

		my $frg_inf="Parent=$uniq_id;";

		#my $uid=join("_",$uniq_id,$frg_sym,$i);
		#my $frg_inf=&replace_id_infcol($exoninf,$uid);

		my $exon=join("\t",$chr,$type,$frg_type,$frg_start,$frg_end,$kazu,$di,$phase,$frg_inf);
		$finres.="$exon\n";
	}

	return $finres;
}


sub exon_start_end_ext(){
	my($start,$end,$ext_start,$ext_stop,$di)=@_;

	my $fin_start=$start;
	my $fin_end=$end;

	if($di eq "+"){
		if($ext_start < $start){
			$fin_start=$ext_start;
		}
		if($end < $ext_stop){
			$fin_end=$ext_stop;
		}
	} elsif($di eq "-"){
		if($ext_stop < $start){
			$fin_start=$ext_stop;
		}

		if($end < $ext_start){
			$fin_end=$ext_start;
		}
	}
	return ($fin_start,$fin_end);
}


sub length_5_UTR(){
	my ($exon)=@_;

	my @data=split(/,/,$exon);

	my $sum=0;
	for (my $i=0;$i<@data;$i++){
		my @tmp=split(/\|/,$data[$i]);

		if($tmp[0] eq "5"){
			my $len=abs($tmp[2]-$tmp[1])+1;
			$sum+=$len;
		}
	}

	return $sum;
}


sub extend_start_stop(){
	my ($seq,$exon,$di,$extlim,$flghash)=@_;


	my $Xblock_lim=50;

	my ($CDS_start,$CDS_end)=&CDS_start_end_check($exon,$di);

	my ($cmb_exon,$cmb_CDS)=&conv_CDS_to_exon2($exon,$di);

	my $ext_stop=&search_back_stop($seq,$di,$CDS_end,$Xblock_lim,$extlim);
	my $ext_stop2=&search_back_exon_stop($seq,$di,$CDS_end,$cmb_exon,$Xblock_lim,$extlim);


	$ext_stop=$ext_stop2;

	my $ext_start=-1;

	my $orinuc=&get_start($seq,$di,$CDS_start);

	my $length_5_UTR=&length_5_UTR($exon);

	if($$flghash{"atg_start"}==2 && $length_5_UTR > 2){
		$ext_start=$CDS_start;
	} elsif($$flghash{"atg_start"}==1 && $orinuc eq "ATG"){
		$ext_start=$CDS_start;
	} else {
		$ext_start=&check_start_stop($seq,$di,$CDS_start,$cmb_exon,$ext_start,$Xblock_lim,$extlim);
	}

	return ($ext_start,$ext_stop2);
}


sub CDS_start_end_check(){
	my($exon,$di)=@_;

	my @data=split(/,/,$exon);

	my $start=-1;
	my $end=-1;

	my $startflg=0;

	my @box;
	my $len=0;

	my $tmpend=-1;
	for (my $i=0;$i<@data;$i++){
		my @tmp=split(/\|/,$data[$i]);
		if($tmp[0] eq "C"){
			push(@box,[$tmp[1],$tmp[2]]);
			my $exonlen=abs($tmp[2]-$tmp[1])+1;
			$len+=$exonlen;

			my $rem=$len % 3;

			if($rem < $exonlen){
				if($di eq "+"){
					$tmpend=$tmp[2]-$rem;
				} elsif($di eq "-"){
					$tmpend=$tmp[1]+$rem;
				}
			}
		}
	}

	if($di eq "+"){
		$start=$box[0][0];
		$end=$box[$#box][1];
	} elsif($di eq "-"){
		$start=$box[0][1];
		$end=$box[$#box][0];
	}

	my $rem=$len % 3;

	if($rem!=0){
		$end=$tmpend;
	}
	#print "TMP $tmpend\n";

	return($start,$end);
}


sub fastafile_to_seqhash(){
	my ($filename,$seqhash)=@_;

	if($filename=~/gz$/){
		open(SEQ,"zcat $filename|") || die "$filename:$!";
	}elsif($filename=~/zip$/){
		open(SEQ,"zcat $filename|") || die "$filename:$!";
	} else {
		open(SEQ,"$filename");
	}

	my $num=0;
	my $id="";
	while(<SEQ>){
		chomp;
		my $sen=$_;
		if($sen=~/^>/){
			if($num!=0){
			} else {
				$num++;
			}
			my @items=split(' ',$sen,2);
			$id=substr($items[0],1,length($items[0])-1);
			$$seqhash{$id}="";
		} elsif($sen ne ""){
			$$seqhash{$id}.=$sen;
		}
	}

}


sub take_id_val(){
	my($val,$gffver,$infhash)=@_;
	my @data=split(/;/,$val);
	for (my $i=0;$i<@data;$i++){
		my @tmp;
		if($gffver eq "3"){
			@tmp=split(/=/,$data[$i],2);
		} else{
			@tmp=split(/[\s]+/,$data[$i],2);
		}
		my $insval=&ins_paren($tmp[1]);
		my $resval=&first_val($insval);

		#print "$tmp[0] $resval\n";
		$$infhash{$tmp[0]}=$resval;
	}
}


sub first_val(){
	my($val)=@_;
	my $res=$val;
	if($res=~/,/){
		my @items=split(/,/,$res);
		$res=$items[0];
	}
	return $res;
}


sub ins_paren(){
	my($val)=@_;
	my $res=$val;
	if(substr($val,0,1) eq '"' && substr($val,length($val)-1,1) eq '"'){
		$res=substr($val,1,length($val)-2);
	}
	return $res;
}


sub replace_gff_file(){
	my ($file,$infhash,$gffver)=@_;

	my %duphash;

	my %kindhash=('mRNA' => 'mRNA',
		  'polypeptide' =>'CDS',
		  'five_prime_UTR' =>'5',
		  'three_prime_UTR' =>'3',
		  'UTR' =>'UTR');

	my $fin_sen="";
	open(TMPREP,"$file") || die "$file:$!";
	while(<TMPREP>){
		chomp;
		if($_=~/^\#/){
			$fin_sen.="$_\n";
			next;
		}

		my @items=split(/\t/,$_);
		my $chr=$items[0];
		my $method=$items[1];
		my $type=$items[2];
		my $start=$items[3];
		my $end=$items[4];
		my $score=$items[5];
		my $direction=$items[6];
		my $phase=$items[7];
		my $preinf=$items[8];

		if(!defined $kindhash{$type}){
			$fin_sen.="$_\n";
			next;
		}

		my %tmphash;
		&take_id_val($preinf,$gffver,\%tmphash);


		my $uid="";
		if($kindhash{$type} eq "mRNA"){
			if(defined $tmphash{"ID"}){
				$uid=$tmphash{"ID"};
			} elsif(defined $tmphash{"Parent"}){
				$uid=$tmphash{"Parent"};
			}
		} else {
			if(defined $tmphash{"Parent"}){
				$uid=$tmphash{"Parent"};
			}
		}

		if(defined $duphash{$uid}){
			next;
		}

		if(defined $$infhash{$uid}){
			$fin_sen.="$$infhash{$uid}";
			$duphash{$uid}=1;
		}
	}
	close(TMPREP);

	return $fin_sen;
}


sub general_convert_gff_to_line(){
	my ($file,$gffver,$resbox)=@_;

	my %kind=('gene' => 'G',
		'mRNA' => 'M',
		'5\'-UTR' => '5',
		'polypeptide' => 'C',
		'CDS' => 'C',
		'3\'-UTR' => '3',
		'UTR' => 'U',
		'exon' => 'U',
		'match' => 'M',
		'match_part' => 'C',
		'cross_mRNA' => 'M',
		'cross_CDS' => 'C',
		'cross_5\'-UTR' => '5',
		'cross_3\'-UTR' => '3',
		'cross_exon' => 'U',
		'rap_mRNA' => 'M',
		'rap_exon' => 'U',
		'rap_CDS' => 'C',
		'rap_5\'-UTR' => '5',
		'rap_3\'-UTR' => '3',
		'three_prime_UTR' => '3',
		'five_prime_UTR' => '5',
		'rep_mRNA' => 'M',
		'rep_CDS' => 'C',
		'rep_5\'-UTR' => '5',
		'rep_3\'-UTR' => '3',
		'rep_5\'-UTR' => '5',
		'rep_3\'-UTR' => '3',
		'rep_UTR' => 'U',
		'rep_EST_predicted_CDS' =>'C',
		'rep_EST_predicted_mRNA' =>'M',
		'EST_predicted_mRNA' => 'M',
		'EST_predicted_CDS' => 'C',
		'predicted_gene' => 'G',
		'predicted_mRNA' => 'M',
		'predicted_3\'-UTR' => '3',
		'predicted_5\'-UTR' => '5',
		'predicted_CDS' =>'C');

	my %moto;
	my %gen;
	my $old_seq_id=-1;
	my $old_locus_id=-1;
	my $old_trans_id=-1;
	my %reshash;


	open(TMPIN,"$file") || die "$file:$!";

	my $ord=1;
	my $dummy="";

	while(<TMPIN>){
		chomp;
		if($_=~/^\#/){
			next;
		}

		my @items=split(/\t/,$_);
		my $chr=$items[0];
		my $method=$items[1];
		my $type=$items[2];
		my $start=$items[3];
		my $end=$items[4];
		my $score=$items[5];
		my $direction=$items[6];
		my $phase=$items[7];
		my $preinf=$items[8];


		my $typekind="";
		if(defined $kind{$type}){
			$typekind=$kind{$type};
		}

		my %tmphash;
		&take_id_val($preinf,$gffver,\%tmphash);

		if($typekind=~/[M53CU]/){
			#if(!defined $tmphash{seq_id}){
			#	next;
			#}
		} else {
			next;
		}

		my @info=split(/;/,$items[8]);

		my $seq_id="";
		my $locus_id="";
		my $trans_id="";
		my $des="";
		my $cluster_id="";

		if($gffver eq "3"){
			if($typekind eq "M"){
				if(defined $tmphash{ID}){
					$seq_id=$tmphash{ID};
					$locus_id=$tmphash{ID};
				} elsif(defined $tmphash{Parent}){
					$seq_id=$tmphash{Parent};
					$locus_id=$tmphash{Parent};
				} elsif(defined $tmphash{Derives_from}){
					$seq_id=$tmphash{Derives_from};
					$locus_id=$tmphash{Derives_from};
				}
			} else {
				if(defined $tmphash{Parent}){
					$seq_id=$tmphash{Parent};
					$locus_id=$tmphash{Parent};
				} elsif(defined $tmphash{Derives_from}){
					$seq_id=$tmphash{Derives_from};
					$locus_id=$tmphash{Derives_from};
				} elsif(defined $tmphash{ID}){
					$seq_id=$tmphash{ID};
					$locus_id=$tmphash{ID};
				}
			}
		} else {
			if(defined $tmphash{seq_id}){
				$seq_id=$tmphash{seq_id};
			}
				if(defined $tmphash{locus_id}){
				$locus_id=$tmphash{locus_id};
			}

		}

		if($tmphash{Cluster_id}){
			$cluster_id=$tmphash{Cluster_id};
		}

		my $note="";

		if($typekind eq "M"){
			 $note=$items[8];
		}


		my $identity=0;
		my $coverage=0;


		if($typekind eq "M"){

			$gen{$seq_id}{chr}=$chr;
			$gen{$seq_id}{start}=$start;
			$gen{$seq_id}{end}=$end;

			$gen{$seq_id}{direction}=$direction;
			$gen{$seq_id}{locus_id}=$locus_id;
			#$gen{$seq_id}{seq};
			$gen{$seq_id}{note}=$note;
			#$gen{$seq_id}{note}="NOTE";
			$gen{$seq_id}{identity}=$identity;
			$gen{$seq_id}{clusterid}=$cluster_id;
			$gen{$seq_id}{method}=$method;
			$gen{$seq_id}{exoninf}="";
			$gen{$seq_id}{ord}=$ord++;

		} elsif($typekind eq "C" || $typekind eq "5" || $typekind eq "3"){
			my $frg_inf=join("\|",$typekind,$start,$end,$phase);
			$gen{$seq_id}{exoninf}=$preinf;
			push(@{$gen{$seq_id}{seq}},$frg_inf);
		} elsif($typekind eq "U"){
			my $frg_inf=join("\|",$typekind,$start,$end,$phase);
			push(@{$gen{$seq_id}{Uinf}},$frg_inf);
		}

	}
	close(TMPIN);

	for my $id (sort {$gen{$a}{ord} <=> $gen{$b}{ord}} keys %gen){

		my $exon="";
		if(defined $gen{$id}{seq}){
			$exon=&exon_make_by_di($gen{$id}{seq},$gen{$id}{direction});
		}

		my $res_inf=join("\t",$id,$gen{$id}{chr},$gen{$id}{start},$gen{$id}{end},$gen{$id}{direction},$exon,$gen{$id}{clusterid},,$gen{$id}{identity},$dummy,$gen{$id}{method},$gen{$id}{exoninf},$gen{$id}{note});

		push(@{$resbox},$res_inf);
	}

}


sub exon_make_by_di(){
	my ($list,$di)=@_;

	my @box;
	for (my $i=0;$i<@{$list};$i++){
		#print "$$list[$i]\n";
		my @tmp=split(/\|/,$$list[$i]);
		push(@box,[$tmp[1],$tmp[2],$$list[$i]]);
	}

	if($di eq "+"){
		@box=@box[sort {$box[$a][0] <=> $box[$b][0] || $box[$a][1] <=> $box[$b][1]} 0..$#box];
	} elsif($di eq "-"){
		@box=@box[sort {$box[$b][0] <=> $box[$a][0] || $box[$b][1] <=> $box[$a][1]} 0..$#box];
	}

	my @exonbox;
	for (my $i=0;$i<@box;$i++){
		#print "$box[$i][0]\t$box[$i][1]\t$box[$i][2]\n";
		push(@exonbox,$box[$i][2]);
	}

	my $res=join(",",@exonbox);
	return $res;

}


sub CDS_trans2(){
	my($seq,$inf,$di)=@_;

	my @exon=split(/,/,$inf);

	my $res="";
	for my $i (0..$#exon){
		my @pos=split(/\|/,$exon[$i]);
		if($pos[0] eq "C"){
			if($di eq "+"){
				$res.=&cut_seq_di($seq,$pos[1],$pos[2],$di);
			} else {
				$res.=&cut_seq_di($seq,$pos[2],$pos[1],$di);
			}
		}
	}

	$res=~tr/a-z/A-Z/;
	if($debugflg==1){
		#print "PRE $res\n";
	}
	my $resseq=&translate($res,0,"+");

	return ($res,$resseq);
}


sub cut_seq_di(){
	my($seq,$start,$end,$di)=@_;
	my $res="";

	if($di eq "+"){
		$res=substr($$seq,$start-1,$end-$start+1);
	} elsif($di eq "-"){
		my $tmp1=substr($$seq,$end-1,$start-$end+1);
		$res=reverse($tmp1);
		$res=~tr/ATGC/TACG/;
		$res=~tr/atgc/tacg/;
	}
	return $res;
}


sub check_start_stop(){
	my ($seq,$di,$pos,$exon,$ext_start,$Xblock_lim,$extlim)=@_;

	my $gstop=0;
	my $gstart=$ext_start;
	my %fwhash=("TAA" =>1, "TGA" =>2, "TAG" =>3);

	my %revhash=("TTA" =>1, "TCA" =>2, "CTA" =>3);

	my @data=split(/,/,$exon);
	my @box;
	my $gresseq="";
	my $beg=-1;

	my $seqlen=length($$seq);

	my $pre_start=-1;
	my $pre_stop=-1;
	my $preseq="";
	my $next_start=-1;
	my $next_stop=-1;


	for (my $i=0;$i<@data;$i++){
		my @tmp=split(/\|/,$data[$i]);
		my $sym=$tmp[0];
		my $tmp_start=$tmp[1];
		my $tmp_end=$tmp[2];

		if($i==0){
			if($di eq "+"){
				$beg=$tmp_start;
			} else {
				$beg=$tmp_end;
			}
		}
		if($tmp_start <=$pos && $pos <= $tmp_end){
			if($debugflg==1){
				print "INSIDE $tmp_start $pos $tmp_end $di\n";
			}

			#$pre_start=$tmp_start;
			#$pre_stop=$tmp_end;

			if($i!=$#data){
				my @nexttmp=split(/\|/,$data[$i+1]);

				$next_start=$nexttmp[1];
				$next_stop=$nexttmp[2];

				if($di eq "+"){
					if($pos==$tmp_end){
						$preseq=substr($$seq,$next_start-1,2);
					} elsif($pos+1==$tmp_end){
						$preseq=substr($$seq,$next_start-1,1);
					}
				} elsif($di eq "-"){
					if($pos==$tmp_start){
						$preseq=substr($$seq,$next_stop-2,2);
					} elsif($pos==$tmp_start+1){
						$preseq=substr($$seq,$next_stop-1,1);
					}
				}
			}
			if($debugflg==1){
				print "RRRRRRRR   $pos $tmp_end $preseq\n";
			}

			my ($stopflg,$stoppos,$startpos,$resseq,$borderstop)=&between_stop($seq,$di,$pos,$tmp_start,$tmp_end,$preseq);
			my $hajilen=length($preseq);

			if($debugflg==1){
				print "FISRT $stopflg,$stoppos,$startpos,$resseq,$borderstop  KK $i\n";
			}
			$gresseq=$resseq;
			if($startpos!=-1){
				$gstart=$startpos;
			}

			if($stopflg==1){
				my $tmp=&get_start($seq,$di,$stoppos);
				if($gstart==-1){
					if($di eq "+"){
						if($borderstop!=1){
							$gstart=$stoppos+3;
						} else {
							$gstart=$next_start+$hajilen;
						}

					} elsif($di eq "-"){
						if($borderstop!=1){
							$gstart=$stoppos-3;
						} else {
							$gstart=$next_stop-$hajilen;
						}
					}
				}
				$gstop=1;
				if($debugflg==1){
					print "WWWW STOP_for_start  $gstart  $startpos $tmp $stoppos   GG $next_start $next_stop\n";
				}
			}

			$pre_start=$tmp_start;
			$pre_stop=$tmp_end;
			last;
		} else {
			push(@box,$data[$i]);
		}

	}

	if($gstop==0){
		for (my $i=$#box;$i>=0;$i--){
			if($debugflg==1){
				print "AA $box[$i] $gresseq $gstart\n";
			}
			my @tmp=split(/\|/,$box[$i]);
			my $sym=$tmp[0];
			my $tmp_start=$tmp[1];
			my $tmp_end=$tmp[2];
			my $hajilen=length($gresseq);
			my ($stopflg,$stoppos,$startpos,$resseq,$borderstop)=&between_stop($seq,$di,-1,$tmp_start,$tmp_end,$gresseq);
			if($debugflg==1){
				print "BB $stopflg,$stoppos,$startpos,$resseq, $borderstop\n";
			}
			$gresseq=$resseq;


			if($startpos!=-1){
				$gstart=$startpos;
			}

			if($stopflg==1){
				my $tmp=&get_start($seq,$di,$stoppos);
				if($gstart==-1){
					if($di eq "+"){
						if($borderstop!=1){
							$gstart=$stoppos+3;
						} else {
							$gstart=$pre_start+$hajilen;
						}

					} elsif($di eq "-"){
						if($borderstop!=1){
							$gstart=$stoppos-3;
						} else {
							$gstart=$pre_stop-$hajilen;
						}
					}
				}
				$gstop=1;
				if($debugflg==1){
					print "ga STOP_for_start  $gstart  $startpos $tmp $stoppos\n";
				}
				last;

			}
			$pre_start=$tmp_start;
			$pre_stop=$tmp_end;
		}
	}
	if($gstop==0){
		my $remlen=length($gresseq);
		my $extstart=$beg;
		my $res="";

		#print "$remlen $gresseq $beg KK $gstart\n";


		if($remlen>0){
			if($remlen==1){
				if($di eq "+"){
					$extstart=$beg+1;

					if($beg >=3){
						$res=substr($$seq,$beg-3,2);
					}
				} elsif($di eq "-"){
					$extstart=$beg-1;

					if($beg+2 < $seqlen){
						$res=substr($$seq,$beg,2);
					}
				}
			} elsif($remlen==2){
				if($di eq "+"){
					$extstart=$beg+2;
					if($beg >=2){
						$res=substr($$seq,$beg-2,1);
					}
				} elsif($di eq "-"){
					$extstart=$beg-2;
					if($beg+1 < $seqlen){
						$res=substr($$seq,$beg,1);
					}
				}
			}

			if($di eq "+"){
				$res=$res.$gresseq;
				if(defined $fwhash{$res}){
					$gstop=1;
				} elsif($res eq "ATG"){
					if($remlen==1){
						$gstart=$beg-2;
					} elsif($remlen==2){
						$gstart=$beg-1;
					}
				}
			} elsif($di eq "-"){
				$res=$gresseq.$res;
				if(defined $revhash{$res}){
					$gstop=1;
				} elsif($res eq "CAT"){
					if($remlen==1){
						$gstart=$beg+2;
					} elsif($remlen==2){
						$gstart=$beg+1;
					}
				}
			}
		}
		if($gstop==0){
			my $rm_extlim=$extlim;
			if($extlim!=-1){
				$rm_extlim=$extlim+$remlen;
			}

			#print "EXTENSION $extlim $rm_extlim\n";

			my($startEND,$startpos)=&search_back_start($seq,$di,$extstart,$Xblock_lim,$rm_extlim);


			my $tmpEND=&get_start($seq,$di,$startEND);

			my $tmpAAA="HHH";
			if($startpos!=-1){
				$gstart=$startpos;
				$tmpAAA=&get_start($seq,$di,$startpos);
			} else {
				if($gstart==-1){
					if($di eq "+"){
						$gstart=$startEND+3;
					} elsif($di eq "-"){
						$gstart=$startEND-3;
					}
				}
			}

			#print "EEEEEEEEEE $extstart $startEND,$startpos  $tmpEND $tmpAAA $gstart\n";
		}

	}

	if($gstart==-1){
		$gstart=$pos;
	}

	return $gstart;
}


sub between_stop(){
	my ($seq,$di,$pos,$fst,$sec,$addseq)=@_;

	my %fwhash=("TAA" =>1, "TGA" =>2, "TAG" =>3);

	my %revhash=("TTA" =>1, "TCA" =>2, "CTA" =>3);
	my $stopflg=0;
	my $stoppos=-1;
	my $startpos=-1;

	my $lenadd=length($addseq);

	#print "GGGGGGGGG $addseq $lenadd\n";


	my $curpos=$pos;
	my $res="";

	my $resseq="";

	my $borderstop=0;

	if($pos==-1){
		if($lenadd==0){
			if($di eq "+"){
				$curpos=$sec-2;
			} elsif($di eq "-"){
				$curpos=$fst+2;
			}
		} elsif($lenadd==1){
			if($di eq "+"){
				#bugfix 20101207
				#$curpos=$sec-1;
				$curpos=$sec-1-3;
				$res=substr($$seq,$sec-2,2);
				$res=$res.$addseq;
				$res=~tr/a-z/A-Z/;
				if(defined $fwhash{$res}){
					$stoppos=$sec-1;
					$stopflg=1;
					$borderstop=1;
				} elsif($res eq "ATG"){
					$startpos=$sec-1;
				}
			} elsif($di eq "-"){
				#bugfix 20101207
				#$curpos=$fst+1;
				$curpos=$fst+1+3;

				$res=substr($$seq,$fst-1,2);
				$res=$addseq.$res;
				$res=~tr/a-z/A-Z/;
				if(defined $revhash{$res}){
					$stoppos=$fst+1;
					$stopflg=1;
					$borderstop=1;
				} elsif($res eq "CAT"){
					$startpos=$fst+1;
				}
			}

		} elsif($lenadd==2){
			if($di eq "+"){
				#bugfix 20101207
				#$curpos=$sec;
				$curpos=$sec-3;

				$res=substr($$seq,$sec-1,1);
				$res=$res.$addseq;
				$res=~tr/a-z/A-Z/;
				if(defined $fwhash{$res}){
					$stopflg=1;
					$stoppos=$sec;
					$borderstop=1;
				} elsif($res eq "ATG"){
					$startpos=$sec;
				}
			} elsif($di eq "-"){
				#bugfix 20101207
				#$curpos=$fst;
				$curpos=$fst+3;
				$res=substr($$seq,$fst-1,1);
				$res=$addseq.$res;
				$res=~tr/a-z/A-Z/;


				#print "GGGGGGGG $res $curpos\n";
				if(defined $revhash{$res}){
					$stopflg=1;
					$stoppos=$fst;
					$borderstop=1;
				} elsif($res eq "CAT"){
					$startpos=$fst;
				}
			}
		}
	} else {
		$curpos=$pos;
		if($lenadd==1){
			if($di eq "+"){
				$curpos=$pos-3;

				$res=substr($$seq,$pos-1,2);
				$res=$res.$addseq;
				$res=~tr/a-z/A-Z/;
				if(defined $fwhash{$res}){
					$stoppos=$pos;
					$stopflg=1;
					$borderstop=1;
				} elsif($res eq "ATG"){
					$startpos=$pos;
				}
			} elsif($di eq "-"){
				$curpos=$pos+3;
				$res=substr($$seq,$pos-2,2);
				$res=$addseq.$res;
				$res=~tr/a-z/A-Z/;
				if(defined $revhash{$res}){
					$stoppos=$pos;
					$stopflg=1;
					$borderstop=1;
				} elsif($res eq "CAT"){
					$startpos=$pos;
				}
			}
		} elsif($lenadd==2){
			if($di eq "+"){
				$curpos=$pos-3;
				$res=substr($$seq,$pos-1,1);
				$res=$res.$addseq;
				$res=~tr/a-z/A-Z/;
				if(defined $fwhash{$res}){
					$stopflg=1;
					$stoppos=$pos;
					$borderstop=1;
				} elsif($res eq "ATG"){
					$startpos=$pos;
				}
			} elsif($di eq "-"){
				$curpos=$pos+3;
				$res=substr($$seq,$pos-1,1);
				$res=$addseq.$res;
				$res=~tr/a-z/A-Z/;
				if(defined $revhash{$res}){
					$stopflg=1;
					$stoppos=$pos;
					$borderstop=1;
				} elsif($res eq "CAT"){
					$startpos=$pos;
				}
			}
		}
	}

	if($stopflg==0){
		if($di eq "+"){
			while($curpos >=$fst){
				$res=substr($$seq,$curpos-1,3);
				$res=~tr/a-z/A-Z/;
				if($debugflg==1){
					#print "$curpos $res\n";
				}
				if(defined $fwhash{$res}){
					$stoppos=$curpos;
					$stopflg=1;
					last;
				} elsif($res eq "ATG"){
					$startpos=$curpos;
				}
				$curpos-=3;
			}
		} elsif($di eq "-"){
			while($curpos <=$sec){
				$res=substr($$seq,$curpos-3,3);
				$res=~tr/a-z/A-Z/;

				if($debugflg==1){
					print "$curpos $res\n";
				}
				if(defined $revhash{$res}){
					$stoppos=$curpos;
					$stopflg=1;
					last;
				} elsif($res eq "CAT"){
					$startpos=$curpos;
				}
				$curpos+=3;
			}
		}
	}

	#my $rem=($sec-$fst+1+$lenadd) % 3;
	my $rem=0;
	if($di eq "+"){
		if($curpos+1==$fst){
			$rem=2;
		} elsif($curpos+2==$fst){
			$rem=1;
		}
	} elsif($di eq "-"){
		if($sec+2==$curpos){
			$rem=1;
		} elsif($sec+1==$curpos){
			$rem=2;
		}
	}

	if($rem>0){
		if($di eq "+"){
			$resseq=substr($$seq,$fst-1,$rem);
		} elsif($di eq "-"){
			$resseq=substr($$seq,$sec-$rem,$rem);
		}
	}

	if($di eq "+" && ($sec-$stoppos)<=2){
		$borderstop=1;
	} elsif($di eq "-" && ($stoppos-$fst)<=2){
		$borderstop=1;
	}

	return($stopflg,$stoppos,$startpos,$resseq,$borderstop);
}


sub search_back_start(){
	my ($seq,$di,$pos,$Xblock_lim,$extlim)=@_;

	my %fwhash=("TAA" =>1, "TGA" =>2, "TAG" =>3);

	my %revhash=("TTA" =>1, "TCA" =>2, "CTA" =>3);

	my $seqlen=length($$seq);


	my $curpos=$pos;
	my $gstart=-1;

	my $res="";
	my $Ncount=0;
	my $Nflg=0;
	my $PreNpos=$curpos;

	if($di eq "+"){
		my $searchlim;
		if($extlim==-1){
			$searchlim=0;
		} else {
			$searchlim=$curpos-$extlim;
		}

		while($curpos >= $searchlim && $curpos>0){
			$res=substr($$seq,$curpos-1,3);
			$res=~tr/a-z/A-Z/;
			my $ckflg=&ATGC_check($res);

			if(defined $fwhash{$res}){
				last;
			} elsif($ckflg==0){
				last;
			} elsif($res eq "ATG"){
				$gstart=$curpos;
			}

			$curpos-=3;
		}

	} elsif($di eq "-"){
		my $searchlim;
		if($extlim==-1){
			$searchlim=$seqlen;
		} else {
			$searchlim=$curpos+$extlim;
		}
		while($curpos <=$searchlim){
			$res=substr($$seq,$curpos-3,3);
			$res=~tr/a-z/A-Z/;
			my $ckflg=&ATGC_check($res);

			if(defined $revhash{$res}){
				last;
			} elsif($ckflg==0){
				last;
			} elsif($res eq "CAT"){
				$gstart=$curpos;
			}

			$curpos+=3;
		}
	}

	return ($curpos,$gstart);
}


sub get_start(){
	my ($seq,$di,$pos)=@_;

	my $res="";
	if($di eq "+"){
		$res=substr($$seq,$pos-1,3);
	} elsif($di eq "-"){
		$res=substr($$seq,$pos-3,3);
		$res=reverse($res);
		$res=~tr/ATGCatgc/TACGtacg/;
	}

	$res=~tr/a-z/A-Z/;
	return $res;
}


sub search_back_exon_stop(){
	my ($seq,$di,$pos,$exon,$Xblock_lim,$extlim)=@_;

	my %fwhash=("TAA" =>1, "TGA" =>2, "TAG" =>3);

	my %revhash=("TTA" =>1, "TCA" =>2, "CTA" =>3);

	#print "$exon\n";

	my @data=split(/,/,$exon);

	my $curpos=$pos;
	my $conflg=0;

	my $stopflg=-1;
	my $preseq="";

	my $last_exon_start;
	my $last_exon_stop;

	my $total=0;
	for (my $i=0;$i<@data;$i++){
		my @tmp=split(/\|/,$data[$i]);
		my $r_start=$tmp[1];
		my $r_end=$tmp[2];
		my $len=abs($r_end-$r_start)+1;

		#print "QQQQ $i $#data $curpos $r_start $r_end\n";
		if($conflg==1 || ($r_start <=$curpos && $curpos <=$r_end)){
			if($i==$#data){
				$last_exon_start=$r_start;
				$last_exon_stop=$r_end;

				last;
			} else {
				my @tmp2=split(/\|/,$data[$i+1]);
				my $next_start=$tmp2[1];
				my $next_end=$tmp2[2];

				#print "GG $next_start $next_end\n";

				my $ckseq;
				my $revckseq;
				if($di eq "+"){
					if($conflg==0){
						my $tmp_start=$curpos-3;
						my $cklen=$r_end-$curpos+3;
						$ckseq=substr($$seq,$tmp_start,$cklen);
					} elsif($conflg==1){
						$ckseq=substr($$seq,$r_start-1,$r_end-$r_start+1);
						$ckseq=$preseq.$ckseq;
					}

					$ckseq=~tr/a-z/A-Z/;
					my ($hit,$rem,$remseq)=&check_stop_remain($ckseq);

					#print "DDDDDDD $hit,$rem,$remseq JJJ $ckseq MM $curpos\n";


					my $prelen=length($preseq);
					if($hit!=-1){
						$curpos=$curpos+$hit;
						if($prelen>0){
							$curpos=$curpos-3;
						}
						$stopflg=1;
						last;
					} elsif($hit==-1){
						$preseq=$remseq;
						if($rem==0){
							$curpos=$next_start+2;
						} else {
							$curpos=$next_start+2+(3-$rem);
						}

					}

				} elsif($di eq "-"){
					if($conflg==0){
						#my $tmp_start=$curpos-1;
						my $cklen=$curpos+2-$r_start+1;
						$ckseq=substr($$seq,$r_start-1,$cklen);
						$revckseq=reverse($ckseq);
						$revckseq=~tr/a-z/A-Z/;
						$revckseq=~tr/ATGC/TACG/;
					} elsif($conflg==1){
						$ckseq=substr($$seq,$r_start-1,$r_end-$r_start+1);
						$revckseq=reverse($ckseq);
						$revckseq=~tr/a-z/A-Z/;
						$revckseq=~tr/ATGC/TACG/;
						$revckseq=$preseq.$revckseq;
					}
					my ($hit,$rem,$remseq)=&check_stop_remain($revckseq);
					#print "SSSS $hit,$rem,$remseq KKK $curpos HHH $revckseq\n";


					#my $test=substr($$seq,$r_start-1,$r_end-$r_start+1);
					#my $rev=reverse($test);
					#$rev=~tr/ATGC/TACG/;
					#print "FFFF $rev\n";

					if($hit!=-1){
						$curpos=$curpos-$hit+2-2;
						$stopflg=1;
						last;
					} elsif($hit==-1){
						$preseq=$remseq;
						if($rem==0){
							$curpos=$next_end-2;
						} elsif($rem==1){
							$curpos=$next_end-1;
						} elsif($rem==0){
							$curpos=$next_end;
						}
					}
				}


				if($conflg==0){
					$conflg=1;
				}
			}

		}
	}

	#print "FIN $curpos\n";

	my $finstop;
	if($stopflg==1){
		$finstop=$curpos;
	} else {
		my $extlen=0;

		if($extlim==-1){
			$extlen=-1;
		} else {
			if($di eq "+"){
				$extlen=($last_exon_stop-$curpos)+$extlim;
			} elsif($di eq "-"){
				$extlen=($curpos-$last_exon_start)+$extlim;
			}
		}
	#print "$extlen $extlim $curpos $last_exon_start $last_exon_stop\n";

		$finstop=&search_back_stop($seq,$di,$curpos,$Xblock_lim,$extlen);
	}

	#print "DDDDDDD $curpos   $finstop\n";

	return $finstop;
}


sub check_stop_remain(){
	my($seq)=@_;

	my %fwhash=("TAA" =>1, "TGA" =>2, "TAG" =>3);

	my $len=length($seq);

	my $rem=$len % 3;
	my $hit=-1;
	for (my $i=0;$i<=$len-3-$rem;$i+=3){
		my $moji=substr($seq,$i,3);
		if(defined $fwhash{$moji}){
			$hit=$i;
			#2010_11_15 bug fix amano add last;
			last;
		}
	}

	my $remseq=substr($seq,$len-$rem,$rem);


	return ($hit,$rem,$remseq);
}


sub search_back_stop(){
	my ($seq,$di,$pos,$Xblock_lim,$extlim)=@_;

	my %fwhash=("TAA" =>1, "TGA" =>2, "TAG" =>3);

	my %revhash=("TTA" =>1, "TCA" =>2, "CTA" =>3);

	my $seqlen=length($$seq);

	my $endflg=0;
	my $curpos=$pos;

	my $res="";
	my $Ncount=0;
	my $Nflg=0;
	my $PreNpos=$curpos;

	if($di eq "+"){
		my $searchlim;
		if($extlim==-1){
			$searchlim=$seqlen;
		} else {
			$searchlim=$pos+$extlim;
		}
		while($curpos <=$searchlim && $endflg==0){
			#while($curpos <=$seqlen && $endflg==0){
			$res=substr($$seq,$curpos-3,3);
			$res=~tr/a-z/A-Z/;
			my $ckflg=&ATGC_check($res);

			#print "$di $curpos $res\n";
			if(defined $fwhash{$res}){
				$endflg=1;
				last;
			} elsif($ckflg==0){
				$endflg=1;
				last;
			}

			$curpos+=3;
		}

		if($endflg==0){
			$curpos-=3
		}
	} elsif($di eq "-"){
		my $searchlim;
		if($extlim==-1){
			$searchlim=0;
		} else {
			$searchlim=$pos-$extlim;
		}

		#print "$di $curpos $searchlim $endflg\n";


		while($curpos >= $searchlim && $curpos >0 && $endflg==0){
		#Bugfix 2010_11_15 = is needed amano
		#while($curpos > $searchlim && $endflg==0){
		#while($curpos >0 && $endflg==0){
			$res=substr($$seq,$curpos-1,3);
			$res=~tr/a-z/A-Z/;
			my $ckflg=&ATGC_check($res);

			#print "$di $curpos $res\n";
			if(defined $revhash{$res}){
				$endflg=1;
				last;
			} elsif($ckflg==0){
				$endflg=1;
				last;
			}

			$curpos-=3;
		}

		#print "LAST $curpos $endflg\n";

		if($endflg==0){
			$curpos+=3;
		}
	}

	return $curpos;
}


sub ATGC_check(){
	my ($codon)=@_;

	my $flg=0;
	if($codon=~/[ATGC]{3}/){
		$flg=1;
	}

	return $flg;
}


sub insert_startend_exon(){
	my ($cds_start,$cds_end,$exon,$di)=@_;

	my @data=split(/,/,$exon);

	my $flg=0;
	my @res;
	for (my $i=0;$i<@data;$i++){
		my @tmp=split(/\|/,$data[$i]);
		my $tmp_start=$tmp[1];
		my $tmp_end=$tmp[2];

		if($di eq "+"){
			if($flg==0){
				if($cds_start <=$tmp_start){
					if($cds_end <= $tmp_end){
						my $reg=join("\|","C",$cds_start,$cds_end);
						push(@res,$reg);

						if($cds_end != $tmp_end){
							my $reg=join("\|","3",$cds_end+1,$tmp_end);
							push(@res,$reg);
						}
						$flg=2;
					} else {
						if($i==$#data){
							my $reg=join("\|","C",$cds_start,$cds_end);
							push(@res,$reg);
							$flg=2;
						} else {
							my $reg=join("\|","C",$cds_start,$tmp_end);
							push(@res,$reg);
							$flg=1;
						}
					}
				} elsif($tmp_start < $cds_start && $cds_start<=$tmp_end){
					my $reg=join("\|",5,$tmp_start,$cds_start-1);
					push(@res,$reg);
					if($tmp_end < $cds_end){
						if($i!=$#data){
							my $reg=join("\|","C",$cds_start,$tmp_end);
							push(@res,$reg);
							$flg=1;
						} elsif($i==$#data){
							my $reg=join("\|","C",$cds_start,$cds_end);
							push(@res,$reg);
							$flg=2
						}
					} elsif($cds_end <= $tmp_end){
						my $reg=join("\|","C",$cds_start,$cds_end);
						push(@res,$reg);

						if($cds_end != $tmp_end){
							my $reg=join("\|","3",$cds_end+1,$tmp_end);
							push(@res,$reg);
						}
						$flg=2;
					}
				} elsif($tmp_end < $cds_start){
					my $reg=join("\|",5,$tmp_start,$tmp_end);
					push(@res,$reg);
				}
			} elsif($flg==1){
				if($tmp_end < $cds_end){
					if($i!=$#data){
						my $reg=join("\|","C",$tmp_start,$tmp_end);
						push(@res,$reg);
					} else {
						my $reg=join("\|","C",$tmp_start,$cds_end);
						push(@res,$reg);
					}
				} elsif($cds_end < $tmp_start){
					my $reg=join("\|",3,$tmp_start,$tmp_end);
					push(@res,$reg);
					$flg=2;
				} elsif($tmp_start <=$cds_end && $cds_end<=$tmp_end){
					my $reg=join("\|","C",$tmp_start,$cds_end);
					push(@res,$reg);
					if($cds_end!=$tmp_end){
						my $reg=join("\|",3,$cds_end+1,$tmp_end);
						push(@res,$reg);
					}
					$flg=2;
				}
			} elsif($flg==2){
				my $reg=join("\|",3,$tmp_start,$tmp_end);
				push(@res,$reg);
			}
		} elsif($di eq "-"){
			if($flg==0){
				if($tmp_end <= $cds_start){
					if($tmp_start <=$cds_end){
						my $reg=join("\|","C",$cds_end,$cds_start);
						push(@res,$reg);
						if($tmp_start!=$cds_end){
							my $reg=join("\|","3",$tmp_start,$cds_end-1);
							push(@res,$reg);
						}
						$flg=2;
					} else {
						if($i==$#data){
							my $reg=join("\|","C",$cds_end,$cds_start);
							push(@res,$reg);
							$flg=2;
						} else {
							my $reg=join("\|","C",$tmp_start,$cds_start);
							push(@res,$reg);
							$flg=1;
						}
					}
				} elsif($tmp_start <= $cds_start && $cds_start<$tmp_end){
					my $reg=join("\|",5,$cds_start+1,$tmp_end);
					push(@res,$reg);


					if($cds_end < $tmp_start){
						if($i!=$#data){
							my $reg=join("\|","C",$tmp_start,$cds_start);
							push(@res,$reg);
							$flg=1;
						} elsif($i==$#data){
							my $reg=join("\|","C",$cds_end,$cds_start);
							push(@res,$reg);
							$flg=2;
						}

					} elsif($tmp_start <= $cds_end){
						my $reg=join("\|","C",$cds_end,$cds_start);
						push(@res,$reg);
						if($tmp_start != $cds_end){
							my $reg=join("\|","3",$tmp_start,$cds_end-1);
							push(@res,$reg);
						}
						$flg=2;
					}
				} elsif($cds_start < $tmp_start){
					my $reg=join("\|",5,$tmp_start,$tmp_end);
					push(@res,$reg);
				}
			} elsif($flg==1){
				if($cds_end < $tmp_start){
					if($i!=$#data){
						my $reg=join("\|","C",$tmp_start,$tmp_end);
						push(@res,$reg);
					} else {
						my $reg=join("\|","C",$cds_end,$tmp_end);
						push(@res,$reg);
					}
				} elsif($tmp_start <=$cds_end && $cds_end<=$tmp_end){
					my $reg=join("\|","C",$cds_end,$tmp_end);
					push(@res,$reg);

					if($tmp_start!=$cds_end){
						my $reg=join("\|",3,$tmp_start,$cds_end-1);
						push(@res,$reg);
					}
					$flg=2;
				} elsif($tmp_end < $cds_end){
					my $reg=join("\|",3,$tmp_start,$tmp_end);
					push(@res,$reg);
					$flg=2;
				}
			} elsif($flg==2){
				my $reg=join("\|",3,$tmp_start,$tmp_end);
				push(@res,$reg);
			}
		}
	}

	my $resline=join(",",@res);
	return $resline;
}


sub conv_CDS_to_exon2(){
	my ($inf,$di)=@_;

	my @data=split(/,/,$inf);
	my @exon;
	my @cds;

	my $oldstart=-1;
	my $oldend=-1;


	my $oldsym="";

	if(@data==1){
		my @tmp=split(/\|/,$inf);
		my $sym=$tmp[0];
		my $start=$tmp[1];
		my $end=$tmp[2];
		push(@exon,$inf);
		if($sym eq "C" || $sym eq "5C" || $sym eq "C3" || $sym eq "5C3"){
			push(@cds,$inf);
		}
	} else {
		for (my $pos=0;$pos<@data;$pos++){
			#print "$pos $#data\n";
			my @tmp=split(/\|/,$data[$pos]);
			my $sym=$tmp[0];
			my $start=$tmp[1];
			my $end=$tmp[2];

			if($sym eq $oldsym){
				#print "$pos $oldsym,$oldstart,$oldend\n";
				my $res=join("\|",$oldsym,$oldstart,$oldend);
				push(@exon,$res);
				if($oldsym eq "C" || $oldsym eq "5C" || $oldsym eq "C3" || $oldsym eq "5C3"){
					push(@cds,$res);
				}
			} else{
				if($oldsym eq ""){
					$oldsym=$sym;
					$oldstart=$start;
					$oldend=$end;
					next;
				}
				my $cksym;
				if($oldsym eq "5" and $sym eq "C"){
					$cksym="5C";
				} elsif($oldsym eq "C" and $sym eq "3"){
					$cksym="C3";
				} elsif($oldsym eq "5C" and $sym eq "3"){
					$cksym="5C3";
				}

				if($di eq "+"){
					if(($oldend+1)==$start){
						$sym=$cksym;
						$start=$oldstart;
					} else {
						my $res=join("\|",$oldsym,$oldstart,$oldend);
						push(@exon,$res);
						if($oldsym eq "C" || $oldsym eq "5C" || $oldsym eq "C3" || $oldsym eq "5C3"){
							push(@cds,$res);
						}
					}
				} elsif($di eq "-"){
					if(($oldstart-1)==$end){
						$sym=$cksym;
						$end=$oldend;
					} else {
			my $res=join("\|",$oldsym,$oldstart,$oldend);
						push(@exon,$res);
						if($oldsym eq "C" || $oldsym eq "5C" || $oldsym eq "C3"|| $oldsym eq "5C3"){
							push(@cds,$res);
						}
					}
				}

			}
			if($pos==$#data){
				#print "$pos $#data $sym,$start,$end\n";
				my $res=join("\|",$sym,$start,$end);
				push(@exon,$res);
				if($sym eq "C" || $sym eq "5C" || $sym eq "C3" || $sym eq "5C3"){
					push(@cds,$res);
				}
			}
			$oldsym=$sym;
			$oldstart=$start;
			$oldend=$end;
		}
	}
	my $exon_inf=join(",",@exon);
	my $cds_inf=join(",",@cds);


	#print "GGG $exon_inf\n";

	return ($exon_inf,$cds_inf);
}


sub printfasta2(){
	my ($name,$seq,$num)=@_;
	my $len=length($seq);
	my $pos=0;
	my $res=">$name\n";
	while($pos < $len){
		my $rem=$len-$pos;
			if($rem > $num){
				$rem=$num;
			}
		my $tmpseq=substr($seq,$pos,$rem);
		$res.="$tmpseq\n";
		$pos+=$num;
	}
	return($res);
}


sub translate(){
	my ($seq,$frame,$strand)=@_;
	my $res;
	if($strand eq "-"){
		$res=reverse($seq);
		$res=~tr/ATGC/TACG/;
		$res=~tr/atgc/tacg/;
	} else {
		$res=$seq;
	}

	my $bseq=substr($res,$frame,length($res)-$frame);
	my $resseq="";
	for(my $i=0;$i<length($bseq);$i+=3){
		my $amino=&codontable(substr($bseq,$i,3));
		$resseq.=$amino;
	}
	return $resseq;
}


sub codontable(){
	my($seq)=@_;
	my %codon=('TTT' => 'F',
			   'TTC' => 'F',
			   'TTA' => 'L',
			   'TTG' => 'L',
			   'CTT' => 'L',
			   'CTC' => 'L',
			   'CTA' => 'L',
			   'CTG' => 'L',
			   'ATT' => 'I',
			   'ATC' => 'I',
			   'ATA' => 'I',
			   'ATG' => 'M',
			   'GTT' => 'V',
			   'GTC' => 'V',
			   'GTA' => 'V',
			   'GTG' => 'V',
			   'TCT' => 'S',
			   'TCC' => 'S',
			   'TCA' => 'S',
			   'TCG' => 'S',
			   'CCT' => 'P',
			   'CCC' => 'P',
			   'CCA' => 'P',
			   'CCG' => 'P',
			   'ACT' => 'T',
			   'ACC' => 'T',
			   'ACA' => 'T',
			   'ACG' => 'T',
			   'GCT' => 'A',
			   'GCC' => 'A',
			   'GCA' => 'A',
			   'GCG' => 'A',
			   'TAT' => 'Y',
			   'TAC' => 'Y',
			   'TAA' => '*',
			   'TAG' => '*',
			   'CAT' => 'H',
			   'ATA' => 'I',
			   'ATG' => 'M',
			   'GTT' => 'V',
			   'GTC' => 'V',
			   'GTA' => 'V',
			   'GTG' => 'V',
			   'TCT' => 'S',
			   'TCC' => 'S',
			   'TCA' => 'S',
			   'TCG' => 'S',
			   'CCT' => 'P',
			   'CCC' => 'P',
			   'CCA' => 'P',
			   'CCG' => 'P',
			   'ACT' => 'T',
			   'ACC' => 'T',
			   'ACA' => 'T',
			   'ACG' => 'T',
			   'GCT' => 'A',
			   'GCC' => 'A',
			   'GCA' => 'A',
			   'GCG' => 'A',
			   'TAT' => 'Y',
			   'TAC' => 'Y',
			   'TAA' => '*',
			   'TAG' => '*',
			   'CAT' => 'H',
			   'CAC' => 'H',
			   'CAA' => 'Q',
			   'CAG' => 'Q',
			   'AAT' => 'N',
			   'AAC' => 'N',
			   'AAA' => 'K',
			   'AAG' => 'K',
			   'GAT' => 'D',
			   'GAC' => 'D',
			   'GAA' => 'E',
			   'GAG' => 'E',
			   'TGT' => 'C',
			   'TGC' => 'C',
			   'TGA' => '*',
			   'TGG' => 'W',
			   'CGT' => 'R',
			   'CGC' => 'R',
			   'CGA' => 'R',
			   'CGG' => 'R',
			   'AGT' => 'S',
			   'AGC' => 'S',
			   'AGA' => 'R',
			   'AGG' => 'R',
			   'GGT' => 'G',
			   'GGC' => 'G',
			   'GGA' => 'G',
			   'GGG' => 'G');
	my $ans;
	if(defined $codon{$seq}){
		$ans=$codon{$seq};
	} else {
		$ans="X";
	}
	return $ans;
}

1;
