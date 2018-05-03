use Test2::V0 -no_srand => 1;
use Test2::Tools::HTTP;
use Test2::Mock;
use HTTP::Request;
use HTTP::Request::Common;
use Test2::Tools::URL;
use JSON::MaybeXS qw( encode_json );

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

  is( http_last, undef, 'http_last starts out as undef' );

  my $mock = Test2::Mock->new( class => 'LWP::UserAgent' );

  $mock->override('simple_request' => sub {
    (undef, $req) = @_;
    $res;
  });

  subtest 'good' => sub {

    undef $req;
    $res = HTTP::Response->parse(<<'EOM');
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

    isa_ok http_last, 'Test2::Tools::HTTP::Last';
    isa_ok(http_last->req, 'HTTP::Request');
    isa_ok(http_last->res, 'HTTP::Response');
    is(http_last->ok, T());
    is(http_last->connection_error, F());

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
        call uri    => 'https://example.test/status/200';
      },
    );

  
  };

  subtest 'bad' => sub {

    undef $req;
    $res = HTTP::Response->parse(<<'EOM');
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

    isa_ok http_last, 'Test2::Tools::HTTP::Last';
    isa_ok(http_last->req, 'HTTP::Request');
    isa_ok(http_last->res, 'HTTP::Response');
    is(http_last->ok, F());
    is(http_last->connection_error, T());

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

  subtest 'single' => sub {

    http_base_url 'http://psgi-app.test';

    psgi_app_add sub { [ 200, [ 'Content-Type' => 'text/plain' ], [ 'some text' ] ] };

    is(
      intercept {
        http_request(
          GET('http://psgi-app.test/'),
          http_response {
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

    isa_ok http_last, 'Test2::Tools::HTTP::Last';
    isa_ok(http_last->req, 'HTTP::Request');
    isa_ok(http_last->res, 'HTTP::Response');
    is(http_last->ok, T());

    is(
      intercept {
        http_request(
          GET('http://psgi-app.test/'),
          http_response {
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

    isa_ok http_last, 'Test2::Tools::HTTP::Last';
    isa_ok(http_last->req, 'HTTP::Request');
    isa_ok(http_last->res, 'HTTP::Response');
    is(http_last->ok, F());

    psgi_app_del;

  };

  subtest 'double' => sub {

    psgi_app_add 'http://myhost1.test:8001' => sub { [ 200, [ 'Content-Type' => 'text/plain' ], [ 'app 1' ] ] };
    psgi_app_add 'http://myhost2.test:8002' => sub { [ 200, [ 'Content-Type' => 'text/plain' ], [ 'app 2' ] ] };

    http_request(
      GET('http://myhost1.test:8001/foo/bar/baz'),
      http_response {
        http_content 'app 1';
      },
    );

    http_request(
      GET('http://myhost2.test:8002/foo/bar/baz'),
      http_response {
        http_content 'app 2';
      },
    );

    psgi_app_del 'http://myhost1.test:8001';
    psgi_app_del 'http://myhost2.test:8002';
  
  };

};

subtest 'http_response' => sub {

  is(
    intercept {
      is(
        HTTP::Response->new(GET => 'http://localhost/'),
        http_response {},
      );
    },
    array {
      event Ok => sub {
        call pass => T();
      };
      end;
    },
  );

  is(
    intercept {
      is(
        bless({}, 'Foo::Bar'),
        http_response {},
      );
    },
    array {
      event Ok => sub {
        call pass => F();
      };
      etc;
    },
  );

};

subtest 'basic calls code, message, content' => sub {

  psgi_app_add sub { [ 200, [ 'Content-Type' => 'text/plain' ], [ 'some text' ] ] };

  http_request(
    GET('http://psgi-app.test/'),
    http_response {
      http_code 200;
      http_message 'OK';
      http_content 'some text';
    },
  );

  is(
    intercept {
      http_request(
        GET('http://psgi-app.test/'),
        http_response {
          http_code 201;
        },
      );
    },
    array {
      event Ok => sub {
        call pass => F();
      };
      etc;
    },
  );

  is(
    intercept {
      http_request(
        GET('http://psgi-app.test/'),
        http_response {
          http_message 'Created';
        },
      );
    },
    array {
      event Ok => sub {
        call pass => F();
      };
      etc;
    },
  );

  is(
    intercept {
      http_request(
        GET('http://psgi-app.test/'),
        http_response {
          http_content 'bad';
        },
      );
    },
    array {
      event Ok => sub {
        call pass => F();
      };
      etc;
    },
  );

  eval { http_code 200 };
  like $@, qr/No current build!/;

  eval {
    intercept {
      http_request(
        GET('/'),
        object {
          http_code 200;
        },
      );
    };
  };
  like $@, qr/'Test2::Compare::Object=HASH\(.*?\)' is not a Test2::Tools::HTTP::ResponseCompare/;

  eval {
    intercept {
      http_request(
        GET('/'),
        http_response {
          my $x = http_code 200;
        },
      );
    }
  };
  like $@, qr/'http_code' should only ever be called in void contex/;

  psgi_app_del;

};

subtest 'json' => sub {

  psgi_app_add 'http://valid-json.test' => sub { 
    [ 200, [ 'Content-Type' => 'application/json' ], [ 
      encode_json ({ a => 'b', c => [1,3,4], d => { roger => 'rabbit' }, na => undef }) 
    ] ]
  };

  is(
    intercept {
      http_request(
        GET('http://valid-json.test'),
        http_response {
          http_json { a => 'b', c => [1,3,4], d => { roger => 'rabbit' }, na => undef };
        },
      );
    },
    array {
      event Ok => sub {
        call pass => T();
      };
      end;
    },
    'http_json with default (root) jsoin pointer pass',
  );

  is(
    intercept {
      http_request(
        GET('http://valid-json.test'),
        http_response {
          http_json { a => 'b', c => [1,10,4], d => { roger => 'rabbit' }, na => undef };
        },
      );
    },
    array {
      event Ok => sub {
        call pass => F();
      };
      etc;
    },
    'http_json with default (root) jsoin pointer fail',
  );

  is(
    intercept {
      http_request(
        GET('http://valid-json.test'),
        http_response {
          http_json '/c' => [1,3,4];
        },
      );
    },
    array {
      event Ok => sub {
        call pass => T();
      };
      end;
    },
    'http_json with pointer to array pass',
  );

  is(
    intercept {
      http_request(
        GET('http://valid-json.test'),
        http_response {
          http_json '/c' => [1,10,4];
        },
      );
    },
    array {
      event Ok => sub {
        call pass => F();
      };
      etc;
    },
    'http_json with pointer to array fail',
  );

  is(
    intercept {
      http_request(
        GET('http://valid-json.test'),
        http_response {
          http_json '/na' => E();
        },
      );
    },
    array {
      event Ok => sub {
        call pass => T();
      };
      end;
    },
    'http_json with pointer undef if exists pass',
  );

  is(
    intercept {
      http_request(
        GET('http://valid-json.test'),
        http_response {
          http_json '/na2' => E();
        },
      );
    },
    array {
      event Ok => sub {
        call pass => F();
      };
      etc;
    },
    'http_json with pointer na if exists fail',
  );

  is(
    intercept {
      http_request(
        GET('http://valid-json.test'),
        http_response {
          http_json '/na' => DNE();
        },
      );
    },
    array {
      event Ok => sub {
        call pass => F();
      };
      etc;
    },
    'http_json with pointer undef if not exists fail',
  );

  is(
    intercept {
      http_request(
        GET('http://valid-json.test'),
        http_response {
          http_json '/na2' => DNE();
        },
      );
    },
    array {
      event Ok => sub {
        call pass => T();
      };
      end;
    },
    'http_json with pointer na if not exists pass',
  );

  psgi_app_add 'http://invalid-json.test' => sub { 
    [ 200, [ 'Content-Type' => 'application/json' ], [ 
      '{"foo":"bar"',
    ] ]
  };

  is(
    intercept {
      http_request(
        GET('http://invalid-json.test'),
        http_response {
          http_json '/anything', 'else';
        },
      );
    },
    array {
      event Ok => sub {
        call pass => F();
      };
      etc;
    },
    'http_json fails with invalid JSON',
  );

  psgi_app_del 'http://valid-json.test';
  psgi_app_del 'http://invalid-json.test';

};

subtest 'diagnostc with large respinse' => sub {

  my $content = 'frooble';

  psgi_app_add sub { [ 200, [ 'Content-Type' => 'text/plain' ], [ $content ] ] };

  http_request(
    GET('/')
  );

  http_last->note;

  is(
    intercept {
      http_last->note;
    },
    array {
      event Note => sub {};
      event Note => sub {
        call message => http_last->res->as_string;
      };
      etc;
    },
  );

  $content = 'whaaa?' x 1024;
  http_request(
    GET('/'),
  );

  http_last->note;

  is(
    intercept {
      http_last->note;
    },
    array {
      event Note => sub {};
      event Note => sub {
        call message => http_last->res->headers->as_string . "[large body removed]";
      };
      etc;
    },
  );

};

done_testing
