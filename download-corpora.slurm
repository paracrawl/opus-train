#!/bin/bash
#SBATCH -A T2-CS119-CPU
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=12:00:00
#SBATCH --output=logs/slurm-%x_%j.out

#SBATCH -p skylake

# Set the environment
. /etc/profile.d/modules.sh
module purge
module load rhel7/default-peta4
module load python/3.7
source ./venv/bin/activate

MTDATA_CACHE=.mtdata
DATA=data
PC_VERSION=7.1
TED_SETS=multilingual-ted/paracrawl-v6
L1=$1
L2=$2
L1_ISO=$(python -m mtdata.iso $L1 | grep "^$L1" | cut -f2)
L2_ISO=$(python -m mtdata.iso $L2 | grep "^$L2" | cut -f2)

# blacklisted corpora for the test
BLACKLIST=('GNOME' 'KDE4' 'Ubuntu' 'PHP' 'OpenSubtitles')

# Obtain list of available corpora
CORPORA=$(mtdata list -l $L1-$L2 \
    | cut -f 1 \
    | grep -vi 'total\|paracrawl\|opus100\|opus_qed\|tedtalks\|ted2013' \
    | ./scripts/uniq-versions.py)

mkdir -p $DATA/$L1-$L2
DATA=$DATA/$L1-$L2

# Download corpora
mtdata -c $MTDATA_CACHE get -l $L1-$L2 -tr ${CORPORA[@]} -o $DATA

# Download ParaCrawl
wget -nc -O $DATA/paracrawlv$PC_VERSION.$L1-$L2.gz "https://s3.amazonaws.com/web-language-models/paracrawl/release$PC_VERSION/$L1-$L2.txt.gz"

# Keep little corpora for dev/test sets except blacklisted
DEVTEST=()
TRAIN=()
rm -f $DATA/opus.*.gz
for corpus in $CORPORA
do
    if [ "$corpus" == "JW300" ]
    then
        # Detokenize JW300
        mv $DATA/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L1_ISO $DATA/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L1_ISO.tok
        sacremoses -l $L1 detokenize < $DATA/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L1_ISO.tok \
            > $DATA/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L1_ISO
        mv $DATA/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L2_ISO $DATA/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L2_ISO.tok
        sacremoses -l $L2 detokenize < $DATA/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L2_ISO.tok \
            > $DATA/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L2_ISO
    fi

    # Look for the corpus in the blacklist
    blacklisted="FALSE"
    for b in ${BLACKLIST[@]}; do
        if [[ "$corpus" =~ "$b" ]]; then
            blacklisted="TRUE"
            continue
        fi
    done
    # Always count the english number of tokens
    if [[ "$blacklisted" == "FALSE" ]] && [[ $(cat $DATA/train-parts/$corpus-"$L1_ISO"_$L2_ISO.eng | wc -w) -lt 250000 ]]
    then
        DEVTEST+=($corpus)
    else
        TRAIN+=($corpus)
    fi
done

# Merge dev/test corpora
# Filter-out sentences with les than 4 spaces (words)
MYTEMP=$(mktemp)
for corpus in "${DEVTEST[@]}"
do
    paste $DATA/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L1_ISO $DATA/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L2_ISO
done | shuf | awk -F ' ' '{if((NF-1) >= 4) print $0}' > $MYTEMP

# Merge train files
# remove dev/test sentences
# and save both languages separately
for corpus in "${TRAIN[@]}"
do
    paste $DATA/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L1_ISO $DATA/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L2_ISO
done | ./scripts/overlap.py -r $MYTEMP \
    | tee >(cut -f1 | gzip -c > $DATA/opus.$L1.gz) \
    | cut -f2 | gzip -c > $DATA/opus.$L2.gz

# Combine OPUS+ParaCrawl
zcat $DATA/paracrawlv$PC_VERSION.$L1-$L2.gz \
    | cut -f1 | gzip \
    | cat $DATA/opus.$L1.gz - \
    > $DATA/opus-paracrawlv$PC_VERSION.$L1.gz
zcat $DATA/paracrawlv$PC_VERSION.$L1-$L2.gz \
    | cut -f2 | gzip \
    | cat $DATA/opus.$L2.gz - \
    > $DATA/opus-paracrawlv$PC_VERSION.$L2.gz


echo Corpora for dev/test "${DEVTEST[@]}"
echo Creating dev and test sets...

# Split into dev and test
lines=$(cat $MYTEMP | wc -l)
if [[ $lines -lt 5000 ]]; then
    head -$((lines/2)) $MYTEMP > $DATA/dev.$L1-$L2
    tail -n +$((lines/2+1)) $MYTEMP > $DATA/test-opus.$L1-$L2
elif [[ $lines -lt 10000 ]]; then
    head -5000 $MYTEMP > $DATA/dev.$L1-$L2
    tail -n +5001 $MYTEMP > $DATA/test-opus.$L1-$L2
else
    head -5000 $MYTEMP > $DATA/test-opus.$L1-$L2
    tail -n +5001 $MYTEMP | head -10000 > $DATA/dev.$L1-$L2
fi

# if TED data available
# concatenate dev and create another test
lines=$(cat $TED_SETS/multi-ted-*.$L1-$L2 | wc -l)
if [ "$lines" -gt 3000 ]; then
    echo Multilingual TED dev/test sets available, copying...
    cat $TED_SETS/multi-ted-dev.$L1-$L2 >> $DATA/dev.$L1-$L2
    cp $TED_SETS/multi-ted-test.$L1-$L2 $DATA/test-ted.$L1-$L2
fi

# Separate languages
for i in dev test-opus test-ted
do
    test -s $DATA/$i.$L1-$L2 || continue
    cut -f1 $DATA/$i.$L1-$L2 > $DATA/$i.$L1
    cut -f2 $DATA/$i.$L1-$L2 > $DATA/$i.$L2
    rm $DATA/$i.$L1-$L2
done

rm -f $MYTEMP

echo Done
