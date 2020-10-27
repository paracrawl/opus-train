# opus-train
This is a set of scripts to ease automation of downloading and training NMT models.

## Installation
```bash
module load python/3.7
python3.7 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

### Compile Marian (optional)
By default training script points to a compiled marian on `~/rds/rds-t2-cs119/cs-zara1/marian-dev/build` version 1.9.0, so you don't need to compile it.
If you want to compile your own Marian, place this into your `.bashrc` on a `login-gpu` node:
```
# User specific aliases and functions
#Upgrade to CUDA 9.2 (the default is 8.0)
module switch cuda/8.0 cuda/10.1
#Upgrade to a newer cmake
module add cmake-3.12.3-gcc-5.4.0-rgjxm2x
#Add MPI support for multi-node training
module add openmpi-2.1.1-gcc-5.4.0-wtt3gne
#Makes CPU version of Marian compile correctly.
module add intel/mkl/2019.3
#Set your compiler to optimize by default
export CFLAGS="-O3 -march=native -pipe"
export CXXFLAGS="-O3 -march=native -pipe"
#tcmalloc makes Marian faster
export INCLUDE=/home/cs-zara1/rds/rds-t2-cs119/cs-zara1/perftools/include${INCLUDE:+:$INCLUDE}
export LIB=/home/cs-zara1/rds/rds-t2-cs119/cs-zara1/perftools/lib${LIB:+:$LIB}
export CPATH=/home/cs-zara1/rds/rds-t2-cs119/cs-zara1/perftools/include${CPATH:+:$CPATH}
export LIBRARY_PATH=/home/cs-zara1/rds/rds-t2-cs119/cs-zara1/perftools/lib${LIBRARY_PATH:+:$LIBRARY_PATH}
export LD_LIBRARY_PATH=/home/cs-zara1/rds/rds-t2-cs119/cs-zara1/perftools/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
#If you want to compile Marian with SentencePiece (-DUSE_SENTENCEPIECE=on)
module add protobuf-3.4.0-gcc-5.4.0-zkpendv
```
and build (marian is included as submodule)
```
cd marian-dev
git submodule update --init
mkdir build
cd build
cmake .. -DUSE_SENTENCEPIECE=ON
make -j24
```

## Download corpora

```bash
sbatch -J download-mt download.slurm en mt
```

**IMPORTANT**: for downloading use always ParaCrawl convention for source-target. For example: `en ??` or `es ??`.
Otherwise it won't find ParaCrawl files.
After downloading, languages are kept in separated files to allow training in both directions easily.

## Training models

```bash
sbatch -J train-mt train.sh mt en
```
