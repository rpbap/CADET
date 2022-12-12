#!/bin/bash
function Usage()
{
cat <<-ENDOFMESSAGE
#################################################################################
##      CADECT - Concatemer by Amplification DEteCtion Tool v0.2.1                ##
##                               Baptista, Rodrigo, 2022                       ##
#################################################################################

Usage

$0 [OPTIONS] -R <Reads.fastq> -w <window size> -s <slide size> -p <your_prefix>

Flag description:

    -R  --reads     fasta/fastq file with reads generated by WGA sequencing using ONT (required)
    -w --window    length of desired window sequences in bp (required) (default = 500)
    -s  --slide     length to slide each window over in bp (required) (default = 500)
    -p  --prefix    Prefix name for your output folder (default = "CADECT_output")

Options: 
    -h  --help      display this message

ENDOFMESSAGE
    exit 1
}

function Die()
{
    echo "$*"
    exit 1
}


function GetOpts() {
    reads=""
    window="500"
    slide="500"
    prefix="CADECT_output"
    
    while [ $# -gt 0 ]
    do
        opt=$1
        shift
        case ${opt} in
            -R|--reads)
                arg_has_reads=1
                if [ $# -eq 0 -o "${1:0:1}" = "-" ]; then
                    Die "The ${opt} option requires an argument."
                fi
                reads="$1"
                shift
                ;;
           -w|--window)
                arg_has_window=1
                if [ $# -eq 0 -o "${1:0:1}" = "-" ]; then
                    Die "The ${opt} option requires an argument."
                fi
                window="$1"
                shift
                ;;
           -s|--slide)
                arg_has_slide=1
                if [ $# -eq 0 -o "${1:0:1}" = "-" ]; then
                    Die "The ${opt} option requires an argument."
                fi
                slide="$1"
                shift
                ;;
           -p|--prefix)
                arg_has_prefix=1
                if [ $# -eq 0 -o "${1:0:1}" = "-" ]; then
                        Die "The ${opt} option requires an argument."
                fi
                prefix="$1"
                shift
                ;;
            -h|--help)
                Usage;;
            *)
                if [ "${opt:0:1}" = "-" ]; then
                    Die "${opt}: unknown option."
                fi
 
        esac
    done 


        if [ $arg_has_reads -ne 0 ]; then
                GENOME=${reads}
       else
             echo "Error: -R (reads.fastq) absent"
                Usage
        fi
        if [ -n $arg_has_window ]; then
                W=$window
      else
            echo "Error: window size absent"
                Usage
        fi
        if [ -n $arg_has_slide ]; then
                S=$slide
      else
            echo "Error: slide size absent"
                Usage
        fi
        if [ -n $arg_has_prefix ]; then
                SAMPLE=$prefix
        else
                echo "Error: prefix file absent"
                Usage
   
    exit 1
  fi
}

GetOpts $*

echo "Read file used: $GENOME"
echo "Window size used: $W"
echo "Slide size used: $S"
echo "Prefix used: $SAMPLE"
dict="${GENOME%.*}"

########################

seqtk seq -A $GENOME > input.fa
cat input.fa| grep -c ">" > nseq.txt
fasta="input.fa"
inFasta=$fasta
inW=$W
inS=$S
n=$(<nseq.txt)
#$n=$nseq

## Remove already existing result file
final_name=$(paste -d '_' \
              <(echo 'windows') \
              <(basename $inFasta))
rm -f $final_name

## Separate sequences
echo "> Splitting fasta sequences"
mkdir -p ./fasta_indiv

### Remove alignment formating 
awk '!(NR%2) {gsub("-","")}{print}' $inFasta > ./fasta_indiv/inFasta_format.fasta

### Split sequences
awk '/^>/{close(s); s="fasta_indiv/"++d".fa"} {print > s}' < ./fasta_indiv/inFasta_format.fasta

## Make sliding windows
mkdir -p $SAMPLE

