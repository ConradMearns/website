// ============================================================================
//  porkchop.ks  --  Interplanetary Launch Window Planner for kOS
// ----------------------------------------------------------------------------
//  An in-game reimplementation of Alex Moon's KSP Launch Window Planner
//  (https://alexmoon.github.io/ksp/  --  his source is CC BY-NC-SA 4.0).
//
//  This is an INDEPENDENT implementation of the same published algorithms
//  rather than a translation of his code:
//    * Lambert solver : F.T. Sun, "On the Minimum Time Trajectory and Multiple
//                       Solutions of Lambert's Problem", AAS 79-164 (1979).
//                       Single-revolution case only (N = 0), which is what the
//                       porkchop plot uses.
//    * Patched conics : Robert Braeunig, "Rocket & Space Technology".
//  Credit for the tool, its parameter set and its plot layout goes to Alex Moon.
//
//  The defaults below reproduce the URL:
//     #/Kerbin/150/Moho/5/false/optimalPlaneChange/false/1/130
//     origin Kerbin, 150 km parking orbit, destination Moho, 5 km capture
//     orbit, insertion burn included, mid-course plane change transfer,
//     earliest departure Year 1 Day 130.
//
//  USAGE:  put this in Ships/Script (or the archive) and RUN PORKCHOP.
//          The vessel must be in flight -- POSITIONAT needs an active vessel.
// ============================================================================


// ============================================================================
//  SECTION 0 -- kOS HOUSEKEEPING
// ============================================================================

// kOS runs a fixed number of instructions per physics tick. The default (200)
// makes this script take minutes; 2000 is the maximum and gets a full
// porkchop done in roughly 10-40 seconds. Restored on exit.
GLOBAL OLD_IPU IS CONFIG:IPU.
SET CONFIG:IPU TO 2000.

// kOS has NO string escape sequences -- "\n" is literally backslash-n.
// Newlines have to come from CHAR().
GLOBAL NL  IS CHAR(10).
// U+2588 FULL BLOCK, one plot pixel. If your UI font renders this as a hollow
// box, swap it for CHAR(35) ("#") -- everything else still works.
GLOBAL BLK IS CHAR(9608).

CLEARSCREEN.
PRINT "Launch Window Planner loading...".


// ============================================================================
//  SECTION 1 -- MATH HELPERS
// ----------------------------------------------------------------------------
//  *** THE #1 kOS GOTCHA ***  kOS trig works in DEGREES, not radians. All the
//  orbital mechanics below is in radians, so every trig call goes through one
//  of these wrappers. Mixing them up gives silently wrong answers.
// ============================================================================

FUNCTION rsin   { PARAMETER a. RETURN SIN(a * CONSTANT:RADTODEG). }
FUNCTION rcos   { PARAMETER a. RETURN COS(a * CONSTANT:RADTODEG). }
FUNCTION ratan  { PARAMETER x. RETURN ARCTAN(x) * CONSTANT:DEGTORAD. }
FUNCTION ratan2 { PARAMETER y, x. RETURN ARCTAN2(y, x) * CONSTANT:DEGTORAD. }

// arccos with clamping. Round-off routinely produces dot/(|a||b|) values like
// 1.0000000002, which would otherwise throw a domain error mid-plot.
FUNCTION racos {
  PARAMETER x.
  RETURN ARCCOS(MAX(-1, MIN(1, x))) * CONSTANT:DEGTORAD.
}

// Inverse cotangent and inverse hyperbolic cotangent -- kOS has neither, and
// Sun's Lambert formulation needs both.
FUNCTION racot  { PARAMETER x. RETURN CONSTANT:PI/2 - ratan(x). }
FUNCTION racoth { PARAMETER x. RETURN 0.5 * LN((x + 1) / (x - 1)). }

// NOTE: do not name a variable "v" anywhere in this file -- it shadows kOS's
// built-in V(x,y,z) vector constructor and the compiler rejects the whole
// script with a CLOBBERBUILTINS error.
FUNCTION clampv {
  PARAMETER val, lo, hi.
  RETURN MAX(lo, MIN(hi, val)).
}

// Rodrigues' rotation: rotate v about a UNIT axis by angRad.
//
// kOS uses a LEFT-handed coordinate system, so "which way is positive" is not
// obvious. It does not matter here: we always build the axis with the same
// VCRS() call we later rotate around, and the identity VCRS(h_hat, r_hat) =
// v_hat holds in either handedness -- so "+angle" always means "forward along
// the direction of motion". In the one place where the sign genuinely matters
// (the plane-change rotation) we try both and keep whichever lands on target.
FUNCTION rotateAbout {
  PARAMETER vec, axis, angRad.
  LOCAL ca IS rcos(angRad).
  LOCAL sa IS rsin(angRad).
  RETURN vec*ca + VCRS(axis, vec)*sa + axis*(VDOT(axis, vec))*(1 - ca).
}


// ============================================================================
//  SECTION 2 -- EPHEMERIS
// ----------------------------------------------------------------------------
//  We do not need to write a Kepler propagator: kOS ships POSITIONAT and
//  VELOCITYAT, which query KSP's own on-rails solver. Both return values in
//  the SHIP-RAW frame (relative to the ship's CURRENT position), so absolute
//  values are meaningless -- but DIFFERENCES between two of them are exactly
//  the relative vectors we want.
// ============================================================================

// Position of body b at universal time t, relative to its parent.
FUNCTION bodyPos {
  PARAMETER b, t.
  LOCAL p IS POSITIONAT(b, t).
  IF b:HASBODY {
    RETURN p - POSITIONAT(b:BODY, t).
  }
  RETURN p - b:POSITION.        // the Sun has no parent and never moves
}

// Orbital velocity of body b at time t, relative to its parent.
FUNCTION bodyVel {
  PARAMETER b, t.
  LOCAL vb IS VELOCITYAT(b, t):ORBIT.
  IF b:HASBODY {
    RETURN vb - VELOCITYAT(b:BODY, t):ORBIT.
  }
  RETURN V(0,0,0).
}


