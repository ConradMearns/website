// plotlib.ks - draw saved flights in the kOS terminal
// RUNONCEPATH("0:/plotlib.ks").
//
// Widen the terminal first, or the plots will be cramped:
//   SET TERMINAL:WIDTH TO 80.
//   SET TERMINAL:HEIGHT TO 40.
//
//   PLOT("tier0", "alt", "gamma")            one flight
//   PLOT2("tier0", "tier2", "alt", "gamma")  two flights overlaid
//   BUDGET("tier0")                          delta-v accounting bar chart
//   FIELDS()                                 what you can plot
//
// Useful pairs:
//   "alt","pitch"    the attitude curve you actually flew
//   "alt","gamma"    the trajectory the rocket actually took
//   "alt","aoa"      angle of attack - steering loss made visible
//   "t","etaap"      time to apoapsis, the governor variable
//   "alt","dynp"     dynamic pressure, to find max Q
//   "t","dv"         cumulative delta-v spent

FUNCTION FIELDS {
    PRINT "t alt spd vspd pitch gamma aoa dynp mass thr ap etaap dv grav steer drag".
}

FUNCTION FLLOAD {
    PARAMETER name.
    LOCAL fpath IS "0:/fl_" + name + ".json".
    IF NOT EXISTS(fpath) {
        PRINT "plot: no flight called '" + name + "'".
        RETURN 0.
    }
    RETURN READJSON(fpath).
}

FUNCTION COLOF {
    PARAMETER blob, fname.
    LOCAL idx IS 0.
    FOR fld IN blob["fields"] {
        IF fld = fname { RETURN idx. }
        SET idx TO idx + 1.
    }
    RETURN -1.
}

// Pull one field out of a flight as a flat list.
FUNCTION SERIESOF {
    PARAMETER blob, fname.
    LOCAL idx IS COLOF(blob, fname).
    LOCAL out IS LIST().
    IF idx < 0 { RETURN out. }
    FOR datarow IN blob["rows"] { out:ADD(datarow[idx]). }
    RETURN out.
}

// ------------------------------------------------------------ the canvas

// series is a LIST of LEXICON("x", xlist, "y", ylist, "g", glyph)
FUNCTION DRAWPLOT {
    PARAMETER series.
    PARAMETER title IS "".
    PARAMETER xlab IS "x".
    PARAMETER ylab IS "y".
    PARAMETER wide IS 60.
    PARAMETER tall IS 20.

    // ---- bounds across every series ---------------------------------
    LOCAL xmin IS 1e18. LOCAL xmax IS -1e18.
    LOCAL ymin IS 1e18. LOCAL ymax IS -1e18.
    FOR ser IN series {
        FOR val IN ser["x"] {
            IF val < xmin { SET xmin TO val. }
            IF val > xmax { SET xmax TO val. }
        }
        FOR val IN ser["y"] {
            IF val < ymin { SET ymin TO val. }
            IF val > ymax { SET ymax TO val. }
        }
    }
    IF xmax <= xmin { SET xmax TO xmin + 1. }
    IF ymax <= ymin { SET ymax TO ymin + 1. }

    // ---- blank grid ---------------------------------------------------
    LOCAL grid IS LIST().
    FROM { LOCAL j IS 0. } UNTIL j >= tall STEP { SET j TO j+1. } DO {
        LOCAL gridrow IS LIST().
        FROM { LOCAL i IS 0. } UNTIL i >= wide STEP { SET i TO i+1. } DO {
            gridrow:ADD(" ").
        }
        grid:ADD(gridrow).
    }

    // ---- plot points ---------------------------------------------------
    FOR ser IN series {
        LOCAL xs IS ser["x"].
        LOCAL ys IS ser["y"].
        LOCAL glyph IS ser["g"].
        LOCAL count IS MIN(xs:LENGTH, ys:LENGTH).
        FROM { LOCAL k IS 0. } UNTIL k >= count STEP { SET k TO k+1. } DO {
            LOCAL cx IS ROUND((xs[k] - xmin) / (xmax - xmin) * (wide - 1)).
            LOCAL cy IS ROUND((ys[k] - ymin) / (ymax - ymin) * (tall - 1)).
            SET cx TO MIN(wide-1, MAX(0, cx)).
            SET cy TO MIN(tall-1, MAX(0, cy)).
            SET grid[tall - 1 - cy][cx] TO glyph.
        }
    }

    // ---- render ---------------------------------------------------------
    PRINT " ".
    IF title <> "" { PRINT "  " + title. }
    PRINT "  " + ylab + " max " + ROUND(ymax, 2).
    FOR gridrow IN grid {
        LOCAL line IS " |".
        FOR cell IN gridrow { SET line TO line + cell. }
        PRINT line.
    }
    LOCAL axis IS " +".
    FROM { LOCAL i IS 0. } UNTIL i >= wide STEP { SET i TO i+1. } DO {
        SET axis TO axis + "-".
    }
    PRINT axis.
    PRINT "  " + ylab + " min " + ROUND(ymin, 2).
    PRINT "  " + xlab + ": " + ROUND(xmin,2) + " to " + ROUND(xmax,2).
}

