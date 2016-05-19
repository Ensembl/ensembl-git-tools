# ensembl-git-tools

A collection of tools which Ensembl uses to work with Git. These are split into the `bin` utilities which are useful general purposes scripts and `advanced_bin` which should be used with caution.

## Usage

To clone and to bring onto your bash path use the following:

```
git clone https://github.com/Ensembl/ensembl-git-tools.git
export PATH=$PWD/ensembl-git-tools/bin:$PATH
```

To bring in the advanced commands also run
```
export PATH=$PWD/ensembl-git-tools/advanced_bin:$PATH
```

Now to use the commands you can either call them by their name or using the git syntax. Both examples are functionally equivalent.

```
git-ensembl --list

git ensembl --list
```

## Basic Commands

### git-ensembl

```
> git ensembl --list
[Registered Modules]
    ensembl (https://github.com/Ensembl/ensembl.git)
    ensembl-compara (https://github.com/Ensembl/ensembl-compara.git)
    ensembl-funcgen (https://github.com/Ensembl/ensembl-funcgen.git)
    ensembl-variation (https://github.com/Ensembl/ensembl-variation.git)

[api] - API module set used for querying and processing Ensembl data
	ensembl
	ensembl-compara
	ensembl-funcgen
	ensembl-variation
....

> git ensembl --clone api
... wait a bit ...
```

The ensembl tool is a way of performing tasks over multiple repositories which are grouped together. Currently we support:

- Cloning a set of repositories
- Switching the working branch (automatically creates remote tracking branches)
- Fetching new changes from origin (GitHub)
- Pulling in new changes from origin (fetching and merging into the current branch)

Groups can be found using the `--list` command which reports all available groups and the repositories they will work with.

#### Using SSH

Git ensembl supports cloning using the SSH protocol but prefers to use HTTPS instead. To switch to using SSH you must use the `--ssh` command line option when cloning.

#### Switching Release

```
> git ensembl --checkout --branch release/74 api
```

You can use the `--checkout` command. This will perform a fetch from the default remote and switch to a tracking branch.

#### Configuration

The `git-ensembl` command can be supplemented with user and global configuration allowing you to define new groups and modules or override existing groups and modules with new definitions. That configuration must be called `git-ensembl.cfg` and can be located in `$HOME` or `~ensembl`. User based configuration will always win. You can also specify a config on the command line.

#### ensembl-io and Bio::DB::HTS

Tabix and BAM/CRAM file access using ensembl-io requires the Bio::DB::HTS module
to be installed. For details on how to obtain and install this please
see [https://github.com/Ensembl/Bio-HTS](https://github.com/Ensembl/Bio-HTS).

Alternatively, Bio::DB::HTS can be installed from CPAN.


### git-mgw

```
git mgw --rebase
* MGW strategy is 'rebase'
* Source branch is 'dev'
* Target branch is 'master'
* OK to continue? (y/N)...
....
* DONE
```

MGW (Minimal Git Workflow) is a lightweight branching strategy developed by [Anacode at the Wellcome Trust Sanger Institute](http://github.com/Anacode). It works by having developers never working on *master* but changes being applied to a local branch *dev*. When changes need to be released dev is rebased against master and then merged into master. 

This strategy encourages a fast-forward merges as well as a linear commit history. We call this the `--rebase` strategy. Alternatively should *dev* have been developed for so long that we want or need to maintain the parallel development history you can use the `--merge` strategy. This will enforce the creation of a commit merge even if a fast-forward merge was possible.

## Advanced Commands

### git-rewrite-authors

*This is an advanced command and should be used with caution*

```
> git rewrite-authors -list
Author: Some User <user@email.com>

> git rewrite-authors -old 'Some User <user@email.com>' -new 'New User <other@email.com>'
```

Rewrite authors is a tool for re-writing the history of a repository by scanning through the repository commit history and replacing the old username and email with the new one. This will result in new SHA-1 hashes being generated and so is a very unsafe operation to perform. Use with extreme caution.

### git-simplecvs

*This is an advanced command and should be used with caution*

```
> git simplecvs -cvs /path/to/cvs/dir --commitid HEAD^^ --dry-run
```

Simple CVS can be seen as a very simplified version of the Git command `git-cvsexportcommit`. If you need to maintain history *at all* please use that command instead of this one. This command makes no attempt at maintaining history preferring to scan Git for changes between the `--commitid` and `HEAD` of the current branch (you can specify a different `--target_commitid`). Files are copied or deleted according to Git and then added into CVS with a consistent message detailing the source and target hashes involved as well as the CVS and Git branches.
