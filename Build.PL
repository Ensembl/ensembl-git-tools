#!/usr/bin/env perl

use strict;
use warnings;

use Module::Build::Pluggable ( 'CPANfile' );

my $builder = Module::Build::Pluggable->new(
    module_name => 'EnsEMBL::Git',
    license => 'apache',
    dist_author => 'Ensembl <helpdesk@ensembl.org>',
    dist_abstract => 'Modules for interacting with Git',
);
$builder->create_build_script();