// ============================================================================
//  SECTION 3 -- LAMBERT SOLVER (Sun's method, single revolution)
// ----------------------------------------------------------------------------
//  Given mu, a departure position p1, an arrival position p2 and a flight time
//  dt, find the conic that joins them.
//
//  Sun's formulation collapses the whole problem onto ONE scalar unknown x,
//  the "path parameter", defined on (-1, infinity):
//        -1 < x < 1   elliptical transfer
//             x = 1   parabolic
//             x > 1   hyperbolic
//  Bigger x = more energy = shorter flight, so the time equation is strictly
//  decreasing in x and plain bisection is bullet-proof. (Moon's JS uses
//  Brent's method; bisection costs a few extra iterations but is a fraction of
//  the code and never diverges -- which matters in kOS, where one unhandled
//  exception kills the whole script mid-plot.)
//
//  hRef sets the direction of travel: a transfer is "prograde" when its
//  angular momentum points the same way as hRef. Pass the ORIGIN body's own
//  orbital angular momentum and you get the transfer people actually fly.
//
//  Returns LIST(v1, v2, transferAngleRadians), or LIST() on failure.
// ============================================================================

FUNCTION lambertSolve {
  PARAMETER mu, p1, p2, dt, hRef.

  LOCAL r1 IS p1:MAG.
  LOCAL r2 IS p2:MAG.
  LOCAL dpos IS p2 - p1.
  LOCAL c IS dpos:MAG.                     // chord length
  IF c < 1 OR dt <= 0 { RETURN LIST(). }   // degenerate geometry

  // m and n are the semi-perimeter combinations Sun's paper is written in.
  LOCAL m IS r1 + r2 + c.
  LOCAL n IS r1 + r2 - c.

  // ---- transfer angle -----------------------------------------------------
  // arccos only spans 0..pi. To tell the short way (<180 deg) from the long
  // way (>180 deg) we check whether p1 x p2 agrees with the reference sense.
  LOCAL ta IS racos(VDOT(p1, p2) / (r1 * r2)).
  IF VDOT(VCRS(p1, p2), hRef) < 0 {
    SET ta TO 2*CONSTANT:PI - ta.
  }

  // sigma ("angle parameter") encodes the geometry, and its SIGN is what
  // carries short-way/long-way information into the time equation.
  LOCAL sig IS SQRT(n / m).
  IF ta > CONSTANT:PI { SET sig TO -sig. }

  // Non-dimensional flight time, plus the parabolic flight time that divides
  // the elliptical branch from the hyperbolic one.
  LOCAL tau  IS 4 * dt * SQRT(mu / (m*m*m)).
  LOCAL tauP IS (2/3) * (1 - sig*sig*sig).

  // y is x's companion: y = +/- sqrt(1 - sig^2 (1 - x^2)), signed like sigma.
  FUNCTION fy {
    PARAMETER x.
    LOCAL yy IS 1 - sig*sig*(1 - x*x).
    IF yy < 0 { SET yy TO 0. }
    LOCAL y IS SQRT(yy).
    IF sig < 0 { RETURN -y. }
    RETURN y.
  }

  // Residual: (flight time implied by x) - (requested flight time).
  // Its root is the answer.
  FUNCTION ftau {
    PARAMETER x.
    IF ABS(x - 1) < 1e-11 { RETURN tauP - tau. }          // parabolic
    LOCAL y IS fy(x).
    IF x > 1 {                                            // hyperbolic branch
      LOCAL g IS SQRT(x*x - 1).
      LOCAL h IS SQRT(y*y - 1).
      RETURN (-racoth(x/g) + racoth(y/h) + x*g - y*h) / (g*g*g) - tau.
    }
    LOCAL g IS SQRT(1 - x*x).                             // elliptical branch
    LOCAL h IS SQRT(1 - y*y).
    RETURN (racot(x/g) - ratan(h/y) - x*g + y*h) / (g*g*g) - tau.
  }

  // ---- bracket, then bisect ----------------------------------------------
  LOCAL xr IS 1.

  IF ABS(1 - tau/tauP) < 1e-6 {
    SET xr TO 1.                                          // exactly parabolic
  } ELSE IF tau < tauP {
    // Faster than parabolic => hyperbolic. Push the upper bound out by
    // doubling until the residual flips sign.
    LOCAL xlo IS 1.
    LOCAL xhi IS 2.
    LOCAL guard IS 0.
    UNTIL ftau(xhi) < 0 OR guard > 60 {
      SET xlo TO xhi.
      SET xhi TO xhi * 2.
      SET guard TO guard + 1.
    }
    IF guard > 60 { RETURN LIST(). }
    SET xr TO bisect(ftau@, xlo, xhi).
  } ELSE {
    // Elliptical: the root is always inside (-1, 1). As x -> -1 the flight
    // time diverges (residual positive); at x -> 1 it equals tauP (residual
    // negative), so the bracket is guaranteed.
    SET xr TO bisect(ftau@, -1 + 1e-9, 1 - 1e-9).
  }

  // ---- rebuild the velocity vectors --------------------------------------
  // Sun's method expresses the transfer velocity as a component along the
  // chord plus a radial component along each position vector. No cross
  // products here, which is why the whole solver is handedness-agnostic.
  LOCAL y  IS fy(xr).
  LOCAL sm IS SQRT(mu).
  LOCAL vc IS sm * (y/SQRT(n) + xr/SQRT(m)).   // chord-wise speed
  LOCAL vr IS sm * (y/SQRT(n) - xr/SQRT(m)).   // radial speed
  LOCAL ec IS dpos * (vc / c).

  LOCAL v1 IS ec + p1 * (vr / r1).             // velocity just after departure
  LOCAL v2 IS ec - p2 * (vr / r2).             // velocity just before arrival

  RETURN LIST(v1, v2, ta).
}

// Bisection on a strictly decreasing residual. 80 halvings takes the bracket
// far below double precision; the width test normally exits much sooner.
FUNCTION bisect {
  PARAMETER f, lo, hi.
  LOCAL i IS 0.
  UNTIL i > 80 OR (hi - lo) < 1e-11 {
    LOCAL mid IS 0.5*(lo + hi).
    IF f(mid) > 0 { SET lo TO mid. } ELSE { SET hi TO mid. }
    SET i TO i + 1.
  }
  RETURN 0.5*(lo + hi).
}


// ============================================================================
//  SECTION 4 -- BURN COST MODELS (patched conics)
// ============================================================================

