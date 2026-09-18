#!/usr/bin/env python3
"""Repeatable mapped-netlist M1 development campaign; no source RTL hints.

Evaluator-only directory contains raw netlists/mappings. Each recovery worker
is invoked solely with anonymous JSON. No claim of LLM gain or held-out data.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from harness.ir import SourceGraph, save_json

ROOT=Path(__file__).resolve().parents[1]
DEFAULTS=[('counter','examples/counter/counter_netlist.v'),
          ('traffic','examples/traffic_fsm/traffic_netlist.v'),
          ('alu8','examples/complex/alu8_netlist.v'),
          ('fifo','examples/complex/fifo_netlist.v'),
          ('uart_tx','examples/complex/uart_tx_netlist.v')]


def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--seeds',nargs='+',type=int,default=[17,42,99]);ap.add_argument('--final-budget',type=float,default=60)
    ap.add_argument('--design',action='append',help='top:path; default existing five development netlists')
    args=ap.parse_args(); out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    yosys=os.environ.get('YOSYS') or shutil.which('yosys')
    if not yosys: raise SystemExit('Set YOSYS or install yosys on PATH')
    designs=[tuple(x.split(':',1)) for x in args.design] if args.design else DEFAULTS
    reports=[];started=time.monotonic()
    version=subprocess.run([yosys,'-V'],capture_output=True,text=True,check=True).stdout.strip()
    for index,(top,relative) in enumerate(designs):
        private=out/'evaluator_only'/f'd{index}'; private.mkdir(parents=True,exist_ok=True)
        source=Path(relative);source=source if source.is_absolute() else ROOT/source
        shutil.copyfile(source,private/'input.v')
        if not __import__('re').fullmatch(r'[A-Za-z_][A-Za-z0-9_$]*',top): raise ValueError('invalid top identifier')
        script=f'read_verilog input.v; hierarchy -check -top {top}; proc; flatten; check -assert; write_json input.json\n'
        (private/'import.ys').write_text(script)
        proc=subprocess.run([yosys,'-s','import.ys'],cwd=private,capture_output=True,text=True,timeout=60)
        (private/'import.log').write_text(proc.stdout+proc.stderr)
        if proc.returncode:
            reports.append({'design_index':index,'status':'import_error','returncode':proc.returncode});continue
        graph=SourceGraph.from_yosys_json(json.loads((private/'input.json').read_text()),top)
        save_json(private/'source_manifest.json',{'input_path':str(source),'input_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'yosys':version,'source':graph.manifest()})
        for seed in args.seeds:
            admission_errors=graph.validate()
            if admission_errors:
                reports.append({'design_index':index,'seed':seed,'status':'unsupported','admission_stage':'source',
                                'whole_design_proven':False,'reasons':admission_errors})
                print(json.dumps(reports[-1]),flush=True)
                save_json(out/'campaign.json',{'schema':'m1-campaign/2','track':'development_only','yosys':version,'reports':reports,'elapsed_s':time.monotonic()-started})
                continue
            public,mapping=graph.anonymize(seed=seed,hide_ports=True)
            save_json(private/f'mapping_{seed}.json',mapping)
            task=out/'anonymous_runs'/f'd{index}_s{seed}';task.mkdir(parents=True,exist_ok=True)
            save_json(task/'anonymous.json',public)
            command=[sys.executable,'-m','harness.cli','recover',str(task/'anonymous.json'),'--out',str(task/'run'),'--final-budget',str(args.final_budget)]
            try:
                proc=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=args.final_budget*4+180)
                (task/'worker.log').write_text(proc.stdout+proc.stderr)
                path=task/'run/report.json'
                report=json.loads(path.read_text()) if path.exists() else {'status':'worker_error','whole_design_proven':False,'reason':proc.stderr[-2000:]}
                if proc.returncode and report.get('whole_design_proven'):
                    report={'status':'worker_error','whole_design_proven':False,'reason':'worker exited unsuccessfully despite a saved success report'}
                reports.append({'design_index':index,'seed':seed,'worker_returncode':proc.returncode,**report})
            except subprocess.TimeoutExpired:
                reports.append({'design_index':index,'seed':seed,'status':'worker_timeout','whole_design_proven':False})
            print(json.dumps({k:reports[-1].get(k) for k in ('design_index','seed','status','candidate_count','accepted_candidates','replaced_cells','retained_source_cells') }),flush=True)
            save_json(out/'campaign.json',{'schema':'m1-campaign/2','track':'development_only','yosys':version,'reports':reports,'elapsed_s':time.monotonic()-started})
    save_json(out/'campaign.json',{'schema':'m1-campaign/2','track':'development_only','yosys':version,'reports':reports,'elapsed_s':time.monotonic()-started})
    return 0 if reports and all(x.get('whole_design_proven') for x in reports) else 1

if __name__=='__main__':raise SystemExit(main())
