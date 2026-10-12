# The fix switches: one section per bug.  Sourced by scripts/run_fixes.sh, run_eval.sh and run_eval_all.sh.
#
# HOW A FIX IS TURNED ON OR OFF
#
#   1. The patch (once, at build time).  scripts/build_eval.sh applies every patch of patches/series to clean clones
#      of dunecore and duneopdet and compiles them into $DATA_DIR/evaldev.  A patch adds the corrected code AND keeps the
#      old (buggy) code, behind a new fcl parameter.  Nothing is decided yet at this point.
#
#   2. The switch (every job, at run time).  Each section below has a boolean
#
#          FIX_<ID>=true      the fix is ON:  the job gets the fcl lines of the corrected behaviour
#          FIX_<ID>=false     the fix is OFF: the job gets the fcl lines of the legacy (buggy) behaviour
#
#      and a function fcl_<ID> that prints those fcl lines.  scripts/run_eval.sh writes them at the end of the job fcl
#      of the stage they belong to (g4, det or reco), so they override the defaults.  The lines are written for
#      every bug, on or off, so the result never depends on the defaults of the patch.
#
#   So a fix is on in a run if and only if FIX_<ID> was true for that run.  Every run writes its list in
#   $DATA_DIR/eval/run/<config>/<s>/evt<i>/stages_<config>.txt  ("on B C D ...") and the exact fcl lines in the
#   det/detsim.fcl, reco/reco.fcl, g4/g4a.fcl, g4/g4b.fcl of its cache directories (paths in the same file).
#
#   Some bugs need no patch: the parameter exists in the stock code and only its value is wrong (N4, N7.1, N7.2, F,
#   N5).  For those the switch is the corrected value itself.
#
# HOW TO CHANGE THEM
#
#   - edit the FIX_<ID>= line of a section below (the value used when nothing else is given), or
#   - set it for one command:          FIX_A=false scripts/run_fixes.sh sol:0
#   - or use the options of scripts/run_fixes.sh (--only, --all-except, --one-by-one, ...).
#   scripts/run_fixes.sh --dry-run sol:0   prints the table of all bugs, ON/OFF, and the fcl lines, without running.
#
# The stages, in the order of the simulation:
#   g4    G4 light (PDFastSim), rerun only when N4, N71 or N72 is on:   N4  N71  N72
#   det   light detsim (SIPMOpSensorSim, WaveformDigitizerSim):          B  C  D  E  N1  N2  N3  N6
#   reco  OpHits and flashes (ophit10ppm, opflash10ppm):                 F  N5  A
#
# The bug ids keep the names of the cache directories: N71 = bug N7.1, N72 = bug N7.2.  The pages are docs/bug<ID>.md;
# docs/SUMMARY.md explains every bug in plain words.

G4_IDS="N4 N71 N72"
DET_IDS="B C D E N1 N2 N3 N6"
RECO_IDS="F N5 A"
ALL_IDS="$G4_IDS $DET_IDS $RECO_IDS"

SIPM_MODULES="sipmAr10ppm sipmXe10ppm sipmAr10ppmExt sipmXe10ppmExt"     # the 4 SIPMOpSensorSim instances of FD-VD


# ======================================================================================================================
#   G4 LIGHT STAGE   (Geant4 stage 1: argon light, PDFastSimAr;  stage 2: xenon light, PDFastSimXe)
# ======================================================================================================================


# ----------------------------------------------------------------------------------------------------------------------
# Bug N4 -- the leftover argon light glows too long
# ----------------------------------------------------------------------------------------------------------------------
#   bug      the argon triplet light that survives the xenon doping decays with 1600 ns, the time of pure argon.
#            With 10 ppm xenon it should be 1/(1/1600 + 10/7320) = 502 ns.
#   effect   argon PE within 1 us of the interaction: 50% (bug) -> 68% (fixed)
#   stage    g4  (modules PDFastSimAr, PDFastSimArExternal)
#   patch    none: the parameter exists, its value is the fix
#   switch   ScintTimeTool.SlowDecayTime     1600 (bug)  ->  502.23 (fixed)
#   page     docs/bugN4.md

FIX_N4=${FIX_N4:-true}

TITLE_N4="leftover argon light decays in 1.6 us instead of 0.5 us"
STAGE_N4=g4
PATCH_N4="(none, fcl value)"

