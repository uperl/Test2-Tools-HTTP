package Test2::Tools::HTTP;

use strict;
use warnings;
use 5.008001;
use LWP::UserAgent;
use parent qw( Exporter );
use Test2::API qw( context );
use Test2::Compare ();
use URI;

our @EXPORT    = qw( http_request http_ua http_base_url psgi_app_add psgi_app_del );
our @EXPORT_OK = (@EXPORT);

# ABSTRACT: Test HTTP / PSGI
# VERSION

=head1 FUNCTIONS

=head2 http_request

 http_request($request, $check, $message);

=cut

my %psgi;

sub http_request
{
  my($request, $check, $message) = @_;

  my $url = URI->new_abs($request->uri, http_base_url());
  my $key = _uri_key($url);

  $message ||= "@{[ $request->method ]} @{[ $url ]}";

  my $ctx = context();
  my $ok = 1;
  my @diag;
  my $res;

  if(my $tester = $psgi{$key})
  {
    $res = $tester->request($request);
  }
  else
  {
    $res = http_ua()->simple_request($request);
  }

  if(my $warning = $res->header('Client-Warning'))
  {
    $ok = 0;
    push @diag, "connection error: " . ($res->decoded_content || $warning);
  }

  if($ok && defined $check)
  {
    my $delta = Test2::Compare::compare($res, $check, \&Test2::Compare::strict_convert);
    if($delta)
    {
      $ok = 0;
      push @diag, $delta->diag;
    }
  }

  $ctx->ok($ok, $message, \@diag);
  $ctx->release;
  $ok;
}

=head2 http_base_url

 http_base_url($url);
 my $url = http_base_url;

=cut

my $base_url;

sub http_base_url
{
  my($new) = @_;

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

=head2 http_ua

 http_ua(LWP::UserAgent->new);
 my $ua = http_ua;

=cut

my $ua;

sub http_ua
{
  my($new) = @_;

  $ua = $new if $new;

  unless(defined $ua)
  {
    $ua = LWP::UserAgent->new;
    $ua->env_proxy;
    $ua->cookie_jar({});
  }

  $ua;
}

=head2 psgi_app_add

 psgi_app_add $app;
 psgi_app_add $url, $app;

=cut

sub _uri_key
{
  my($uri) = @_;
  $uri = URI->new($uri) unless ref $uri;
  join ':', map { $uri->$_ } qw( scheme host port );
}

sub psgi_app_add
{
  my($url, $app) = @_ == 1 ? (http_base_url, @_) : (@_);
  require Plack::Test;
  my $key = _uri_key $url;
  $psgi{$key} = Plack::Test->create($app);
  return;
}

=head2 psgi_app_del

 psgi_app_del;
 psgi_app_del $url;

=cut

sub psgi_app_del
{
  my($url) = @_;
  $url ||= http_base_url;
  my $key = _uri_key $url;
  delete $psgi{$key};
  return;
}

1;
