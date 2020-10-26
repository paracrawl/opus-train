#!/bin/bash

OPUS_DIR=opus_dir
DATA=data
L1=en
L2=mt

# blacklisted corpora for the test
BLACKLIST=('GNOME' 'KDE4' 'Ubuntu', 'PHP', 'OpenSubtitles')

# Obtain list of available corpora
CORPORA=$(wget -q -O - "http://opus.nlpl.eu/opusapi/?corpora=True&source=$L1&target=$L2" \
    | jq '.corpora[]' \
    | grep -v ParaCrawl \
    | tr -d '"')

# Download opus corpora in moses format
mkdir -p $OPUS_DIR/$L1-$L2
mkdir -p $DATA/$L1-$L2
for corpus in $CORPORA
do
    if [ "$corpus" == "JW300" ] && [ ! -f $OPUS_DIR/$L1-$L2/$corpus.$L1-$L2.tok ]
    then
        printf "Downloading JW300... "
        # JW300 does not have moses file and comes tokenized
        opus_read -s $L1 -t $L2 \
            -wm moses -d $corpus -dl $OPUS_DIR/$L1-$L2 \
            > $OPUS_DIR/$L1-$L2/$corpus.$L1-$L2.tok
        echo done
    else
        # Get latest version of the corpus
        version=$(wget -O - -q http://opus.nlpl.eu/$corpus/ \
            | grep -o '>v.*/</a>' | grep -o 'v[^/]*' | tail -1)

        # Direct download moses file to avoid doing alignment with opus_tools
        wget --progress=bar -nc -O $OPUS_DIR/$L1-$L2/$corpus.zip "https://object.pouta.csc.fi/OPUS-$corpus/$version/moses/$L1-$L2.txt.zip"
    fi
done

# Download ParaCrawl
wget -nc -O $OPUS_DIR/$L1-$L2/paracrawlv7.$L1-$L2.txt.gz "https://s3.amazonaws.com/web-language-models/paracrawl/release7.1/$L1-$L2.txt.gz"

# Extract Opus files
DEVTEST=()
for corpus in $CORPORA
do
    if [ "$corpus" == "JW300" ]
    then
        # Detokenize JW300
        cut -f 1 $OPUS_DIR/$L1-$L2/JW300.$L1-$L2.tok \
            | sacremoses -l $L1 detokenize \
            > $OPUS_DIR/$L1-$L2/JW300.$L1-$L2.$L1
        cut -f 2 $OPUS_DIR/$L1-$L2/JW300.$L1-$L2.tok \
            | sacremoses -l $L2 detokenize \
            > $OPUS_DIR/$L1-$L2/JW300.$L1-$L2.$L2
    else
        unzip -nd $OPUS_DIR/$L1-$L2 $OPUS_DIR/$L1-$L2/$corpus.zip -x README LICENSE *.xml *.ids
    fi

    # Keep little corpora for dev/test sets except blacklisted
    # Always count the english number of tokens
    #tokens=$(cat $OPUS_DIR/$L1-$L2/$corpus.$L1-$L2.$L1 | wc -w)
    printf '%s\n' "${BLACKLIST[@]}" | grep -q -P "^$corpus$"
    code=$?
    echo $corpus code: $code
    if [[ $code -gt 0 ]] && [[ $(cat $OPUS_DIR/$L1-$L2/$corpus.$L1-$L2.en | wc -w) -gt 250000 ]]
    then
        paste $OPUS_DIR/$L1-$L2/$corpus.$L1-$L2.$L1 $OPUS_DIR/$L1-$L2/$corpus.$L1-$L2.$L2 > $DATA/$L1-$L2/$corpus.$L1-$L2
    else
        DEVTEST+=($corpus)
    fi
done

echo "${DEVTEST[@]}"

# Separate into dev and test
# Filter-out sentences with les than 4 spaces (words)
MYTEMP=$(mktemp)
for corpus in "${DEVTEST[@]}"
do
    paste $OPUS_DIR/$L1-$L2/$corpus.$L1-$L2.$L1 $OPUS_DIR/$L1-$L2/$corpus.$L1-$L2.$L2
done | shuf | awk -F ' ' '{if((NF-1) >= 4) print $0}' > $MYTEMP

# Split into dev and test
head -5000 $MYTEMP > $DATA/$L1-$L2/test.$L1-$L2
tail -n +5001 $MYTEMP | head -10000 > $DATA/$L1-$L2/dev.$L1-$L2

rm -f $MYTEMP
