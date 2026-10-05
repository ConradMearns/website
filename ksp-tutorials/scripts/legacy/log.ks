// flightlog.ks - record an ascent, by hand or by script
// RUNONCEPATH("0:/flightlog.ks").
//
//   FLRECORD("name")   standalone recorder. Start it, fly however you like,
//                      press AG1 to stop and save. Fires nothing.
//   FLINIT() / FLSAMPLE() / FLSAVE("name")
//                      call these from inside your own ascent loop.
//   FLLIST()           show saved flights.
//
// Saves two files to the archive:
//   0:/fl_<name>.json   for replay and plotting
//   0:/fl_<name>.csv    for a spreadsheet, if you want one
//
// Also integrates the ascent loss budget as it goes, so every recording
// carries its own delta-v accounting.

GLOBAL FL_FIELDS IS LIST(
    "t", "alt", "spd", "vspd", "pitch", "gamma", "aoa",
    "dynp", "mass", "thr", "ap", "etaap", "dv", "grav", "steer", "drag",
    "lat", "lng").

GLOBAL FL_ROWS IS LIST().
GLOBAL FL_LAST IS 0.
GLOBAL FL_RATE IS 0.2.        // seconds between samples
GLOBAL FL_T0 IS 0.
GLOBAL FL_SPENT IS 0.
GLOBAL FL_GRAV IS 0.
GLOBAL FL_STEER IS 0.
GLOBAL FL_SPD0 IS 0.
GLOBAL FL_PREV IS 0.

FUNCTION FLINIT {
    SET FL_ROWS TO LIST().
    SET FL_T0 TO TIME:SECONDS.
    SET FL_LAST TO 0.
    SET FL_PREV TO TIME:SECONDS.
    SET FL_SPENT TO 0.
    SET FL_GRAV TO 0.
    SET FL_STEER TO 0.
    SET FL_SPD0 TO SHIP:VELOCITY:SURFACE:MAG.
}

FUNCTION FLSAMPLE {
    LOCAL now IS TIME:SECONDS.

    // ---- integrate losses every call, at full tick rate ----------------
    LOCAL dt IS now - FL_PREV.
    SET FL_PREV TO now.
    IF dt > 0 AND dt < 1 {
        LOCAL spd IS SHIP:VELOCITY:SURFACE:MAG.
        LOCAL aThrust IS SHIP:AVAILABLETHRUST * THROTTLE / SHIP:MASS.
        LOCAL rad IS SHIP:BODY:RADIUS + SHIP:ALTITUDE.
        LOCAL grav IS SHIP:BODY:MU / (rad * rad).

        LOCAL gamma IS 90.
        LOCAL alpha IS 0.
        IF spd > 1 {
            SET gamma TO 90 - VANG(SHIP:VELOCITY:SURFACE, SHIP:UP:VECTOR).
            SET alpha TO VANG(SHIP:FACING:VECTOR, SHIP:VELOCITY:SURFACE).
        }

        SET FL_SPENT TO FL_SPENT + aThrust * dt.
        SET FL_GRAV TO FL_GRAV + grav * SIN(gamma) * dt.
        SET FL_STEER TO FL_STEER + aThrust * (1 - COS(alpha)) * dt.
    }

    // ---- store a row at the sample rate --------------------------------
    IF now - FL_LAST < FL_RATE { RETURN. }
    SET FL_LAST TO now.

    LOCAL spd IS SHIP:VELOCITY:SURFACE:MAG.
    LOCAL gamma IS 90.
    LOCAL alpha IS 0.
    IF spd > 1 {
        SET gamma TO 90 - VANG(SHIP:VELOCITY:SURFACE, SHIP:UP:VECTOR).
        SET alpha TO VANG(SHIP:FACING:VECTOR, SHIP:VELOCITY:SURFACE).
    }
    LOCAL pitchNow IS 90 - VANG(SHIP:FACING:VECTOR, SHIP:UP:VECTOR).
    LOCAL gained IS spd - FL_SPD0.
    LOCAL dragLoss IS FL_SPENT - gained - FL_GRAV - FL_STEER.

    LOCAL etaAp IS 0.
    IF SHIP:ORBIT:ECCENTRICITY < 1 { SET etaAp TO ETA:APOAPSIS. }

    FL_ROWS:ADD(LIST(
        ROUND(now - FL_T0, 2),
        ROUND(SHIP:ALTITUDE, 1),
        ROUND(spd, 2),
        ROUND(SHIP:VERTICALSPEED, 2),
        ROUND(pitchNow, 2),
        ROUND(gamma, 2),
        ROUND(alpha, 2),
        ROUND(SHIP:Q, 5),
        ROUND(SHIP:MASS, 4),
        ROUND(SHIP:AVAILABLETHRUST * THROTTLE, 2),
        ROUND(SHIP:APOAPSIS, 1),
        ROUND(etaAp, 1),
        ROUND(FL_SPENT, 2),
        ROUND(FL_GRAV, 2),
        ROUND(FL_STEER, 2),
        ROUND(dragLoss, 2),
        ROUND(SHIP:GEOPOSITION:LAT, 6),
        ROUND(SHIP:GEOPOSITION:LNG, 6)
    )).
}