for indiv_f in fasta_indiv/*.fa ;
do
  # Get sequence name
  seqName=$(awk 'NR==1; ORS=""; OFS=""' $indiv_f | sed 'y/>/ /')
  echo ">" $seqName
  
  # Create result file name
  filename=$(paste -d '_' \
              <(echo "$SAMPLE/windows") \
              <(basename $indiv_f))
              
  # Calculate number of windows
  ## Total characters in sequence
  length=$(awk 'FNR == 2' $indiv_f | wc -m)
  ## Calcuate total complete windows
  total=$((($length-$inW)/$inS))

  ## Exit with error if sequence does not create at least 2 windows
  if (( $total < 2 ));
  then
      echo ">>> Sequence is too short to create more than 2 windows using the specified parameters. SequenceID will be stored at short.txt"
      echo $seqName >> $SAMPLE/short.txt
      cat $SAMPLE/short.txt | wc -l| awk '{print "Short sequences:\t"$0}' >> $SAMPLE/stats.txt
      short=$(cat $SAMPLE/short.txt | wc -l)
      continue
  else
      echo ">>> Creating" $total "windows"
  fi
  
  # Create windows
  for i in `seq 1 $total`;
  do
    # Define start and end of window
    start=$((1 + ($i-1)*$inS))
    end=$(($start + $inW -1))

    # Create window name
    nameW=$(paste -d '_' \
              <(echo ">$i") \
              <(echo $seqName) \
              <(echo 'window') \
              <(echo $start) \
              <(echo $end))
            
    echo $nameW >> $filename
    
    # Get window sequence
    awk 'FNR == 2' $indiv_f | \
      awk -v start="$start" -v w="$inW" '{ print substr($1, start, w) }' \
      >> $filename
    
  done
         
done

## Run Nucmer for overlaps
for (( j = 1; j <= $n; j++ ))
  do

nucmer --maxmatch --coords -p $SAMPLE/window_$j $SAMPLE/windows_$j.fa $SAMPLE/windows_$j.fa --nosimplify
more $SAMPLE/window_$j.coords| sed 's/|/\t/g' |grep -v "NUCMER\|TAGS\|=="|cut -f5,6| awk '{if ($1 != $2) print $0}' > $SAMPLE/window_$j.concat
more $SAMPLE/window_$j.coords| sed 's/|/\t/g' |grep -v "NUCMER\|TAGS\|=="|cut -f5,6| awk '{if ($1 != $2) print $0}'|awk -F'\t' 'NR>0{$0=$0"\t"NR-1} 1'| sed 's/_/\t/g'| cut -f2| sort| uniq| awk -v var=$j '{print "window_"var"\t"$0}' >> window_read_ID.txt
more $SAMPLE/window_$j.coords| sed 's/|/\t/g' |grep -v "NUCMER\|TAGS\|=="|cut -f5,6| awk '{if ($1 != $2) print $0}'| wc -l| sed 's/ //g' >> $SAMPLE/concat_count.tab

done

## Parse Results and build Stats file

more $SAMPLE/concat_count.tab | awk -F'\t' 'NR>0{$0=$0"\t"NR-1} 1'| awk '{print "window_"$2+1"\t"$1/2}'| awk '{if ($2 != 0) print $0}' > Concat_Final.tab
#more $SAMPLE/concat_count.tab | awk -F'\t' 'NR>0{$0=$0"\t"NR-1} 1'| awk '{print "window_"$2+1"\t"$1}'| awk '{if ($2 ==0) print $2}'| wc -l| awk '{print "Number of non-concatemer detected: "$0}' >> $SAMPLE/stats.txt 
nconc=$(more $SAMPLE/concat_count.tab | awk -F'\t' 'NR>0{$0=$0"\t"NR-1} 1'| awk '{print "window_"$2+1"\t"$1}'| awk '{if ($2 ==0) print $2}'| wc -l)
count=$(expr $nconc - $short)
echo "Number of non-concatemer detected: "$count >> $SAMPLE/stats.txt
more $SAMPLE/concat_count.tab | awk -F'\t' 'NR>0{$0=$0"\t"NR-1} 1'| awk '{print "window_"$2+1"\t"$1}'| awk '{if ($2 !=0) print $2}'| wc -l| awk '{print "Number of putative concatemer detected: "$0}' >> $SAMPLE/stats.txt
grep -c ">" input.fa | awk '{print "Total number of Reads:\t"$0"\n### putative concatemers ###\nread_number\tread_ID\tself_alignemts"}' >> $SAMPLE/stats.txt
join window_read_ID.txt Concat_Final.tab >> $SAMPLE/stats.txt
join window_read_ID.txt Concat_Final.tab | sed 's/ /\t/g'| cut -f 2 > $SAMPLE/concat_IDs

## Make fastq/fasta  output files

seqtk subseq $GENOME $SAMPLE/concat_IDs > $SAMPLE/Conc.fastq
cat input.fa | grep ">" | sed 's/>//' > in.fasta.readsID
cat $SAMPLE/concat_IDs $SAMPLE/short.txt > $SAMPLE/conc_shortIDs
grep -f  $SAMPLE/conc_shortIDs in.fasta.readsID -v > remaining.list
seqtk subseq $GENOME remaining.list > $SAMPLE/Non_conc.fastq
seqtk subseq $GENOME $SAMPLE/short.txt > $SAMPLE/Short.fastq
mv remaining.list $SAMPLE/non_concatIDs

## Remove intermediate files

rm in.fasta.readsID
rm Concat_Final.tab
rm window_read_ID.txt
rm -R fasta_indiv
rm nucmer.error
rm $SAMPLE/*.delta
rm $SAMPLE/window*.concat
rm $SAMPLE/windows*.fa
rm input.fa
rm nseq.txt
rm $SAMPLE/conc_shortIDs
rm $SAMPLE/concat_count.tab

## Move Alignments to folder

mkdir $SAMPLE/coords
mv $SAMPLE/*.coords $SAMPLE/coords/
echo "> FINISHED!"
echo "Thank you for Running CADECT v0.2.1"
