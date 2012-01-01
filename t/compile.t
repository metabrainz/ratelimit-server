#!/usr/bin/env perl
# vi: set ts=4 sw=4 :

use warnings;
use strict;

use Test::More tests => 2;
require_ok("RateLimitServer");

subtest "request id" => sub {
	plan tests => 4;

	my $req = "get_size";
	my $ans = "size=0 keys=0";

	is RateLimitServer::process_request($req), $ans, "request without an id";
	is RateLimitServer::process_request("27823 $req"), "27823 $ans", "request with an id";
	is RateLimitServer::process_request("000867465 $req"), "000867465 $ans", "request with an id starting with zero";
	is RateLimitServer::process_request("394769760968709384567 $req"), "394769760968709384567 $ans", "request with a large id";
};

