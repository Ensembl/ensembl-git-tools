requires 'HTTP::Tiny';
requires 'JSON';
requires 'DateTime::Format::ISO8601';

recommends 'JSON::XS';

on 'build' => sub {
    requires 'Module::Build::Pluggable';
    requires 'Module::Build::Pluggable::CPANfile';
};
