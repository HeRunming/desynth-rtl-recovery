import pathlib,subprocess,json,time,os,signal,hashlib,sys
p=pathlib.Path(sys.argv[1]).resolve();os.chdir(p);base=p.parent
A=os.environ.get('ABC','yosys-abc');Y=os.environ.get('YOSYS','yosys')
def sha(f):return hashlib.sha256(pathlib.Path(f).read_bytes()).hexdigest()
def run(label,cmd,limit=60):
 with open(label+'.log','w') as f:
  proc=subprocess.Popen(cmd,stdout=f,stderr=subprocess.STDOUT,start_new_session=True);start=time.time()
  try:rc=proc.wait(timeout=limit)
  except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.wait();raise RuntimeError(label+' timeout')
 info={'argv':cmd,'rc':rc,'elapsed_s':time.time()-start,'log_sha256':sha(label+'.log')};(p/(label+'.json')).write_text(json.dumps(info,indent=2));assert rc==0
 return pathlib.Path(label+'.log').read_text()
for bit in (31,63):
 log=run('negative_'+str(bit),[A,'-c',f'&cec -T 45 lhs.aig rhs_flip{bit}.aig'])
 assert 'not equivalent' in log.lower(),log
 assert 'Networks are equivalent.' not in log
(p/'regenerate.ys').write_text('read_verilog -formal ../cells_init.v ../pico_big_netlist.v\nprep -top picorv32\ncheck -assert\nwrite_json regenerated.json\n')
run('regenerate',[Y,'-s','regenerate.ys'],120)
r=json.loads((p/'regenerated.json').read_text())['modules']['picorv32'];old=json.loads((base/'pico_big_netlist.json').read_text())['modules']['picorv32']
semantic=lambda m:{k:{f:v[f] for f in ('type','parameters','port_directions','connections')} for k,v in m['cells'].items()}
assert semantic(r)==semantic(old),'cell semantics changed'
assert {k:v['bits'] for k,v in r['netnames'].items()}=={k:v['bits'] for k,v in old['netnames'].items()},'mapping changed'
manifest=json.loads((p/'manifest.json').read_text());assert manifest['source_json_sha256']==sha(base/'pico_big_netlist.json')
assert manifest['lhs_sha256']==sha('lhs.v') and manifest['rhs_sha256']==sha('rhs.v')
for side in ('lhs','rhs'):
 info=json.loads((p/(side+'_build.json')).read_text());assert info['rc']==0 and info['status']=='finished'
 assert 'Warning:' not in (p/(side+'_build.log')).read_text()
info=json.loads((p/'standard_cec.json').read_text());assert info['rc']==0 and info['status']=='finished'
log=(p/'standard_cec.log').read_text();assert 'Networks are equivalent.' in log
assert 'not equivalent' not in log.lower()
# Fail closed for the separate experimental arithmetic checker; its counterexample
# was replayed on both original AIGs and contradicted. Only standard CEC is accepted.
result={'status':'proven','scope':'all 64 rd FF D functions vs signed 33x33 product truncated to 64 bits','engine':'ABC &cec (new engine plus old CEC fallback)','elapsed_s':info['elapsed_s'],'negative_controls':[31,63],'source_regeneration':'exact cells and net-bit map match','obligations':[dict(x,status='proven',proof='standard_cec.log') for x in manifest['proof_obligations'] if 31<=x['bit']<=63],'sha256':{str(f):sha(f) for f in ['lhs.v','rhs.v','lhs.aig','rhs.aig','standard_cec.log','manifest.json',str(base/'pico_big_netlist.v'),str(base/'pico_big_netlist.json'),str(base/'cells_init.v'),'standard_cec.json','negative_31.log','negative_63.log','negative_31.json','negative_63.json']}}
assert len(result['obligations'])==33
(p/'accepted_proof.json').write_text(json.dumps(result,indent=2)+'\n');print('ACCEPTED: 33 obligations proven; 2 negative controls rejected; source binding verified')