fcl_N4() {
  local decay_time=1600
  [ "$FIX_N4" = true ] && decay_time=502.23

  cat <<EOF
physics.producers.PDFastSimAr.ScintTimeTool.SlowDecayTime: $decay_time
physics.producers.PDFastSimArExternal.ScintTimeTool.SlowDecayTime: $decay_time
EOF
}


# ----------------------------------------------------------------------------------------------------------------------
# Bug N7.1 (id N71) -- argon light stops at 10 m
# ----------------------------------------------------------------------------------------------------------------------
#   bug      PDFastSimAr does not deliver argon light to photon detectors more than 10 m from the energy deposit.
#   effect   +1.5% argon photons when fixed
#   stage    g4  (module PDFastSimAr)
#   patch    none: the parameter exists, its value is the fix
#   switch   VUVHits.MaxPDDistance           1000 (bug)  ->  2500 (fixed)   [cm]
#   page     docs/bugN7.md, section 4

FIX_N71=${FIX_N71:-true}

TITLE_N71="argon light not delivered beyond 10 m"
STAGE_N71=g4
PATCH_N71="(none, fcl value)"

fcl_N71() {
  local max_distance=1000
  [ "$FIX_N71" = true ] && max_distance=2500

  cat <<EOF
physics.producers.PDFastSimAr.VUVHits.MaxPDDistance: $max_distance
EOF
}


# ----------------------------------------------------------------------------------------------------------------------
# Bug N7.2 (id N72) -- buffer xenon light at the argon speed
# ----------------------------------------------------------------------------------------------------------------------
#   bug      the xenon light from outside the field cage uses the argon timing parameterisation: ~13 ns late.
#   effect   invisible at the waveform level
#   stage    g4  (module PDFastSimXeExternal, Geant4 stage 2)
#   patch    none: the parameter exists, its value is the fix
#   switch   VUVTiming                       (stock argon table, no line written)  ->  @local::dunevd_xe_timing_geo
#   page     docs/bugN7.md, section 5

FIX_N72=${FIX_N72:-true}

TITLE_N72="buffer xenon light uses the argon timing (13 ns late)"
STAGE_N72=g4
PATCH_N72="(none, fcl value)"

fcl_N72() {
  [ "$FIX_N72" = true ] || return 0          # off: keep the stock value, write nothing

  cat <<EOF
physics.producers.PDFastSimXeExternal.VUVTiming: @local::dunevd_xe_timing_geo
EOF
}


# ======================================================================================================================
#   DETSIM STAGE   (SIPMOpSensorSim: photons -> PE;  WaveformDigitizerSim: PE -> digitised snippets)
# ======================================================================================================================


# ----------------------------------------------------------------------------------------------------------------------
# Bug B -- a pulse is stored twice
# ----------------------------------------------------------------------------------------------------------------------
#   bug      when light piles up, the digitizer's readout ranges overlap and the same samples are stored twice.
#   effect   mixed events: 16% of stored samples stored twice -> 0
#   stage    det  (module opdigi10ppm = WaveformDigitizerSim)
#   patch    duneopdet-light-sim-fixes.patch
#   switch   MergeOverlappingRanges          false (bug)  ->  true (fixed)
#   page     docs/bugB.md

FIX_B=${FIX_B:-true}

TITLE_B="pulses stored twice when light piles up"
STAGE_B=det
PATCH_B="duneopdet-light-sim-fixes.patch"

fcl_B() {
  cat <<EOF
physics.producers.opdigi10ppm.MergeOverlappingRanges: $FIX_B
EOF
}


# ----------------------------------------------------------------------------------------------------------------------
# Bug C -- the late-light clock starts at the wrong time
# ----------------------------------------------------------------------------------------------------------------------
#   bug      the argon light that comes "late" is reduced, but "late" is counted from the first photon of the whole
#            event on that detector, not of the same particle: with pile-up, the neutrino's prompt light is dimmed.
#   effect   mixed events: neutrino argon PE 270 -> 431
#   stage    det  (modules sipmAr10ppm, sipmAr10ppmExt = SIPMOpSensorSim, argon light only)
#   patch    duneopdet-light-sim-fixes.patch
#   switch   LateLightReference              "Event" (bug)  ->  "Track" (fixed)
#   page     docs/bugC.md

FIX_C=${FIX_C:-true}

TITLE_C="late-light clock starts at the first photon of the event"
STAGE_C=det
PATCH_C="duneopdet-light-sim-fixes.patch"

fcl_C() {
  local reference=Event
  [ "$FIX_C" = true ] && reference=Track

  cat <<EOF
physics.producers.sipmAr10ppm.LateLightReference: "$reference"
physics.producers.sipmAr10ppmExt.LateLightReference: "$reference"
EOF
}


