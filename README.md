# Test2::Tools::HTTP [![Build Status](https://secure.travis-ci.org/plicease/Test2-Tools-HTTP.png)](http://travis-ci.org/plicease/Test2-Tools-HTTP)

Test HTTP / PSGI

# SYNOPSIS

    use Test2::V0;
    use Test2::Tools::HTTP;
    use HTTP::Request::Common;
    
    psgi_add_app sub { [ 200, [ 'Content-Type' => 'text/plain;charset=utf-8' ], [ 'Test Document' ] ] };
    
    # Internally test the app from within the .t file itself
    http_request(
      # if no host/port/protocol is given then
      # the default PSGI app above is assumed
      GET('/'),
      http_response {
    
        http_code '200';
    
        # http_response {} is a subclass of object {}
        # for HTTP::Response objects only, so you can
        # also use object {} style comparisons:
        call code => 200; 

        http_content_type match qr/^text\/(html|plain)$/;
        http_content_type_charset 'UTF-8';
        http_content qr/Test/;
      }
    );

    use Test2::Tools::JSON::Pointer;
    
    # test an external website
    http_request(
      GET('http://example.test'),
      http_response {
        http_is_success;
        # JSON pointer { "key":"val" }
        http_content json '/key' => 'val';
      }
    );
    
    done_testing;

# DESCRIPTION

This module provides an interface for testing websites and PSGI based apps with a [Test2](https://metacpan.org/pod/Test2) style comparisons interface.

# FUNCTIONS

## http\_request

    http_request($request);
    http_request($request, $check);
    http_request($request, $check, $message);

Make a HTTP request.  If there is a client level error then it will fail immediately.  Otherwise you can use a
`object {}` or `http_request` comparison check to inspect the HTTP response and ensure that it matches what you
expect.

## http\_response

    my $check = http_response {
      ... # object or http checks
    };

This is a comparison check specific to HTTP::Response objects.  You may include these subchecks:

### http\_code

    http_response {
      http_code $check;
    };

The HTTP status code should match the given check.

### http\_message

    http_response {
      http_message $check;
    };

The HTTP status message ('OK' for 200, 'Not Found' for 404, etc) should match the given check.

### http\_content

    http_response {
      http_content $check;
    };

The decoded response body content.  This is the _decoded_ content, as for most application testing this is what you will be interested in.
If you want to test the undecoded content you can use call instead:

    http_response {
      call content => $check;
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

### http\_content\_type, http\_content\_type\_charset

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

### http\_content\_length

    http_response {
      http_content_length $check;
    };

Check that the `Content-Length` header matches the given check.

### http\_content\_length\_ok

    http_response {
      http_content_length_ok;
    };

Checks that the `Content-Length` header matches the actual length of the content.

### http\_location, http\_location\_uri

    http_response {
      http_location $check;
      http_location_uri $check;
    };

Check the `Location` HTTP header.  The `http_location_uri` variant converts `Location` to a [URI](https://metacpan.org/pod/URI) using the base URL of the response
so that it can be tested with [Test2::Tools::URL](https://metacpan.org/pod/Test2::Tools::URL).

## http\_last

    my $req  = http_last->req;
    my $res  = http_last->res;
    my $bool = http_last->ok;
    my $bool = http_last->connection_error;
    http_last->note;
    http_last->diag;

This returns the last transaction object, which you can use to get the last request, response and status information
related to the last `http_request`.

- http\_last->req

    The [HTTP::Request](https://metacpan.org/pod/HTTP::Request) object.

- http\_last->res

    The [HTTP::Response](https://metacpan.org/pod/HTTP::Response) object.

    Warning: In the case of a connection error, this may be a synthetic response produced by [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent), rather
    than an actual message from the remote end.

- http\_last->ok

    True if the last call to `http_request` passed.

- http\_last->connection\_error.

    True if there was a connection error during the last `http_request`.

- http\_last->note

    Send the request, response and ok to Test2's "note" output.

- http\_last->diag

    Send the request, response and ok to Test2's "diag" output.

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

## http\_ua

    http_ua(LWP::UserAgent->new);
    my $ua = http_ua;

Gets/sets the [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) object used to make requests against real web servers.  For tests against a PSGI app, this will NOT be used.
If not provided, the default [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) will call `env_proxy` and add an in-memory cookie jar.

## psgi\_app\_add

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

    This is a very capable web application testing module.  Definitely worth checking out, even if you aren't developing a [Mojolicious](https://metacpan.org/pod/Mojolicious) app since it can be used
    (with [Test::Mojo::Role::PSGI](https://metacpan.org/pod/Test::Mojo::Role::PSGI)) to test any PSGI application.

# AUTHOR

Graham Ollis <plicease@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2018 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
