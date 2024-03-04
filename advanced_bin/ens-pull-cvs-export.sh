#!/bin/bash
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2024] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


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

# set -x

# config var base to keep last successfully exported commit ID
LAST_EXPORT_CFG_VAR='cvsexportcommit.ens.lastexport'

# Number of commits to scan back through before we give up automatically detecting the right version
MAX_COMMITS_BACK=10
COMMIT_ARG=''
# COMMIT_ARG='-c'

usage(){
  echo "Usage: $0 -g[it_dir] [git dir] -c[vs_dir] [cvs dir] -C[commit] -l[ist configs] -u[nset configs]"
  echo "  * -g = git directory. The directory to use as the source of patches for CVS"
  echo "  * -c = CVS directory. CVS sandbox to push commits into"
  echo "  * -C = Commit any changes to CVS"
  echo "  * -l = List configs. List every configuration in the current config with the prefix ${LAST_EXPORT_CFG_VAR}"
  echo "  * -u = Unset configs. Remove every configuration in the current config with the prefix ${LAST_EXPORT_CFG_VAR}"
}

# following functiontaken from 
# http://stackoverflow.com/questions/3878624/how-do-i-programmatically-determine-if-there-are-uncommited-changes
require_clean_work_tree () {
  # Update the index
  git update-index -q --ignore-submodules --refresh
  err=0

  # Disallow unstaged changes in the working tree
  if ! git diff-files --quiet --ignore-submodules --; then
    echo >&2 "!! Cannot $1: you have unstaged changes."
    git diff-files --name-status -r --ignore-submodules -- >&2
    err=1
  fi

  # Disallow uncommitted changes in the index
  if ! git diff-index --cached --quiet HEAD --ignore-submodules --;  then
    echo >&2 "!! Cannot $1: your index contains uncommitted changes."
    git diff-index --cached --name-status -r --ignore-submodules HEAD -- >&2
    err=1
  fi

  if [ $err = 1 ]; then
    echo >&2 "!! Please commit/stash them and retry this command"
    exit 1
  fi
}

# Exit if the repo is not under git control
git_ok() {
  pushd $GIT_DIR > /dev/null
  git rev-parse
  if [[ $? -ne 0 ]]; then
    echo "!! Current directory is not under git control. Exiting" 1>&2
    exit 1
  fi
  require_clean_work_tree
  popd > /dev/null
}

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

detect_cvs_branch() {
  pushd $CVS_DIR > /dev/null
  CVS_BRANCH='HEAD'
  for f in $(find $PWD -type f -maxdepth 1); do
    base=$(basename $f)
    status=$(cvs -Q status $base | grep 'Status:' | perl -ne '$_ =~ /Status: ([-a-z]+)/i; print $1, "\n";' )
    if [[ "$status" == 'Up-to-date' ]]; then
      sticky_tag=$(cvs status $base | grep 'Sticky Tag:' | perl -ne '$_ =~ /Sticky tag:\s+([-a-z0-9_()]+)/i; print $1, "\n";')
      if [[ "$sticky_tag" != '(none)' ]]; then
        CVS_BRANCH=$sticky_tag
      fi
    fi
  done
  popd > /dev/null
}

list_all_config() {
  git config --get-regexp $LAST_EXPORT_CFG_VAR
}

unset_all_config() {
  for c in $(git config --get-regexp $LAST_EXPORT_CFG_VAR | cut -d ' ' -f 1); do
    git config --unset-all $c
  done
}

function uptodate_check() {
  branch=$1
  echo "*  Checking that $branch is at the same rev as origin/$branch"
  git fetch origin
  local_hash=$(git rev-parse $branch)
  remote_hash=$(git rev-parse origin/$branch)
  if [[ "$local_hash" != "$remote_hash" ]]; then
    echo "Git local ($local_hash) and remote ($remote_hash) are not the same" 1>&2
    echo "Rerun this script to rebase to the new remote $branch HEAD" 1>&2
    exit 6
  fi
}

# git and CVS source directories
GIT_DIR=''
CVS_DIR=''
list_configs=''
unset_configs=''

# Parse options
while getopts ":g:c:luhC" opt; do
  case $opt in
    g)
      GIT_DIR=$OPTARG
      # Canonicalisation of the paths cross platform style
      readlink_cross $GIT_DIR
      GIT_DIR=$RL_RESULT
      ;;
    c)
      CVS_DIR=$OPTARG
      # Canonicalisation of the paths cross platform style
      readlink_cross $CVS_DIR
      CVS_DIR=$RL_RESULT
      ;;
    l)
      list_configs='1'
      ;;
    u)
      unset_configs='1'
      ;;
    C)
      COMMIT_ARG='-c'
      echo "* Committing is on"
      ;;
    h)
      usage
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      usage
      exit 1
      ;;
  esac
