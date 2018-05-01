use Test2::V0 -no_srand => 1;
use Test2::Tools::HTTP;
use Test2::Mock;
use HTTP::Request;
use HTTP::Request::Common;
use Test2::Tools::URL;

subtest 'ua' => sub {

  my $ua = http_ua;
  isa_ok $ua, 'LWP::UserAgent';

};

subtest 'base url' => sub {

  subtest default => sub {

    is(
      http_base_url,
      url {
        url_component 'scheme' => 'http';
        url_component 'host'   => 'localhost';
        url_component 'path'   => '/';
        url_component 'port'   => match qr/^[0-9]+$/;
      },
    );

    note "http_base_url default = @{[ http_base_url ]}";

    isa_ok http_base_url, 'URI';
  
  };

  subtest override => sub {

    http_base_url 'https://example.test:4141/foo/bar';

    is(
      http_base_url,
      url {
        url_component 'scheme' => 'https';
        url_component 'host'   => 'example.test';
        url_component 'path'   => '/foo/bar';
        url_component 'port'   => 4141;
      },
    );

    isa_ok http_base_url, 'URI';
  
  };

};

subtest 'basic' => sub {

  my $req;
  my $res;

  my $mock = Test2::Mock->new( class => 'LWP::UserAgent' );

  $mock->override('simple_request' => sub {
    (undef, $req) = @_;
    $res;
  });

  subtest 'good' => sub {

    undef $req;
    $res = HTTP::Request->parse(<<'EOM');
HTTP/1.1 200 OK
Connection: close
Date: Tue, 01 May 2018 13:03:23 GMT
Via: 1.1 vegur
Server: gunicorn/19.7.1
Content-Length: 0
Content-Type: text/html; charset=utf-8
Access-Control-Allow-Credentials: true
Access-Control-Allow-Origin: *
Client-Date: Tue, 01 May 2018 13:03:23 GMT
Client-Peer: 54.243.149.76:80
Client-Response-Num: 1
X-Powered-By: Flask
X-Processed-Time: 0

EOM

    my $ret;

    is(
      intercept {
        $ret = http_request(
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

    is $ret, T();

    is(
      $req,
      object {
        call method => 'GET';
        call uri    => 'http://httpbin.org/status/200';
      },
    );

  };

  subtest 'with base url' => sub {

    http_base_url 'https://example.test/';
    
    is(
      intercept {
        http_request(
          GET('/status/200'),
        );
      },
      array {
        event Ok => sub {
          call pass => T();
          call name => 'GET https://example.test/status/200';
        };
        end;
      },
    );

    is(
      $req,
      object {
        call method => 'GET';
        call uri    => '/status/200';
      },
    );

  
  };

  subtest 'bad' => sub {

    undef $req;
    $res = HTTP::Request->parse(<<'EOM');
500 Can't connect to bogus.httpbin.org:80 (Name or service not known)
Content-Type: text/plain
Client-Date: Tue, 01 May 2018 13:36:43 GMT
Client-Warning: Internal response

Can't connect to bogus.httpbin.org:80 (Name or service not known)

Name or service not known at /usr/share/perl5/LWP/Protocol/http.pm line 50.

EOM

    my $ret;

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
    );

    is($ret, F());

    is(
      $req,
      object {
        call method => 'GET';
        call uri    => 'http://bogus.httpbin.org/status/200';
      },
    );
  };


};

subtest psgi => sub {

  http_base_url 'http://psgi-app.test';

  psgi_app_add sub { [ 200, [ 'Content-Type' => 'text/plain' ], [ 'some text' ] ] };

  is(
    intercept {
      http_request(
        GET('http://psgi-app.test/'),
        object {
          call code => 200;
        },
      );
    },
    array {
      event Ok => sub {
        call pass => T();
        call name => 'GET http://psgi-app.test/';
      };
      end;
    },
  );

  is(
    intercept {
      http_request(
        GET('http://psgi-app.test/'),
        object {
          call code => 201;
        },
      );
    },
    array {
      event Ok => sub {
        call pass => F();
        call name => 'GET http://psgi-app.test/';
      };
      etc;
    },
  );

};

done_testing
