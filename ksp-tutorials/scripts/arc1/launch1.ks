CLEARSCREEN.

//print 5 second countdown
FROM {LOCAL t IS 5.} UNTIL t = 0 STEP {SET t TO t-1.} DO {
  PRINT "T-MINUS " + t at (0,0).
  WAIT 1.
}

//disable sas, lock throttle to full and steering to straight up due east
SAS OFF. RCS OFF. LOCK THROTTLE TO 1.
LOCK STEERING TO HEADING(90,90).

//stage
STAGE.

//hold vertical until 1000m
WAIT UNTIL SHIP:ALTITUDE > 1000.

//pitch to 80deg above horizon
LOCK STEERING TO HEADING(90, 80).

//continue to print alt, ap, surface speed at fixed screen positions
//cut throttle when ap passes 75km
UNTIL SHIP:APOAPSIS > 75000 {
  PRINT "ALT  " + ROUND(SHIP:ALTITUDE) + "    " AT (0, 4).
  PRINT "AP   " + ROUND(SHIP:APOAPSIS) + "    " AT (0, 5).
  PRINT "SPD  " + ROUND(SHIP:VELOCITY:SURFACE:MAG) + "    " AT (0, 6).
  WAIT 0.
}

LOCK THROTTLE TO 0.

//print MECO
WAIT 1.
PRINT "MECO".