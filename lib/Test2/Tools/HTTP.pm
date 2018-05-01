package Test2::Tools::HTTP;

use strict;
use warnings;
use 5.008001;
use LWP::UserAgent;
use parent qw( Exporter );
use Test2::API qw( context );

our @EXPORT_OK = qw( http_request http_ua );
our @EXPORT    = qw( http_request http_ua );

# ABSTRACT: Test HTTP / PSGI
# VERSION

=head1 FUNCTIONS

=head2 http_request

 http_request($request, $check, $message);

=cut

our $res;

sub http_request
{
  my($request, $check, $message) = @_;

  $message ||= "@{[ $request->method ]} @{[ $request->uri ]}";

  my $ctx = context();
  my $ok = 1;
  my @diag;
  
  local $res = http_ua()->simple_request($request);

  if(my $warning = $res->header('Client-Warning'))
  {
    $ok = 0;
    push @diag, "connection error: " . ($res->decoded_content || $warning);
  }

  $ctx->ok($ok, $message, \@diag);

  $ctx->release;
}

=head2 http_ua

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

1;
