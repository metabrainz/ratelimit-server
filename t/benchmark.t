#!/usr/bin/env perl
# vi: set ts=4 sw=4 :

use warnings;
use strict;

use Test::More tests => 2;

require_ok("RateLimitServer");

no warnings qw/ once redefine /;
local *RateLimitServer::find_ratelimit_params = sub {
    # ($over_limit, $rate, $limit, $period, $strict, $key, $keep_stats);
	return (undef, undef, 22, 20, 1, $_[0], 0);
};

use Benchmark ':all';

timethis(100000,
	sub {
		my $key = "key ".int(rand 10000);
		my $ans = RateLimitServer::process_request("over_limit $key");
	},
);

ok 1, "benchmark completed";

# eof benchmark.t