done

# Checking the Git configs are OK
if [ -z "$GIT_DIR" ]; then
  echo "No GIT_DIR was given" >&2
  usage
  exit 1
fi
if [ ! -d "$GIT_DIR" ]; then
  echo "No GIT_DIR was found" >&2
  usage
  exit 1
fi

# Check the git dir is OK and the current work tree is clean
git_ok

# switch to git dir
pushd $GIT_DIR > /dev/null

# do any actions not requiring CVS
if [ -n "$list_configs" ]; then
  list_all_config
  exit 0
fi

if [ -n "$unset_configs" ]; then
  unset_all_config
  exit 0
fi

# Finish checking for CVS
if [ -z "$CVS_DIR" ]; then
  echo "No CVS_DIR was given" >&2
  usage
  exit 1
fi
if [ ! -d "$CVS_DIR" ]; then
  echo "No CVS_DIR was found" >&2
  usage
  exit 1
fi

# Make sure we where called correctly.
# CURRENT_GIT="$(git rev-parse --git-dir 2>/dev/null)" || exit 4 "** First argument must be a git repository **"

# Get the CVS branch and Git branch
detect_cvs_branch
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Ask if this is OK
echo "* Git branch is '$GIT_BRANCH'"
echo "* CVS branch is '$CVS_BRANCH'"
if [ -z "$NO_PROMPT" ]; then
  read -p "* Is this correct? Press return to continue (ctrl+c to abort)... " -s
  echo
fi

LAST_EXPORT_VAR="${LAST_EXPORT_CFG_VAR}.${CVS_BRANCH}"

# do a fetch and check we are upto date
git fetch origin
uptodate_check $GIT_BRANCH

# Get last exported
LAST_EXPORTED=$(git config --local --get --null $LAST_EXPORT_VAR)
if [ -z "$LAST_EXPORTED" ]; then
  echo "* No last exported config var found. Running scan"
  # diff CVS to Git. If HEAD Git isn't good then go back and try the last 5 commits
  # to find a last commit
  
  for i in $(seq 0 $MAX_COMMITS_BACK); do
    echo -n "*   Checking HEAD@{$i} for equality"
    git checkout -f -q HEAD@{$i}
    diff_output=$(diff -xCVS -x.git -x.DS_Store -ru $CVS_DIR $GIT_DIR)
    if [ $? -eq 0 ]; then
      # Add the current hash as the new tag
      echo '  .. Yes'
      git config --add "${LAST_EXPORT_CFG_VAR}.${CVS_BRANCH}" $(git rev-parse HEAD)
      break
    else
      echo '  .. No'
    fi
  done
  # Back to our starting branch
  git checkout -q $GIT_BRANCH
fi

# get new commit IDs
LAST_EXPORTED=$(git config --local --get --null $LAST_EXPORT_VAR)

NEW_COMMITS=''
if [ -z "$LAST_EXPORTED" ]; then
  echo "Cannot detect the last time $CVS_DIR and $GIT_DIR were identical" >&2
  echo "No $LAST_EXPORT_CFG_VAR found in local config. Have you ever pushed this before? Aborting" >&2
  echo "To populate run: git config --local --add $LAST_EXPORT_VAR HASH" >&2
  exit 3
else
  #First set the LAST_EXPORTED to the full hash. If we could not do this then the given ref is bogus
  LAST_EXPORTED=$(git rev-parse $LAST_EXPORTED)
  if [[ $? != 0 ]]; then
    echo "The ref we were going to use $LAST_EXPORTED is unknown to this repository. Please check your current value" >&2
    echo "To remove run: git config --local --unset $LAST_EXPORT_VAR" >&2
    echo "To populate run: git config --local --add $LAST_EXPORT_VAR VAR" >&2
    exit 4
  fi
  
  #No need to check if the LAST_EXPORTED is currently the same as HEAD as HEAD..HEAD gives us nothing
  #We also use --first-parent. Makes us follow only the first parent commit upon seeing a merge commit
  #Also reverse the commits so we process the eldest first
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
    git config --local --unset-all $LAST_EXPORT_VAR
    git config --local --add $LAST_EXPORT_VAR $COMMIT
    #Last exported commit is now this one
    LAST_EXPORTED=$COMMIT
  else
    #Quick hack. We just run the commits through & do not overwrite a thing.
    #CVS & cvsexportcommit could get grumpy about this
    if [ -f $CVS_DIR/.msg ]; then 
      # If commit was off then we can only apply 1 commit
      echo "** Commit is not on. Only applying 1 commit"
      break
    fi
    LAST_EXPORTED=$COMMIT
  fi
done