// --- EJECTION ---------------------------------------------------------------
// Leaving a circular parking orbit of radius r0 with required hyperbolic
// excess velocity vinfVec (expressed in the origin body's frame):
//
//   vHyp  = sqrt(vinf^2 + 2*mu/r0)   speed at periapsis of the escape hyperbola
//   vPark = sqrt(mu/r0)              speed in the circular parking orbit
//
// If the escape asymptote is tilted out of the parking plane by angle i, the
// single combined burn costs (law of cosines):
//
//   dv = sqrt(vHyp^2 + vPark^2 - 2*vHyp*vPark*cos(i))
//
// This is the model the web planner uses, which is why it lists "ejection
// inclination" as its own line. It slightly overestimates the true optimum --
// a real ejection can shade its burn point to trade plane change against
// prograde component -- but only by a few m/s.
//
// Returns LIST(deltaV, ejectionInclinationRadians).
FUNCTION ejectionCost {
  PARAMETER mu, r0, vinfVec, poleHat.
  LOCAL vinf  IS vinfVec:MAG.
  LOCAL vHyp  IS SQRT(vinf*vinf + 2*mu/r0).
  LOCAL vPark IS SQRT(mu/r0).
  // Declination of the asymptote above the parking (equatorial) plane.
  LOCAL inc IS ABS(CONSTANT:PI/2 - racos(VDOT(vinfVec:NORMALIZED, poleHat))).
  LOCAL dv IS SQRT(vHyp*vHyp + vPark*vPark - 2*vHyp*vPark*rcos(inc)).
  RETURN LIST(dv, inc).
}

// --- INSERTION --------------------------------------------------------------
// Capture from hyperbolic excess speed vinf into a circular orbit of radius r1.
// No inclination penalty: we are free to accept whatever plane the arrival
// hyperbola happens to lie in.
FUNCTION insertionCost {
  PARAMETER mu, r1, vinf.
  RETURN SQRT(vinf*vinf + 2*mu/r1) - SQRT(mu/r1).
}


// ============================================================================
//  SECTION 5 -- THE TRANSFER MODEL
// ----------------------------------------------------------------------------
//  Three transfer types, matching the web tool:
//
//  BALLISTIC
//      One Lambert arc through real 3D space. The ejection burn pays for the
//      entire plane change up front, which is brutal for inclined targets
//      such as Moho (7.2 deg).
//
//  MID-COURSE PLANE CHANGE
//      Solve Lambert in the ORIGIN'S ORBITAL PLANE, against the destination
//      position rotated into that plane about the departure radius vector.
//      Rotating about r1 preserves both |r2| and the transfer angle, so the
//      in-plane geometry is untouched. The two planes then intersect along the
//      line through the departure point, so the transfer orbit re-crosses that
//      line exactly 180 deg of true anomaly after departure -- out near
//      apoapsis, where the vessel is slowest and rotating the orbit is
//      cheapest:
//          dv_planechange = 2 * v * sin(theta/2)
//      If the transfer angle is under 180 deg the vessel arrives before ever
//      reaching that crossing, so no mid-course option exists and this grid
//      point falls back to ballistic.
//
//  OPTIMAL
//      Compute both, keep the cheaper. (This is why Moho plots look so
//      different between transfer types.)
//
//  Returns a LEXICON holding every field the web tool's transfer panel shows,
//  or a lexicon whose "ok" is FALSE.
// ============================================================================

