// althold.ks - simple altitude hold for airplanes
// Usage: RUN althold(2000).   // hold 2000 m
// Change altitude mid-flight: SET TARGETALT TO 3500. (from another terminal or edit below)

PARAMETER holdAlt IS 2000.

CLEARSCREEN.
SET TARGETALT TO holdAlt.

// Hold whatever heading we're flying when the script starts
SET holdHeading TO MOD(360 - LATLNG(90,0):BEARING, 360). // current compass heading

// PID: altitude error (m) -> commanded pitch (deg)
// Output clamped to +/-15 deg so we don't stall or dive hard
SET altPid TO PIDLOOP(0.02, 0.0005, 0.02, -15, 15).
SET altPid:SETPOINT TO TARGETALT.

SAS OFF.
LOCK STEERING TO HEADING(holdHeading, pitchCmd).
SET pitchCmd TO 0.

UNTIL FALSE {
    // Allow live retarget: if TARGETALT was changed, update the PID setpoint
    IF altPid:SETPOINT <> TARGETALT {
        SET altPid:SETPOINT TO TARGETALT.
    }

    SET pitchCmd TO altPid:UPDATE(TIME:SECONDS, SHIP:ALTITUDE).

    PRINT "Target alt : " + ROUND(TARGETALT)        + " m   " AT (0, 1).
    PRINT "Current alt: " + ROUND(SHIP:ALTITUDE)    + " m   " AT (0, 2).
    PRINT "Pitch cmd  : " + ROUND(pitchCmd, 1)      + " deg " AT (0, 3).
    PRINT "VSpeed     : " + ROUND(SHIP:VERTICALSPEED, 1) + " m/s " AT (0, 4).

    WAIT 0. // run every physics tick
}
