#!/bin/sh

############################################################
### Git to CVS exporter code based on a project available on
### GitHub orignially developed by Klaus Purer. Code will
###
### - Get the current Git directory
### - Pull from origin (or whatever is your default remote) on
###   your current branch
### - Check the $CVSDIR/.cvslastexport file for the last 
###   REF to be committed to CVS
### - If a REF is available everything from that REF to HEAD
###   is pushed
### - If no REF is available then die; all Ensembl repositories
###   exist in CVS
### - Commit into CVS assuming no errors
###
### Forked version is available from 
### https://github.com/andrewyatz/git-cvs-export
### (done to avoid possible repo deletion).
############################################################

clean_up() {
  #cvs -d /srv/cvs/drupal up -C $GITSRV/$MODULE_BASE/$MODULE/ > /dev/null
  rm $CVS_DIR/.msg $CVSDIR/.cvsexportcommit.diff
  find $CVS_DIR -name '.#*' -exec rm '{}' \;
  echo "** CVS commit failed. Cleaning up cvs directory... **"
  exit 2
}

readlink_cross() {
  RL_TARGET_FILE=$1

  cd `dirname $RL_TARGET_FILE`
  RL_TARGET_FILE=`basename $RL_TARGET_FILE`

  # Iterate down a (possible) chain of symlinks
  while [ -L "$RL_TARGET_FILE" ]; do
    RL_TARGET_FILE=`readlink $RL_TARGET_FILE`
    cd `dirname $RL_TARGET_FILE`
    RL_TARGET_FILE=`basename $RL_TARGET_FILE`
  done

  # Compute the canonicalized name by finding the physical path 
  # for the directory we're in and appending the target file.
  RL_PHYS_DIR=`pwd -P`
  RL_RESULT=$RL_PHYS_DIR/$RL_TARGET_FILE
}

COMMIT_ARG=''
# COMMIT_ARG='-c'

if [ $# -lt 2 ]
then
  echo "Usage: $0 <git dir source> <CVS dir destination> <Git branch> <CVS branch>"
fi

# git and CVS source directories
GIT_DIR=$1
CVS_DIR=$2

#Get Git branch
GIT_BRANCH=$3
if [ -z "$GIT_BRANCH" ]; then
  GIT_BRANCH='master'
fi

#Get CVS branch
CVS_BRANCH=$4
if [ -z "$CVS_BRANCH" ]; then
  CVS_BRANCH='HEAD'
fi

# Canonicalisation of the paths cross platform style
readlink_cross $GIT_DIR
GIT_DIR=$RL_RESULT
readlink_cross $CVS_DIR
CVS_DIR=$RL_RESULT

# file to keep last successfully exported commit ID
LAST_EXPORT_CFG_VAR='cvsexportcommit.ens.lastexport'

# switch to git dir
cd $GIT_DIR

# Make sure we where called correctly.
CURRENT_GIT="$(git rev-parse --git-dir 2>/dev/null)" || exit 4 "** First argument must be a git repository **"

# pull
git pull -q
if [ $? -ne 0 ]
then
 echo "** git pull failed **"
 exit 1
fi

# get new commit IDs
LAST_EXPORTED=$(git config --local --get --null $LAST_EXPORT_CFG_VAR)
if [ -z "$LAST_EXPORTED" ]; then
  echo "** No $LAST_EXPORT_CFG_VAR found in local config. Have you ever pushed this before? Aborting"
  echo "** To populate run: git config --local --add $LAST_EXPORT_CFG_VAR VAR"
  exit 3
else
  refs_exists=$(git branch -r -q --contains $LAST_EXPORTED 2>&1)
  if [[ $? != 0 ]]; then
    echo "** The ref we were going to use $LAST_EXPORTED is not on this branch. Please set to something sensible"
    echo "** To remove run: git config --local --unset $LAST_EXPORT_CFG_VAR"
    echo "** To populate run: git config --local --add $LAST_EXPORT_CFG_VAR VAR"
    exit 4
  fi
  NEW_COMMITS=$(git rev-list $LAST_EXPORTED..HEAD | awk '{print NR,$0}' | sort -nr | sed 's/^[0-9]* //')
fi

for COMMIT in $NEW_COMMITS; do
  echo '** Exporting $COMMIT commit to CVS: **'
  git cvsexportcommit -a -p $COMMIT_ARG $CVS_DIR $COMMIT || clean_up
  # save successful exported commit to local Git config
  git config --local --unset $LAST_EXPORT_CFG_VAR
  git config --local --add $LAST_EXPORT_CFG_VAR $COMMIT
done
