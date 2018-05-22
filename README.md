# Test2::Tools::HTTP [![Build Status](https://secure.travis-ci.org/plicease/Test2-Tools-HTTP.png)](http://travis-ci.org/plicease/Test2-Tools-HTTP)

Test HTTP / PSGI

# SYNOPSIS

    use Test2::V0;
    use Test2::Tools::HTTP;
    use HTTP::Request::Common;
    
    psgi_add_app sub { [ 200, [ 'Content-Type' => 'text/plain;charset=utf-8' ], [ "Test Document\n" ] ] };
    
    # Internally test the app from within the .t file itself
    http_request(
      # if no host/port/protocol is given then
      # the default PSGI app above is assumed
      GET('/'),
      http_response {
    
        http_code 200;
    
        # http_response {} is a subclass of object {}
        # for HTTP::Response objects only, so you can
        # also use object {} style comparisons:
        call code => 200; 

        http_content_type match qr/^text\/(html|plain)$/;
        http_content_type_charset 'UTF-8';
        http_content match qr/Test/;
      }
    );

    use Test2::Tools::JSON::Pointer;
    
    # test an external website
    http_request(
      # you can also test against a real HTTP server
      GET('http://example.test'),
      http_response {
        http_is_success;
        # JSON pointer { "key":"val" }
        http_content json '/key' => 'val';
      }
    );
    
    done_testing;

