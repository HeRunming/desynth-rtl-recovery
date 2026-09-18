#!/usr/bin/env python3
"""Emit Config A MUL repair only with complete, hash-bound ABC CEC evidence.

The legacy direct-Minisat harness is replaced by scripts/config_a_proof/. Run its
source and negative-control validation before invoking this emission step.
"""
import argparse, hashlib, json, pathlib, re
BITS=list(range(31,64))
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def load(p):return json.loads(pathlib.Path(p).read_text())
def require(ok,msg):
 if not ok:raise ValueError(msg)
def check_proof(proof_dir,netlist):
 proof=load(proof_dir/'accepted_proof.json');parts=proof.get('obligations',[])
 require(proof.get('status')=='proven','proof not proven')
 require([r.get('bit') for r in parts]==BITS and all(r.get('status')=='proven' for r in parts),'all 33 bit proofs required')
 for path,digest in proof['sha256'].items():
  local=proof_dir/pathlib.Path(path).name
  if not local.exists():local=netlist.parent/pathlib.Path(path).name
  require(local.is_file() and sha(local)==digest,'changed proof input: '+str(path))
 require(any(pathlib.Path(k).name==netlist.name and sha(netlist)==v for k,v in proof['sha256'].items()),'netlist not bound')
 info=load(proof_dir/'standard_cec.json');text=(proof_dir/'standard_cec.log').read_text()
 require(info['rc']==0 and info['status']=='finished' and 'Networks are equivalent.' in text and 'not equivalent' not in text.lower(),'no accepted standard CEC verdict')
 for bit in (31,63):
  info=load(proof_dir/f'negative_{bit}.json');text=(proof_dir/f'negative_{bit}.log').read_text()
  require(info['rc']==0 and 'not equivalent' in text.lower() and 'Networks are equivalent.' not in text,'negative control did not fail')
 return proof

def generate(mech,names,netlist_json,lift):
 qids=set(mech['ff_q_ids']);sem={};used=set()
 for bus in names['buses']:
  base=re.sub(r'\W','_',bus.get('name') or 'unnamed');name=base;n=1
  while name in used:name=f'{base}_{n}';n+=1
  used.add(name);bits=[q for q in bus['bits'] if q in qids]
  for i,q in enumerate(bits):
   require(q not in sem,'duplicate qid');sem[q]=(name,i,len(bits))
 for q in qids:
  if q not in sem:sem[q]=(f'unnamed_{q}',0,1)
 meta=mech['net_meta'];module=netlist_json['modules']['picorv32'];nets=module['netnames'];ffq={c['connections']['Q'][0] for c in module['cells'].values() if c['type']=='FF'}
 provenance={}
 for label,start,count in [('rd',27075,64),('rs1',27140,33),('rs2',27173,33)]:
  for bit in range(count):
   q=start+bit;source=f'genblk1.pcpi_mul.{label}';require(meta[str(q)]['name']==f'{source}({bit})' and meta[str(q)]['cat']=='ff_q','source qid mismatch')
   require(nets[source]['bits'][bit] in ffq,'source not FF Q')
   name,i,width=sem[q];decl=re.search(r'\breg\s+(?:\[(\d+):0\]\s+)?'+re.escape(name)+r'\s*;',lift)
   require(bool(decl) and (int(decl[1])+1 if decl[1] else 1)==width,'lift declaration mismatch '+name)
   provenance[q]={'source':f'{source}({bit})','yosys_bit':nets[source]['bits'][bit],'rtl':name+(f'[{i}]' if width>1 else '')}
 # This repair is intentionally specific to the audited Config A lift. Reject
 # reordered manifest bits even when signal widths still match.
 for bit in range(64):
  expected=f'unnamed_27075[{bit}]' if bit<39 else f'control_state_5[{bit-39}]'
  require(provenance[27075+bit]['rtl']==expected,'rd span/order mismatch')
 for bit in range(33):
  require(provenance[27140+bit]['rtl']==f'data_word_a[{bit}]','rs1 span/order mismatch')
  expected=f'input_capture_reg[{bit}]' if bit<32 else 'data_word_b_msb_flag'
  require(provenance[27173+bit]['rtl']==expected,'rs2 span/order mismatch')
 require(sorted(x['q_id'] for x in mech['ff_defs'] if x.get('skipped'))==list(range(27106,27139)),'unexpected skipped qids')
 out=lift
 for bit in BITS:
  dest=provenance[27075+bit]['rtl']
  pat=r'(?m)^(\s*)'+re.escape(dest)+r"\s*<=\s*1'bx;[^\n]*genblk1\.pcpi_mul\.rd\("+str(bit)+r'\)[^\n]*$'
  out,n=re.subn(pat,lambda m:m[1]+f'{dest} <= mul_word_candidate[{bit}]; // ABC CEC proven rd({bit})',out)
  require(n==1,f'expected exactly one skipped rd({bit}) assignment')
 require('mul_word_candidate' not in lift,'already patched or candidate name collision')
 operand=lambda start:'{'+', '.join(provenance[start+i]['rtl'] for i in reversed(range(33)))+'}'
 decl='\n  // Low 64 bits of signed 33x33 product; all repaired D bits ABC CEC proven.\n'
 decl+=f'  wire signed [32:0] mul_rs1_candidate = $signed({operand(27140)});\n'
 decl+=f'  wire signed [32:0] mul_rs2_candidate = $signed({operand(27173)});\n'
 decl+='  wire [63:0] mul_word_candidate = $signed(mul_rs1_candidate) * $signed(mul_rs2_candidate);\n'
 # Place after all reg declarations to avoid implicit forward-declared wires.
 declarations=list(re.finditer(r'(?m)^\s*reg\s+[^;]+;[^\n]*\n',out));require(bool(declarations),'no register declarations')
 pos=declarations[-1].end();out=out[:pos]+decl+out[pos:]
 header=out.index('module picorv32_lift')
 out='// Config A lift: rd[31:63] repaired after ABC CEC; see mul_repair_report.json.\n// Other state transformations retain their original implementation.\n'+out[header:]
 require(not re.search(r"<=\s*1'bx;",out),'remaining unknown next state')
 return out,provenance

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--root',type=pathlib.Path,required=True);ap.add_argument('--proof-dir',type=pathlib.Path,required=True);args=ap.parse_args();r=args.root;p=args.proof_dir
 proof=check_proof(p,r/'pico_big_netlist.v')
 mech=load(r/'big_mech_cse.json');names=load(r/'big_names.json');nj=load(r/'pico_big_netlist.json');original=r/'pico_big_lift.v'
 result,mapping=generate(mech,names,nj,original.read_text());out=r/'pico_big_lift_mul_repaired.v';out.write_text(result)
 report={'status':'repaired','proof_sha256':sha(p/'accepted_proof.json'),'proven_bits':BITS,'mapping':mapping,'sha256':{f.name:sha(f) for f in [original,out,r/'big_mech_cse.json',r/'big_names.json',r/'pico_big_netlist.v',r/'pico_big_netlist.json']}}
 (r/'mul_repair_report.json').write_text(json.dumps(report,indent=2)+'\n');print('Generated repaired RTL with 33 hash-bound proven assignments')
if __name__=='__main__':main()
