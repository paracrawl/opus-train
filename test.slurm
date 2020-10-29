#!/bin/bash
#SBATCH -A T2-CS119-GPU
#SBATCH --nodes=1
#SBATCH --gres=gpu:1
#SBATCH --time=1:00:00

#SBATCH -p pascal

if [ "$1" == "-h" ]
then
    echo "Run test with a model"
    echo "Usage: sbatch [params] `basename $0` <lang1> <lang2> <modelname>"
    echo "modelname must follow the pattern <corpus_train>.<model_config>"
    exit 0
fi

MARIAN=~/rds/rds-t2-cs119/cs-zara1/marian-dev/build
L1=$1
L2=$2
MODELNAME=$3
DECODER_CONFIG=config/decoder.yml
MODELS=models/
DATA=data/$L1-$L2
LOGS=logs/

cat $DATA/test.$L1 \
    | $MARIAN/marian-decoder \
        -m $MODELS/$L1$L2.$MODELNAME.npz.best-ce-mean-words.npz \
        -v $MODELS/vocab.$L1$L2.$MODELNAME.spm $MODELS/vocab.$L1$L2.$MODELNAME.spm \
        -c $DECODER_CONFIG \
        -d $CUDA_VISIBLE_DEVICES \
        -q --log $LOGS/test.$MODELNAME.$L1-$L2.log
    | tee $LOGS/test.$MODELNAME.$L1-$L2.hyp \
    | sacrebleu $DATA/test.$L2 \
    > $LOGS/test.$MODELNAME.$L1-$L2.bleu

