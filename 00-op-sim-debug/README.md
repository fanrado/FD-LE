# 00 — FD-VD light simulation: workflow and bug fixes

The DUNE far-detector vertical-drift (FD-VD) photon-detector simulation, as used for low-energy (solar, supernova)
physics: how it works, a minimum workflow that runs it, and five bugs in `duneopdet` with proposed fixes.
The bugs were found by Xin Qian
([fdvd_sim doc 08a](https://github.com/WireCell/wcp-porting-validation/blob/main/fdvd_sim/docs/08a_duneopdet-light-simulation-bugs.md)
and doc 30).

- **Tech-note:** [`tech-note/fdvd-light-sim-tech-note.pdf`](tech-note/fdvd-light-sim-tech-note.pdf). Start here: it
  explains the low-energy workflow, every step of the light simulation, and each bug with before/after plots.
- **All bugs in short:** [`docs/SUMMARY.md`](docs/SUMMARY.md). Each bug in plain words, with a waveform picture and
  what its fix changes, measured on 6 events with every fix switchable on and off.
- **Plan of the patches and their evaluation:** [`PLAN.md`](PLAN.md).
- **Notebook, every bug before and after its fix:** [`notebooks/fdvd_light_bugs.ipynb`](notebooks/fdvd_light_bugs.ipynb).
  Waveforms, histograms, numbers and the effect on charge-light matching, executed. Rebuild:
  `python3 work/analysis/make_bug_notebook.py`, then `jupyter nbconvert --execute --inplace`.
- **ROOT macro for the reconstructed files:** [`work/analysis/eval_reco.C`](work/analysis/eval_reco.C). It reads the
  OpHits, flashes, waveforms and truth of every configuration and does the charge-light matching (a truth-based proxy
  of `SolarNuAna`). Output: TTrees `evt`, `flash`, `ophit` and a before/after table. Run it in the container:
  `env/in-sl7.sh root -l -b -q 'analysis/eval_reco.C("data/eval/run", "", "data/eval/eval_reco.root")'`.
- **Bug B in detail:** [`docs/bugB.md`](docs/bugB.md): overlapping focus ranges in `WaveformDigitizerSim`, from the
  stock code to the fix, on toy and real waveforms.
- **The other bugs in detail:** [`docs/bugC.md`](docs/bugC.md) (late-light reference),
  [`docs/bugD.md`](docs/bugD.md) (dark-count times), [`docs/bugE.md`](docs/bugE.md) (snippet start wraps around),
  [`docs/bugF.md`](docs/bugF.md) (issue F: the OpHit finder settings drop most of the light; not fixed by the patch).
- **Further items of Xin Qian's doc 30 (FD-VD):** [`docs/bugA.md`](docs/bugA.md) (flash finder builds flashes from the
  wrong OpHits), [`docs/bugN1.md`](docs/bugN1.md) (Poisson-on-Poisson detection),
  [`docs/bugN2.md`](docs/bugN2.md) (dark counts only on lit OpDets, 4 times),
  [`docs/bugN3.md`](docs/bugN3.md) (`OpDetDivRec` track attribution), [`docs/bugN4.md`](docs/bugN4.md) (residual Ar
  light keeps the 1.6 µs constant), [`docs/bugN5.md`](docs/bugN5.md) (OpHit PE calibration +0.43),
  [`docs/bugN6.md`](docs/bugN6.md) (snippets overlap by up to 20 samples), [`docs/bugN7.md`](docs/bugN7.md)
  (configuration inconsistencies, and the `FlashMatchAna` OpDet/channel index bug).
- **Code:** [`work/`](work/). Data and builds go to `DATA_DIR`, written at the top of each script.
- **Background:** the official DUNE low-energy reconstruction (S. Manthey Corchado): job files
  `dunesw/fcl/dunefdvd/reco/solar_reco_dunevd10kt_1x8x14_3view_30deg.fcl`, code in `dunereco/LowEUtils`,
  `duneopdet/LowEPDSUtils` and `duneana/SolarNuAna`. (Sergio's own introduction is kept locally as
  `sergio-introduction.md`, not committed.)

## Quick start

On a `dunegpvm` or `dunebuild` machine (AlmaLinux 9), or any host with `apptainer` and `/cvmfs` (e.g. the BNL
`wcgpu` machines). Every LArSoft command runs inside the Fermilab SL7 container through `work/env/in-sl7.sh`; the
scripts do that themselves. Choose the host with `env/in-sl7.sh --host wcgpu1|dunegpvm` or `SL7_HOST=...` (default:
guessed from the machine name): it sets which host directories the container sees. `env/in-sl7.sh` with no command
opens a shell in the container.

**First, once per machine:** write the absolute path of the data directory (created if missing) in the `DATA_DIR=` line
below `WORK_DIR` at the top of `env/in-sl7.sh` and of each script in `scripts/`; all at once:
`sed -i 's|^DATA_DIR=[^ ]*|DATA_DIR=/your/path|' env/in-sl7.sh scripts/*.sh`. In `env/in-sl7.sh` also set
`CONTAINER_TMP_DIR` (the container's `/tmp`; empty = host `/tmp`, too small on wcgpu1), and in
`scripts/build_duneopdet.sh` `SOURCE_DIR`, where the git clone of duneopdet is saved.

```bash
cd work
scripts/run_chain.sh sol 0          # one solar-only event: gen -> g4 -> light detsim -> OpHits   (~2.5 min)
scripts/run_chain.sh mix 0          # one solar + radiological-background event                    (~10 min, 6 GB)
scripts/run_chain.sh bkg 0          # one radiological-background-only event (no MARLEY)
scripts/build_duneopdet.sh          # duneopdet v10_26_00d00 + the fixes, in $DATA_DIR/opdev        (~2 min)
scripts/run_rerun.sh stock mix 0    # rerun the light simulation of that event: stock build
scripts/run_rerun.sh all   mix 0    #   ... with every fix
scripts/run_all.sh                  # everything in the tech-note: 20+20 events, 8 configurations  (~1.5 h, 12 cores)
python3 analysis/make_plots.py $DATA_DIR ../tech-note/figs && ../tech-note/build.sh
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
| `work/scripts/build_eval.sh` | mrb build of dunecore + duneopdet with every patch of `patches/series`, in `$DATA_DIR/evaldev` |
| `work/scripts/run_fixes.sh` | **start here**: rerun events with the fixes you choose (`--only B,C`, `--all-except A`, `--one-by-one`, `--leave-one-out`, `--dry-run`) |
| `work/scripts/eval_switches.sh` | one section per bug: its `FIX_<ID>=true/false` switch, patch, stage, fcl parameter and page |
| `work/scripts/run_eval.sh`, `run_eval_all.sh` | the engine behind `run_fixes.sh`: one configuration by name (`all`, `all-X`, `none+X`, `none`, `stock`), with stage caching |
| `work/analysis/eval_*.py` | dumps, the stock/none gate (`eval_compare.py`), and the figures and numbers of `docs/SUMMARY.md` (`eval_doc.py`) |
| `tech-note/` | LaTeX source, figures, PDF; `tech-note/build.sh` builds it |