// ---------------------------------------------------------------- fronts

FUNCTION PLOT {
    PARAMETER name, xfield, yfield.
    LOCAL blob IS FLLOAD(name).
    IF blob:TYPENAME = "Scalar" { RETURN. }

    LOCAL ser IS LIST(LEXICON(
        "x", SERIESOF(blob, xfield),
        "y", SERIESOF(blob, yfield),
        "g", "*")).
    DRAWPLOT(ser, name + ": " + yfield + " vs " + xfield, xfield, yfield).
}

FUNCTION PLOT2 {
    PARAMETER nameA, nameB, xfield, yfield.
    LOCAL blobA IS FLLOAD(nameA).
    LOCAL blobB IS FLLOAD(nameB).
    IF blobA:TYPENAME = "Scalar" OR blobB:TYPENAME = "Scalar" { RETURN. }

    LOCAL ser IS LIST(
        LEXICON("x", SERIESOF(blobA, xfield), "y", SERIESOF(blobA, yfield), "g", "*"),
        LEXICON("x", SERIESOF(blobB, xfield), "y", SERIESOF(blobB, yfield), "g", "#")).
    DRAWPLOT(ser, "* " + nameA + "   # " + nameB, xfield, yfield).
}

// ------------------------------------------------------------ bar chart

FUNCTION BUDGET {
    PARAMETER name.
    LOCAL blob IS FLLOAD(name).
    IF blob:TYPENAME = "Scalar" { RETURN. }

    LOCAL rows IS blob["rows"].
    IF rows:LENGTH = 0 { PRINT "plot: empty flight.". RETURN. }
    LOCAL final IS rows[rows:LENGTH - 1].

    LOCAL dv IS final[COLOF(blob, "dv")].
    LOCAL grav IS final[COLOF(blob, "grav")].
    LOCAL steer IS final[COLOF(blob, "steer")].
    LOCAL drag IS final[COLOF(blob, "drag")].
    LOCAL gained IS dv - grav - steer - drag.

    LOCAL span IS MAX(1, dv).
    PRINT " ".
    PRINT "  === " + name + " budget ===".
    BARLINE("speed   ", gained, span).
    BARLINE("gravity ", grav, span).
    BARLINE("steering", steer, span).
    BARLINE("drag    ", drag, span).
    PRINT "  " + "total    " + ROUND(dv,1) + " m/s".
    IF dv > 0 {
        PRINT "  efficiency " + ROUND(100*gained/dv, 1) + " %".
    }
}

FUNCTION BARLINE {
    PARAMETER label, value, span.
    LOCAL cells IS ROUND(MAX(0, value) / span * 40).
    LOCAL bar IS "".
    FROM { LOCAL i IS 0. } UNTIL i >= cells STEP { SET i TO i+1. } DO {
        SET bar TO bar + "#".
    }
    PRINT "  " + label + " " + bar + " " + ROUND(value,1).
}

PRINT "plotlib.ks loaded. Widen the terminal, then call PLOT.".

