// go.ks - driver
PARAMETER cmd IS "".
PARAMETER a IS "".
PARAMETER b IS "".
PARAMETER c IS "".
PARAMETER d IS "".

IF EXISTS("0:/log.ks")     { RUNONCEPATH("0:/log.ks"). }
IF EXISTS("0:/plotlib.ks") { RUNONCEPATH("0:/plotlib.ks"). }
IF EXISTS("0:/vectors.ks") { RUNONCEPATH("0:/vectors.ks"). }
IF EXISTS("0:/circ.ks")    { RUNONCEPATH("0:/circ.ks"). }
IF EXISTS("0:/exec.ks")    { RUNONCEPATH("0:/exec.ks"). }

IF cmd = "rec"         { FLRECORD(a). }
ELSE IF cmd = "list"   { FLLIST(). }
ELSE IF cmd = "budget" { BUDGET(a). }
ELSE IF cmd = "plot"   { PLOT(a, b, c). }
ELSE IF cmd = "plot2"  { PLOT2(a, b, c, d). }
ELSE IF cmd = "ghost"  { GHOST(a). }
ELSE IF cmd = "circ"   { CIRCNODE("ap"). }
ELSE IF cmd = "circpe" { CIRCNODE("pe"). }
ELSE IF cmd = "exec"   { EXECNODE(). }
ELSE IF cmd = "clear"  { CLEARNODES(). }
ELSE {
    PRINT "rec list budget plot plot2 ghost circ circpe exec clear".
}