FUNCTION FLSAVE {
    PARAMETER name.

    LOCAL jpath IS "0:/fl_" + name + ".json".
    LOCAL cpath IS "0:/fl_" + name + ".csv".

    IF EXISTS(jpath) { DELETEPATH(jpath). }
    IF EXISTS(cpath) { DELETEPATH(cpath). }

    LOCAL blob IS LEXICON(
        "name", name,
        "body", SHIP:BODY:NAME,
        "fields", FL_FIELDS,
        "rows", FL_ROWS
    ).
    WRITEJSON(blob, jpath).

    // csv header
    LOCAL head IS "".
    FOR fname IN FL_FIELDS {
        IF head = "" { SET head TO fname. } ELSE { SET head TO head + "," + fname. }
    }
    LOG head TO cpath.
    FOR datarow IN FL_ROWS {
        LOCAL line IS "".
        FOR cell IN datarow {
            IF line = "" { SET line TO cell:TOSTRING. }
            ELSE { SET line TO line + "," + cell:TOSTRING. }
        }
        LOG line TO cpath.
    }

    PRINT "saved " + FL_ROWS:LENGTH + " samples to " + jpath.
    PRINT "       and " + cpath.
}

FUNCTION FLLIST {
    PRINT "saved flights:".
    LIST FILES IN allfiles.
    FOR entry IN allfiles {
        IF entry:NAME:STARTSWITH("fl_") AND entry:NAME:ENDSWITH(".json") {
            PRINT "  " + entry:NAME.
        }
    }
}

// ------------------------------------------------------- standalone mode

// Run this, then fly by hand. AG1 stops and saves.
FUNCTION FLRECORD {
    PARAMETER name IS "manual".

    FLINIT().
    AG1 OFF.
    CLEARSCREEN.
    PRINT "=== recording '" + name + "' - fires nothing ===".
    PRINT "AG1 to stop and save.".

    UNTIL AG1 {
        FLSAMPLE().
        PRINT "samples  " + FL_ROWS:LENGTH:TOSTRING:PADLEFT(8) + "     " AT (0,3).
        PRINT "alt      " + ROUND(SHIP:ALTITUDE):TOSTRING:PADLEFT(8) + " m   " AT (0,4).
        PRINT "speed    " + ROUND(SHIP:VELOCITY:SURFACE:MAG,1):TOSTRING:PADLEFT(8) + " m/s " AT (0,5).
        PRINT "ap       " + ROUND(SHIP:APOAPSIS/1000,1):TOSTRING:PADLEFT(8) + " km  " AT (0,6).
        PRINT "eta ap   " + ROUND(ETA:APOAPSIS):TOSTRING:PADLEFT(8) + " s   " AT (0,7).
        PRINT " " AT (0,8).
        PRINT "dv spent " + ROUND(FL_SPENT,1):TOSTRING:PADLEFT(8) + " m/s " AT (0,9).
        PRINT "gravity  " + ROUND(FL_GRAV,1):TOSTRING:PADLEFT(8) + " m/s " AT (0,10).
        PRINT "steering " + ROUND(FL_STEER,1):TOSTRING:PADLEFT(8) + " m/s " AT (0,11).
        WAIT 0.
    }

    FLSAVE(name).
    AG1 OFF.
}

PRINT "flightlog.ks loaded. Try FLRECORD(hand1) with quotes around the name.".

