// killrel.ks - node to null relative velocity at closest approach
// RUN killrel.
// Needs a target and an existing encounter.

IF NOT HASTARGET {
    PRINT "killrel: set a target first.".
} ELSE {

// ---- find closest approach by sampling ------------------------------
LOCAL t0 IS TIME:SECONDS + 5.
LOCAL span IS SHIP:ORBIT:PERIOD.
IF TARGET:ORBIT:PERIOD < span { SET span TO TARGET:ORBIT:PERIOD. }
LOCAL t1 IS t0 + span * 1.5.

LOCAL best IS 1e14.
LOCAL bestT IS t0.
LOCAL lo IS t0.
LOCAL hi IS t1.
LOCAL samples IS 80.

FROM { LOCAL pass IS 0. } UNTIL pass > 2 STEP { SET pass TO pass+1. } DO {
    LOCAL dt IS (hi - lo) / samples.
    SET best TO 1e14.
    FROM { LOCAL i IS 0. } UNTIL i > samples STEP { SET i TO i+1. } DO {
        LOCAL t IS lo + i*dt.
        LOCAL sep IS (POSITIONAT(SHIP, t) - POSITIONAT(TARGET, t)):MAG.
        IF sep < best { SET best TO sep. SET bestT TO t. }
    }
    SET lo TO MAX(t0, bestT - dt*2).
    SET hi TO MIN(t1, bestT + dt*2).
    SET samples TO 24.
}

PRINT "killrel: closest approach " + ROUND(best/1000, 2) + " km".
PRINT "         in " + ROUND(bestT - TIME:SECONDS) + " s".

// ---- relative velocity there ----------------------------------------
LOCAL vShip IS VELOCITYAT(SHIP, bestT):ORBIT.
LOCAL vTgt IS VELOCITYAT(TARGET, bestT):ORBIT.
LOCAL vRel IS vTgt - vShip.

PRINT "         relative speed " + ROUND(vRel:MAG, 1) + " m/s".

// ---- project into node axes at that moment ---------------------------
LOCAL pos IS POSITIONAT(SHIP, bestT) - POSITIONAT(SHIP:BODY, bestT).
LOCAL basisP IS vShip:NORMALIZED.
LOCAL basisN IS VCRS(vShip, pos):NORMALIZED.
LOCAL basisR IS VCRS(basisN, basisP):NORMALIZED.

ADD NODE(bestT,
    VDOT(vRel, basisR),
    VDOT(vRel, basisN),
    VDOT(vRel, basisP)).

PRINT "         node added, " + ROUND(vRel:MAG,1) + " m/s to match.".

}
