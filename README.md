Execution
=========

bind addr and port are specified in the ./run script (arguments to ratelimit-server).

Logs
====

"tail -F -s 0.1 log/main/current | tain64local" - tail the busy log (all
requests/responses)

"tail -F -s 0.1 log/quiet/current | tain64local" - tail the quiet log
(excludes requests/responses, so this is just start/stop/error, etc)

Monitoring
==========

"./top" - every 10 seconds, shows the most-requested keys, their rates,
limits, what proportion of requests are being denied, etc.

Debugging
=========

"./request COMMAND ..." - simple hook to send a request to the ratelimit-server
e.g.
	./request get_size

Slightly less crap version:
"./ratelimit-client ADDR PORT QUERY"
e.g.
	"./ratelimit-client 10.1.1.245 2000 get_size"

snmp
====

http://stats.musicbrainz.org/mrtg/drraw/drraw.cgi?Mode=view;Dashboard=1262470284.29707

From left to right:

- number of keys.  Not amazingly useful.  This is just the size of the
  in-memory Perl hash in the ratelimit-server.  Starts at zero when the
  ratelimit-server (re-)starts; grows.
  (Think: scalar keys %hash)

- bucket spread.  Represents the percentage of buckets used in the above hash.
  (Think: scalar %hash)

- "ws global" requests.  Currently shows requests/refusals per second.
  Ideally of course refusals should be zero.

- "ws global" peak rate.  This is the peak rate per time-period.  We currently
  have ws-global set to 900 per 10 seconds, so the max rate is 900.  If this
  is constantly pegged at 900, it means that (during every 5-minute interval)
  we hit the 900 limit at least once.

So in summary:

- keys: pretty much ignore
- spread: 100% good, 0% bad
- ws global requests:
  - requests represents our traffic
  - refusals: 0 good, higher=bad
- ws global peak rate:
  - pegged at our configured limit = bad, lower=good

Still plenty of work to be done to get that packaged up, to get it to work
across carl too, etc.

TODO:

- have snmpd on carl/lenny listen on specific IPs, not 0.0.0.0
- have scooby mrtg monitor snmp on ratelimit.localdomain
?

- package it up

