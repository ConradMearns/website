# Lesson Plan — kOS Ascent Guidance

Six arcs, sixteen lessons. Each lesson pairs a kOS mechanic with a derivation you do yourself.

## Arc 1 — Make it fly (1–3)

Lessons: [`arc1-make-it-fly/`](arc1-make-it-fly/)

**1. [Cooked control & the loop](arc1-make-it-fly/kos-01-cooked-control.html).** `LOCK STEERING`, `LOCK THROTTLE`, `WAIT UNTIL`, `HEADING()`. Hardcoded vertical climb, one fixed pitch-over. Math: none — just TWR as a sanity number.

**2. [Pitch as a function of altitude](arc1-make-it-fly/kos-02-pitch-program.html).** Linear interpolation, clamping. You derive: the general lerp form from two points. kOS: `FUNCTION`, `MIN`/`MAX`.

**3. [Staging & the ΔV budget](arc1-make-it-fly/kos-03-staging-deltav.html).** Tsiolkovsky. You derive: burn time from mass flow ṁ = F/(Isp·g₀). This is where autostaging debounce shows up.

## Arc 2 — Measure it (4)

**4. Telemetry logging.** `LOG` to CSV, fixed-rate sampling instead of per-tick, run-tagged headers so files overlay. Columns: UT, alt, srf & orbital speed, mass, thrust, pitch, γ, q, AP/PE. Plus a companion HTML analyzer — drop CSVs in, get overlaid plots. That tool then serves every remaining lesson.

The real payoff: you can't measure gravity loss directly, you integrate it from logged data. Accumulate g·sin γ·dt and drag decel·dt in the loop, and each run ends with an actual ΔV loss breakdown. That's the number that settles arguments — and it's exactly how you'll see the lerp from lesson 2 bleeding steering loss that a prograde-follower doesn't.

## Arc 3 — Make it efficient (5–8)

**5. Where the ΔV actually goes.** Gravity loss ∫g·sin γ dt, drag loss, steering loss — derived properly now that lesson 4 can measure them. You derive: gravity loss for a constant pitch angle, then see why 90° is the worst possible ascent.

**6. The atmosphere.** ρ = ρ₀e^(−h/H), dynamic pressure q = ½ρv². You derive: terminal velocity where D = T − mg.

**7. PID control.** Throttle-limiting to hold a q ceiling. kOS `PIDLOOP` vs rolling your own so you know what's inside it.

**8. Vectors & flight path angle.** `SRFPROGRADE`, `VXCL`, `VANG`. You derive: γ from velocity components. Closed-loop prograde-following gravity turn — steering losses go to ~zero.

## Arc 4 — Make it precise (9–10)

**9. Apoapsis targeting.** Feathering throttle to hold `ETA:AP` constant through the upper atmosphere.

**10. Circularization.** Vis-viva two ways: you derive the ΔV at apoapsis for a target circular orbit, then the node-splitting for burn start time.

## Arc 5 — Make it aimed (11–14)

The arc that makes the whole thing mission-useful.

**11. Launch azimuth.** sin A = cos i / cos φ, then the rotating-frame correction as a vector triangle. You derive the correction. Also: why |i| < |φ| is unreachable from the pad.

**12. Launch windows.** Your latitude circle pierces any target plane twice per sidereal day. You derive: the UT of next node crossing from the plane's LAN and your current longitude. Polar orbits fall straight out of this — a sun-synchronous polar launch is just "what time of day puts KSC under the plane."

**13. Minmus plane matching.** i ≈ 6°, LAN ≈ 78°. Launch directly into it and your ejection burn costs zero plane change. This is the one that saves the most ΔV in an actual campaign.

**14. Rendezvous.** Plane match from #12, then phase angle and a phasing orbit to arrive with the station in reach. Ties into the constellation-slot math.

## Arc 6 — Endgame (15–16)

**15. Linear tangent steering.** Why optimal pitch is tan γ = a − bt, not a lerp — and the logs from Arc 2 show why linear-in-altitude was never right. The bridge to real guidance.

**16. PEG.** Closed-loop, solves for cutoff conditions in flight. The endgame script.
