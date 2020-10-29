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
L1=$1
L2=$2
L1_ISO=$(python -m mtdata.iso $L1 | grep "^$L1" | cut -f2)
L2_ISO=$(python -m mtdata.iso $L2 | grep "^$L2" | cut -f2)

# blacklisted corpora for the test
BLACKLIST=('GNOME' 'KDE4' 'Ubuntu', 'PHP', 'OpenSubtitles')

# Obtain list of available corpora
CORPORA=$(mtdata list -l $L1-$L2 \
    | cut -f 1 \
    | grep -vi 'total\|paracrawl\|opus100' \
    | ./uniq-versions.py)

mkdir -p $DATA/$L1-$L2

# Download corpora
mtdata -c $MTDATA_CACHE get -l $L1-$L2 -tr ${CORPORA[@]} -o $DATA/$L1-$L2

# Download ParaCrawl
wget -nc -O $DATA/$L1-$L2/paracrawlv$PC_VERSION.$L1-$L2.gz "https://s3.amazonaws.com/web-language-models/paracrawl/release$PC_VERSION/$L1-$L2.txt.gz"

# Merge train files
# Keep little corpora for dev/test sets except blacklisted
DEVTEST=()
rm -f $DATA/$L1-$L2/opus.*.gz
for corpus in $CORPORA
do
    if [ "$corpus" == "JW300" ]
    then
        # Detokenize JW300
        mv $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L1_ISO $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L1_ISO.tok
        sacremoses -l $L1 detokenize < $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L1_ISO.tok \
            > $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L1_ISO
        mv $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L2_ISO $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L2_ISO.tok
        sacremoses -l $L2 detokenize < $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L2_ISO.tok \
            > $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L2_ISO
    fi

    # Look for the corpus in the blacklist
    printf '%s\n' "${BLACKLIST[@]}" | grep -q -P "$corpus"
    code=$?
    tokens=$(cat $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.eng | wc -w)
    echo $corpus: $tokens tokens, $code found
    # Always count the english number of tokens
    if [[ $code -gt 0 ]] && [[ $tokens -gt 250000 ]]
    then
        #paste $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L1_ISO $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L2_ISO
        gzip -c $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L1_ISO >> $DATA/$L1-$L2/opus.$L1.gz
        gzip -c $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L2_ISO >> $DATA/$L1-$L2/opus.$L2.gz
    else
        DEVTEST+=($corpus)
    fi
done

# Combine OPUS+ParaCrawl
zcat $DATA/$L1-$L2/paracrawlv$PC_VERSION.$L1-$L2.gz \
    | cut -f1 | gzip \
    | cat $DATA/$L1-$L2/opus.$L1.gz - \
    > $DATA/$L1-$L2/opus-paracrawlv$PC_VERSION.$L1.gz
zcat $DATA/$L1-$L2/paracrawlv$PC_VERSION.$L1-$L2.gz \
    | cut -f2 | gzip \
    | cat $DATA/$L1-$L2/opus.$L2.gz - \
    > $DATA/$L1-$L2/opus-paracrawlv$PC_VERSION.$L2.gz

echo Corpora for dev/test "${DEVTEST[@]}"
echo Creating dev and test sets...

# Separate into dev and test
# Filter-out sentences with les than 4 spaces (words)
MYTEMP=$(mktemp)
for corpus in "${DEVTEST[@]}"
do
    paste $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L1_ISO $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L2_ISO
done | shuf | awk -F ' ' '{if((NF-1) >= 4) print $0}' > $MYTEMP

# Split into dev and test
head -5000 $MYTEMP > $DATA/$L1-$L2/test.$L1-$L2
tail -n +5001 $MYTEMP | head -10000 > $DATA/$L1-$L2/dev.$L1-$L2
# Separate languages
for i in dev test
do
    cut -f1 $DATA/$L1-$L2/$i.$L1-$L2 > $DATA/$L1-$L2/$i.$L1
    cut -f2 $DATA/$L1-$L2/$i.$L1-$L2 > $DATA/$L1-$L2/$i.$L2
    rm $DATA/$L1-$L2/$i.$L1-$L2
done

rm -f $MYTEMP

echo Done