# ----------------------------------------------------------------------------------------------------------------------
# Bug D -- dark counts all land on the neutrino
# ----------------------------------------------------------------------------------------------------------------------
#   bug      dark-count times are drawn in us but stored as ns, so all of them fall within a few us of t = 0.
#   effect   245 dark PE within 5 us of the neutrino -> 0
#   stage    det  (the 4 SIPMOpSensorSim modules)
#   patch    duneopdet-light-sim-fixes.patch
#   switch   DarkNoiseTimeInNs               false (bug)  ->  true (fixed)
#   page     docs/bugD.md

FIX_D=${FIX_D:-true}

TITLE_D="dark-count times in us stored as ns"
STAGE_D=det
PATCH_D="duneopdet-light-sim-fixes.patch"

fcl_D() {
  local module
  for module in $SIPM_MODULES; do
    printf 'physics.producers.%s.DarkNoiseTimeInNs: %s\n' $module $FIX_D
  done
}


# ----------------------------------------------------------------------------------------------------------------------
# Bug E -- a snippet time of 9,000 years, and fake hits
# ----------------------------------------------------------------------------------------------------------------------
#   bug      a snippet triggered in the first ticks of the readout window gets a start before tick 0, which wraps
#            around (unsigned integer): time ~3e17 us, and samples read from outside the waveform.
#   effect   28 such snippets, OpHits of 2,790 PE at that time -> 0
#   stage    det  (module opdigi10ppm = WaveformDigitizerSim)
#   patch    duneopdet-snippet-clamp-switch.patch  (the clamp itself is in duneopdet-light-sim-fixes.patch)
#   switch   ClampSnippetStart               false (bug)  ->  true (fixed)
#   page     docs/bugE.md

FIX_E=${FIX_E:-true}

TITLE_E="snippet start wraps around: 9,352 years, fake OpHits"
STAGE_E=det
PATCH_E="duneopdet-snippet-clamp-switch.patch"

fcl_E() {
  cat <<EOF
physics.producers.opdigi10ppm.ClampSnippetStart: $FIX_E
EOF
}


# ----------------------------------------------------------------------------------------------------------------------
# Bug N1 -- detection is randomized twice
# ----------------------------------------------------------------------------------------------------------------------
#   bug      PDFastSim already draws a Poisson number of photons; the sensor then draws Poisson(QE * n) again, so
#            the PE count fluctuates too much.  Fixed: Binomial(n, QE).
#   effect   probability of 0 PE for 1 photon: 68.9% -> 62.7%
#   stage    det  (the 4 SIPMOpSensorSim modules)
#   patch    duneopdet-light-sim-fixes.patch
#   switch   BinomialQE                      false (bug)  ->  true (fixed)
#   note     changes the number of random draws: later PE are drawn differently (same statistics, not bit for bit)
#   page     docs/bugN1.md

FIX_N1=${FIX_N1:-true}

TITLE_N1="detection randomized twice (Poisson on Poisson)"
STAGE_N1=det
PATCH_N1="duneopdet-light-sim-fixes.patch"

fcl_N1() {
  local module
  for module in $SIPM_MODULES; do
    printf 'physics.producers.%s.BinomialQE: %s\n' $module $FIX_N1
  done
}


# ----------------------------------------------------------------------------------------------------------------------
# Bug N2 -- dark counts only where there is light, and up to four times
# ----------------------------------------------------------------------------------------------------------------------
#   bug      each of the 4 sensor modules adds dark noise, but only on the detectors it has photons for: dark
#            counts are missing on dark detectors and counted up to 4 times on lit ones.
#   effect   mixed events: 239 -> 49 dark PE
#   stage    det  (the 4 SIPMOpSensorSim modules)
#   patch    duneopdet-darknoise-allopdets.patch
#   switch   off (bug):  DarkNoiseAllOpDets false in all 4 modules (the stock 10 Hz rate in each)
#            on (fixed): DarkNoiseAllOpDets true in sipmXe10ppm only, DarkNoiseRate 0 in the other 3
#   note     changes the number of random draws (as N1)
#   page     docs/bugN2.md

FIX_N2=${FIX_N2:-true}

TITLE_N2="dark counts only on lit detectors, up to 4 times"
STAGE_N2=det
PATCH_N2="duneopdet-darknoise-allopdets.patch"