FUNCTION computeTransfer {
  PARAMETER t0, tof, mode.   // departure UT, flight time (s), 0=bal 1=pc 2=opt

  LOCAL t1 IS t0 + tof.
  LOCAL mu IS PARENT_B:MU.

  // State of both bodies relative to their shared parent.
  LOCAL p1  IS bodyPos(ORIGIN_B, t0).
  LOCAL v1b IS bodyVel(ORIGIN_B, t0).
  LOCAL p2  IS bodyPos(DEST_B, t1).
  LOCAL v2b IS bodyVel(DEST_B, t1).

  // Reference sense of travel = the origin body's orbital angular momentum.
  // Everything "prograde" is defined against this.
  LOCAL hRef IS VCRS(p1, v1b):NORMALIZED.

  // Parking orbit normal. KSP planets have no axial tilt, so the spin axis and
  // the reference plane normal coincide; we still prefer the real spin axis
  // and only use hRef to decide which end of it counts as "north".
  LOCAL poleHat IS hRef.
  IF ORIGIN_B:ANGULARVEL:MAG > 0 {
    LOCAL sp IS ORIGIN_B:ANGULARVEL:NORMALIZED.
    IF VDOT(sp, hRef) < 0 { SET sp TO -sp. }
    SET poleHat TO sp.
  }

  LOCAL r0 IS ORIGIN_B:RADIUS + PARK_ALT*1000.
  LOCAL rf IS DEST_B:RADIUS + CAPT_ALT*1000.

  LOCAL best IS LEXICON("ok", FALSE, "total", -1).

  // ---------------- ballistic ----------------------------------------------
  IF mode = 0 OR mode = 2 {
    LOCAL sol IS lambertSolve(mu, p1, p2, tof, hRef).
    IF sol:LENGTH = 3 {
      LOCAL vinf1 IS sol[0] - v1b.               // excess velocity at departure
      LOCAL vinf2 IS sol[1] - v2b.               // excess velocity at arrival
      LOCAL ej IS ejectionCost(ORIGIN_B:MU, r0, vinf1, poleHat).
      LOCAL ins IS 0.
      IF NOT NO_INSERTION { SET ins TO insertionCost(DEST_B:MU, rf, vinf2:MAG). }
      SET best TO LEXICON(
        "ok", TRUE, "type", "ballistic",
        "t0", t0, "tof", tof, "t1", t1,
        "ejDv", ej[0], "ejInc", ej[1],
        "pcDv", 0, "pcTime", 0, "pcAngle", 0,
        "insDv", ins, "insVinf", vinf2:MAG,
        "total", ej[0] + ins,
        "ta", sol[2], "vinf1", vinf1, "v1b", v1b,
        "pole", poleHat, "r0", r0).
    }
  }

  // ---------------- mid-course plane change --------------------------------
  IF mode = 1 OR mode = 2 {
    // Orthonormal frame at the departure point:
    //   e1 = along r1  (this is the rotation axis / line of nodes)
    //   e2 = in the origin's orbital plane, perpendicular to e1
    //   e3 = out of plane
    LOCAL e1 IS p1:NORMALIZED.
    LOCAL e2 IS VCRS(hRef, e1):NORMALIZED.
    LOCAL e3 IS VCRS(e1, e2):NORMALIZED.

    LOCAL a  IS VDOT(p2, e1).
    LOCAL b  IS VDOT(p2, e2).
    LOCAL cc IS VDOT(p2, e3).
    LOCAL bc IS SQRT(b*b + cc*cc).

    IF bc > 1 {
      // Rotate p2 about e1 until it lies in the reference plane. Both |p2| and
      // the p1-p2 angle survive untouched, by construction.
      LOCAL sgn IS 1.
      IF b < 0 { SET sgn TO -1. }
      LOCAL p2p IS e1*a + e2*(bc*sgn).
      LOCAL pcAng IS racos(ABS(b)/bc).            // the plane change angle

      LOCAL sol IS lambertSolve(mu, p1, p2p, tof, hRef).
      IF sol:LENGTH = 3 AND sol[2] > CONSTANT:PI {
        // --- orbital elements of the coplanar transfer arc ---
        LOCAL vv  IS sol[0].
        LOCAL rr  IS p1:MAG.
        LOCAL sma IS 1 / (2/rr - vv:SQRMAGNITUDE/mu).
        LOCAL hm  IS VCRS(p1, vv):MAG.
        LOCAL prm IS hm*hm/mu.                    // semi-latus rectum
        LOCAL ecc IS SQRT(MAX(0, 1 - prm/sma)).

        IF sma > 0 AND ecc < 1 {
          // True anomaly at departure, signed by the radial velocity.
          LOCAL nu0 IS racos((prm/rr - 1)/MAX(ecc, 1e-9)).
          IF VDOT(p1, vv) < 0 { SET nu0 TO -nu0. }

          // The plane change happens half a revolution later, where the
          // transfer crosses the -r1 direction (the line of nodes).
          LOCAL nuPC IS nu0 + CONSTANT:PI.
          LOCAL rPC IS prm / (1 + ecc*rcos(nuPC)).
          LOCAL vPC IS SQRT(mu*(2/rPC - 1/sma)).
          LOCAL dvPC IS 2 * vPC * rsin(pcAng/2).

          // Time from departure to that point, via Kepler's equation.
          LOCAL nMean IS SQRT(mu/(sma*sma*sma)).
          LOCAL dtPC IS (meanAnom(nuPC, ecc) - meanAnom(nu0, ecc)) / nMean.
          IF dtPC < 0 { SET dtPC TO dtPC + 2*CONSTANT:PI/nMean. }

          // The post-node arc is the pre-node arc rotated about e1. We do not
          // know our rotation's sign convention in kOS's left-handed frame, so
          // just try both and keep whichever maps the projected destination
          // back onto the real one.
          LOCAL rotAng IS pcAng.
          IF (rotateAbout(p2p, e1, pcAng) - p2):MAG > (rotateAbout(p2p, e1, -pcAng) - p2):MAG {
            SET rotAng TO -pcAng.
          }
          LOCAL vArr IS rotateAbout(sol[1], e1, rotAng).

          LOCAL vinf1 IS sol[0] - v1b.
          LOCAL vinf2 IS vArr - v2b.
          LOCAL ej IS ejectionCost(ORIGIN_B:MU, r0, vinf1, poleHat).
          LOCAL ins IS 0.
          IF NOT NO_INSERTION { SET ins TO insertionCost(DEST_B:MU, rf, vinf2:MAG). }
          LOCAL tot IS ej[0] + dvPC + ins.

          // In "optimal" mode this only wins if it beats the ballistic arc.
          IF (NOT best:ok) OR tot < best:total {
            SET best TO LEXICON(
              "ok", TRUE, "type", "plane change",
              "t0", t0, "tof", tof, "t1", t1,
              "ejDv", ej[0], "ejInc", ej[1],
              "pcDv", dvPC, "pcTime", t0 + dtPC, "pcAngle", pcAng,
              "insDv", ins, "insVinf", vinf2:MAG,
              "total", tot,
              "ta", sol[2], "vinf1", vinf1, "v1b", v1b,
              "pole", poleHat, "r0", r0).
          }
        }
      }
    }
  }

  RETURN best.
}

// Mean anomaly from true anomaly (elliptical orbits only).
FUNCTION meanAnom {
  PARAMETER nu, ecc.
  LOCAL eAnom IS 2 * ratan2(SQRT(1-ecc)*rsin(nu/2), SQRT(1+ecc)*rcos(nu/2)).
  RETURN eAnom - ecc*rsin(eAnom).
}

// Ejection angle: where in the parking orbit the burn happens, measured from
// the origin body's prograde direction, along the direction of motion.
// Geometry: on an escape hyperbola of eccentricity e the outgoing asymptote
// sits acos(-1/e) of true anomaly past periapsis, so we rotate the asymptote
// direction BACKWARDS by that angle to land on the burn point.
FUNCTION ejectionAngle {
  PARAMETER d.
  IF NOT d:ok { RETURN 0. }
  LOCAL vinf IS d:vinf1:MAG.
  LOCAL ecc IS 1 + d:r0 * vinf*vinf / ORIGIN_B:MU.
  LOCAL nuInf IS racos(-1/ecc).
  LOCAL pole IS d:pole.
  LOCAL aDir IS VXCL(pole, d:vinf1):NORMALIZED.       // asymptote, in-plane
  LOCAL bDir IS rotateAbout(aDir, pole, -nuInf).      // burn point direction
  LOCAL prog IS VXCL(pole, d:v1b):NORMALIZED.         // body's prograde
  LOCAL ang IS ratan2(VDOT(VCRS(prog, bDir), pole), VDOT(prog, bDir)) * CONSTANT:RADTODEG.
  RETURN MOD(ang + 360, 360).
}

