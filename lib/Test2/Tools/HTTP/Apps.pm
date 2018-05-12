package Test2::Tools::HTTP::Apps;

use strict;
use warnings;
use URI;

# ABSTRACT: App container class for Test2::Tools::HTTP
# VERSION

sub new
{
  my($class) = @_;
  
  bless {
    psgi     => {},
    base_url => undef,
  }, $class;
}

sub uri_key
{
  my(undef, $uri) = @_;
  $uri = URI->new($uri) unless ref $uri;
  join ':', map { $uri->$_ } qw( scheme host port );
}

sub psgi
{
  shift->{psgi};
}

sub base_url
{
  my($self, $new) = @_;
  
  if($new)
  {
    $self->{base_url} = ref $new ? $new : URI->new($new);
  }
  
  unless(defined $self->{base_url})
  {
    $self->{base_url} = URI->new('http://localhost/');
    require IO::Socket::INET;
    $self->{base_url}->port(IO::Socket::INET->new(Listen => 5, LocalAddr => "127.0.0.1")->sockport);
  }

  $self->{base_url};
}

sub uri_to_app
{
  my($self, $uri) = @_;
  
  my $url = URI->new_abs($uri, $self->base_url);
  my $key = $self->uri_key($url);
  $self->psgi->{$key};
}

1;
