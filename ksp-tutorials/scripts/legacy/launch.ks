// launch.ks - ascent to a chosen apoapsis and inclination
//
// Two ways to use it:
//   RUN launch(100000, 0).            // launches immediately
//   RUNONCEPATH("0:/launch.ks").      // just loads LAUNCH() and AZFOR()
//   LAUNCH(100000, 0).
//
//   LAUNCH(apAlt, inc, turnEnd)
//     apAlt    target apoapsis, metres. 100000 = 100 km.
//     inc      target inclination, degrees. Negative flies the southern
//              branch of the same inclination. Default 0.
//     turnEnd  altitude where the gravity turn finishes pitching over.
//              Default 45000, fine for most Kerbin lifters.
//
// Ends parked at apoapsis with a circularisation node ready.
// Run EXECNODE() from exec.ks to close the orbit.

PARAMETER autoApAlt IS -1.      // script args, only used by RUN
PARAMETER autoInc IS 0.

FUNCTION AUTOSTAGE {
    IF SHIP:AVAILABLETHRUST < 0.01 AND STAGE:READY {
        STAGE.
        WAIT 0.7.
        RETURN TRUE.
    }
    // drop spent boosters that flamed out while others still burn
    LIST ENGINES IN es.
    FOR eng IN es {
        IF eng:FLAMEOUT AND eng:IGNITION AND STAGE:READY {
            STAGE.
            WAIT 0.7.
            RETURN TRUE.
        }
    }
    RETURN FALSE.
}

// Launch azimuth for an inclination, corrected for the body's rotation.
FUNCTION AZFOR {
    PARAMETER inc.
    PARAMETER apAlt.

    LOCAL lat IS SHIP:LATITUDE.
    LOCAL want IS ABS(inc).

    IF want < ABS(lat) {
        PRINT "launch: inclination " + want + " is below latitude " + ROUND(lat,2).
        PRINT "        clamping to " + ROUND(ABS(lat),2) + " deg.".
        SET want TO ABS(lat).
    }

    LOCAL azI IS ARCSIN(MIN(1, MAX(-1, COS(want) / COS(lat)))).

    // rotating frame correction - the pad is already moving east
    LOCAL rad IS SHIP:BODY:RADIUS + apAlt.
    LOCAL vOrb IS SQRT(SHIP:BODY:MU / rad).
    LOCAL vRot IS (2 * CONSTANT:PI * SHIP:BODY:RADIUS
                   / SHIP:BODY:ROTATIONPERIOD) * COS(lat).
    LOCAL vx IS vOrb * SIN(azI) - vRot.
    LOCAL vy IS vOrb * COS(azI).
    LOCAL az IS ARCTAN2(vx, vy).

    IF inc < 0 { SET az TO 180 - az. }      // southern branch
    RETURN az.
}

FUNCTION LAUNCH {
    PARAMETER apAlt IS 100000.
    PARAMETER inc IS 0.
    PARAMETER turnEnd IS 45000.

    LOCAL az IS AZFOR(inc, apAlt).
    LOCAL turnStart IS 250.

    CLEARSCREEN.
    PRINT "=== launch ===".
    PRINT "Apoapsis : " + ROUND(apAlt/1000,1) + " km".
    PRINT "Inclin.  : " + inc + " deg".
    PRINT "Azimuth  : " + ROUND(az, 2) + " deg".
    PRINT " ".

    SAS OFF.
    LOCK THROTTLE TO 1.
    LOCK STEERING TO HEADING(az, 90).

    IF SHIP:STATUS = "PRELAUNCH" { STAGE. WAIT 1. }
    IF SHIP:AVAILABLETHRUST < 0.01 { STAGE. WAIT 1. }

    LOCAL pitch IS 90.
    LOCK STEERING TO HEADING(az, pitch).

    // ---- powered ascent ------------------------------------------------
    UNTIL SHIP:APOAPSIS >= apAlt {
        AUTOSTAGE().

        IF SHIP:ALTITUDE > turnStart {
            LOCAL frac IS (SHIP:ALTITUDE - turnStart) / (turnEnd - turnStart).
            SET frac TO MIN(1, MAX(0, frac)).
            SET pitch TO 90 * (1 - frac^0.72).
            SET pitch TO MAX(3, pitch).
        }

        // ease off as apoapsis approaches so we do not sail past it
        LOCAL remain IS apAlt - SHIP:APOAPSIS.
        IF remain < apAlt * 0.03 {
            LOCK THROTTLE TO MAX(0.08, remain / (apAlt * 0.03)).
        }

        PRINT "alt   " + ROUND(SHIP:ALTITUDE):TOSTRING:PADLEFT(8) + " m  " AT (0,5).
        PRINT "ap    " + ROUND(SHIP:APOAPSIS):TOSTRING:PADLEFT(8) + " m  " AT (0,6).
        PRINT "pitch " + ROUND(pitch,1):TOSTRING:PADLEFT(8) + " deg" AT (0,7).
        WAIT 0.
    }

    LOCK THROTTLE TO 0.
    PRINT " ".
    PRINT "launch: apoapsis reached, coasting out.".

    // ---- coast clear of the atmosphere ---------------------------------
    LOCK STEERING TO SHIP:PROGRADE.
    LOCAL atmTop IS SHIP:BODY:ATM:HEIGHT.
    IF atmTop > 0 {
        UNTIL SHIP:ALTITUDE > atmTop {
            AUTOSTAGE().
            // trim if drag has eaten the apoapsis
            IF SHIP:APOAPSIS < apAlt * 0.98 {
                LOCK THROTTLE TO 0.15.
            } ELSE {
                LOCK THROTTLE TO 0.
            }
            WAIT 0.
        }
    }
    LOCK THROTTLE TO 0.
    UNLOCK THROTTLE.
    UNLOCK STEERING.
    SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.

    // ---- hand off a circularisation node -------------------------------
    LOCAL rad IS SHIP:BODY:RADIUS + SHIP:APOAPSIS.
    LOCAL vAp IS SQRT(SHIP:BODY:MU * (2/rad - 1/SHIP:ORBIT:SEMIMAJORAXIS)).
    LOCAL vCirc IS SQRT(SHIP:BODY:MU / rad).
    LOCAL dvCirc IS vCirc - vAp.

    ADD NODE(TIME:SECONDS + ETA:APOAPSIS, 0, 0, dvCirc).

    PRINT "launch: on orbit path, " + ROUND(SHIP:PERIAPSIS/1000,1) + " x "
        + ROUND(SHIP:APOAPSIS/1000,1) + " km".
    PRINT "        inclination " + ROUND(SHIP:ORBIT:INCLINATION, 2) + " deg".
    PRINT "        circ node added: " + ROUND(dvCirc,1) + " m/s".
    PRINT "        run EXECNODE() to close the orbit.".
}

// If called as RUN launch(apAlt, inc), go straight away.
// If loaded with RUNONCEPATH, just leave the functions defined.
IF autoApAlt > 0 {
    LAUNCH(autoApAlt, autoInc).
} ELSE {
    PRINT "launch.ks loaded. Call LAUNCH(100000, 0).".
}

