=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2017] EMBL-European Bioinformatics Institute

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

package EnsEMBL::GitHub;
use strict;
use warnings;

use base qw/Exporter/;
use Carp;
use Cwd;
use File::Spec;
use HTTP::Tiny;
use Fcntl ':mode';

my $base_url = 'https://api.github.com';

our $DEBUG = 0;

our $JSON = 0;
eval {
  require JSON;
  $JSON = 1;
};

our @EXPORT = qw/
  rest_request
  parse_oauth_token
  public_repositories
  paginated_rest_request
/;

sub public_repositories {
  my ($organisation, $oauth) = @_;
  my $json = paginated_rest_request('GET', "/orgs/${organisation}/repos?type=public", $oauth);
  return [ sort map { $_->{name} } @{$json} ];
}

# GitHub provides paginated items in sets of 30.
# This method get the maximum number of pages,
# loop through each pages
# and return the complete json object back.
sub paginated_rest_request {
  my ($method, $url, $oauth_token, $content) = @_;  
  my ($json, $headers) = rest_request($method, $url, $oauth_token, $content);
  my ($json_page, $headers_page);
  if ($headers->{link}){
    my @links = split(/,/, $headers->{link});
    foreach my $link (@links) {
      if ($link =~ m/.+page=([0-9])>;\srel=\"(last)\"/) {  
        for (my $page=2; $page<=$1; $page++) {
          if ($url =~ m/\?/) {
            ($json_page, $headers_page) = rest_request($method, $url."&page=${page}", $oauth_token);
          }
          else {
            ($json_page, $headers_page) = rest_request($method, $url."?page=${page}", $oauth_token);
          }
          push (@{$json}, @{$json_page});
        }
      }
    }
  }
  return $json;
}

# Performs a REST request. You can specify the METHOD, extension URL, oauth token 
# and body content
sub rest_request {
  my ($method, $url, $oauth_token, $content) = @_;
  die 'No method specified' if ! $method;
  die 'No URL specified' if ! $url;
  my $http = HTTP::Tiny->new();
  my $options = { headers => { Accept => 'application/vnd.github.v3+json' } };
  $options->{headers}->{Authorization} = "token $oauth_token" if $oauth_token;
  if($content) {
    $options->{headers}->{'Content-Type'} = 'application/json';
    $options->{content} = JSON::encode_json($content);
  }
  my $response = $http->request($method, $base_url.$url, $options);
  if(! $response->{success}) {
    use Data::Dumper; warn Dumper $response->{headers};
    die "Failed to process $method (${url})! STATUS: $response->{status} REASON: $response->{reason} CONTENT: $response->{content}\n";
  }
  my $decoded_json = JSON::decode_json($response->{content});
  if(wantarray) {
    return ($decoded_json, $response->{headers});
  }
  else {
    return $decoded_json;
  }
}

# Pulls out the oauth token held in the specified file. It 
# also will check the file's permissions and containing directory
# to ensure no token leaks
sub parse_oauth_token {
  my ($path) = @_;
  my $abs_path = File::Spec->rel2abs($path);
  if(! -f $abs_path) {
    die "Cannot find a file at the path $abs_path";
  }

  my ($vol, $dirs, $file) = File::Spec->splitpath($abs_path);

  # Check the permisssions of the directory. User only
  my $dir_path = File::Spec->catdir($vol, $dirs);
  my $dir_mode = (stat($dir_path))[2];
  if(($dir_mode & S_IRWXO) != 0) { #Exclude others from reading/writing/executing
    die "Other users have read/write/execute access to dir $dir_path";
  }
  if((($dir_mode & S_IRWXG) >> 3) != 0) { #Exclude groups from reading/writing/executing
    die "Group users have read/write/execute access to dir $dir_path";
  }

  # Then check the permissions of the file. User only
  my $file_mode = (stat($abs_path))[2];
  if(($file_mode & S_IRWXO) != 0) { #Exclude others from reading/writing/executing the file
    die "Other users have read/write/execute access to path $abs_path";
  }
  if((($file_mode & S_IRWXG) >> 3) != 0) { #Exclude group from reading/writing/executing the file
    die "Group users have read/write/execute access to path $abs_path";
  }

  my $oauth;
  #Slurp file in and push into the OAuth variable
  {
    local $/ = undef;
    open my $fh, '<', $abs_path or die "Cannot open $abs_path for reading: $!";
    my $slurp = <$fh>;
    close $fh;
    $slurp =~ s/\s//g; # remove any whitespace
    $oauth = $slurp;
  }

  return $oauth;
}

1;