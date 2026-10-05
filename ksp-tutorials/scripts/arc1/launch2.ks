clearScreen.

// ascent target

set target_ap to 75000.
set azimuth to 90.

// ascent profile

set turn_start to 1000.
set turn_end to 45000.
set pitch0 to 90.
set pitch1 to 0.

set shape_k to 1.0.

// program

// countdown
FROM {LOCAL t IS 5.} UNTIL t = 0 STEP {SET t TO t-1.} DO {
  PRINT "T-MINUS          " + t AT (0,0).
  WAIT 1.
}

sas off.
rcs off.
lock throttle to 1.
lock steering to heading(azimuth, pitch_at(ship:altitude)).
stage.
print "LIFTOFF             " at (0, 0).

until ship:apoapsis > target_ap {
  telemetry().
  wait 0.
}

// MECO
lock throttle to 0.
// clearScreen.
print "MECO                                   " at (0,0).
print "vertical    " + ROUND(ship:verticalspeed,2) at (0,7).
print "horizontal  " + ROUND(horizontal_speed(),2) at (0,8).
wait 1.
unlock steering.
unlock throttle.
// sas on.

// util

function telemetry {
  PRINT "ALT   " + ROUND(SHIP:ALTITUDE,2) + "    " AT (0, 2).
  PRINT "AP    " + ROUND(SHIP:APOAPSIS,2) + "    " AT (0, 3).
  PRINT "SPD   " + ROUND(SHIP:VELOCITY:SURFACE:MAG,2) + "    " AT (0, 4).
  PRINT "PITCH " + ROUND(pitch_at(ship:altitude),2) + "    " AT (0, 5).
  PRINT "deg/s " + ROUND(pitch_rate(),2) + "    " AT (0, 6).
}

function turn_fraction {
  declare parameter h.
  local f is (h - turn_start) / (turn_end - turn_start).
  return min(max(f,0),1).
}

function pitch_at {
  declare parameter h.
  return pitch0 + (pitch1 - pitch0) * (turn_fraction(h) ^ shape_k).
}

function pitch_rate {
  local h is ship:altitude.
  local dh is 10.
  local slope is (pitch_at(h + dh) - pitch_at(h - dh)) / (2 * dh).
  return slope * ship:verticalspeed.
}

FUNCTION horizontal_speed {
  LOCAL vt IS SHIP:VELOCITY:ORBIT:MAG.
  LOCAL vv IS SHIP:VERTICALSPEED.
  RETURN SQRT(MAX(vt^2 - vv^2, 0)).
}