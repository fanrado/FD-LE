#!/usr/bin/env python3
"""Per-run dump for the fix evaluation (PLAN.md section 2): where two configurations differ, and what the OpHits and
flashes are.

usage (inside the SL7 container with dunesw set up, env/in-sl7.sh):
    eval_dump.py <detsim.root> <reco.root> <out.npz>

Written:
  snip      [S,5] int64  per raw::OpDetWaveform (opdigi10ppm): OpChannel, TimeStamp [ns, rounded], samples, max ADC,
                         a 63-bit FNV-1a hash of the samples (to find the snippets two configurations disagree on)
  hits      [H,5]        per recob::OpHit (ophit10ppm), in collection order: OpChannel, PeakTime [us], Width [us],
                         Area [ADC x tick], PE
  <L>_flash [F,3]        per recob::OpFlash of label L (opflash10ppm, solarflash): Time [us], TotalPE, number of OpHits
  <L>_hits  [sum]        indices (into hits) of the OpHits of each flash, flash after flash (art::Assns)
  <L>_missing            present (= 1) if the job did not run flash finder L
  div       [D,6]        per sim::OpDetDivRec row of the four sipm* products: product index, OpDet, time [ns],
                         trackID, PE, 1 if the track is MARLEY's (the neutrino) else 0 (dump_light.py's truth join)
                         (only rows with |time| < 20 us: the neutrino region; dark counts are trackID 0)
  divrows   [4]          number of DivRec rows (time, channel, track) per product, whole event
  btr       [4,184]      photons per OpDet in the four PDFastSim products (PDFastSimAr, PDFastSimXe, PDFastSimArExternal,
                         PDFastSimXeExternal; the latest process's), whole event: 0 = no backtracker record
"""
import sys

import os

import numpy as np
import ROOT

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dump_light import marley_label_function  # noqa: E402

ROOT.gROOT.SetBatch(True)
ROOT.gSystem.Load("libgallery")
for h in ("gallery/Event.h", "lardataobj/RawData/OpDetWaveform.h", "lardataobj/RecoBase/OpHit.h",
          "lardataobj/RecoBase/OpFlash.h", "canvas/Persistency/Common/FindMany.h", "dunecore/DuneObj/OpDetDivRec.h",
          "lardataobj/Simulation/OpDetBacktrackerRecord.h"):
    ROOT.gInterpreter.ProcessLine(f'#include "{h}"')
