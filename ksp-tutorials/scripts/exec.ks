// exec.ks - execute the next maneuver node
// RUNONCEPATH("0:/exec.ks"). then: EXECNODE().
//
// Handles alignment, rails warp to the burn, half-burn lead-in, and a
// throttle taper at the end so you don't overshoot by a few m/s.

SET G0 TO 9.80665.

FUNCTION E_ISP {
    LOCAL num IS 0. LOCAL den IS 0.
    LIST ENGINES IN es.
    FOR e IN es {
        IF e:IGNITION AND NOT e:FLAMEOUT AND e:ISP > 0 {
            SET num TO num + e:AVAILABLETHRUST.
            SET den TO den + e:AVAILABLETHRUST / e:ISP.
        }
    }
    IF den = 0 { RETURN 0. }
    RETURN num / den.
}

FUNCTION EXECNODE {
    PARAMETER autowarp IS TRUE.
    PARAMETER leadTime IS 30.       // settle + align margin before ignition

    IF NOT HASNODE {
        PRINT "exec: no maneuver node.".
        RETURN.
    }

    LOCAL nd IS NEXTNODE.
    LOCAL dv0 IS nd:BURNVECTOR.
    LOCAL dvTotal IS dv0:MAG.

    LOCAL f IS SHIP:AVAILABLETHRUST.
    LOCAL isp IS E_ISP().
    IF f <= 0 OR isp <= 0 {
        PRINT "exec: no thrust. Stage or activate an engine first.".
        RETURN.
    }
    LOCAL ve IS isp * G0.
    LOCAL burnT IS (SHIP:MASS * ve / f) * (1 - CONSTANT:E^(-dvTotal/ve)).

    PRINT "exec: " + ROUND(dvTotal,1) + " m/s, burn " + ROUND(burnT,1) + " s".
    PRINT "      node in " + ROUND(nd:ETA) + " s".

    IF burnT/2 > nd:ETA {
        PRINT "exec: WARNING - node is closer than half the burn time.".
        PRINT "      You are already late. Burning anyway.".
    }

    SAS OFF.
    LOCK THROTTLE TO 0.

    // ---- warp ----------------------------------------------------------
    LOCAL ignition IS TIME:SECONDS + nd:ETA - burnT/2.
    IF autowarp AND (ignition - leadTime) > TIME:SECONDS + 30 {
        PRINT "exec: warping...".
        WARPTO(ignition - leadTime).
        WAIT UNTIL TIME:SECONDS >= ignition - leadTime
                   OR KUNIVERSE:TIMEWARP:RATE = 1.
        KUNIVERSE:TIMEWARP:CANCELWARP().
        WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED AND SHIP:UNPACKED.
    }

    // ---- align ---------------------------------------------------------
    LOCAL steerDir IS nd:BURNVECTOR.
    LOCK STEERING TO steerDir.
    PRINT "exec: aligning...".
    WAIT UNTIL VANG(SHIP:FACING:VECTOR, nd:BURNVECTOR) < 0.5
               OR TIME:SECONDS > ignition.

    // ---- wait for ignition ---------------------------------------------
    SET ignition TO TIME:SECONDS + nd:ETA - burnT/2.
    IF ignition > TIME:SECONDS {
        WAIT UNTIL TIME:SECONDS >= ignition.
    }

    // ---- burn ------------------------------------------------------------
    PRINT "exec: ignition.".
    LOCAL thr IS 0.
    LOCK THROTTLE TO thr.
    LOCAL burning IS TRUE.

    UNTIL NOT burning {
        LOCAL rem IS nd:BURNVECTOR.
        LOCAL maxAcc IS SHIP:AVAILABLETHRUST / SHIP:MASS.

        IF maxAcc <= 0 {
            PRINT "exec: thrust lost.".
            SET burning TO FALSE.
        } ELSE {
            // hold the commanded direction steady once the remainder gets
            // small - chasing a 0.2 m/s vector just makes the ship wobble
            IF rem:MAG > 2 { SET steerDir TO rem. }

            // full throttle until roughly the last 2 seconds, then taper
            SET thr TO MIN(1, MAX(0.02, rem:MAG / (maxAcc * 2))).

            // stop the moment the remaining burn flips to the far side
            IF VDOT(dv0, rem) < 0 {
                SET burning TO FALSE.
            }
        }
        WAIT 0.
    }

    LOCK THROTTLE TO 0.
    WAIT 0.
    UNLOCK THROTTLE.
    UNLOCK STEERING.
    SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.

    PRINT "exec: done. residual " + ROUND(nd:BURNVECTOR:MAG, 2) + " m/s".
    IF nd:BURNVECTOR:MAG < 0.5 {
        REMOVE nd.
        PRINT "exec: node removed.".
    } ELSE {
        PRINT "exec: node left in place - trim it or re-run.".
    }
}

PRINT "exec.ks loaded. Call EXECNODE().".

