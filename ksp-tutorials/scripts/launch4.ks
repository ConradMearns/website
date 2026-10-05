clearScreen.

// logging
SET log_file TO "0:/run_a.csv".
IF EXISTS (log_file) { DELETEPATH(). }
LOG "run,k,h0,h1,ut,met,alt,vsrf,vorb,spd,gamma,pitch,alpha,mass,thrust,dynp,ap,pe,dvIdeal,lossGrav,lossSteer,lossDrag,stagenum" TO log_file.


set met_start to time:seconds.
set met to time:seconds.



// const
set g0 to 9.80665.

// ascent target

set target_ap to 75000.
set azimuth to 90.

// ascent profile

set turn_start to 1000.
set turn_end to 45000.
set pitch0 to 90.
set pitch1 to 0.

set shape_k to 1.0.

// staging parameters

set cooldown to 1.
set last_cooldown to time:seconds.

// telemetry global state
set telemetry_row to 0.


// program

// countdown
FROM {LOCAL countdown IS 5.} UNTIL countdown = 0 STEP {SET countdown TO countdown-1.} DO {
  PRINT "T-MINUS          " + countdown AT (0,0).
  WAIT 1.
}

sas off.
rcs off.
lock throttle to 1.
lock steering to heading(azimuth, pitch_at(ship:altitude)).
stage.
print "LIFTOFF             " at (0, 0).

// ascent loop
until ship:apoapsis > target_ap {
  print_telemetry().
  auto_stage().
  log_telemetry().
  wait 0.
}

// MECO
lock throttle to 0.
// clearScreen.
print "MECO                                   " at (0,0).
// print "vertical    " + ROUND(ship:verticalspeed,2) at (0,7).
// print "horizontal  " + ROUND(horizontal_speed(),2) at (0,8).
wait 1.
unlock steering.
unlock throttle.
// sas on.

// util
function t {
  set telemetry_row to telemetry_row + 1.
  return telemetry_row.
}

function print_telemetry {
  set telemetry_row to 0.
  PRINT "ALT      " + ROUND(SHIP:ALTITUDE,2) + "    " AT (0, t()).
  PRINT "AP       " + ROUND(SHIP:APOAPSIS,2) + "    " AT (0, t()).
  PRINT "SPD      " + ROUND(SHIP:VELOCITY:SURFACE:MAG,2) + "    " AT (0, t()).
  PRINT "PITCH    " + ROUND(pitch_at(ship:altitude),2) + "    " AT (0, t()).
  PRINT "DEG/S    " + ROUND(pitch_rate(),2) + "    " AT (0, t()).
  // PRINT "STAGE    " + stage:number + "    " AT (0, t()).

  //  (current stage)
  // PRINT "dv left  " + remaining_stage_deltav()  + "    " AT (0, t()).
  // current mass
  PRINT "THRUST   " + ROUND(current_thrust(), 2) + "    " AT (0, t()).
  PRINT "ISP      " + ROUND(current_isp(), 2) + "    " AT (0, t()).
  // remaining propellent
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



FUNCTION should_stage {
  LOCAL IS_READY IS stage:ready.
  LOCAL IS_THROTTLE IS throttle > 0 .
  LOCAL IS_COOL IS (time:seconds - last_cooldown) > cooldown.
  LOCAL IS_BURNED IS all_engines_burned().

  PRINT "------------------------------" AT (0, t()).
  PRINT "READY    " + IS_READY + "     " AT (0, t()).
  PRINT "THROTTLE " + IS_THROTTLE + "     " AT (0, t()).
  PRINT "COOLDOWN " + time:seconds - last_cooldown +" > "+ cooldown + "     " AT (0, t()).
  PRINT "BURNED   " + IS_BURNED + "     " AT (0, t()).

  return IS_READY 
    and IS_THROTTLE
    and IS_COOL 
    and IS_BURNED.
}

FUNCTION all_engines_burned {
  local all_flamed is True.
  LIST ENGINES in es.
  for e in es {
    if e:stage = stage:number {
      SET all_flamed TO all_flamed and e:flameout.
    }
  }
  return all_flamed.
}

FUNCTION auto_stage {
  if should_stage() {
    set last_cooldown to time:seconds.
    stage.
    PRINT "STAGE " + STAGE:NUMBER + "          " AT (0,0).
  }
}

FUNCTION current_isp {
  LIST ENGINES in es.
  LOCAL mass_isp IS 0.
  LOCAL total_flow IS 0.
  for e in es {
    if e:stage = stage:number and e:isp > 0{
      SET mass_isp TO mass_isp + (e:availableThrust / g0).
      SET total_flow TO total_flow + (e:availableThrust / (e:isp * g0)).
    }
  }
  IF total_flow > 0 {
    RETURN mass_isp / total_flow.
  }
  RETURN 0.

}

FUNCTION current_thrust {
  LIST ENGINES in es.
  LOCAL thrust IS 0.
  for e in es {
    if e:stage = stage:number {
      SET thrust TO thrust + e:availablethrust.
    }

  }
  RETURN thrust.

}




FUNCTION update_telemetry {
  set met to time:seconds - met_start.
}

FUNCTION log_telemetry {
  // run k05_h1000
  LOG "k"+ROUND(shape_k,1)+"_h"+turn_start TO log_file.
  LOG shape_k TO log_file.
  LOG turn_start TO log_file.
  LOG turn_end TO log_file.
  LOG TIME:SECONDS TO log_file.
  LOG met TO log_file.
  LOG ship:altitude TO log_file.
  LOG SHIP:VELOCITY:SURFACE:MAG TO log_file.
  LOG SHIP:velocity:orbit:mag TO log_file.
  LOG SHIP:verticalspeed TO log_file.
  // gamma,
  LOG pitch_at(ship:altitude) TO log_file. // pitch,
  // alpha,
  LOG SHIP:mass TO log_file.
  LOG SHIP:thrust TO log_file.
  LOG SHIP:Q * 101.325 TO log_file. // dynp,
  LOG SHIP:apoapsis TO log_file.
  LOG SHIP:periapsis TO log_file.
  // dvIdeal,
  // lossGrav,
  // lossSteer,
  // lossDrag,
  LOG STAGE:number TO log_file.

}