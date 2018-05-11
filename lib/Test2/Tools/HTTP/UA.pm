package Test2::Tools::HTTP::UA;

use strict;
use warnings;
use URI;

# ABSTRACT: User agent wrapper for Test2::Tools::HTTP
# VERSION

sub new
{
  my($class, $ua) = @_;  
  bless {
    ua => $ua,
  }, $class;
}

sub ua
{
  shift->{ua};
}

sub uri_key
{
  my(undef, $uri) = @_;
  $uri = URI->new($uri) unless ref $uri;
  join ':', map { $uri->$_ } qw( scheme host port );
}

my %psgi;

sub psgi
{
  \%psgi;
}

my $base_url;

sub base_url
{
  my(undef, $new) = @_;
  
  if($new)
  {
    $base_url = ref $new ? $new : URI->new($new);
  }
  
  unless(defined $base_url)
  {
    $base_url = URI->new('http://localhost/');
    require IO::Socket::INET;
    $base_url->port(IO::Socket::INET->new(Listen => 5, LocalAddr => "127.0.0.1")->sockport);
  }

  $base_url;
}

1;
