requires 'HTTP::Tiny';
requires 'JSON';
requires 'DateTime';
requires 'DateTime::Duration';

recommends 'JSON::XS';

on 'build' => sub {
    requires 'Module::Build::Pluggable';
    requires 'Module::Build::Pluggable::CPANfile';
};