// Phase angle: destination ahead of origin, measured in the origin's plane.
FUNCTION phaseAngle {
  PARAMETER t0.
  LOCAL p1 IS bodyPos(ORIGIN_B, t0).
  LOCAL v1 IS bodyVel(ORIGIN_B, t0).
  LOCAL p2 IS bodyPos(DEST_B, t0).
  LOCAL h IS VCRS(p1, v1):NORMALIZED.
  LOCAL qv IS VXCL(h, p2).
  LOCAL ang IS ratan2(VDOT(VCRS(p1, qv), h), VDOT(p1, qv)) * CONSTANT:RADTODEG.
  RETURN MOD(ang + 360, 360).
}


// ============================================================================
//  SECTION 6 -- DATES
// ----------------------------------------------------------------------------
//  KUNIVERSE:HOURSPERDAY is 6 on Kerbin time and 24 on Earth time -- exactly
//  the toggle the web tool offers, so we just follow the game setting.
//  Year 1 Day 1 00:00 is UT 0.
// ============================================================================

FUNCTION dayLen { RETURN KUNIVERSE:HOURSPERDAY * 3600. }
FUNCTION daysPerYear {
  IF KUNIVERSE:HOURSPERDAY > 6 { RETURN 365. }
  RETURN 426.
}
FUNCTION yearLen { RETURN daysPerYear() * dayLen(). }

FUNCTION ymdToUT {
  PARAMETER y, d.
  RETURN (y - 1)*yearLen() + (d - 1)*dayLen().
}

FUNCTION pad2 {
  PARAMETER n.
  IF n < 10 { RETURN "0" + ROUND(n). }
  RETURN "" + ROUND(n).
}

FUNCTION fmtUT {
  PARAMETER ut.
  LOCAL yl IS yearLen().
  LOCAL dl IS dayLen().
  LOCAL y IS FLOOR(ut / yl).
  LOCAL rem IS ut - y*yl.
  LOCAL d IS FLOOR(rem / dl).
  SET rem TO rem - d*dl.
  LOCAL hh IS FLOOR(rem / 3600).
  LOCAL mm IS FLOOR((rem - hh*3600) / 60).
  RETURN "Y" + (y+1) + " D" + (d+1) + " " + hh + ":" + pad2(mm).
}

FUNCTION toDays { PARAMETER s. RETURN s / dayLen(). }


// ============================================================================
//  SECTION 7 -- STATE
// ============================================================================

GLOBAL ORIGIN_B IS BODY("Kerbin").
GLOBAL DEST_B   IS BODY("Moho").
GLOBAL PARENT_B IS ORIGIN_B:BODY.
GLOBAL PARK_ALT IS 150.          // km, circular equatorial parking orbit
GLOBAL CAPT_ALT IS 5.            // km, circular capture orbit
GLOBAL NO_INSERTION IS FALSE.
GLOBAL XFER_MODE IS 1.           // 0 ballistic, 1 plane change, 2 optimal

GLOBAL NCOLS IS 24.              // departure-date samples (x axis)
GLOBAL NROWS IS 18.              // time-of-flight samples (y axis)

GLOBAL GRID IS LIST().           // GRID[row][col] = total dv, -1 = no solution
GLOBAL DEP0 IS 0.                // earliest departure UT
GLOBAL DEPSTEP IS 0.
GLOBAL TOFMIN IS 0.
GLOBAL TOFMAX IS 0.
GLOBAL TOFSTEP IS 0.
GLOBAL DVMIN IS 0.
GLOBAL DVTOP IS 0.               // top of the colour scale
GLOBAL SELR IS 0.                // cursor row
GLOBAL SELC IS 0.                // cursor column
GLOBAL HAVEPLOT IS FALSE.

// Flags raised by GUI callbacks, consumed by the main loop. A kOS callback
// runs on the main thread between waits, so doing real work inside one stalls
// the interpreter -- callbacks only ever flip a flag here.
GLOBAL WANT_PLOT IS FALSE.
GLOBAL WANT_QUIT IS FALSE.
GLOBAL WANT_MOVE IS FALSE.
GLOBAL WANT_BEST IS FALSE.
GLOBAL MOVE_DR IS 0.
GLOBAL MOVE_DC IS 0.

// Blue -> red colour ramp, cheapest first.
GLOBAL PALETTE IS LIST(
  "#3030ff", "#0060ff", "#0090ff", "#00c0f0", "#00e0b0", "#00e060",
  "#60e000", "#a0e000", "#e0e000", "#ffb000", "#ff7000", "#ff2020").


// ============================================================================
//  SECTION 8 -- GUI
// ----------------------------------------------------------------------------
//  Same parameter set as the web form: origin + parking orbit, destination +
//  capture orbit, no-insertion checkbox, earliest departure, transfer type,
//  plus the "advanced" search-span and time-of-flight fields.
// ============================================================================

GLOBAL G IS GUI(560).
SET G:X TO 60.
SET G:Y TO 60.

LOCAL titleLbl IS G:ADDLABEL("<b>Interplanetary Launch Window Planner</b>").
SET titleLbl:STYLE:ALIGN TO "CENTER".

// ---- origin --------------------------------------------------------------
LOCAL rowA IS G:ADDHLAYOUT().
rowA:ADDLABEL("Origin").
GLOBAL originMenu IS rowA:ADDPOPUPMENU().
rowA:ADDLABEL("Parking orbit (km)").
GLOBAL parkField IS rowA:ADDTEXTFIELD("150").

// ---- destination ---------------------------------------------------------
LOCAL rowB IS G:ADDHLAYOUT().
rowB:ADDLABEL("Destination").
GLOBAL destMenu IS rowB:ADDPOPUPMENU().
rowB:ADDLABEL("Capture orbit (km)").
GLOBAL captField IS rowB:ADDTEXTFIELD("5").

// Fill both menus with every body in the system, walking the tree from the
// Sun down. Origin and destination must share a parent; that is checked when
// you press Plot, which also lets this handle e.g. Mun -> Minmus.
//
// We keep our own parallel list of names because a popup's :VALUE suffix
// cannot be SET from a plain string on some kOS builds ("Invalid cast from
// System.String to Structure"). Selecting by :INDEX works on all of them, so
// every menu in this script is driven by index and BODYNAMES is how we get
// back from an index to a body.
GLOBAL BODYNAMES IS LIST().

