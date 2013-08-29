#!/bin/sh

function checkout() {
  branch=$1
  echo "*  Checking out $branch"
  git checkout $branch
  if [[ $? -ne 0 ]]; then
    echo "Git checkout of $branch branch failed" 1>&2
    exit 4
  fi
}

function pull() {
  branch=$1
  echo "*  Pulling in remote $branch"
  git pull $branch
  if [[ $? -ne 0 ]]; then
    echo "Git pull of $branch remote failed" 1>&2
    exit 5
  fi
}

function rebase() {
  branch=$1
  echo "*  Rebasing current branch onto $branch"
  git rebase $branch
  if [[ $? -ne 0 ]]; then
    echo "Git rebase to $branch failed" 1>&2
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

# Exit if we do not have a dev branch
git show-ref --verify --quiet refs/heads/dev
if [[ $? -ne 0 ]]; then
  echo "!! The branch dev does not exist. Cannot continue as there is nothing to merge" 1>&2
  exit 2
fi

dev_merge=$(git config --get branch.dev.merge)
dev_remote=$(git config --get branch.dev.remote)
if [ -n "$dev_merge" ]; then
  echo "!! The dev branch is setup to merge with '$dev_merge'. Do not do this. dev must be a local branch non-tracking branch" 1>&2
  exit 3
fi
if [ -n "$dev_remote" ]; then
  echo "!! The dev branch is tracking a remote '$dev_remote'. Do not do this. dev must be a local branch non-tracking branch" 1>&2
  exit 3
fi

# Do the master checkout & pull
checkout 'master'
pull 'origin'

# Switch back to dev and rebase
checkout 'dev'
current_rev=$(git rev-parse HEAD)
rebase 'master'

# Get the user to check the rebase
echo "*  Please take a moment to review your changes."
echo "*  Example cmd: git log --oneline --reverse master..dev"
read -p "*  Press return to continue (ctrl+c to abort)... " -s
result=$?
echo
if [[ $result -ne 0 ]]; then
  echo "!! Process has been abandoned. Please review the changes" 1>&2
  echo "!! You can reset the current changes using the following command (this will re-write your history and ref pointers)" 1>&2
  echo "!! git reset $current_rev" 1>&2
  exit 8
fi

#Now switch back, merge and push
checkout 'master'
merge 'dev'
push

#Go back to dev
checkout 'dev'

echo "*  Finished merge and push"