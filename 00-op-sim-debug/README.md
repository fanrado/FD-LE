# 00 — FD-VD light simulation: workflow and bug fixes

The DUNE far-detector vertical-drift (FD-VD) photon-detector simulation, as used for low-energy (solar, supernova)
physics: how it works, a minimum workflow that runs it, and five bugs in `duneopdet` with proposed fixes.
The bugs were found by Xin Qian
([fdvd_sim doc 08a](https://github.com/WireCell/wcp-porting-validation/blob/main/fdvd_sim/docs/08a_duneopdet-light-simulation-bugs.md)
and doc 30).

- **Tech-note:** [`tech-note/fdvd-light-sim-tech-note.pdf`](tech-note/fdvd-light-sim-tech-note.pdf). Start here: it
  explains the low-energy workflow, every step of the light simulation, and each bug with before/after plots.
- **Code:** [`work/`](work/). Data and builds go to `work/data/`, which is not committed.
- **Background:** the official DUNE low-energy reconstruction (S. Manthey Corchado): job files
  `dunesw/fcl/dunefdvd/reco/solar_reco_dunevd10kt_1x8x14_3view_30deg.fcl`, code in `dunereco/LowEUtils`,
  `duneopdet/LowEPDSUtils` and `duneana/SolarNuAna`. (Sergio's own introduction is kept locally as
  `sergio-introduction.md`, not committed.)

## Quick start

On a `dunegpvm` or `dunebuild` machine (AlmaLinux 9), or any host with `apptainer` and `/cvmfs` (e.g. the BNL
`wcgpu` machines). Every LArSoft command runs inside the Fermilab SL7 container through `work/env/in-sl7.sh`; the
scripts do that themselves. Choose the host with `env/in-sl7.sh --host wcgpu1|dunegpvm` or `SL7_HOST=...` (default:
guessed from the machine name): it sets which host directories the container sees and where its `/tmp` is
(`work/data/tmp` on wcgpu1). `work/data` may be a symlink to a local scratch disk.

```bash
cd work
scripts/run_chain.sh sol 0          # one solar-only event: gen -> g4 -> light detsim -> OpHits   (~2.5 min)
scripts/run_chain.sh mix 0          # one solar + radiological-background event                    (~10 min, 6 GB)
scripts/build_duneopdet.sh          # duneopdet v10_26_00d00 + the fixes, in work/data/opdev       (~2 min)
scripts/run_rerun.sh stock mix 0    # rerun the light simulation of that event: stock build
scripts/run_rerun.sh all   mix 0    #   ... with every fix
scripts/run_all.sh                  # everything in the tech-note: 20+20 events, 8 configurations  (~1.5 h, 12 cores)
python3 analysis/make_plots.py data ../tech-note/figs && ../tech-note/build.sh
```

## Layout

| path | what |
|---|---|
| `work/env/in-sl7.sh` | runs a command in the SL7 container with dunesw `v10_26_00d00` set up: `env/in-sl7.sh [--host wcgpu1\|dunegpvm] <cmd>` (`OPDEV=` adds a local build; scripts pass the host through `SL7_HOST`) |
| `work/fcl/` | light-only detsim and reco job files, and the rerun jobs |
| `work/scripts/run_chain.sh` | the minimum workflow for one event, with fixed seeds |
| `work/scripts/build_duneopdet.sh` | mrb build of duneopdet with `work/patches/duneopdet-light-sim-fixes.patch` |
| `work/scripts/run_rerun.sh` | rerun the light simulation of an event in one of 8 configurations |
| `work/analysis/dump_light.py` | per-event numbers (snippets, OpHits, PE by source, dark counts, ...) -> `light.npz` |
| `work/analysis/make_plots.py` | every figure and number of the tech-note |
| `work/patches/` | `duneopdet-light-sim-fixes.patch`: the tech-note's duneopdet change, the same change as a commit: branch [`fix-light-sim-pileup`](https://github.com/HaiwangYu/duneopdet/tree/fix-light-sim-pileup) of the duneopdet fork. `series`: every patch, each fix with an fcl switch (`scripts/eval_switches.sh`). `series.proposal`: the proposed FD-VD settings |
| `work/scripts/build_eval.sh` | mrb build of dunecore + duneopdet with every patch of `patches/series`, in `work/data/evaldev` |
| `work/scripts/run_fixes.sh` | **start here**: rerun events with the fixes you choose (`--only B,C`, `--all-except A`, `--one-by-one`, `--leave-one-out`, `--dry-run`) |
| `work/scripts/eval_switches.sh` | one section per bug: its `FIX_<ID>=true/false` switch, patch, stage, fcl parameter and page |
| `work/scripts/run_eval.sh`, `run_eval_all.sh` | the engine behind `run_fixes.sh`: one configuration by name (`all`, `all-X`, `none+X`, `none`, `stock`), with stage caching |
| `tech-note/` | LaTeX source, figures, PDF; `tech-note/build.sh` builds it |
