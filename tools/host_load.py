"""Wall-clock limits for checks that run the game, scaled for a busy host.

A game-running check waits for real frames, so its time limits only stop a hung
process; they are never the thing a check proves. On a host that other work
loads, the same run takes longer. `limit(seconds)` stretches a base limit by
the current load per processor (at least 1x, at most MAX_SCALE). The
environment variable EGGSHELL_TIMEOUT_SCALE sets the factor instead.
"""

import os

MAX_SCALE = 12.0


def scale():
    configured = os.environ.get("EGGSHELL_TIMEOUT_SCALE", "")
    if configured:
        return max(1.0, float(configured))
    try:
        load = os.getloadavg()[0]
    except OSError:
        return 1.0
    return min(MAX_SCALE, max(1.0, load / (os.cpu_count() or 1)))


def limit(seconds):
    return seconds * scale()
