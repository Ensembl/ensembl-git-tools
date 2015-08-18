requires 'HTTP::Tiny';
requires 'JSON';
requires 'JSON::XS';

on 'build' => sub {
    requires 'Module::Build::Pluggable';
    requires 'Module::Build::Pluggable::CPANfile';
};