// oberth.ks - Oberth effect tooling for kOS
// Save as oberth.ks in Ships/Script, then:  RUNONCEPATH("0:/oberth.ks").
//
// Provides:
//   VAT(hgt)              speed on the current orbit at a given altitude
//   VESC(hgt)             escape speed at a given altitude
//   EJECTDV(hgt, vinf)    dv needed at that altitude to leave with excess vel vinf
//   OBERTHREPORT(vinf)    table: is it worth lowering periapsis first?
//   BURNTIME(dv)          burn duration for current stage
//   PERIBURN(dv)          execute a prograde burn centred on periapsis
//
// vinf = hyperbolic excess velocity (m/s). If you have C3, vinf = SQRT(C3).
// Rough Kerbin ejection vinf: Duna ~920, Eve ~1030, Jool ~2000, Moho ~2350.

SET G0 TO 9.80665.

// ---------------------------------------------------------------- basics

FUNCTION MUOF { RETURN SHIP:BODY:MU. }
FUNCTION RADAT { PARAMETER hgt. RETURN SHIP:BODY:RADIUS + hgt. }

// vis-viva on the current orbit
FUNCTION VAT {
    PARAMETER hgt.
    LOCAL rad IS RADAT(hgt).
    LOCAL a IS SHIP:ORBIT:SEMIMAJORAXIS.
    RETURN SQRT(MUOF() * (2/rad - 1/a)).
}

FUNCTION VESC {
    PARAMETER hgt.
    RETURN SQRT(2 * MUOF() / RADAT(hgt)).
}

FUNCTION VCIRC {
    PARAMETER hgt.
    RETURN SQRT(MUOF() / RADAT(hgt)).
}

// Speed required at radius rad to end up with excess velocity vinf at infinity.
// This is the whole Oberth story: the 2*mu/rad term is free energy, and it is
// bigger the deeper you are.
FUNCTION VNEEDED {
    PARAMETER hgt, vinf.
    RETURN SQRT(vinf*vinf + 2*MUOF()/RADAT(hgt)).
}

// dv to eject from the current orbit, burning at the given altitude
FUNCTION EJECTDV {
    PARAMETER hgt, vinf.
    RETURN VNEEDED(hgt, vinf) - VAT(hgt).
}

// ------------------------------------------------- periapsis-lowering cost

// dv to change periapsis to newPeriAlt, burning once at current apoapsis
FUNCTION LOWERPERIDV {
    PARAMETER newPeriAlt.
    LOCAL rApo IS RADAT(SHIP:APOAPSIS).
    LOCAL rPeriNew IS RADAT(newPeriAlt).
    LOCAL aNew IS (rApo + rPeriNew) / 2.
    LOCAL vNow IS VAT(SHIP:APOAPSIS).
    LOCAL vNew IS SQRT(MUOF() * (2/rApo - 1/aNew)).
    RETURN ABS(vNew - vNow).
}

// Total dv: lower periapsis to newPeriAlt, then eject from there.
FUNCTION TOTALVIALOWERING {
    PARAMETER newPeriAlt, vinf.
    LOCAL rApo IS RADAT(SHIP:APOAPSIS).
    LOCAL rPeriNew IS RADAT(newPeriAlt).
    LOCAL aNew IS (rApo + rPeriNew) / 2.
    LOCAL dv1 IS LOWERPERIDV(newPeriAlt).
    LOCAL vPeriNew IS SQRT(MUOF() * (2/rPeriNew - 1/aNew)).
    LOCAL dv2 IS VNEEDED(newPeriAlt, vinf) - vPeriNew.
    RETURN LIST(dv1, dv2, dv1 + dv2).
}

// ---------------------------------------------------------------- report

