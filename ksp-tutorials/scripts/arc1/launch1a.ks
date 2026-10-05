clearScreen.

set target_ap to 75000.
set turn_alt to 1000.
set azimuth to 90.

// countdown
FROM {LOCAL t IS 5.} UNTIL t = 0 STEP {SET t TO t-1.} DO {
  PRINT "T-MINUS " + t.
  WAIT 1.
}

sas off.
rcs off.
set pitch to 90.
lock throttle to 1.
lock steering to heading(azimuth, pitch).

stage.

print "LIFTOFF          " at (0, 0).

until ship:altitude > turn_alt {
  telemetry().
  wait 0.
}

set pitch to 80.
print "PITCH PROGRAM           " at (0,0).

until ship:apoapsis > target_ap {
  telemetry().
  wait 0.
}

// MECO
lock throttle to 0.
print "MECO                                   " at (0,0).
wait 1.
unlock steering.
unlock throttle.
sas on.

// util

function telemetry {
  PRINT "ALT   " + ROUND(SHIP:ALTITUDE) + "    " AT (0, 2).
  PRINT "AP    " + ROUND(SHIP:APOAPSIS) + "    " AT (0, 3).
  PRINT "SPD   " + ROUND(SHIP:VELOCITY:SURFACE:MAG) + "    " AT (0, 4).
  PRINT "PITCH " + pitch + "    " AT (0, 5).
}