FUNCTION addBodies {
  PARAMETER b, menuA, menuB.
  menuA:ADDOPTION(b:NAME).
  menuB:ADDOPTION(b:NAME).
  BODYNAMES:ADD(b:NAME).
  FOR ch IN b:ORBITINGCHILDREN { addBodies(ch, menuA, menuB). }
}
FOR pl IN BODY("Sun"):ORBITINGCHILDREN { addBodies(pl, originMenu, destMenu). }

// Find a name's position in BODYNAMES; falls back to the first entry.
FUNCTION nameIndex {
  PARAMETER nm.
  FROM {LOCAL i IS 0.} UNTIL i >= BODYNAMES:LENGTH STEP {SET i TO i+1.} DO {
    IF BODYNAMES[i] = nm { RETURN i. }
  }
  RETURN 0.
}

SET originMenu:INDEX TO nameIndex("Kerbin").
SET destMenu:INDEX TO nameIndex("Moho").

// ---- options -------------------------------------------------------------
LOCAL rowC IS G:ADDHLAYOUT().
GLOBAL noInsCheck IS rowC:ADDCHECKBOX("No insertion burn (fly-by / aerocapture)", FALSE).
rowC:ADDLABEL("Transfer").
GLOBAL typeMenu IS rowC:ADDPOPUPMENU().
typeMenu:ADDOPTION("Ballistic").
typeMenu:ADDOPTION("Mid-course plane change").
typeMenu:ADDOPTION("Optimal").
SET typeMenu:INDEX TO 1.          // Mid-course plane change

// ---- earliest departure --------------------------------------------------
LOCAL rowD IS G:ADDHLAYOUT().
rowD:ADDLABEL("Earliest departure   Year").
GLOBAL yearField IS rowD:ADDTEXTFIELD("1").
rowD:ADDLABEL("Day").
GLOBAL dayField IS rowD:ADDTEXTFIELD("130").
GLOBAL nowButton IS rowD:ADDBUTTON("Now").

// ---- advanced settings ---------------------------------------------------
LOCAL rowE IS G:ADDHLAYOUT().
rowE:ADDLABEL("Departure span (days, blank = 1 synodic period)").
GLOBAL spanField IS rowE:ADDTEXTFIELD("").

LOCAL rowF IS G:ADDHLAYOUT().
rowF:ADDLABEL("Time of flight (days)  from").
GLOBAL tofMinField IS rowF:ADDTEXTFIELD("").
rowF:ADDLABEL("to").
GLOBAL tofMaxField IS rowF:ADDTEXTFIELD("").
rowF:ADDLABEL("Grid").
GLOBAL resMenu IS rowF:ADDPOPUPMENU().
resMenu:ADDOPTION("16 x 12  (fast)").
resMenu:ADDOPTION("24 x 18").
resMenu:ADDOPTION("32 x 24  (slow)").
SET resMenu:INDEX TO 1.           // 24 x 18

// ---- buttons -------------------------------------------------------------
LOCAL rowG IS G:ADDHLAYOUT().
GLOBAL plotButton IS rowG:ADDBUTTON("Plot it!").
GLOBAL closeButton IS rowG:ADDBUTTON("Close").

GLOBAL statusLabel IS G:ADDLABEL("Ready.").
SET statusLabel:STYLE:ALIGN TO "CENTER".

// ---- the porkchop --------------------------------------------------------
GLOBAL topAxis IS G:ADDLABEL("").
SET topAxis:STYLE:ALIGN TO "CENTER".

// The plot is ONE label full of Unity rich-text colour tags, each cell a full
// block glyph. kOS's GUI has no pixel canvas, so this is how you draw a
// heat map. Uncomment the FONT line if you have a monospace font available --
// block glyphs are uniform width in most fonts, so it is usually unnecessary.
GLOBAL plotLabel IS G:ADDLABEL("").
SET plotLabel:STYLE:ALIGN TO "CENTER".
SET plotLabel:STYLE:FONTSIZE TO 13.
SET plotLabel:STYLE:RICHTEXT TO TRUE.
// SET plotLabel:STYLE:FONT TO "Consolas".

GLOBAL botAxis IS G:ADDLABEL("").
SET botAxis:STYLE:ALIGN TO "CENTER".
GLOBAL legendLabel IS G:ADDLABEL("").
SET legendLabel:STYLE:ALIGN TO "CENTER".
SET legendLabel:STYLE:RICHTEXT TO TRUE.

// ---- cursor controls (the web tool's WSAD selection) ---------------------
LOCAL rowH IS G:ADDHLAYOUT().
rowH:ADDLABEL("Selection:").
GLOBAL leftBtn  IS rowH:ADDBUTTON("< earlier").
GLOBAL rightBtn IS rowH:ADDBUTTON("later >").
GLOBAL downBtn  IS rowH:ADDBUTTON("- short TOF").
GLOBAL upBtn    IS rowH:ADDBUTTON("+ long TOF").
GLOBAL bestBtn  IS rowH:ADDBUTTON("Best").

GLOBAL detailLabel IS G:ADDLABEL("").
SET detailLabel:STYLE:RICHTEXT TO TRUE.

// ---- callbacks -----------------------------------------------------------
SET plotButton:ONCLICK TO { SET WANT_PLOT TO TRUE. }.
SET closeButton:ONCLICK TO { SET WANT_QUIT TO TRUE. }.
SET nowButton:ONCLICK TO {
  SET yearField:TEXT TO "" + TIME:YEAR.
  SET dayField:TEXT TO "" + TIME:DAY.
}.
SET leftBtn:ONCLICK  TO { SET MOVE_DC TO -1. SET WANT_MOVE TO TRUE. }.
SET rightBtn:ONCLICK TO { SET MOVE_DC TO  1. SET WANT_MOVE TO TRUE. }.
SET upBtn:ONCLICK    TO { SET MOVE_DR TO -1. SET WANT_MOVE TO TRUE. }.
SET downBtn:ONCLICK  TO { SET MOVE_DR TO  1. SET WANT_MOVE TO TRUE. }.
SET bestBtn:ONCLICK  TO { SET WANT_BEST TO TRUE. }.

G:SHOW.


// ============================================================================
//  SECTION 9 -- PLOTTING
// ============================================================================

