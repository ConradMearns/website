// plan.ks - Moho ejection planning, read-only
PARAMETER vinf IS 2350.
PARAMETER maxBurn IS 120.

SET vinf TO vinf:TONUMBER(2350).
SET maxBurn TO maxBurn:TONUMBER(120).

RUNONCEPATH("0:/oberth.ks").
RUNONCEPATH("0:/perikick.ks").

OBERTHREPORT(vinf).
PRINT " ".
KICKPLAN(vinf, maxBurn).

