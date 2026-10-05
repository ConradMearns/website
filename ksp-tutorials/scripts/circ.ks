// circ.ks - add a circularisation node
// RUN circ.        node at apoapsis
// RUN circ("pe").  node at periapsis

PARAMETER spot IS "ap".

LOCAL mu IS SHIP:BODY:MU.
LOCAL sma IS SHIP:ORBIT:SEMIMAJORAXIS.
LOCAL altAt IS SHIP:APOAPSIS.
LOCAL tGo IS ETA:APOAPSIS.

IF spot = "pe" {
    SET altAt TO SHIP:PERIAPSIS.
    SET tGo TO ETA:PERIAPSIS.
}

IF altAt < SHIP:BODY:ATM:HEIGHT {
    PRINT "circ: WARNING - that point is inside the atmosphere.".
}

LOCAL rad IS SHIP:BODY:RADIUS + altAt.
LOCAL vNow IS SQRT(mu * (2/rad - 1/sma)).
LOCAL vCirc IS SQRT(mu / rad).
LOCAL dv IS vCirc - vNow.

ADD NODE(TIME:SECONDS + tGo, 0, 0, dv).

PRINT "circ: " + ROUND(dv,1) + " m/s in " + ROUND(tGo) + " s".
PRINT "      target " + ROUND(altAt/1000,1) + " km circular".
