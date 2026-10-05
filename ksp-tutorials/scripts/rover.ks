// kOS Rover Script - waypoint / fixed-distance driving
CLEARSCREEN.
PRINT "Initializing Rover...".

// --- Configuration ---
SET SETSPEED TO 1.          // Target speed (m/s)
SET USE_TARGET TO TRUE.      // TRUE: drive to the waypoint set as target
                             // FALSE: drive DRIVE_DISTANCE meters straight ahead
SET DRIVE_DISTANCE TO 500.   // Distance (m) to drive when USE_TARGET is FALSE
SET ARRIVE_DIST TO 15.       // Stop when within this many meters of the waypoint

// Release brakes and turn on lights
SET BRAKES TO FALSE.
// SET SHIP:CONTROL:LIGHT TO TRUE.

// Remember where we started (for fixed-distance mode)
SET START_POS TO SHIP:GEOPOSITION.

SET WAYPOINT_TARGET TO 0.
FOR wp IN ALLWAYPOINTS() {
    IF wp:ISSELECTED {
        SET WAYPOINT_TARGET TO wp.
        BREAK.
    }
}

IF USE_TARGET {
    // IF HASTARGET AND TARGET:TYPENAME = "Waypoint" {
    IF WAYPOINT_TARGET:ISSELECTED {
        PRINT "Driving to waypoint: " + WAYPOINT_TARGET:NAME.
    } ELSE {
        PRINT "No waypoint targeted! Set a waypoint as target first.".
        PRINT "Falling back to fixed-distance mode.".
        SET USE_TARGET TO FALSE.
    }
}
IF NOT USE_TARGET {
    PRINT "Driving " + DRIVE_DISTANCE + " m forward.".
}

// Main loop - press TAB to abort
UNTIL False {
    SET SETSTEER TO 0.
    SET done TO FALSE.

    IF USE_TARGET {
        // --- Waypoint mode ---
        SET tgt TO WAYPOINT_TARGET:GEOPOSITION.
        SET dist TO tgt:DISTANCE.

        IF dist < ARRIVE_DIST {
            SET done TO TRUE.
        } ELSE {
            // Heading error between rover nose and direction to waypoint
            SET toTgt TO VXCL(SHIP:UP:VECTOR, tgt:POSITION - SHIP:POSITION):NORMALIZED.
            SET fwd TO VXCL(SHIP:UP:VECTOR, SHIP:FACING:VECTOR):NORMALIZED.
            SET err TO VANG(fwd, toTgt).
            IF VDOT(VCRS(fwd, toTgt), SHIP:UP:VECTOR) < 0 {
                SET err TO -err.
            }
            // Steer proportionally to heading error (full lock at 30 deg)
            SET SETSTEER TO MAX(-1, MIN(1, err / 30)).
            PRINT "Distance to waypoint: " + ROUND(dist, 1) + " m   " AT (0, 10).
        }
    } ELSE {
        // --- Fixed-distance mode ---
        SET traveled TO START_POS:DISTANCE.
        IF traveled >= DRIVE_DISTANCE {
            SET done TO TRUE.
        } ELSE {
            PRINT "Distance traveled: " + ROUND(traveled, 1) + " / " + DRIVE_DISTANCE + " m   " AT (0, 10).
        }
    }

    IF done { BREAK. }

    SET SHIP:CONTROL:WHEELTHROTTLE TO SETSPEED / 5. // Adjust scaling as needed
    SET SHIP:CONTROL:WHEELSTEER TO -SETSTEER.
    WAIT 0.05.
}

// Stop the rover
SET SHIP:CONTROL:WHEELTHROTTLE TO 0.
SET SHIP:CONTROL:WHEELSTEER TO 0.
SET BRAKES TO TRUE.
PRINT "Rover stopped.".
