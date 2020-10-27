#!/bin/bash
#SBATCH -A T2-CS119-GPU
#SBATCH --nodes=1
#SBATCH --gres=gpu:4
#SBATCH --array=1-7%1
#SBATCH --time=24:00:00

#SBATCH -p pascal

MARIAN=~/rds/rds-t2-cs119/cs-zara1/marian-dev/build
L1=$1
L2=$2
CORPUS=opus
CONFIG=config/transformer-base.yml
MODELS=models/
DATA=data/$L1-$L2
LOGS=logs/

MODELNAME=$CORPUS.`basename ${CONFIG%.yml}`

$MARIAN/marian \
    -m $MODELS/$L1$L2.$MODELNAME.npz \
    -v $MODELS/vocab.$L1$L2.spm $MODELS/vocab.$L1$L2.spm \
    -t $DATA/$CORPUS.$L1.gz $DATA/$CORPUS.$L2.gz\
    --valid-sets $DATA/dev.$L1 $DATA/dev.$L2 \
    -c $CONFIG \
    -d $CUDA_VISIBLE_DEVICES \
    --log $LOGS/train.$MODELNAME.log --valid-log $LOGS/valid.$MODELNAME.log

