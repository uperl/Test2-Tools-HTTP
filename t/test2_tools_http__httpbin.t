use Test2::V0 -no_srand => 1;
use Test2::Tools::HTTP;
use Test2::Require::Internet -tcp => [ 'httpbin.org', 'http' ];
use HTTP::Request::Common;

my $res;

is(
  intercept {
    $res = http_request(
      GET('http://httpbin.org/status/200'),
    );
  },
  array {
    event Ok => sub {
      call pass => T();
      call name => 'GET http://httpbin.org/status/200';
    };
    end;
  },
);

is($res, T());

is(
  intercept {
    $res = http_request(
      GET('http://bogus.httpbin.org/status/200'),
    );
  },
  array {
    event Ok => sub {
      call pass => F();
      call name => 'GET http://bogus.httpbin.org/status/200';
    };
    event Diag => sub { };
    event Diag => sub { call message => match qr/connection error: /; };
    end;
  },
);

is($res, F());

done_testing
