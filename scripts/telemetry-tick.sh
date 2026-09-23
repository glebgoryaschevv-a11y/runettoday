#!/bin/sh
export HOME="/Users/goryachev"
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH
cd "/Users/goryachev/runettoday" || exit 1
./cli/runettoday device telemetry >> /tmp/runettoday-telemetry.log 2>&1
