// rdv.ks - Hohmann transfer node to a target
// RUN rdv.
// Assumes both orbits are near-circular.

IF NOT HASTARGET { PRINT "rdv: set a target first.". PRINT " ". }

LOCAL mu IS SHIP:BODY:MU.
LOCAL pShip IS -SHIP:BODY:POSITION.
LOCAL pTgt IS TARGET:POSITION - SHIP:BODY:POSITION.

LOCAL nShip IS VCRS(pShip, SHIP:VELOCITY:ORBIT).
LOCAL nTgt IS VCRS(pTgt, TARGET:VELOCITY:ORBIT).
LOCAL relInc IS VANG(nShip, nTgt).

PRINT "rdv: relative inclination " + ROUND(relInc, 3) + " deg".
IF relInc > 0.5 {
    PRINT "     TOO HIGH. Match planes first at the AN/DN markers,".
    PRINT "     then run this again. Node added anyway for reference.".
}

LOCAL r1 IS SHIP:ORBIT:SEMIMAJORAXIS.
LOCAL r2 IS TARGET:ORBIT:SEMIMAJORAXIS.
LOCAL aT IS (r1 + r2) / 2.
LOCAL tTrans IS CONSTANT:PI * SQRT(aT^3 / mu).

LOCAL t1 IS SHIP:ORBIT:PERIOD.
LOCAL t2 IS TARGET:ORBIT:PERIOD.

// where the target must be, relative to us, when we burn
LOCAL wantPhase IS 180 - 360 * tTrans / t2.
UNTIL wantPhase <= 180 { SET wantPhase TO wantPhase - 360. }
UNTIL wantPhase > -180 { SET wantPhase TO wantPhase + 360. }

// where it is now, signed positive if ahead of us
LOCAL nowPhase IS VANG(pShip, pTgt).
IF VDOT(VCRS(pShip, pTgt), nShip) < 0 { SET nowPhase TO -nowPhase. }

// close the gap at the relative angular rate
LOCAL wRel IS (360/t2) - (360/t1).
LOCAL dPhase IS wantPhase - nowPhase.
IF wRel > 0 { UNTIL dPhase > 0 { SET dPhase TO dPhase + 360. } }
ELSE        { UNTIL dPhase < 0 { SET dPhase TO dPhase - 360. } }
LOCAL tWait IS dPhase / wRel.

LOCAL vNow IS SQRT(mu / r1).
LOCAL vTrans IS SQRT(mu * (2/r1 - 1/aT)).
LOCAL dv IS vTrans - vNow.

ADD NODE(TIME:SECONDS + tWait, 0, 0, dv).

PRINT "rdv: phase now " + ROUND(nowPhase,1) + ", want " + ROUND(wantPhase,1).
PRINT "     burn in " + ROUND(tWait) + " s, dv " + ROUND(dv,1) + " m/s".
PRINT "     transfer takes " + ROUND(tTrans) + " s".
