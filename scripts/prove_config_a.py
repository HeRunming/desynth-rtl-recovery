#!/usr/bin/env python3
"""Regenerate and prove all rd D bits with bounded ABC CEC; never patches RTL."""
import argparse,hashlib,json,os,pathlib,signal,subprocess,sys,time
ap=argparse.ArgumentParser();ap.add_argument('--root',type=pathlib.Path,required=True);ap.add_argument('--output',default='proof_replay');args=ap.parse_args();root=args.root.resolve();p=root/args.output
if p.exists():raise SystemExit('Refusing to overwrite existing proof directory: '+str(p))
p.mkdir();scripts=pathlib.Path(__file__).resolve().parent/'config_a_proof'
Y=os.environ.get('YOSYS','yosys');A=os.environ.get('ABC','yosys-abc')
def run(label,cmd,limit):
 start=time.time();info={'argv':cmd,'started':start,'limit_s':limit,'status':'running'}
 with (p/(label+'.log')).open('w') as f:
  proc=subprocess.Popen(cmd,cwd=p,stdout=f,stderr=subprocess.STDOUT,start_new_session=True);info['pid']=proc.pid
  (p/(label+'.json')).write_text(json.dumps(info,indent=2))
  try:info['rc']=proc.wait(timeout=limit);info['status']='finished' if proc.returncode==0 else 'tool_error'
  except subprocess.TimeoutExpired:
   os.killpg(proc.pid,signal.SIGKILL);info['rc']=proc.wait();info['status']='timeout'
 info['elapsed_s']=time.time()-start;(p/(label+'.json')).write_text(json.dumps(info,indent=2))
 if info['status']!='finished':raise RuntimeError(label+': '+info['status'])
run('build_cones',[sys.executable,str(scripts/'build.py'),str(root/'pico_big_netlist.json'),str(p)],120)
for side in ('lhs','rhs'):
 run(side+'_build',[Y,'-s',side+'.ys'],120)
 if 'Warning:' in (p/(side+'_build.log')).read_text():raise RuntimeError('unexpected model warning')
run('standard_cec',[A,'-c','&cec -T 1800 -v lhs.aig rhs.aig'],1800)
log=(p/'standard_cec.log').read_text()
if 'Networks are equivalent.' not in log or 'not equivalent' in log.lower():raise RuntimeError('unproven, failed, or undecided')
run('aig_audit',[sys.executable,str(scripts/'audit_aig.py'),str(p)],60)
run('validate',[sys.executable,str(scripts/'validate.py'),str(p)],180)
print('Proof accepted: '+str(p/'accepted_proof.json'))
