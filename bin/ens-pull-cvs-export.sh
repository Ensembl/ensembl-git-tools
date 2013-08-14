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

############################################################
### When merging branches into master you must always have
### a parent commit. cvsexportcommit will perform a diff 
### against the parent.
###
### *THIS DOES NOT HAPPEN IF YOU ALLOWS FAST FORWARD MERGES*
###
### The correct commant to use is:
###
###   git checkout master
###   git merge --no-ff --log -m 'OPTIONAL MESSAGE' topic_branch 
###
### We also recommend bundling as much into a branch before
### merging and remembering we can keep code in Git for as
### long as possible. We should only CVS merge if we need
### code available to the public.
###
############################################################

clean_up() {
  rm $CVS_DIR/.msg $CVS_DIR/.cvsexportcommit.diff
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

# COMMIT_ARG=''
COMMIT_ARG='-c'

if [ $# -ne 2 ]; then
  echo "Usage: $0 <git dir source> <CVS dir destination>"
  exit 1
fi

# git and CVS source directories
GIT_DIR=$1
CVS_DIR=$2

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
NEW_COMMITS=''
if [ -z "$LAST_EXPORTED" ]; then
  echo "** No $LAST_EXPORT_CFG_VAR found in local config. Have you ever pushed this before? Aborting"
  echo "** To populate run: git config --local --add $LAST_EXPORT_CFG_VAR VAR"
  exit 3
else
  #First set the LAST_EXPORTED to the full hash. If we could not do this then the given ref is bogus
  LAST_EXPORTED=$(git rev-parse $LAST_EXPORTED)
  if [[ $? != 0 ]]; then
    echo "** The ref we were going to use $LAST_EXPORTED is unknown to this repository. Please check your current value"
    echo "** To remove run: git config --local --unset $LAST_EXPORT_CFG_VAR"
    echo "** To populate run: git config --local --add $LAST_EXPORT_CFG_VAR VAR"
    exit 4
  fi
  
  #No need to check if the LAST_EXPORTED is currently the same as HEAD as HEAD..HEAD gives us nothing
  #We also use --first-parent. Makes us follow only the first parent commit upon seeing a merge commit
  #Also reverse the commits
  NEW_COMMITS=$(git rev-list --first-parent $LAST_EXPORTED..HEAD 2>/dev/null | awk '{print NR,$0}' | sort -nr | sed 's/^[0-9]* //')
fi

if [ -z "$NEW_COMMITS" ]; then
  echo "** Finishing as there is nothing to export. We looked for git rev-list $LAST_EXPORTED..HEAD"
  exit 0
fi

for COMMIT in $NEW_COMMITS; do
  echo "** Exporting $COMMIT commit to CVS. Using $LAST_EXPORTED as our root"
  git cvsexportcommit -a -p $COMMIT_ARG -w $CVS_DIR $LAST_EXPORTED $COMMIT || clean_up
  # save successful exported commit to local Git config
  if [ -n "$COMMIT_ARG" ]; then
    git config --local --unset-all $LAST_EXPORT_CFG_VAR
    git config --local --add $LAST_EXPORT_CFG_VAR $COMMIT
    #Last exported commit is now this one
    LAST_EXPORTED=$COMMIT
  else
    #Quick hack. We just run the commits through & do not overwrite a thing.
    #CVS & cvsexportcommit could get grumpy about this
    if [ -f $CVS_DIR/.msg ]; then 
      rm $CVS_DIR/.msg
    fi
    LAST_EXPORTED=$COMMIT
  fi
done
