// launchrdv.ks - launch into a target's orbital plane
// Needs launch.ks loaded first:
//   RUNONCEPATH("0:/launch.ks").
//   RUNONCEPATH("0:/launchrdv.ks").
//   TUNE / set your target, then: LAUNCHRDV(90000).
//
//   LAUNCHRDV(apAlt, lead)
//     apAlt  parking apoapsis. Keep it BELOW the target so you catch up
//            from behind. Default 90000.
//     lead   seconds to launch ahead of the plane crossing. Default 45.
//
// This solves the plane, not the phasing. You will come out coplanar with
// the target but at some random phase angle - close that afterwards with a
// Hohmann node plus TUNE() from intercept.ks.

// Signed angle between our radius vector and the target's orbital plane.
// Zero exactly when the launch site passes through the plane.
FUNCTION PLANEERR {
    LOCAL rShip IS -SHIP:BODY:POSITION.
    LOCAL rTgt IS TARGET:POSITION - SHIP:BODY:POSITION.
    LOCAL n IS VCRS(rTgt, TARGET:VELOCITY:ORBIT):NORMALIZED.
    RETURN 90 - VANG(rShip, n).
}

// Is the target crossing northward here? Decides which branch of the
// inclination we fly - north-east or south-east.
FUNCTION TGTGOINGNORTH {
    RETURN VDOT(TARGET:VELOCITY:ORBIT:NORMALIZED, SHIP:NORTH:VECTOR) > 0.
}

FUNCTION LAUNCHRDV {
    PARAMETER apAlt IS 90000.
    PARAMETER lead IS 45.

    IF NOT HASTARGET {
        PRINT "launchrdv: set a target first.".
        RETURN.
    }

    LOCAL inc IS TARGET:ORBIT:INCLINATION.

    CLEARSCREEN.
    PRINT "=== rendezvous launch ===".
    PRINT "Target   : " + TARGET:NAME.
    PRINT "Their inc: " + ROUND(inc, 3) + " deg".
    PRINT "Their alt: " + ROUND(TARGET:ALTITUDE/1000, 1) + " km".
    PRINT "Parking  : " + ROUND(apAlt/1000, 1) + " km".
    PRINT " ".

    IF inc < ABS(SHIP:LATITUDE) - 0.1 {
        PRINT "launchrdv: WARNING - target inclination is below your".
        PRINT "           latitude. You cannot reach that plane from here.".
        PRINT "           Launching to the closest achievable plane.".
    }

    IF apAlt > TARGET:ALTITUDE {
        PRINT "launchrdv: NOTE - parking above the target means it catches".
        PRINT "           you from behind, which takes longer. Consider a".
        PRINT "           lower parking orbit.".
    }

    // ---- wait for the plane crossing ------------------------------------
    PRINT "launchrdv: waiting for the plane...".
    LOCAL rotP IS SHIP:BODY:ROTATIONPERIOD.
    LOCAL waiting IS TRUE.

    UNTIL NOT waiting {
        LOCAL e0 IS PLANEERR().
        WAIT 1.
        LOCAL e1 IS PLANEERR().
        LOCAL rate IS e1 - e0.               // degrees per second

        IF ABS(rate) < 0.000001 {
            WAIT 5.
        } ELSE {
            LOCAL tz IS -e1 / rate.          // seconds until err hits zero

            IF tz <= 0 OR tz > rotP {
                // crossing is behind us or implausibly far - step forward
                WARPTO(TIME:SECONDS + rotP / 40).
                WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.
            } ELSE IF tz > lead + 60 {
                PRINT "           " + ROUND(tz - lead) + " s to launch   " AT (0, 8).
                WARPTO(TIME:SECONDS + tz - lead - 30).
                WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED AND SHIP:UNPACKED.
            } ELSE {
                KUNIVERSE:TIMEWARP:CANCELWARP().
                WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.
                LOCAL t0 IS TIME:SECONDS + MAX(0, tz - lead).
                UNTIL TIME:SECONDS >= t0 {
                    PRINT "           T-" + ROUND(t0 - TIME:SECONDS) + "   " AT (0, 8).
                    WAIT 0.2.
                }
                SET waiting TO FALSE.
            }
        }
    }

    // ---- pick the branch and go ------------------------------------------
    LOCAL signedInc IS inc.
    IF NOT TGTGOINGNORTH() { SET signedInc TO -inc. }

    PRINT " ".
    PRINT "launchrdv: liftoff, inclination " + ROUND(signedInc, 2) + " deg".
    LAUNCH(apAlt, signedInc).

    PRINT " ".
    PRINT "launchrdv: coplanar. Relative inclination now "
        + ROUND(VANG(VCRS(-SHIP:BODY:POSITION, SHIP:VELOCITY:ORBIT),
                     VCRS(TARGET:POSITION - SHIP:BODY:POSITION,
                          TARGET:VELOCITY:ORBIT)), 3) + " deg".
    PRINT "           Circularise, then build a transfer node and TUNE().".
}

PRINT "launchrdv.ks loaded. Set a target, then LAUNCHRDV(90000).".

