use Test2::V0 -no_srand => 1;
use Test2::Tools::HTTP;
use Test2::Require::Internet -tcp => [ 'httpbin.org', 'http' ];
use HTTP::Request::Common;

my $ret;

http_base_url 'http://httpbin.org';

is(
  intercept {
    $ret = http_request(
      GET('/status/200'),
    );
  },
  array {
    event Ok => sub {
      call pass => T();
      call name => 'GET http://httpbin.org/status/200';
    };
    end;
  },
  'works with standard 200 response'
);

is($ret, T(), 'returns true');

is(
  intercept {
    http_last->note;
  },
  array {
    event Note => sub {
      call message => http_last->req->as_string;
    };
    event Note => sub {
      call message => http_last->res->as_string;
    };
    event Note => sub {
      call message => "ok = 1";
    };
    etc;
  },
  'http_last->note on ok',
);

is(
  intercept {
    http_last->diag;
  },
  array {
    event Diag => sub {
      call message => http_last->req->as_string;
    };
    event Diag => sub {
      call message => http_last->res->as_string;
    };
    event Diag => sub {
      call message => "ok = 1";
    };
    etc;
  },
  'http_last->note on ok',
);

is(
  intercept {
    $ret = http_request(
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
  'fails with a bogus hostname',
);

is($ret, F(), 'returns false');

is(
  intercept {
    http_last->note;
  },
  array {
    event Note => sub {
      call message => http_last->req->as_string;
    };
    event Note => sub {
      call message => http_last->res->as_string;
    };
    event Note => sub {
      call message => "ok = 0";
    };
    etc;
  },
  'http_last->note on fail',
);

is(
  intercept {
    http_last->diag;
  },
  array {
    event Diag => sub {
      call message => http_last->req->as_string;
    };
    event Diag => sub {
      call message => http_last->res->as_string;
    };
    event Diag => sub {
      call message => "ok = 0";
    };
    etc;
  },
  'http_last->diag on fail',
);

http_request(
  GET('/cookies'),
  http_response {
    http_is_success;
    http_json '/cookies' => {};
  },
);

http_request(
  GET('/cookies/set?foo=bar'),
  http_response {
    call is_error => F();
  }
);

http_request(
  GET('/cookies'),
  http_response {
    http_is_success;
    http_json '/cookies' => { foo => 'bar' };
  },
);

http_request(
  GET('/cookies/delete?foo'),
  http_response {
    call is_error => F();
  }
);

http_request(
  GET('/cookies'),
  http_response {
    http_is_success;
    http_json '/cookies' => {};
  },
);

done_testing