with short names:

    use Importer 'Test2::Tools::HTTP' => ':short';
    use HTTP::Request::Common;
    
    app { [ 200, [ 'Content-Type => 'text/plain' ], [ "Test Document\n" ] ] };
    
    req (
      GET('/'),
      res {
        code 200;
        message 'OK';
        content_type 'text/plain';
        content match qr/Test/;
      },
    );
    
    done_testing;

# DESCRIPTION

This module provides an interface for testing websites and PSGI based apps with a [Test2](https://metacpan.org/pod/Test2) style comparisons interface.
You can specify a PSGI app with a URL and responses from that URL will automatically be routed to that app, without
having to actually need a separate server process.  Requests to URLs that haven't been registered will be made
against the actual networks servers as appropriate.  You can also use the user agent returned from `http_ua` to
make requests against PSGI apps.  [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) is the user agent used by default, but it is possible to use
others assuming an appropriate user agent wrapper class is available ([Test2::Tools::HTTP::UA](https://metacpan.org/pod/Test2::Tools::HTTP::UA)).

By default it uses long function names with either a `http_` or `psgi_app_` prefix.  The intent is to make the module
usable when you are importing lots of symbols from lots of different testing tools while reducing the chance of name 
collisions.  You can instead import `:short` which will give you the most commonly used tools with short names. 
The short names are indicated below in square brackets, and were chosen to not conflict with [Test2::V0](https://metacpan.org/pod/Test2::V0).

# FUNCTIONS

## http\_request \[req\]

    http_request($request);
    http_request($request, $check);
    http_request($request, $check, $message);
    http_request([$request, %options], ... );

Make a HTTP request.  If there is a client level error then it will fail immediately.  Otherwise you can use a
`object {}` or `http_request` comparison check to inspect the HTTP response and ensure that it matches what you
expect.  By default only one request is made.  If the response is a forward (has a `Location` header) you can
use the `http_tx-`location> method to make the next request.

Options:

- follow\_redirects

    This allows the user agent to follow redirects.

## http\_response \[res\]

    my $check = http_response {
      ... # object or http checks
    };

This is a comparison check specific to HTTP::Response objects.  You may include these subchecks:

### http\_code \[code\]

    http_response {
      http_code $check;
    };

The HTTP status code should match the given check.

### http\_message \[message\]

    http_response {
      http_message $check;
    };

The HTTP status message ('OK' for 200, 'Not Found' for 404, etc) should match the given check.

### http\_content \[content\]

    http_response {
      http_content $check;
    };

The response body content.  Attempt to decode using the [HTTP::Message](https://metacpan.org/pod/HTTP::Message) method `decoded_content`, otherwise use the raw
response body.  If you want specifically the decoded content or the raw content you can use `call` to specifically check
against them:

    http_response {
      call content => $check1;
      call decoded_content => $check2;
    };

### http\_is\_info, http\_is\_success, http\_is\_redirect, http\_is\_error, http\_is\_client\_error, http\_is\_server\_error

    http_response {
      http_is_info;
      http_is_success;
      http_is_redirect;
      http_is_error;
      http_is_client_error;
      http_is_server_error;
    };

Checks that the response is of the specified type.  See [HTTP::Status](https://metacpan.org/pod/HTTP::Status) for the meaning of each of these.

### http\_isnt\_info, http\_isnt\_success, http\_isnt\_redirect, http\_isnt\_error, http\_isnt\_client\_error, http\_isnt\_server\_error

    http_response {
      http_isnt_info;
      http_isnt_success;
      http_isnt_redirect;
      http_isnt_error;
      http_isnt_client_error;
      http_isnt_server_error;
    };

Checks that the response is NOT of the specified type.  See [HTTP::Status](https://metacpan.org/pod/HTTP::Status) for the meaning of each of these.

### http\_headers \[headers\]

    http_response {
      http_headers $check;
    };

Check the HTTP headers as converted into a Perl hash.  If the same header appears twice, then the values are joined together
using the `,` character.  Example:

    http_request(
      GET('http://example.test'),
      http_response {
        http_headers hash {
          field 'Content-Type' => 'text/plain;charset=utf-8';
          etc;
        };
      },
    );

### http\_header \[head\]

    http_response {
      http_header $name, $check;
    };

Check an HTTP header against the given check.  Can be used with either scalar or array checks.  In scalar mode,
any list values will be joined with `,` character.  Example:

    http_request(
      GET('http://example.test'),
      http_response {

        # single value
        http_header 'X-Foo', 'Bar';

        # list as scalar, will match either:
        #     X-Foo: A
        #     X-Foo: B
        # or 
        #     X-Foo: A,B
        http_header 'X-Foo', 'A,B';

        # list mode, with an array ref:
        http_header 'X-Foo', ['A','B'];

        # list mode, with an array check:
        http_header 'X-Foo', array { item 'A'; item 'B' };
      },
    );

### http\_content\_type \[content\_type\], http\_content\_type\_charset \[charset\]

    http_response {
      http_content_type $check;
      http_content_type_charset $check;
    };

Check that the `Content-Type` header matches the given checks.  `http_content_type` checks just the content type, not the character set, and
`http_content_type_charset` matches just the character set.  Hence:

    http_response {
      http_content_type 'text/html';
      http_content_type_charset 'UTF-8';
    };

### http\_content\_length \[content\_length\]

    http_response {
      http_content_length $check;
    };

Check that the `Content-Length` header matches the given check.

### http\_content\_length\_ok \[content\_length\_ok\]

    http_response {
      http_content_length_ok;
    };

Checks that the `Content-Length` header matches the actual length of the content.

### http\_location \[location\], http\_location\_uri \[location\_uri\]

    http_response {
      http_location $check;
      http_location_uri $check;
    };

Check the `Location` HTTP header.  The `http_location_uri` variant converts `Location` to a [URI](https://metacpan.org/pod/URI) using the base URL of the response
so that it can be tested with [Test2::Tools::URL](https://metacpan.org/pod/Test2::Tools::URL).

## http\_tx \[tx\]

    my $req    = http_tx->req;
    my $res    = http_tx->res;
    my $bool   = http_tx->ok;
    my $string = http_tx->connection_error;
    my $url    = http_tx->location;
    http_tx->note;
    http_tx->diag;

This returns the most recent transaction object, which you can use to get the last request, response and status information
related to the most recent `http_request`.

- http\_tx->req

    The [HTTP::Request](https://metacpan.org/pod/HTTP::Request) object.

- http\_tx->res

    The [HTTP::Response](https://metacpan.org/pod/HTTP::Response) object.

    Warning: Depending on the user agent class in use, in the case of a connection error, this may be either a synthetic
    response or not defined.  For example [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) produced a synthetic response, while [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) does not
    produce a response in the event of a connection error.

- http\_tx->ok

    True if the most recent call to `http_request` passed.

- http\_tx->connection\_error.

    The connection error if any from the most recent `http_reequest`.

- http\_tx->location

    The `Location` header converted to an absolute URL, if included in the response.

- http\_tx->note

    Send the request, response and ok to Test2's "note" output.  Note that the message bodies may be decoded, but
    the headers will not be modified.

- http\_tx->diag

    Send the request, response and ok to Test2's "diag" output.  Note that the message bodies may be decoded, but
    the headers will not be modified.

## http\_base\_url

    http_base_url($url);
    my $url = http_base_url;

Sets the base URL for all requests made by `http_request`.  This is used if you do not provide a fully qualified URL.  For example:

    http_base_url 'http://httpbin.org';
    http_request(
      GET('/status/200') # actually makes a request against http://httpbin.org
    );

If you use `psgi_add_app` without a URL, then this is the URL which will be used to access your app.  If you do not specify a base URL,
then localhost with a random unused port will be picked.

## http\_ua \[ua\]

    http_ua(LWP::UserAgent->new);
    my $ua = http_ua;

Gets/sets the [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) object used to make requests against real web servers.  For tests against a PSGI app, this will NOT be used.
If not provided, the default [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) will call `env_proxy` and add an in-memory cookie jar.

## psgi\_app\_add \[app\]

    psgi_app_add $app;
    psgi_app_add $url, $app;

Add the given PSGI app to the testing environment.  If you provide a URL, then requests to that URL will be intercepted by `http_request` and routed to the app
instead of making a real HTTP request via [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent).

## psgi\_app\_del

    psgi_app_del;
    psgi_app_del $url;

Remove the app at the given (or default) URL.

# SEE ALSO

- [Test::Mojo](https://metacpan.org/pod/Test::Mojo)

    This is a very capable web application testing module.  Definitely worth checking out, even if you aren't developing a [Mojolicious](https://metacpan.org/pod/Mojolicious) 
    app since it can be used (with [Test::Mojo::Role::PSGI](https://metacpan.org/pod/Test::Mojo::Role::PSGI)) to test any PSGI application.

- [Plack::Test](https://metacpan.org/pod/Plack::Test)

    Also allows you to make [HTTP::Request](https://metacpan.org/pod/HTTP::Request) requests against a [PSGI](https://metacpan.org/pod/PSGI) app and get the appropriate [HTTP::Response](https://metacpan.org/pod/HTTP::Response) response back.
    Doesn't provide any special tools for interrogating that response.  This module in fact uses this one internally.

- [Test::LWP::UserAgent](https://metacpan.org/pod/Test::LWP::UserAgent)

    This is a subclass of [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) that can return responses from a local PSGI app, similar to the way this module instruments
    an instance of [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) for similar purposes.  The limitation to this approach is that it cannot be used with classes which
    cannot be used with subclasses of [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent).  By contrast, this module can instrument an existing [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) object
    without having to rebless it into another class or other such shenanigans.  If you can at least get access to another class's user
    agent instance, it can be used with [Test2::Tools::HTTP](https://metacpan.org/pod/Test2::Tools::HTTP)'s mock website system.  Doesn't work with anything that is not an
    [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) object.

- [LWP::Protocol::PSGI](https://metacpan.org/pod/LWP::Protocol::PSGI)

    Provides a similar functionality to [Test::LWP::UserAgent](https://metacpan.org/pod/Test::LWP::UserAgent), but registers apps globally with [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) so that you don't even
    need access to a specific [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) object.  Also doesn't work with anything that is not an [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) object.  It
    is worth reading the section "DIFFERENCES WITH OTHER MODULES" in this modules documentation before you decide which module to use.

# AUTHOR

Graham Ollis <plicease@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2018 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
