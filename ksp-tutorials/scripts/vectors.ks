// vectors.ks - kOS drawing in the world, not in the terminal
// RUNONCEPATH("0:/vectors.ks").
//
//   VWATCH()          live arrows: velocity, nose, up, and the angle
//                     between nose and velocity. Ctrl+C to stop.
//   GHOST("hand1")    redraw a saved flight as a trail in the sky.
//   GHOSTOFF()        clear everything.
//
// VECDRAW is the only real graphics primitive kOS has. It draws in the
// flight scene, in ship-relative coordinates, so anything pinned to the
// world has to be recomputed as the ship moves. That is what the refresh
// loops below are doing.
//
// Arrowheads are optional: the eighth argument is 'pointy'. Pass FALSE
// and you get a plain line segment, which is what makes polylines work.

GLOBAL GH_LINES IS LIST().

FUNCTION GHOSTOFF {
    CLEARVECDRAWS().
    SET GH_LINES TO LIST().
}

// -------------------------------------------------------- live vectors

FUNCTION VWATCH {
    PARAMETER scale IS 18.

    CLEARVECDRAWS().

    LOCAL vVel IS VECDRAW(V(0,0,0), V(0,0,1), RGB(0.2,1,0.3), "velocity",
                          1, TRUE, 0.25, TRUE).
    LOCAL vNose IS VECDRAW(V(0,0,0), V(0,0,1), RGB(1,0.75,0.1), "nose",
                           1, TRUE, 0.25, TRUE).
    LOCAL vUp IS VECDRAW(V(0,0,0), V(0,0,1), RGB(0.4,0.6,1), "up",
                         1, TRUE, 0.15, TRUE).

    CLEARSCREEN.
    PRINT "=== vector watch - fires nothing ===".
    PRINT "Ctrl+C to stop, then run GHOSTOFF().".

    UNTIL FALSE {
        LOCAL surfV IS SHIP:VELOCITY:SURFACE.
        LOCAL spd IS surfV:MAG.

        SET vUp:VEC TO SHIP:UP:VECTOR * scale * 0.7.
        SET vNose:VEC TO SHIP:FACING:VECTOR * scale.

        LOCAL aoa IS 0.
        IF spd > 1 {
            SET vVel:VEC TO surfV:NORMALIZED * scale.
            SET aoa TO VANG(SHIP:FACING:VECTOR, surfV).
            // recolour the nose by how far off velocity it is
            LOCAL bad IS MIN(1, aoa / 30).
            SET vNose:COLOR TO RGB(bad, 1 - bad, 0.1).
        }

        PRINT "speed     " + ROUND(spd,1):TOSTRING:PADLEFT(8) + " m/s " AT (0,4).
        PRINT "alt       " + ROUND(SHIP:ALTITUDE):TOSTRING:PADLEFT(8) + " m   " AT (0,5).
        PRINT "aoa       " + ROUND(aoa,2):TOSTRING:PADLEFT(8) + " deg " AT (0,6).
        PRINT "cos loss  " + ROUND(100*(1-COS(aoa)),2):TOSTRING:PADLEFT(8) + " %   " AT (0,7).

        WAIT 0.
    }
}

// --------------------------------------------------------- ghost trail

FUNCTION GHOST {
    PARAMETER name.
    PARAMETER maxSegs IS 70.
    PARAMETER refresh IS 0.3.

    LOCAL fpath IS "0:/fl_" + name + ".json".
    IF NOT EXISTS(fpath) {
        PRINT "ghost: no flight called '" + name + "'".
        RETURN.
    }
    LOCAL blob IS READJSON(fpath).

    // field lookup
    LOCAL idx IS LEXICON().
    LOCAL col IS 0.
    FOR fld IN blob["fields"] {
        idx:ADD(fld, col).
        SET col TO col + 1.
    }
    IF NOT idx:HASKEY("lat") {
        PRINT "ghost: this recording predates lat/lng logging.".
        PRINT "       Record a new one with the updated flightlog.ks.".
        RETURN.
    }

    LOCAL rows IS blob["rows"].
    IF rows:LENGTH < 4 { PRINT "ghost: not enough data.". RETURN. }

    // downsample to keep the vecdraw count sane
    LOCAL stride IS MAX(1, FLOOR(rows:LENGTH / maxSegs)).
    LOCAL pts IS LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= rows:LENGTH STEP { SET i TO i + stride. } DO {
        LOCAL datarow IS rows[i].
        pts:ADD(LEXICON(
            "lat", datarow[idx["lat"]],
            "lng", datarow[idx["lng"]],
            "alt", datarow[idx["alt"]],
            "aoa", datarow[idx["aoa"]]
        )).
    }

    PRINT "ghost: drawing " + (pts:LENGTH - 1) + " segments from '" + name + "'".
    PRINT "       green = on prograde, red = high angle of attack".
    PRINT "       AG2 to clear.".

    GHOSTOFF().

    // build the segments, coloured by angle of attack
    FROM { LOCAL i IS 0. } UNTIL i >= pts:LENGTH - 1 STEP { SET i TO i+1. } DO {
        LOCAL bad IS MIN(1, pts[i]["aoa"] / 25).
        LOCAL seg IS VECDRAW(V(0,0,0), V(0,0,1),
                             RGB(bad, 1 - bad, 0.15),
                             "", 1, TRUE, 0.12, FALSE).
        GH_LINES:ADD(seg).
    }

    // keep them pinned to the ground as the ship moves
    AG2 OFF.
    UNTIL AG2 {
        FROM { LOCAL i IS 0. } UNTIL i >= GH_LINES:LENGTH STEP { SET i TO i+1. } DO {
            LOCAL pa IS LATLNG(pts[i]["lat"], pts[i]["lng"]):ALTITUDEPOSITION(pts[i]["alt"]).
            LOCAL pb IS LATLNG(pts[i+1]["lat"], pts[i+1]["lng"]):ALTITUDEPOSITION(pts[i+1]["alt"]).
            SET GH_LINES[i]:START TO pa.
            SET GH_LINES[i]:VEC TO pb - pa.
        }
        WAIT refresh.
    }

    GHOSTOFF().
    AG2 OFF.
    PRINT "ghost: cleared.".
}

PRINT "vectors.ks loaded. VWATCH() for live arrows, GHOST for a trail.".

