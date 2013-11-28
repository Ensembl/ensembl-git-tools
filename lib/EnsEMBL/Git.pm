package EnsEMBL::Git;

use parent qw/Exporter/;

our $JSON = 0;
BEGIN {
  eval {
    require JSON;
    $JSON = 1;
  };
}

our @EXPORT = qw/
  json
  is_git_repo is_tree_clean is_origin_uptodate
  clone checkout checkout_tracking pull fetch rebase ff_merge git_push
  rev_parse branch_exists
  get_config add_config unset_all_config
  prompt
/;

# Take a path, slurp and convert to a Perl data structure
sub json {
  my ($file) = @_;
  return {} unless -f $file;
  if(!$JSON) {
    printf STDERR "Cannot open '%s' for JSON parsing because we have no JSON module present\n";
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

# Perform a clone. Local dir will have the same name as the remote minus the organisation and .git stuff
sub clone {
  my ($remote, $verbose) = @_;
  my $v = $verbose ? '--verbose' : q{};
  return system_ok("git clone $v $remote");
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
  my ($remote, $verbose) = @_;
  $remote ||= 'origin';
  my $v = $verbose ? '--verbose' : q{};
  return system_ok("git push $v $remote");
}

# Runs a fetch on origin but unlike pull will not do the merge
sub fetch {
  my ($verbose) = @_;
  my $v = $verbose ? '--verbose' : q{};
  return system_ok("git fetch $v origin");
}

# Rebases against the given branch
sub rebase {
  my ($branch) = @_;
  return system_ok("git rebase $branch");
}

sub ff_merge {
  my ($branch) = @_;
  return system_ok("git merge --ff-only $branch");
}

sub no_ff_merge($$) {
  my ($branch, $message) = @_;
  return system_ok(qq/git merge --no-ff --log -m '$message' ${branch}/);
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
  my ($rev) = @_;
  my ($output) = cmd("git rev-parse $rev");
  chomp $output;
  return $output;
}

# See if the given branch is up to date in comparison with origin.
# We request both refs SHA-1 codes and compare. If they are the 
# same they will have the same hash
sub is_origin_uptodate {
  my ($branch) = @_;
  fetch();
  my $local_hash  = rev_parse($branch);
  my $remote_hash = rev_parse("origin/$branch");
  return ($local_hash eq $remote_hash) ? 1 : 0;
}

# Attempt to checkout a tracking branch. If the branch already exists locally
# we will switch to that one (and assume the other branch is tracking)
sub checkout_tracking {
  my ($branch, $remote, $verbose) = @_;
  $remote ||= 'origin';
  
  my $args;
  if(branch_exists($branch)) {
    $args = $branch;
  }
  else {
    if(! branch_exists($branch, $remote)) {
      print STDERR "No branch exists on ${remote}/${branch}. Cannot checkout\n";
      return 0;
    }
    $args = "--track -b ${branch} origin/${branch}";
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

sub checkout {
  my ($branch, $verbose) = @_;
  my $v = $verbose ? '--verbose' : q{};
  return cmd_ok("git checkout $v $branch");
}

# Perform a system call which means no capture. We will return if the process successfuly completed
sub system_ok {
  my ($cmd) = @_;
  system($cmd);
  my $exitcode = $? >> 8;
  return ($exitcode == 0) ? 1 : 0;
}

# Runs a command and captures its output. Provides two vars; the output and exit code
sub cmd {
  my ($cmd) = @_;
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

# Prompt the user for confirmation
sub prompt {
  my ($msg) = @_;
  print '* OK to continue? (y/N)... ';
  my $in = <STDIN>;
  chomp $in;
  if($in =~ /y(es)?/i) {
    return 1;
  }
  return 0;
}

1;