// Pull the widgets into globals and sanity-check them.
FUNCTION readInputs {
  // Read menus by :INDEX -- see the BODYNAMES comment in Section 8 for why.
  SET ORIGIN_B TO BODY(BODYNAMES[originMenu:INDEX]).
  SET DEST_B TO BODY(BODYNAMES[destMenu:INDEX]).

  IF ORIGIN_B:NAME = DEST_B:NAME {
    SET statusLabel:TEXT TO "<color=#ff6060>Origin and destination must differ.</color>".
    RETURN FALSE.
  }
  IF (NOT ORIGIN_B:HASBODY) OR (NOT DEST_B:HASBODY)
     OR ORIGIN_B:BODY:NAME <> DEST_B:BODY:NAME {
    SET statusLabel:TEXT TO "<color=#ff6060>Both bodies must orbit the same parent.</color>".
    RETURN FALSE.
  }

  SET PARENT_B TO ORIGIN_B:BODY.
  SET PARK_ALT TO parkField:TEXT:TONUMBER(100).
  SET CAPT_ALT TO captField:TEXT:TONUMBER(100).
  SET NO_INSERTION TO noInsCheck:PRESSED.

  // 0 = Ballistic, 1 = Mid-course plane change, 2 = Optimal
  SET XFER_MODE TO typeMenu:INDEX.

  IF resMenu:INDEX = 0 {
    SET NCOLS TO 16. SET NROWS TO 12.
  } ELSE IF resMenu:INDEX = 2 {
    SET NCOLS TO 32. SET NROWS TO 24.
  } ELSE {
    SET NCOLS TO 24. SET NROWS TO 18.
  }

  SET DEP0 TO ymdToUT(yearField:TEXT:TONUMBER(1), dayField:TEXT:TONUMBER(1)).

  // --- default search window ---------------------------------------------
  // Departure span: one synodic period, i.e. how long until the same relative
  // geometry recurs -- exactly one full cycle of launch windows.
  LOCAL T1 IS ORIGIN_B:ORBIT:PERIOD.
  LOCAL T2 IS DEST_B:ORBIT:PERIOD.
  LOCAL syn IS T1.
  IF ABS(1/T1 - 1/T2) > 0 { SET syn TO ABS(1/(1/T1 - 1/T2)). }
  LOCAL span IS spanField:TEXT:TONUMBER(0) * dayLen().
  IF span <= 0 { SET span TO MIN(syn, 4*MAX(T1, T2)). }
  SET DEPSTEP TO span / (NCOLS - 1).

  // Time of flight: bracket the Hohmann transfer time between the two
  // semi-major axes, which is always in the right ballpark.
  LOCAL at IS 0.5*(ORIGIN_B:ORBIT:SEMIMAJORAXIS + DEST_B:ORBIT:SEMIMAJORAXIS).
  LOCAL th IS CONSTANT:PI * SQRT(at*at*at / PARENT_B:MU).
  SET TOFMIN TO tofMinField:TEXT:TONUMBER(0) * dayLen().
  SET TOFMAX TO tofMaxField:TEXT:TONUMBER(0) * dayLen().
  IF TOFMIN <= 0 { SET TOFMIN TO MAX(0.25*th, dayLen()). }
  IF TOFMAX <= TOFMIN { SET TOFMAX TO 2*th. }
  SET TOFSTEP TO (TOFMAX - TOFMIN) / (NROWS - 1).

  RETURN TRUE.
}

// Row 0 is the TOP of the plot and holds the LONGEST time of flight, matching
// the web tool: TOF increases upward, departure date increases rightward.
FUNCTION tofOfRow { PARAMETER ri. RETURN TOFMAX - ri*TOFSTEP. }
FUNCTION depOfCol { PARAMETER c. RETURN DEP0 + c*DEPSTEP. }

FUNCTION buildGrid {
  SET GRID TO LIST().
  SET DVMIN TO -1.
  LOCAL dvMax IS 0.
  LOCAL bestR IS 0.
  LOCAL bestC IS 0.

  FROM {LOCAL ri IS 0.} UNTIL ri >= NROWS STEP {SET ri TO ri+1.} DO {
    LOCAL row IS LIST().
    FROM {LOCAL c IS 0.} UNTIL c >= NCOLS STEP {SET c TO c+1.} DO {
      LOCAL d IS computeTransfer(depOfCol(c), tofOfRow(ri), XFER_MODE).
      IF d:ok {
        row:ADD(d:total).
        IF DVMIN < 0 OR d:total < DVMIN {
          SET DVMIN TO d:total.
          SET bestR TO ri.
          SET bestC TO c.
        }
        IF d:total > dvMax { SET dvMax TO d:total. }
      } ELSE {
        row:ADD(-1).
      }
    }
    GRID:ADD(row).

    // Yield a tick so the GUI repaints and the game does not look frozen.
    SET statusLabel:TEXT TO "Calculating... " + ROUND(100*(ri+1)/NROWS) + "%".
    WAIT 0.
  }

  // The colour scale runs from the cheapest transfer up to twice that (or the
  // true maximum if it is lower). Clamping the top is what gives a porkchop
  // its readable contours instead of one blue dot in a field of red.
  SET DVTOP TO MIN(dvMax, DVMIN*2).
  IF DVTOP <= DVMIN { SET DVTOP TO DVMIN*1.2 + 1. }

  SET SELR TO bestR.
  SET SELC TO bestC.
  SET HAVEPLOT TO TRUE.
}

FUNCTION colourFor {
  PARAMETER dv.
  IF dv < 0 { RETURN "#202020". }                 // no solution at this point
  LOCAL f IS clampv((dv - DVMIN)/(DVTOP - DVMIN), 0, 1).
  RETURN PALETTE[ROUND(f * (PALETTE:LENGTH - 1))].
}