ROOT.gInterpreter.Declare(r'''
std::vector<long long> ev_snippets(gallery::Event& ev) {
  std::vector<long long> out;
  for (auto const& w : *ev.getValidHandle<std::vector<raw::OpDetWaveform>>(art::InputTag("opdigi10ppm"))) {
    unsigned long long h = 1469598103934665603ULL; long long mx = 0;
    for (auto a : w) { h = (h ^ (unsigned long long)a) * 1099511628211ULL; if (a > mx) mx = a; }
    out.push_back(w.ChannelNumber()); out.push_back(std::llround(w.TimeStamp()*1000.)); out.push_back(w.size());
    out.push_back(mx); out.push_back((long long)(h >> 1));
  }
  return out;
}
std::vector<double> ev_hits(gallery::Event& ev) {
  std::vector<double> out;
  for (auto const& h : *ev.getValidHandle<std::vector<recob::OpHit>>(art::InputTag("ophit10ppm"))) {
    out.push_back(h.OpChannel()); out.push_back(h.PeakTime()); out.push_back(h.Width()); out.push_back(h.Area());
    out.push_back(h.PE());
  }
  return out;
}
// flashes: Time, TotalPE, nhits; then the OpHit indices (key of the art::Ptr) of every flash
std::pair<std::vector<double>, std::vector<int>> ev_flashes(gallery::Event& ev, std::string label) {
  std::pair<std::vector<double>, std::vector<int>> out;
  auto fh = ev.getValidHandle<std::vector<recob::OpFlash>>(art::InputTag(label));
  auto const& hits = *ev.getValidHandle<std::vector<recob::OpHit>>(art::InputTag("ophit10ppm"));
  art::FindMany<recob::OpHit> fm(fh, ev, art::InputTag(label));
  for (size_t i = 0; i < fh->size(); ++i) {
    auto const& v = fm.at(i);
    out.first.push_back((*fh)[i].Time()); out.first.push_back((*fh)[i].TotalPE()); out.first.push_back(v.size());
    for (auto p : v) out.second.push_back(p - &hits[0]);
  }
  return out;
}
// first element: number of rows of the whole product; then 5 numbers per row with |time| <= tmax
std::vector<double> ev_btr(gallery::Event& ev, std::string label) {
  std::vector<double> out(184, 0.);
  for (auto const& r : *ev.getValidHandle<std::vector<sim::OpDetBacktrackerRecord>>(art::InputTag(label)))
    for (auto const& tp : r.timePDclockSDPsMap()) for (auto const& sdp : tp.second)
      if (r.OpDetNum() >= 0 && r.OpDetNum() < 184) out[r.OpDetNum()] += sdp.numPhotons;
  return out;
}
std::vector<double> ev_div(gallery::Event& ev, std::string label, int k, double tmax) {
  std::vector<double> out(1, 0.);
  for (auto const& d : *ev.getValidHandle<std::vector<sim::OpDetDivRec>>(art::InputTag(label)))
    for (auto const& tc : d.GetTimeChans()) {
      out[0] += tc.phots.size();
      if (std::abs(tc.time) > tmax) continue;
      for (auto const& p : tc.phots) {
        out.push_back(k); out.push_back(d.OpDetNum()); out.push_back(tc.time); out.push_back(p.trackID); out.push_back(p.phot);
      }
    }
  return out;
}
''')
DIV = ["sipmAr10ppm", "sipmXe10ppm", "sipmAr10ppmExt", "sipmXe10ppmExt"]


def open_event(f):
    ev = ROOT.gallery.Event(ROOT.std.vector("string")(1, f))
    return ev


def main():
    fdet, freco, fout = sys.argv[1:4]
    R = {}
    ed = open_event(fdet)
    R["snip"] = np.array(ROOT.ev_snippets(ed), dtype=np.int64).reshape(-1, 5)
    divs, rows = [], []
    for k, lab in enumerate(DIV):
        v = np.array(ROOT.ev_div(ed, lab, k, 20000.0))
        rows.append(int(v[0]))
        divs.append(v[1:].reshape(-1, 5))
    div = np.concatenate(divs)
    is_marley = marley_label_function(ed, fdet)
    tid = div[:, 3].astype(np.int64)
    R["div"] = np.column_stack([div, ((tid != 0) & is_marley(tid)).astype(float)]) if len(div) else np.zeros((0, 6))
    R["divrows"] = np.array(rows)
    R["btr"] = np.array([np.array(ROOT.ev_btr(ed, b)) for b in
                         ("PDFastSimAr", "PDFastSimXe", "PDFastSimArExternal", "PDFastSimXeExternal")])
    er = open_event(freco)
    R["hits"] = np.array(ROOT.ev_hits(er)).reshape(-1, 5)
    for lab in ("opflash10ppm", "solarflash"):
        try:
            fl, idx = ROOT.ev_flashes(er, lab)
        except Exception:      # solarflash is not run on mixed events with MinWidth 10 (scripts/run_eval.sh)
            fl, idx, R[f"{lab}_missing"] = [], [], np.array(1)
        R[f"{lab}_flash"] = np.array(fl).reshape(-1, 3)
        R[f"{lab}_hits"] = np.array(idx, dtype=np.int64)
    np.savez_compressed(fout, **R)
    print(f"{len(R['snip'])} snippets, {len(R['hits'])} OpHits, "
          f"{len(R['opflash10ppm_flash'])} opflash10ppm / {len(R['solarflash_flash'])} solarflash flashes, "
          f"DivRec rows {rows}")


if __name__ == "__main__":
    main()
