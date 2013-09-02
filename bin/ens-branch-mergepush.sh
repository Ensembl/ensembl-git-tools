#!/bin/sh

usage(){
	echo "Usage: $0 -s [source_branch] -t [target_branch] -n[opush]"
	echo "  * -s = source_branch. Defaults to dev. Cannot be a remote tracking branch"
	echo "  * -t = target_branch. Defaults to master"
	echo "  * -n = nopush. Stop any attempt at pushing to a master server"
}

# following functiontaken from 
# http://stackoverflow.com/questions/3878624/how-do-i-programmatically-determine-if-there-are-uncommited-changes
function require_clean_work_tree () {
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

function branch_exists() {
  testing_branch=$1
  git show-ref --verify --quiet refs/heads/$testing_branch
  if [[ $? -ne 0 ]]; then
    echo "!! The branch $testing_branch does not exist. Cannot continue as there is nothing to merge" 1>&2
    exit 2
  fi
}

function checkout() {
  branch=$1
  echo "*  Checking out $branch"
  git checkout $branch
  if [[ $? -ne 0 ]]; then
    echo "!! Git checkout of $branch branch failed" 1>&2
    exit 4
  fi
}

function pull() {
  branch=$1
  echo "*  Pulling in remote $branch"
  git pull $branch
  if [[ $? -ne 0 ]]; then
    echo "!! Git pull of $branch remote failed" 1>&2
    exit 5
  fi
}

function rebase() {
  branch=$1
  echo "*  Rebasing current branch onto $branch"
  git rebase $branch
  if [[ $? -ne 0 ]]; then
    echo "!! Git rebase to $branch failed" 1>&2
    echo "!! This is probably due to merge conflicts" 1>&2
    echo "!! Resolve the conflicts, run 'git rebase --continue' and rerun this command" 1>&2
    exit 5
  fi
}

function merge() {
  branch=$1
  echo "*  Merge current branch with $branch"
  git merge --ff-only $branch
  if [[ $? -ne 0 ]]; then
    echo "Git merge with $branch failed" 1>&2
    exit 6
  fi
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

function push() {
  echo "*  Pushing to origin"
  git push
  if [[ $? -ne 0 ]]; then
    echo "Git push to origin failed" 1>&2
    exit 7
  fi
}

# Exit if the repo is not under git control
git rev-parse
if [[ $? -ne 0 ]]; then
  echo "!! Current directory is not under git control. Exiting" 1>&2
  exit 1
fi

source_branch='dev'
target_branch='master'
while getopts ":s:t:nh" opt; do
  case $opt in
    s)
      source_branch=$OPTARG
      ;;
    t)
      target_branch=$OPTARG
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

if [ -z "$NO_PROMPT" ]; then
  echo "* Source branch is '$source_branch'"
  echo "* Target branch is '$target_branch'"
  read -p "* Press return to continue (ctrl+c to abort)... " -s
  echo
fi

# Exit if we do not have a source/target branch
branch_exists $source_branch
branch_exists $target_branch

branch_merge=$(git config --get branch.$source_branch.merge)
branch_remote=$(git config --get branch.$source_branch.remote)
if [ -n "$branch_merge" ]; then
  echo "!! The $source_branch branch is setup to merge with '$branch_merge'. Do not do this. dev must be a local branch non-tracking branch" 1>&2
  exit 3
fi
if [ -n "$branch_remote" ]; then
  echo "!! The $source_branch branch is tracking a remote '$branch_remote'. Do not do this. dev must be a local branch non-tracking branch" 1>&2
  exit 3
fi

# Do the target branch (most likely "master") checkout & pull
checkout $target_branch
pull 'origin'

# Switch back to branch and rebase. Rebase can fail due to merge conflicts
checkout $source_branch
require_clean_work_tree 'rebase'
current_rev=$(git rev-parse HEAD)
rebase $target_branch

# Get the user to check the rebase
if [ -z "$NO_PROMPT" ]; then
  echo "*  Please take a moment to review your changes."
  echo "*  Example cmd: git log --oneline --reverse ${target_branch}..${source_branch}"
  read -p "*  Press return to continue (ctrl+c to abort)... " -s
  result=$?
  echo
  if [[ $result -ne 0 ]]; then
    echo "!! Process has been abandoned. Please review the changes" 1>&2
    echo "!! You can reset the current changes using the following command (this will re-write your history and ref pointers)" 1>&2
    echo "!! git reset $current_rev" 1>&2
    exit 8
  fi
fi

#Now switch back, merge and push
checkout $target_branch
uptodate_check $target_branch
merge $source_branch

if [ -z "$NO_PROMPT" ]; then
  echo "* About to push to origin"
  read -p "* Press return to continue (ctrl+c to abort)... " -s
  echo
fi

push

#Go back to target branch
checkout $source_branch

echo "*  Finished merge and push"