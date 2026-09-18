import json,hashlib,pathlib,sys
p=pathlib.Path(sys.argv[2]).resolve() if len(sys.argv)>2 else pathlib.Path(__file__).resolve().parent
p.mkdir(parents=True,exist_ok=True)
src=pathlib.Path(sys.argv[1]); m=json.loads(src.read_text())['modules']['picorv32']; nets=m['netnames']; cells=m['cells']
a=nets['genblk1.pcpi_mul.rs1']['bits']; b=nets['genblk1.pcpi_mul.rs2']['bits']; rd=nets['genblk1.pcpi_mul.rd']['bits']
assert len(a)==len(b)==33 and len(rd)==64 and len(set(a+b))==66
ops={'AND2':(['I0','I1'],'({I0} & {I1})'),'OR2':(['I0','I1'],'({I0} | {I1})'),'XOR':(['I0','I1'],'({I0} ^ {I1})'),'INV':(['I'],'~{I}'),'BUF':(['I'],'{I}'),'MUX':(['I0','I1','S'],'({S} ? {I1} : {I0})')}
drv={};ffs={}
for name,c in cells.items():
 typ=c['type']; con=c['connections']
 assert typ=='FF' or typ in ops, (name,typ)
 out='Q' if typ=='FF' else 'O'; assert len(con[out])==1
 q=con[out][0]; assert q not in drv and q not in ffs
 if typ=='FF': ffs[q]=(name,con['D'][0]); assert c['port_directions']=={'C':'input','D':'input','Q':'output'}
 else: drv[q]=(name,typ,con)
assert all(x in ffs for x in a+b+rd)
refs={x:f'a[{i}]' for i,x in enumerate(a)}; refs.update({x:f'b[{i}]' for i,x in enumerate(b)})
def sig(x):
 if isinstance(x,str):
  assert x in ('0','1'), ('unknown constant',x)
  return "1'b"+x
 return refs.get(x,f'n{x}')
used={};visiting=set();proofs=[]
def visit(x,local,cuts):
 if isinstance(x,str): sig(x);return
 if x in refs: cuts.add(x);return
 if x in local:return
 assert x not in visiting,('cycle',x)
 assert x in drv,('unresolved cut',x)
 visiting.add(x);name,typ,con=drv[x]
 for pin in ops[typ][0]:
  assert con[pin] and len(con[pin])==1
  visit(con[pin][0],local,cuts)
 visiting.remove(x);local.add(x);used[x]=(name,typ,con)
for i,q in enumerate(rd):
 ff,target=ffs[q]; local=set();cuts=set();visit(target,local,cuts)
 proofs.append({'bit':i,'q':q,'ff':ff,'d':target,'gates':len(local),'cuts':sorted(cuts)})
lines=['`default_nettype none','module lhs(input [32:0] a, b, output [63:0] result);']
for x,(name,typ,con) in used.items():
 expr=ops[typ][1].format(**{k:sig(con[k][0]) for k in ops[typ][0]})
 lines.append(f'wire n{x}; assign n{x} = {expr}; // {name} {typ}')
for v in proofs:lines.append(f'assign result[{v["bit"]}] = {sig(v["d"])};')
lines+=['endmodule','`default_nettype wire'];(p/'lhs.v').write_text('\n'.join(lines)+'\n')
(p/'rhs.v').write_text('`default_nettype none\nmodule rhs(input [32:0] a,b, output [63:0] result);\nassign result = $signed(a) * $signed(b);\nendmodule\n`default_nettype wire\n')
for side in ('lhs','rhs'):
 (p/f'{side}.ys').write_text(f'read_verilog -noautowire {side}.v\nhierarchy -check -top {side}\nproc\nflatten\nopt\nmemory\nopt\ntechmap\nopt\ncheck -assert\naigmap\nopt_clean -purge\ncheck -assert\nwrite_aiger -symbols {side}.aig\nwrite_json {side}_mapped.json\n')
manifest={'source_json_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'a':a,'b':b,'proof_obligations':proofs,'lhs_sha256':hashlib.sha256((p/'lhs.v').read_bytes()).hexdigest(),'rhs_sha256':hashlib.sha256((p/'rhs.v').read_bytes()).hexdigest()}
(p/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print('Generated',len(used),'gates,',len(proofs),'D cone obligations')