FUNCTION OBERTHREPORT {
    PARAMETER vinf.

    CLEARSCREEN.
    PRINT "=== Oberth report: " + SHIP:BODY:NAME + " ===".
    PRINT "vinf target   : " + ROUND(vinf) + " m/s  (C3 = " + ROUND(vinf*vinf/1000000, 2) + " km2/s2)".
    PRINT "Current orbit : " + ROUND(SHIP:PERIAPSIS/1000, 1) + " x " + ROUND(SHIP:APOAPSIS/1000, 1) + " km".
    PRINT " ".

    LOCAL baseline IS EJECTDV(SHIP:PERIAPSIS, vinf).
    PRINT "Eject from current periapsis: " + ROUND(baseline, 1) + " m/s".
    PRINT " ".
    PRINT "peri(km)   lower   eject   total    vs now".
    PRINT "---------------------------------------------".

    LOCAL minAlt IS SHIP:BODY:ATM:HEIGHT + 5000.
    IF minAlt < 5000 { SET minAlt TO 10000. }   // airless bodies

    LOCAL candidates IS LIST().
    LOCAL stride IS (SHIP:PERIAPSIS - minAlt) / 6.
    FROM { LOCAL i IS 0. } UNTIL i > 6 STEP { SET i TO i+1. } DO {
        candidates:ADD(minAlt + stride*i).
    }

    FOR pa IN candidates {
        IF pa > 0 AND pa < SHIP:APOAPSIS {
            LOCAL rad IS TOTALVIALOWERING(pa, vinf).
            LOCAL diff IS rad[2] - baseline.
            LOCAL mark IS "".
            IF diff < 0 { SET mark TO "  <-- cheaper". }
            PRINT ROUND(pa/1000,1):TOSTRING:PADLEFT(8)
                + ROUND(rad[0],0):TOSTRING:PADLEFT(8)
                + ROUND(rad[1],0):TOSTRING:PADLEFT(8)
                + ROUND(rad[2],0):TOSTRING:PADLEFT(8)
                + ROUND(diff,0):TOSTRING:PADLEFT(9)
                + mark.
        }
    }

    PRINT " ".
    PRINT "Note: lowering periapsis pays off only when the ejection".
    PRINT "saving beats the cost of the lowering burn. Deep, eccentric".
    PRINT "orbits and large vinf targets favour it most.".
}

// ------------------------------------------------------------ burn timing

FUNCTION STAGEISP {
    LOCAL num IS 0.
    LOCAL den IS 0.
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

// Tsiolkovsky burn duration - constant thrust, constant Isp
FUNCTION BURNTIME {
    PARAMETER dv.
    LOCAL f IS SHIP:AVAILABLETHRUST.
    LOCAL isp IS STAGEISP().
    IF f <= 0 OR isp <= 0 { RETURN -1. }
    LOCAL ve IS isp * G0.
    RETURN (SHIP:MASS * ve / f) * (1 - CONSTANT:E^(-dv/ve)).
}

// ------------------------------------------------------- periapsis burner

// Burn prograde, centred on periapsis, for the requested dv.
// Centring matters: an off-centre burn wastes part of the Oberth benefit.
FUNCTION PERIBURN {
    PARAMETER dv.

    LOCAL bt IS BURNTIME(dv).
    IF bt < 0 {
        PRINT "No thrust or no Isp - stage up first.".
        RETURN.
    }

    PRINT "dv " + ROUND(dv,1) + " m/s over " + ROUND(bt,1) + " s".
    IF bt > 300 {
        PRINT "WARNING: burn is long relative to the periapsis pass.".
        PRINT "Consider splitting it across several periapsis kicks.".
    }

    SAS OFF.
    LOCK STEERING TO SHIP:PROGRADE.
    WAIT UNTIL VANG(SHIP:FACING:VECTOR, SHIP:PROGRADE:VECTOR) < 1.

    LOCAL startAt IS TIME:SECONDS + ETA:PERIAPSIS - bt/2.
    PRINT "Waiting " + ROUND(startAt - TIME:SECONDS, 1) + " s...".
    WAIT UNTIL TIME:SECONDS >= startAt.

    LOCAL v0 IS SHIP:VELOCITY:ORBIT.
    LOCK THROTTLE TO 1.
    WAIT UNTIL (SHIP:VELOCITY:ORBIT - v0):MAG >= dv OR SHIP:AVAILABLETHRUST <= 0.
    LOCK THROTTLE TO 0.

    PRINT "Burn complete. Ap " + ROUND(SHIP:APOAPSIS/1000,1) + " km.".
    UNLOCK THROTTLE.
    UNLOCK STEERING.
}

PRINT "oberth.ks loaded. Try: OBERTHREPORT(920).".

