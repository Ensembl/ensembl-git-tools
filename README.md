ensembl-git-tools
=================

A collection of tools which Ensembl uses to work with Git. These are split into the `bin` utilities which are useful general purposes scripts and `advanced_bin` which should be used with caution.

Usage
-----

To clone and to bring onto your bash path use the following:

```
git clone https://github.com/Ensembl/ensembl-git-tools.git
export PATH=$PWD/ensembl-git-tools/bin:$PATH
```

Now to use the commands you can either call them by their name or using the git syntax. Both examples are functionally equivalent.

```
git-ensembl --list

git ensembl --list
```
