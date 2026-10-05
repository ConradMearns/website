// perikick.ks - periapsis kick planner + executor for long low-TWR ejections
// Save as perikick.ks in Ships/Script, then: RUNONCEPATH("0:/perikick.ks").
//
//   KICKPLAN(vinf, maxBurn)   simulate the whole campaign, print the schedule
//   KICKRUN(vinf, maxBurn)    fly it, warping between passes
//
// vinf = hyperbolic excess velocity you need (m/s).
// Coplanar Kerbin ejection vinf, approx:
//   Duna 920 | Eve 1030 | Jool 2000 | Eeloo 2260 | Moho 2350 | Dres 1780
//
// maxBurn = seconds of thrust per pass (default 120). Smaller = more
// efficient, more passes, more elapsed time. This is the whole trade.

SET G0 TO 9.80665.

// ------------------------------------------------------------- helpers

FUNCTION K_ISP {
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

FUNCTION K_BURNTIME {
    PARAMETER dv, m, f, ve.
    IF f <= 0 OR ve <= 0 { RETURN -1. }
    RETURN (m * ve / f) * (1 - CONSTANT:E^(-dv/ve)).
}

// dv obtainable by burning for t seconds at mass m
FUNCTION K_DVIN {
    PARAMETER t, m, f, ve.
    LOCAL mdot IS f / ve.
    LOCAL mEnd IS m - mdot*t.
    IF mEnd <= 0 { RETURN 1e9. }        // would run dry
    RETURN ve * LN(m / mEnd).
}

FUNCTION K_FMT {
    PARAMETER sec.
    LOCAL spd IS KUNIVERSE:HOURSPERDAY * 3600.
    LOCAL d IS FLOOR(sec / spd).
    LOCAL h IS (sec - d*spd) / 3600.
    RETURN d + "d " + ROUND(h,1) + "h".
}

// ------------------------------------------------------------- planner

FUNCTION KICKPLAN {
    PARAMETER vinf.
    PARAMETER maxBurn IS 120.

    LOCAL mu  IS SHIP:BODY:MU.
    LOCAL rp  IS SHIP:BODY:RADIUS + SHIP:PERIAPSIS.
    LOCAL soi IS SHIP:BODY:SOIRADIUS.
    LOCAL f   IS SHIP:AVAILABLETHRUST.
    LOCAL isp IS K_ISP().

    IF f <= 0 OR isp <= 0 {
        PRINT "No active engine - stage/activate first.".
        RETURN.
    }

    LOCAL ve IS isp * G0.
    LOCAL m  IS SHIP:MASS.
    LOCAL m0 IS m.
    LOCAL vPeri  IS SQRT(mu * (2/rp - 1/SHIP:ORBIT:SEMIMAJORAXIS)).
    LOCAL vTarget IS SQRT(vinf*vinf + 2*mu/rp).
    LOCAL dvTotal IS vTarget - vPeri.

    CLEARSCREEN.
    PRINT "=== Periapsis kick plan ===".
    PRINT "Body      : " + SHIP:BODY:NAME.
    PRINT "Periapsis : " + ROUND(SHIP:PERIAPSIS/1000,1) + " km".
    PRINT "Thrust    : " + ROUND(f,1) + " kN   Isp " + ROUND(isp) + " s".
    PRINT "TWR(peri) : " + ROUND(f / (m * mu/(rp*rp)), 3).
    PRINT "vinf      : " + ROUND(vinf) + " m/s".
    PRINT "Total dv  : " + ROUND(dvTotal,1) + " m/s".
    PRINT "One burn  : " + ROUND(K_BURNTIME(dvTotal, m, f, ve),1) + " s if done in a single go".
    PRINT " ".
    PRINT "pass    dv    burn      Ap(Mm)     period    elapsed".
    PRINT "-----------------------------------------------------".

    LOCAL elapsed IS 0.
    LOCAL pass IS 0.
    LOCAL apCap IS soi * 0.85.        // stay comfortably inside the SOI
    LOCAL finished IS FALSE.
    LOCAL bailout IS FALSE.

    UNTIL finished OR bailout {
        SET pass TO pass + 1.
        IF pass > 60 { SET bailout TO TRUE. BREAK. }

        LOCAL dvRem IS vTarget - vPeri.
        LOCAL dvThis IS K_DVIN(maxBurn, m, f, ve).
        LOCAL burnT IS maxBurn.

        IF dvThis >= dvRem {
            SET dvThis TO dvRem.
            SET burnT TO K_BURNTIME(dvThis, m, f, ve).
            SET finished TO TRUE.
        }

        // provisional new state
        LOCAL vNew IS vPeri + dvThis.
        LOCAL aNew IS 1 / (2/rp - vNew*vNew/mu).
        LOCAL apNew IS 0.
        IF aNew > 0 { SET apNew TO 2*aNew - rp. } ELSE { SET apNew TO 1e12. }

        // if this kick would throw Ap past the cap without finishing the job,
        // clamp it: the remainder becomes one long final burn
        IF NOT finished AND apNew > apCap {
            LOCAL aCap IS (apCap + rp) / 2.
            LOCAL vCap IS SQRT(mu * (2/rp - 1/aCap)).
            IF vCap > vPeri {
                SET dvThis TO vCap - vPeri.
                SET burnT TO K_BURNTIME(dvThis, m, f, ve).
                SET vNew TO vCap.
                SET aNew TO aCap.
                SET apNew TO apCap.
            }
        }

        SET m TO m * CONSTANT:E^(-dvThis/ve).
        SET vPeri TO vNew.

        LOCAL period IS 0.
        IF aNew > 0 AND NOT finished {
            SET period TO 2 * CONSTANT:PI * SQRT(aNew^3 / mu).
            SET elapsed TO elapsed + period.
        }

        LOCAL apStr IS "hyperbolic".
        IF aNew > 0 { SET apStr TO ROUND(apNew/1000000, 2):TOSTRING. }
        LOCAL perStr IS "-".
        IF period > 0 { SET perStr TO K_FMT(period). }

        PRINT pass:TOSTRING:PADLEFT(4)
            + ROUND(dvThis,0):TOSTRING:PADLEFT(7)
            + (ROUND(burnT,0)+"s"):PADLEFT(7)
            + apStr:PADLEFT(12)
            + perStr:PADLEFT(11)
            + K_FMT(elapsed):PADLEFT(11).

        // if we clamped at the cap and still need a lot, the next pass is the
        // long final burn - loop will handle it, but flag it below
        IF NOT finished AND apNew >= apCap AND (vTarget - vPeri) > K_DVIN(maxBurn, m, f, ve) {
            LOCAL dvFinal IS vTarget - vPeri.
            LOCAL tFinal IS K_BURNTIME(dvFinal, m, f, ve).
            PRINT " ".
            PRINT "Ap is now at the SOI limit. Remaining " + ROUND(dvFinal,0)
                + " m/s must go in one".
            PRINT "final burn of " + ROUND(tFinal,0) + " s ("
                + ROUND(tFinal/60,1) + " min).".
            SET finished TO TRUE.
        }
    }

    PRINT " ".
    IF bailout {
        PRINT "Gave up after 60 passes - maxBurn is too small for this dv.".
        RETURN.
    }
    PRINT "Passes    : " + pass.
    PRINT "Elapsed   : " + K_FMT(elapsed) + "  (before the final burn)".
    PRINT "Propellant: " + ROUND(m0 - m, 3) + " t of " + ROUND(m0,2) + " t wet".
    PRINT " ".
    IF elapsed > 25 * KUNIVERSE:HOURSPERDAY * 3600 {
        PRINT "WARNING: this campaign is long enough that your transfer".
        PRINT "window will move. Start early and plan around it.".
    }
}

// ------------------------------------------------------------- executor

FUNCTION KICKRUN {
    PARAMETER vinf.
    PARAMETER maxBurn IS 120.
    PARAMETER leadTime IS 45.        // seconds of settling+alignment before ignition

    LOCAL mu IS SHIP:BODY:MU.
    LOCAL rp IS SHIP:BODY:RADIUS + SHIP:PERIAPSIS.
    LOCAL vTarget IS SQRT(vinf*vinf + 2*mu/rp).

    SAS OFF.
    LOCK THROTTLE TO 0.

    LOCAL pass IS 0.
    LOCAL running IS TRUE.

    UNTIL NOT running {

        SET rp TO SHIP:BODY:RADIUS + SHIP:PERIAPSIS.
        SET vTarget TO SQRT(vinf*vinf + 2*mu/rp).
        LOCAL vNowPeri IS SQRT(mu * (2/rp - 1/SHIP:ORBIT:SEMIMAJORAXIS)).
        LOCAL dvRem IS vTarget - vNowPeri.

        IF dvRem <= 2 {
            PRINT "Target energy reached. vinf = "
                + ROUND(SQRT(MAX(0, vNowPeri*vNowPeri - 2*mu/rp)),1) + " m/s".
            SET running TO FALSE.
            BREAK.
        }

        LOCAL f IS SHIP:AVAILABLETHRUST.
        LOCAL isp IS K_ISP().
        IF f <= 0 OR isp <= 0 {
            PRINT "Lost thrust - out of fuel or engine off. Stopping.".
            SET running TO FALSE.
            BREAK.
        }
        LOCAL ve IS isp * G0.
        LOCAL m0 IS SHIP:MASS.

        LOCAL dvThis IS MIN(dvRem, K_DVIN(maxBurn, m0, f, ve)).
        LOCAL burnT  IS K_BURNTIME(dvThis, m0, f, ve).
        LOCAL mEnd   IS m0 * CONSTANT:E^(-dvThis/ve).

        SET pass TO pass + 1.
        PRINT "--- pass " + pass + ": " + ROUND(dvThis,1) + " m/s over "
            + ROUND(burnT,1) + " s (" + ROUND(dvRem,0) + " m/s to go)".

        // ---- warp to just before the burn window --------------------
        LOCAL ignition IS TIME:SECONDS + ETA:PERIAPSIS - burnT/2.
        LOCAL wakeAt IS ignition - leadTime.

        IF wakeAt > TIME:SECONDS + 30 {
            UNLOCK STEERING.
            WAIT 1.
            PRINT "    warping " + ROUND(wakeAt - TIME:SECONDS) + " s...".
            WARPTO(wakeAt).
            WAIT UNTIL TIME:SECONDS >= wakeAt OR KUNIVERSE:TIMEWARP:RATE = 1.
            KUNIVERSE:TIMEWARP:CANCELWARP().
            WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED AND SHIP:UNPACKED.
        }

        // ---- align ---------------------------------------------------
        LOCK STEERING TO SHIP:PROGRADE.
        WAIT UNTIL VANG(SHIP:FACING:VECTOR, SHIP:PROGRADE:VECTOR) < 0.5
                   OR TIME:SECONDS > ignition.

        // recompute ignition - alignment may have eaten the margin
        SET ignition TO TIME:SECONDS + ETA:PERIAPSIS - burnT/2.
        IF ETA:PERIAPSIS > burnT/2 {
            WAIT UNTIL TIME:SECONDS >= ignition.
        }

        // ---- burn, measured by propellant used, not by velocity ------
        // (velocity differencing is wrong here: gravity changes velocity too)
        LOCAL cutoff IS TIME:SECONDS + burnT * 2.5.
        LOCK THROTTLE TO 1.
        WAIT UNTIL SHIP:MASS <= mEnd
                   OR SHIP:AVAILABLETHRUST <= 0
                   OR TIME:SECONDS > cutoff.
        LOCK THROTTLE TO 0.

        PRINT "    Ap now " + ROUND(SHIP:APOAPSIS/1000000, 3) + " Mm".

        // if we went hyperbolic mid-burn we are done coasting
        IF SHIP:ORBIT:ECCENTRICITY >= 1 {
            PRINT "Hyperbolic. Ejection complete after " + pass + " passes.".
            SET running TO FALSE.
        }

        WAIT 1.
    }

    LOCK THROTTLE TO 0.
    UNLOCK THROTTLE.
    UNLOCK STEERING.
    SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
    PRINT "KICKRUN finished.".
}

PRINT "perikick.ks loaded.".
PRINT "Try: KICKPLAN(2350).      // Moho".
PRINT "Then: KICKRUN(2350).".