fcl_N2() {
  local module
  for module in $SIPM_MODULES; do
    printf 'physics.producers.%s.DarkNoiseAllOpDets: false\n' $module
  done

  [ "$FIX_N2" = true ] || return 0

  # 10 Hz once per detector, on all detectors: in one module only
  printf 'physics.producers.sipmXe10ppm.DarkNoiseAllOpDets: true\n'
  for module in sipmAr10ppm sipmAr10ppmExt sipmXe10ppmExt; do
    printf 'physics.producers.%s.DarkNoiseRate: 0\n' $module
  done
}


# ----------------------------------------------------------------------------------------------------------------------
# Bug N3 -- PE credited to the wrong particle (truth only)
# ----------------------------------------------------------------------------------------------------------------------
#   bug      sim::OpDetDivRec::AddPhoton credits a PE to the first particle already recorded at that time.
#   effect   waveforms identical; the truth record gets 1,605 more rows, each on the right particle
#   stage    det  (the 4 SIPMOpSensorSim modules)
#   patch    dunecore-opdetdivrec.patch  +  duneopdet-divrec-pertrack.patch   (both needed)
#   switch   DivRecPerTrack                  false (bug)  ->  true (fixed)
#   page     docs/bugN3.md

FIX_N3=${FIX_N3:-true}

TITLE_N3="PE credited to the wrong particle (truth only)"
STAGE_N3=det
PATCH_N3="dunecore-opdetdivrec.patch + duneopdet-divrec-pertrack.patch"

fcl_N3() {
  local module
  for module in $SIPM_MODULES; do
    printf 'physics.producers.%s.DivRecPerTrack: %s\n' $module $FIX_N3
  done
}


# ----------------------------------------------------------------------------------------------------------------------
# Bug N6 -- consecutive snippets repeat a few samples
# ----------------------------------------------------------------------------------------------------------------------
#   bug      a trigger shortly after a snippet closed starts its pre-trigger inside that snippet: up to 20 samples
#            are stored twice.
#   effect   0.08% of samples -> 0
#   stage    det  (module opdigi10ppm = WaveformDigitizerSim)
#   patch    duneopdet-snippet-overlap.patch
#   switch   SnippetStartAfterPrevious       false (bug)  ->  true (fixed)
#   note     optional: the real DAPHNE behaviour is not known, so the patch's default is false
#   page     docs/bugN6.md

FIX_N6=${FIX_N6:-true}

TITLE_N6="consecutive snippets repeat up to 20 samples"
STAGE_N6=det
PATCH_N6="duneopdet-snippet-overlap.patch"

fcl_N6() {
  cat <<EOF
physics.producers.opdigi10ppm.SnippetStartAfterPrevious: $FIX_N6
EOF
}


# ======================================================================================================================
#   RECO STAGE   (ophit10ppm: snippets -> OpHits;  opflash10ppm: OpHits -> flashes)
# ======================================================================================================================


# ----------------------------------------------------------------------------------------------------------------------
# Bug F -- the OpHit finder throws away most small pulses
# ----------------------------------------------------------------------------------------------------------------------
#   bug      MinWidth 60 ticks is longer than a single-PE pulse, so most small pulses give no OpHit.
#   effect   OpHits report 31% -> 60% of the neutrino light
#   stage    reco  (module ophit10ppm)
#   patch    none: the parameter exists, its value is the fix
#   switch   HitAlgoPset.MinWidth            60 (bug)  ->  10 (fixed)
#   note     with F on, a mixed event has ~167k OpHits and SolarOpFlash takes ~1 hour: run_eval.sh skips solarflash
#            there (SOLARFLASH=1 runs it anyway)
#   page     docs/bugF.md

FIX_F=${FIX_F:-true}

TITLE_F="OpHit finder MinWidth 60 drops most small pulses"
STAGE_F=reco
PATCH_F="(none, fcl value)"

fcl_F() {
  local min_width=60
  [ "$FIX_F" = true ] && min_width=10

  cat <<EOF
physics.producers.ophit10ppm.HitAlgoPset.MinWidth: $min_width
EOF
}


# ----------------------------------------------------------------------------------------------------------------------
# Bug N5 -- every OpHit gets extra PE
# ----------------------------------------------------------------------------------------------------------------------
#   bug      the OpHit PE calibration (area of one PE, and the shift) does not match the simulated pulse.
#   effect   OpHit PE +6.6% -> 0
#   stage    reco  (module ophit10ppm)
#   patch    none: the parameters exist, their values are the fix
#   switch   SPEArea                         130 (bug)   ->  132.6 (fixed)
#            SPEShift                        0.43 (bug)  ->  0.24 (fixed), ONLY IF F IS ALSO ON
#   note     depends on F: 0.24 is the shift for MinWidth 10.  For MinWidth 60 the right shift is not defined
#            (docs/bugN5.md section 5), so with F off, N5 changes SPEArea only.
#   page     docs/bugN5.md

