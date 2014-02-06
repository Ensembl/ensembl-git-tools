=head1 LICENSE

Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package EnsEMBL::Git;

use parent qw/Exporter/;
use Carp;
use Cwd;
use File::Spec;

our $DEBUG = 0;

our $JSON = 0;
eval {
  require JSON;
  $JSON = 1;
};

our @EXPORT = qw/
  json
  is_git_repo is_tree_clean is_origin_uptodate is_in_merge
  can_fastforward_merge
  clone checkout checkout_tracking branch pull fetch rebase ff_merge no_ff_merge git_push shallow_clone
  status
  rev_parse branch_exists current_branch
  get_config add_config unset_all_config
  prompt
  system_ok cmd cmd_ok safe_cwd
/;

# Take a path, slurp and convert to a Perl data structure
sub json {
  my ($file) = @_;
  return {} unless -f $file;
  if(!$JSON) {
    printf STDERR "Cannot open '%s' for JSON parsing because we have no JSON module present\n", $file;
    return {};
  }
  local $/ = undef;
  open my $fh, '<', $file or die "Cannot open $file for reading: $!";
  my $contents = <$fh>;
  close $fh;
  
  my $json = JSON->new()->relaxed(1)->decode($contents);
  return $json;
}

# Attempts to figure out if your dir is a Git repo
sub is_git_repo {
  return cmd_ok('git rev-parse');
}

# Looks for files in the working tree and index which are not committed or staged.
# If either is true we will return false that the tree is not clean
sub is_tree_clean {
  # Update the index
  if(! cmd_ok('git update-index -q --ignore-submodules --refresh')) {
    return 0;
  }

  my $error = 0;

  # Make sure we have no unstaged changes in the working tree
  if(! cmd_ok('git diff-files --quiet --ignore-submodules --')) {
    my ($output) = cmd('git diff-files --name-status -r --ignore-submodules --');
    print STDERR "Detected unstaged changes in the working tree. Remove before runnning this command\n";
    print STDERR $output;
    $error = 1;
  }

  # Make sure we have no uncommitted changes in the index
  if(! cmd_ok('git diff-index --cached --quiet HEAD --ignore-submodules --')) {
    my ($output) = cmd('git diff-index --cached --name-status -r --ignore-submodules HEAD --');
    print STDERR "Detected uncommitted changes in the index. Remove before runnning this command\n";
    print STDERR $output;
    $error = 1;
  }

  if($error) {
    print STDERR "Please stash those changes away before rerunning\n";
    return 0;
  }
  return 1;
}

sub is_in_merge {
  my ($git_dir) = cmd('git rev-parse --git-dir');
  chomp $git_dir;
  my $merge_head = File::Spec->catfile($git_dir, 'MERGE_HEAD');
  return (-f $merge_head) ? 1 : 0;
}

# Perform a clone. Local dir will have the same name as the remote minus the organisation and .git stuff
sub clone {
  my ($remote_url, $verbose, $remote) = @_;
  my $v = $verbose ? '--verbose' : q{};
  return system_ok("git clone -o $remote $v $remote_url");
}

# Perform a clone but do not bring everything down
sub shallow_clone {
  my ($remote_url, $verbose, $remote, $depth, $branch) = @_;
  $depth ||= 1;
  my $v = $verbose ? '--verbose' : q{};
  my $b = $branch ? "--branch $branch" : q{};
  my $d = $depth ? "--depth $depth" : q{};
  return system_ok("git clone -o $remote $v $d $b $remote_url");
}

# Attempt to find the given branch locally by looking for its ref. If no ref is found then we have no branch
sub branch_exists {
  my ($branch, $remote) = @_;
  my $ref_loc = $remote ? 'remotes/'.$remote : 'heads';
  return cmd_ok("git show-ref --verify --quiet refs/${ref_loc}/${branch}");
}

# Attempt to find the given tag
sub tag_exists {
  my ($tag) = @_;
  return cmd_ok("git show-ref --verify --quiet refs/tags/${tag}");
}

# Runs a pull on whatever is the current branch (which means fetch & merge)
sub pull {
  my ($remote, $verbose) = @_;
  $remote ||= 'origin';
  my $v = $verbose ? '--verbose' : q{};
  return system_ok("git pull $v $remote");
}

# Push to the specified remote
sub git_push {
  my ($remote, $branch, $verbose) = @_;
  $remote ||= 'origin';
  die "No branch given" unless $branch;
  my $v = $verbose ? '--verbose' : q{};
  return system_ok("git push $v $remote $branch");
}

# Runs a fetch on origin but unlike pull will not do the merge
sub fetch {
  my ($fetch_tags, $verbose, $remote) = @_;
  my $v = $verbose ? '--verbose' : q{};
  my $tags = ($fetch_tags) ? '--tags' : q{};
  $remote ||= 'origin';
  return system_ok("git fetch $v $tags $remote");
}

# Rebases against the given branch
sub rebase {
  my ($branch, $continue) = @_;
  die "No branch given" unless $branch;
  if ($continue) {
    return system_ok("git rebase --continue");
  } else {
    return system_ok("git rebase $branch");
  }
}

sub ff_merge {
  my ($branch) = @_;
  return system_ok("git merge --ff-only $branch");
}

sub no_ff_merge($$) {
  my ($branch, $message) = @_;
  return system_ok(qq/git merge --no-ff --log -m '$message' ${branch}/);
}

sub status {
  return system_ok('git status');
}