// Draw the grid into the label. Runs of same-coloured cells share one tag --
// without that run-length encoding a 32x24 plot needs 768 colour tags and
// Unity's text layout crawls.
FUNCTION renderPlot {
  LOCAL s IS "".
  LOCAL openHex IS "".
  FROM {LOCAL ri IS 0.} UNTIL ri >= NROWS STEP {SET ri TO ri+1.} DO {
    LOCAL row IS GRID[ri].
    FROM {LOCAL c IS 0.} UNTIL c >= NCOLS STEP {SET c TO c+1.} DO {
      LOCAL hex IS colourFor(row[c]).
      IF ri = SELR AND c = SELC { SET hex TO "#ffffff". }    // the cursor
      IF hex <> openHex {
        IF openHex <> "" { SET s TO s + "</color>". }
        SET s TO s + "<color=" + hex + ">".
        SET openHex TO hex.
      }
      SET s TO s + BLK.
    }
    IF openHex <> "" {
      SET s TO s + "</color>".
      SET openHex TO "".
    }
    SET s TO s + NL.
  }
  SET plotLabel:TEXT TO s.

  SET topAxis:TEXT TO "TOF " + ROUND(toDays(TOFMAX)) + " d  (top)      departure "
    + fmtUT(DEP0) + "  ->  " + fmtUT(depOfCol(NCOLS-1)).
  SET botAxis:TEXT TO "TOF " + ROUND(toDays(TOFMIN)) + " d  (bottom)".

  // Colour key.
  LOCAL key IS "".
  FROM {LOCAL i IS 0.} UNTIL i >= PALETTE:LENGTH STEP {SET i TO i+1.} DO {
    SET key TO key + "<color=" + PALETTE[i] + ">" + BLK + BLK + "</color>".
  }
  SET legendLabel:TEXT TO ROUND(DVMIN) + " m/s " + key + " " + ROUND(DVTOP) + "+ m/s".
}

// Recompute and display everything about the selected cell. Only the total dv
// is stored in the grid, so the full detail set is recomputed on demand --
// one transfer is cheap compared with the whole plot.
FUNCTION showDetails {
  LOCAL d IS computeTransfer(depOfCol(SELC), tofOfRow(SELR), XFER_MODE).
  IF NOT d:ok {
    SET detailLabel:TEXT TO "<color=#ff6060>No transfer solution at this point.</color>".
    RETURN.
  }

  LOCAL s IS "<b>Selected transfer (" + d:type + ")</b>" + NL.
  SET s TO s + "Departure       " + fmtUT(d:t0) + NL.
  SET s TO s + "Arrival         " + fmtUT(d:t1) + NL.
  SET s TO s + "Time of flight  " + ROUND(toDays(d:tof), 1) + " days" + NL.
  SET s TO s + "Phase angle     " + ROUND(phaseAngle(d:t0), 2) + " deg" + NL.
  SET s TO s + "Ejection angle  " + ROUND(ejectionAngle(d), 2) + " deg from prograde" + NL.
  SET s TO s + "Ejection incl.  " + ROUND(d:ejInc * CONSTANT:RADTODEG, 2) + " deg" + NL.
  SET s TO s + "<b>Ejection dv     " + ROUND(d:ejDv, 1) + " m/s</b>" + NL.
  SET s TO s + "Transfer angle  " + ROUND(d:ta * CONSTANT:RADTODEG, 1) + " deg" + NL.
  IF d:pcDv > 0 {
    SET s TO s + "Plane change    " + fmtUT(d:pcTime)
             + "   (" + ROUND(d:pcAngle * CONSTANT:RADTODEG, 2) + " deg)" + NL.
    SET s TO s + "<b>Plane change dv " + ROUND(d:pcDv, 1) + " m/s</b>" + NL.
  }
  IF NO_INSERTION {
    SET s TO s + "Arrival v-inf   " + ROUND(d:insVinf, 1) + " m/s (no insertion burn)" + NL.
  } ELSE {
    SET s TO s + "<b>Insertion dv    " + ROUND(d:insDv, 1) + " m/s</b>" + NL.
  }
  SET s TO s + "<b>TOTAL dv        " + ROUND(d:total, 1) + " m/s</b>".
  SET detailLabel:TEXT TO s.

  // Echo to the terminal too, so the numbers can be scrolled back through.
  PRINT "-- " + fmtUT(d:t0) + " -> " + fmtUT(d:t1)
      + "   total " + ROUND(d:total, 1) + " m/s".
}


// ============================================================================
//  SECTION 10 -- MAIN LOOP
// ----------------------------------------------------------------------------
//  GUI callbacks run on the main thread between waits, so a long calculation
//  inside one would stall the interpreter. The callbacks raise flags; this
//  loop does the work.
// ============================================================================

PRINT "GUI open. Set your parameters and press 'Plot it!'".

UNTIL WANT_QUIT {

  IF WANT_PLOT {
    SET WANT_PLOT TO FALSE.
    IF readInputs() {
      SET statusLabel:TEXT TO "Calculating...".
      SET plotLabel:TEXT TO "".
      WAIT 0.
      buildGrid().
      renderPlot().
      showDetails().
      SET statusLabel:TEXT TO "Done. Cheapest transfer " + ROUND(DVMIN)
        + " m/s departing " + fmtUT(depOfCol(SELC)).
    }
  }

  IF WANT_MOVE AND HAVEPLOT {
    SET WANT_MOVE TO FALSE.
    SET SELR TO clampv(SELR + MOVE_DR, 0, NROWS - 1).
    SET SELC TO clampv(SELC + MOVE_DC, 0, NCOLS - 1).
    SET MOVE_DR TO 0.
    SET MOVE_DC TO 0.
    renderPlot().
    showDetails().
  }

  IF WANT_BEST AND HAVEPLOT {
    SET WANT_BEST TO FALSE.
    // Re-scan the stored grid for the global minimum.
    LOCAL bd IS -1.
    FROM {LOCAL ri IS 0.} UNTIL ri >= NROWS STEP {SET ri TO ri+1.} DO {
      LOCAL row IS GRID[ri].
      FROM {LOCAL c IS 0.} UNTIL c >= NCOLS STEP {SET c TO c+1.} DO {
        IF row[c] >= 0 AND (bd < 0 OR row[c] < bd) {
          SET bd TO row[c].
          SET SELR TO ri.
          SET SELC TO c.
        }
      }
    }
    renderPlot().
    showDetails().
  }

  WAIT 0.1.
}

// ---- teardown --------------------------------------------------------------
G:HIDE.
G:DISPOSE.
SET CONFIG:IPU TO OLD_IPU.
PRINT "Launch Window Planner closed.".