FIX_N5=${FIX_N5:-true}

TITLE_N5="OpHit PE calibration too high"
STAGE_N5=reco
PATCH_N5="(none, fcl value)"

fcl_N5() {
  local spe_area=130
  local spe_shift=0.43
  [ "$FIX_N5" = true ]                         && spe_area=132.6
  [ "$FIX_N5" = true ] && [ "$FIX_F" = true ]  && spe_shift=0.24

  cat <<EOF
physics.producers.ophit10ppm.SPEArea: $spe_area
physics.producers.ophit10ppm.SPEShift: $spe_shift
EOF
}


# ----------------------------------------------------------------------------------------------------------------------
# Bug A -- flashes list the wrong OpHits
# ----------------------------------------------------------------------------------------------------------------------
#   bug      the FD-VD flash finder stores the positions of OpHits in its time-sorted list instead of their
#            indices, so each flash points to the wrong OpHits.
#   effect   flashes spanning > 100 us: 100% -> 0%; neutrino flash PE (6 events) 868 -> 1687
#   stage    reco  (module opflash10ppm = OpFlashFinderVerticalDrift)
#   patch    duneopdet-opflash-index.patch
#   switch   StoreHitIndices                 false (bug)  ->  true (fixed)
#   page     docs/bugA.md

FIX_A=${FIX_A:-true}

TITLE_A="flashes made of the wrong OpHits"
STAGE_A=reco
PATCH_A="duneopdet-opflash-index.patch"

fcl_A() {
  cat <<EOF
physics.producers.opflash10ppm.StoreHitIndices: $FIX_A
EOF
}


# ======================================================================================================================
#   PATCHED BUT NOT SWITCHED IN THESE RUNS
# ======================================================================================================================
#
# Bug N7.6 -- FlashMatchAna reads per-OpDet PE as per-channel
#   patch    duneopdet-flashmatchana.patch;  parameter PEsPerOpDet (default true = fixed)
#   why not  FlashMatchAna is an analysis module that the evaluation chain does not run
#   page     docs/bugN7.md, section 9
#
# No output change, so no switch:
#   duneopdet-fcl-cosmetic.patch    an instance name no job uses (N7 item 3), comments (N7 item 5, N1), Pedestal
#   the GetFracs || -> && of dunecore-opdetdivrec.patch: functions nothing calls (docs/bugN3.md section 7)


# ======================================================================================================================
#   HELPERS used by the run scripts
# ======================================================================================================================

# fix_is_on <id>           true if FIX_<id> is true
fix_is_on() {
  local variable=FIX_$1
  [ "${!variable}" = true ]
}

# check_fixes              every FIX_<id> must be exactly true or false
check_fixes() {
  local id variable
  for id in $ALL_IDS; do
    variable=FIX_$id
    case "${!variable}" in
      true|false) ;;
      *) printf '%s must be true or false, not "%s"\n' $variable "${!variable}" >&2; return 2 ;;
    esac
  done
}

# set_all_fixes <true|false>
set_all_fixes() {
  local id
  for id in $ALL_IDS; do
    printf -v FIX_$id '%s' "$1"
  done
}

# fixes_on [<id> ...]      the ids among the given ones (default: all) whose fix is on
fixes_on() {
  local id list=""
  for id in ${@:-$ALL_IDS}; do
    fix_is_on $id && list="$list $id"
  done
  printf '%s\n' "${list# }"
}

# fcl_lines <id> [<id> ...]     the fcl lines of these fixes, on or off as set
fcl_lines() {
  local id
  for id in "$@"; do
    fcl_$id
  done
}

# print_fix_table          one line per bug: id, ON/OFF, stage, title, patch
print_fix_table() {
  local id state title stage patch
  printf '  %-4s %-4s %-5s %-58s %s\n' id fix stage bug patch
  for id in $ALL_IDS; do
    title=TITLE_$id; stage=STAGE_$id; patch=PATCH_$id
    state=OFF
    fix_is_on $id && state=ON
    printf '  %-4s %-4s %-5s %-58s %s\n' $id $state ${!stage} "${!title}" "${!patch}"
  done
}