# Get a config value out
sub get_config {
  my ($config) = @_;
  my ($output) = cmd("git config --get $config");
  chomp $output;
  return $output;
}

# Unset all config variables
sub unset_all_config {
  my ($config) = @_;
  return system_ok("git config --local --unset-all '${config}'");
}

# Add a config variable
sub add_config {
  my ($config, $value) = @_;
  return system_ok("git config --local --add '${config}' '${value}'");
}

# Convert a ref symbol into a SHA-1 hash
sub rev_parse {
  my ($rev, $short) = @_;
  die "No rev given" unless $rev;
  my $short_arg = $short ? '--short' : q{};
  my ($output) = cmd("git rev-parse --verify $short_arg $rev");
  chomp $output;
  return $output;
}

# Returns the name of the current branch
sub current_branch {
  my ($output) = cmd('git rev-parse --abbrev-ref HEAD');
  chomp $output;
  return $output;
}

# See if the given branch is up to date in comparison with origin.
# We request both refs SHA-1 codes and compare. If they are the 
# same they will have the same hash
sub is_origin_uptodate {
  my ($branch, $remote) = @_;
  die "No branch given" unless $branch;
  $remote ||= 'origin';
  fetch(undef, undef, $remote);
  my $local_hash  = rev_parse($branch);
  my $remote_hash = rev_parse("$remote/$branch");
  return ($local_hash eq $remote_hash) ? 1 : 0;
}

# See if the remote's branch can be fast-forwarded onto the local
# tracking branch. This is done by taking the remote branch hash
# and see if this is the same as the merge-point of local and remote
sub can_fastforward_merge {
  my ($branch, $remote) = @_;
  die "No branch given" unless $branch;
  $remote ||= 'origin';
  fetch(undef, undef, $remote);
  my $remote_hash = rev_parse("$remote/$branch");
  my ($output) = cmd("git merge-base $remote/$branch $branch");
  chomp $output;
  return ($remote_hash eq $output) ? 1 : 0;
}

# Attempt to checkout a tracking branch. If the branch already exists locally
# we will switch to that one (and assume the other branch is tracking)
sub checkout_tracking {
  my ($branch, $remote, $verbose, $secondary_branch) = @_;
  die "No branch given" unless $branch;
  $remote ||= 'origin';
  
  my $args;
  if(branch_exists($branch)) {
    if(current_branch() eq $branch) {
      print "* Skipping checkout as we are already on $branch\n";
      return 1;
    }
    $args = $branch;
  }
  else {
    if(! branch_exists($branch, $remote)) {
      # If both branch and secondary_branch do not exist then let's bail
      if(! branch_exists($secondary_branch, $remote)) {
        print STDERR "No branch exists on ${remote}/${branch} or ${remote}/${secondary_branch}. Cannot checkout\n";
        return 0;
      }
      #If the secondary branch exists just switch to it
      if(branch_exists($secondary_branch)) {
        if(current_branch() eq $secondary_branch) {
          print "* Skipping checkout as we are already on $secondary_branch\n";
          return 1;
        }
        $args = "$secondary_branch";
      }
      else {
        # Well if the branch didn't exist use the secondary
        $args = "--track -b ${secondary_branch} $remote/${secondary_branch}";
      }
    }
    else {
      # Use the normal branch
      $args = "--track -b ${branch} $remote/${branch}";
    }
  }
  my ($output, $exitcode) = cmd("git checkout $args");
  if($verbose) {
    print $output; 
  }
  if($exitcode) {
    print STDERR 
      "Could not switch $GIT_DIR to branch '${branch}' using options ${args}.\n", 
      'Command output:', "\n",
      $output,"\n";
    return 0;
  }

  return 1;
}

# Switches a branch
sub checkout {
  my ($branch, $verbose) = @_;
  die "No branch given" unless $branch;
  my $v = $verbose ? q{} : q{--quiet};
  return system_ok("git checkout $v $branch");
}

# Creates a branch from the current working point. You can specify a branch point as well
sub branch {
  my ($branch, $verbose, $branchpoint) = @_;
  die "No branch given" unless $branch;
  my $v = $verbose ? q{--verbose} : q{};
  $branchpoint ||= q{};
  return system_ok("git branch $v $branch $branchpoint");
}

# Perform a system call which means no capture. We will return if the process successfuly completed
sub system_ok {
  my ($cmd) = @_;
  warn $cmd if $DEBUG;
  system($cmd);
  my $exitcode = $? >> 8;
  return ($exitcode == 0) ? 1 : 0;
}

# Runs a command and captures its output. Provides two vars; the output and exit code
sub cmd {
  my ($cmd) = @_;
  warn $cmd if $DEBUG;
  my $output = `$cmd 2>&1`;
  my $exitcode = $? >> 8;
  return ($output, $exitcode);
}

# Runs a command and inspects the exit code. 0 exit statuses from cmd() will
# cause this command to reutrn true
sub cmd_ok {
  my ($cmd) = @_;
  my ($output, $exitcode) = cmd($cmd);
  return $exitcode == 0 ? 1 : 0;
}

# Done to cd to a target dir, run some code and then go back
sub safe_cwd {
  my ($dir, $callback) = @_;
  confess "No dir given" unless $dir && -d $dir;
  my $cwd = cwd();
  chdir $dir;
  $callback->();
  chdir $cwd;
}

# Prompt the user for confirmation
sub prompt {
  print '* OK to continue? (y/N)... ';
  my $in = <STDIN>;
  chomp $in;
  if($in =~ /y(es)?/i) {
    return 1;
  }
  return 0;
}

1;
