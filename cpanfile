requires 'HTTP::Tiny';
requires 'JSON';
requires 'DateTime';

recommends 'JSON::XS';

on 'build' => sub {
    requires 'Bio::ASN1::EntrezGene';
    requires 'Module::Build::Pluggable';
    requires 'Module::Build::Pluggable::CPANfile';
};
