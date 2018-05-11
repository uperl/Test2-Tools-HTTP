package Test2::Tools::HTTP::UA::LWP;

use strict;
use warnings;
use URI;
use parent 'Test2::Tools::HTTP::UA';

# ABSTRACT: LWP user agent wrapper for Test2::Tools::HTTP
# VERSION

sub instrument
{
  my($self) = @_;
  
  my $apps = $self->apps;

  my $cb = $self->{request_send_cb} ||= sub {
    my($req, $ua, $h) = @_;
    
    my $url = URI->new_abs($req->uri, $apps->base_url);
    my $key = $apps->uri_key($url);
    
    if(my $tester = $apps->psgi->{$key})
    {
      return $tester->request($req);
    }
    else
    {
      return;
    }
  };
  
  $self->ua->set_my_handler( 'request_send' => $cb );
}

sub request
{
  my($self, $req, %options) = @_;
  $options{follor_redirects}
    ? $self->ua->request($req)
    : $self->ua->simple_request($req);
}

1;
