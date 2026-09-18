#!/usr/bin/env python3
"""Run all acceptance tests on one hash-bound repaired artifact, with hard timeouts."""
import argparse,hashlib,json,os,pathlib,re,signal,subprocess,sys,time
ap=argparse.ArgumentParser();ap.add_argument('--root',type=pathlib.Path,required=True);ap.add_argument('--out',default='regression_replay');args=ap.parse_args();root=args.root.resolve();out=root/args.out
if out.exists():raise SystemExit('Refusing to overwrite '+str(out))
out.mkdir();iv=os.environ.get('IVERILOG','iverilog');vvp=os.environ.get('VVP','vvp');results={};start=time.time()
sha=lambda p:hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
report=json.loads((root/'mul_repair_report.json').read_text())
for name,digest in report['sha256'].items():
 if sha(root/name)!=digest:raise SystemExit('artifact changed: '+name)
subprocess.run([sys.executable,str(pathlib.Path(__file__).with_name('gen_source_internal.py')) ,str(root)],check=True)
for label,tb,top,seconds in [('directed','tb_directed_internal.v','tb_directed_internal',120),('ports_50k','tb_eq_big.v','tb_eq_big',300),('internal','tb_source_internal.v','tb_source_internal',120)]:
 binary=out/('sim_'+label);args_compile=[iv,'-g2012','-s',top,'-o',str(binary),str(root/tb),str(root/'pico_big_netlist.v'),str(root/'pico_big_lift_mul_repaired.v'),str(root/'cells_init.v')]
 for phase,cmd,limit in [('compile',args_compile,120),('run',[vvp,str(binary)],seconds)]:
  log=out/(label+'_'+phase+'.log');t=time.time()
  with log.open('w') as f:
   process=subprocess.Popen(cmd,stdout=f,stderr=subprocess.STDOUT,start_new_session=True)
   try:rc=process.wait(timeout=limit)
   except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait();raise RuntimeError(label+' timeout')
  results[label+'_'+phase]={'argv':cmd,'rc':rc,'elapsed_s':time.time()-t,'log_sha256':sha(log)}
  if rc:raise RuntimeError(label+' '+phase+' failed')
 text=(out/(label+'_run.log')).read_text()
 if label=='directed':
  assert 'errors=0 stores_gold=8 stores_dut=8' in text and 'DIRECTED_INTERNAL bits=2313 errors=0 checks=3469500' in text
  for opcode in range(4):assert re.search(rf'MUL_OPCODE funct3={opcode} gold_handshakes=[1-9]\d* dut_handshakes=[1-9]\d*',text)
 elif label=='ports_50k':assert '0 mismatches / 899820 checks (50000 cycles, 0 all-X checks skipped)' in text
 else:assert 'SOURCE_INTERNAL bits=2313 cycles=3000 errors=0 checks=6939000' in text
results.update(status='passed',elapsed_s=time.time()-start,repaired_sha256=sha(root/'pico_big_lift_mul_repaired.v'))
(out/'result.json').write_text(json.dumps(results,indent=2)+'\n');print('All three acceptance regressions passed')
