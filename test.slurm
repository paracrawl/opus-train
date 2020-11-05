#!/bin/bash
#SBATCH -A T2-CS119-GPU
#SBATCH --nodes=1
#SBATCH --gres=gpu:1
#SBATCH --time=1:00:00
#SBATCH --output=logs/slurm-%x_%j.out

#SBATCH -p pascal

if [ "$1" == "-h" ]
then
    echo "Run tests (OPUS and TED) with a model"
    echo "Usage: sbatch [params] `basename $0` <lang1> <lang2> <modelname>"
    echo "modelname must follow the pattern <corpus_train>.<model_config>"
    exit 0
fi

# Set the environment
. /etc/profile.d/modules.sh
module purge
module load rhel7/default-peta4
module load python/3.7
module load cuda/10.1
source ./venv/bin/activate

MARIAN=~/rds/rds-t2-cs119/cs-zara1/marian-dev/build
L1=$1
L2=$2
MODELNAME=$3
DECODER_CONFIG=config/decoder.yml
MODELS=models
LOGS=logs
if [ -d data/$L1-$L2 ]; then
    DATA=data/$L1-$L2
else
    DATA=data/$L2-$L1
fi

for test_set in test-opus test-ted
do
    test -s $DATA/$test_set.$L1 || continue
    cat $DATA/$test_set.$L1 \
        | $MARIAN/marian-decoder \
            -m $MODELS/$L1$L2.$MODELNAME.npz.best-ce-mean-words.npz \
            -v $MODELS/vocab.$L1$L2.$MODELNAME.spm $MODELS/vocab.$L1$L2.$MODELNAME.spm \
            -c $DECODER_CONFIG \
            -d ${CUDA_VISIBLE_DEVICES//,/ } \
            --quiet --log $LOGS/$test_set.$MODELNAME.$L1-$L2.log \
        | tee $LOGS/$test_set.$MODELNAME.$L1-$L2.hyp \
        | sacrebleu $DATA/$test_set.$L2 \
        > $LOGS/$test_set.$MODELNAME.$L1-$L2.bleu
done
