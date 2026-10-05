// intercept.ks - shrink a sloppy encounter into a tight one
// RUNONCEPATH("0:/intercept.ks"). then: TUNE().
//
// Needs: a TARGET set, and a maneuver node that already produces a rough
// encounter (or at least gets you into the neighbourhood).
//
// Hill-climbs the node's prograde / radial / normal / timing until the
// predicted closest approach stops improving. Pure search - no orbital
// mechanics required, which is why it copes with cases a Hohmann solver
// would choke on.
//
// Raise the instruction budget first or this crawls:
//   SET CONFIG:IPU TO 2000.

// --------------------------------------------------------------- scoring

// Closest approach between ship and target over [t0, t1].
// Coarse sweep, then two refinement passes around the best sample.
FUNCTION CLOSEST {
    PARAMETER t0, t1.
    PARAMETER samples IS 60.

    LOCAL lo IS t0.
    LOCAL hi IS t1.
    LOCAL best IS 1e14.
    LOCAL bestT IS t0.

    FROM { LOCAL pass IS 0. } UNTIL pass > 2 STEP { SET pass TO pass+1. } DO {
        LOCAL dt IS (hi - lo) / samples.
        SET best TO 1e14.
        FROM { LOCAL i IS 0. } UNTIL i > samples STEP { SET i TO i+1. } DO {
            LOCAL t IS lo + i*dt.
            LOCAL d IS (POSITIONAT(SHIP, t) - POSITIONAT(TARGET, t)):MAG.
            IF d < best {
                SET best TO d.
                SET bestT TO t.
            }
        }
        // narrow the window around the winner and go again
        SET lo TO MAX(t0, bestT - dt*2).
        SET hi TO MIN(t1, bestT + dt*2).
        SET samples TO 20.
    }

    RETURN LIST(best, bestT).
}

// ------------------------------------------------------------ node nudge

FUNCTION NUDGE {
    PARAMETER nd, dP, dR, dN, dT.
    SET nd:PROGRADE TO nd:PROGRADE + dP.
    SET nd:RADIALOUT TO nd:RADIALOUT + dR.
    SET nd:NORMAL TO nd:NORMAL + dN.
    SET nd:ETA TO MAX(15, nd:ETA + dT).
    WAIT 0.     // let the game recompute the predicted trajectory
}

// ---------------------------------------------------------------- driver

FUNCTION TUNE {
    PARAMETER span IS 0.            // seconds of trajectory to search
    PARAMETER dvStep IS 5.          // starting dv stride, m/s
    PARAMETER tStep IS 120.         // starting timing stride, s
    PARAMETER floorStep IS 0.05.    // stop when steps get this small

    IF NOT HASTARGET { PRINT "tune: set a target first.". RETURN. }
    IF NOT HASNODE   { PRINT "tune: need a maneuver node.". RETURN. }

    LOCAL nd IS NEXTNODE.

    // default search window: from the node forward by one target period,
    // which covers any encounter the node can plausibly produce
    IF span <= 0 {
        SET span TO TARGET:ORBIT:PERIOD.
        IF span > 200000000 { SET span TO 200000000. }
    }

    LOCAL t0 IS TIME:SECONDS + nd:ETA.
    LOCAL t1 IS t0 + span.

    CLEARSCREEN.
    PRINT "=== intercept tune ===".
    PRINT "Target : " + TARGET:NAME.
    PRINT "Window : " + ROUND(span/3600,1) + " h from the node".
    PRINT " ".

    LOCAL res IS CLOSEST(t0, t1).
    LOCAL best IS res[0].
    PRINT "start  : " + ROUND(best/1000, 1) + " km".

    LOCAL stride IS 1.
    LOCAL iter IS 0.

    UNTIL stride < floorStep OR iter > 400 {

        LOCAL improved IS FALSE.
        LOCAL dP IS dvStep * stride.
        LOCAL dT IS tStep * stride.

        // six directions: +/- prograde, +/- radial, +/- normal, +/- timing
        LOCAL moves IS LIST(
            LIST( dP, 0, 0, 0), LIST(-dP, 0, 0, 0),
            LIST(0,  dP, 0, 0), LIST(0, -dP, 0, 0),
            LIST(0, 0,  dP, 0), LIST(0, 0, -dP, 0),
            LIST(0, 0, 0,  dT), LIST(0, 0, 0, -dT)
        ).

        FOR mv IN moves {
            SET iter TO iter + 1.
            NUDGE(nd, mv[0], mv[1], mv[2], mv[3]).
            LOCAL s IS CLOSEST(t0, t1).
            IF s[0] < best {
                SET best TO s[0].
                SET improved TO TRUE.
            } ELSE {
                // revert
                NUDGE(nd, -mv[0], -mv[1], -mv[2], -mv[3]).
            }
        }

        IF NOT improved {
            SET stride TO stride / 2.
            PRINT "       " + ROUND(best/1000, 2) + " km   (stride "
                + ROUND(stride, 3) + ")".
        }
    }

    LOCAL fin IS CLOSEST(t0, t1).
    PRINT " ".
    PRINT "final  : " + ROUND(fin[0]/1000, 2) + " km".
    PRINT "at     : T+" + ROUND(fin[1] - TIME:SECONDS) + " s".
    PRINT "node dv: " + ROUND(nd:DELTAV:MAG, 1) + " m/s".
    PRINT " ".
    PRINT "Run EXECNODE() when you are happy with it.".
}

PRINT "intercept.ks loaded. SET CONFIG:IPU TO 2000. then TUNE().".

