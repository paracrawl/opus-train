#!/bin/bash

MTDATA_CACHE=.mtdata
DATA=data
PC_VERSION=7.1
L1=en
L2=mt
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
    printf '%s\n' "${BLACKLIST[@]}" | grep -q -P "^$corpus$"
    code=$?
    # Always count the english number of tokens
    if [[ $code -gt 0 ]] && [[ $(cat $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.eng | wc -w) -gt 250000 ]]
    then
        paste $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L1_ISO $DATA/$L1-$L2/train-parts/$corpus-"$L1_ISO"_$L2_ISO.$L2_ISO
    else
        DEVTEST+=($corpus)
    fi
done | gzip > $DATA/$L1-$L2/opus.$L1-$L2.gz

# Combine OPUS+ParaCrawl
cat $DATA/$L1-$L2/opus.$L1-$L2.gz $DATA/$L1-$L2/paracrawlv$PC_VERSION.$L1-$L2.gz \
    > $DATA/$L1-$L2/opus-paracrawlv$PC_VERSION.$L1-$L2.gz

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

rm -f $MYTEMP

echo Done
