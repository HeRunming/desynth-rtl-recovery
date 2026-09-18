"""Compare real mapped FF Q outputs against every emitted lift state bit."""
import pathlib,json,re,argparse
ap=argparse.ArgumentParser();ap.add_argument('root',type=pathlib.Path);args=ap.parse_args();root=args.root
m=json.loads((root/'big_mech_cse.json').read_text());n=json.loads((root/'big_names.json').read_text());nl=json.loads((root/'pico_big_netlist.json').read_text())['modules']['picorv32'];lift=(root/'pico_big_lift_mul_repaired.v').read_text()
qids=set(m['ff_q_ids']);sem={};used=set()
for b in n['buses']:
 name=re.sub(r'\W','_',b.get('name') or 'unnamed');final=name;idx=1
 while final in used:final=f'{name}_{idx}';idx+=1
 used.add(final);bits=[q for q in b['bits'] if q in qids]
 for i,q in enumerate(bits):
  assert q not in sem;sem[q]=(final,i,len(bits))
for q in qids:
 if q not in sem:sem[q]=(f'unnamed_{q}',0,1)
ffs={c['connections']['Q'][0]:name for name,c in nl['cells'].items() if c['type']=='FF'}
refs=[]
for q in sorted(qids):
 raw=m['net_meta'][str(q)]['name'];mat=re.fullmatch(r'(.*)\((\d+)\)',raw);base=mat[1] if mat else raw;offset=int(mat[2]) if mat else 0
 assert base in nl['netnames'],(q,base)
 net=nl['netnames'][base];ybit=net['bits'][offset-net.get('offset',0)];assert ybit in ffs,(q,base,offset,ybit)
 name,i,width=sem[q];decl=re.search(r'\breg\s+(?:\[(\d+):0\]\s+)?'+re.escape(name)+r'\s*;',lift)
 assert decl and (int(decl[1])+1 if decl[1] else 1)==width,(q,name,width)
 dest=f'dut.{name}'+(f'[{i}]' if width>1 else '')
 refs.append({'qid':q,'source':raw,'yosys_bit':ybit,'gold':f'gold.{ffs[ybit]}.Q','dut':dest})
assert len(refs)==len(ffs)==2313 and len({r['yosys_bit'] for r in refs})==2313
# Preserve original 50k regression stimulus and all port comparisons; add FF comparisons.
tb=(root/'tb_eq_big.v').read_text();assert '50000' in tb
tb=tb.replace('module tb_eq_big;','module tb_source_internal;').replace('50000','3000')
checks=['integer ff_errors=0, ff_checks=0;','always @(posedge clk) begin','#1;','if (resetn) begin']
for r in refs:
 checks += ['ff_checks=ff_checks+1;',f'if ({r["gold"]} !== {r["dut"]}) begin',f'if(ff_errors<8) $display("FF_MISMATCH qid={r["qid"]} gold=%b dut=%b", {r["gold"]}, {r["dut"]});','ff_errors=ff_errors+1;','end']
checks+=['end','end']
tb=tb.replace('module tb_source_internal;','module tb_source_internal;\n'+checks[0],1)
tb=tb.replace('endmodule','\n'.join(checks[1:])+'\nendmodule',1)
tb=tb.replace('    $finish;','    $display("SOURCE_INTERNAL bits=2313 cycles=3000 errors=%0d checks=%0d", ff_errors, ff_checks);\n    if (ff_errors != 0 || ff_checks < 2313*3000) $fatal(1,"internal mismatch or incomplete run");\n    $finish;')
(root/'tb_source_internal.v').write_text(tb);(root/'source_internal_mapping.json').write_text(json.dumps(refs,indent=2)+'\n')
# Also instrument the directed test, so repaired states are observed during MUL execution.
tb=(root/'tb_mul_directed.v').read_text().replace('module tb_mul_directed;','module tb_directed_internal;');cs='\n'.join(checks[1:]).replace('gold.','g.').replace('dut.','d.')
tb=tb.replace('module tb_directed_internal;','module tb_directed_internal;\n'+checks[0],1)
tb=tb.replace('endmodule',cs+'\nendmodule',1)
tb=tb.replace('    $finish;','    #2;\n    $display("DIRECTED_INTERNAL bits=2313 errors=%0d checks=%0d",ff_errors,ff_checks);\n    if(ff_errors || errors || stores!=8 || dstores!=8 || ff_checks<2313*1499) $fatal(1,"directed/internal failure");\n    for(oi=0;oi<4;oi=oi+1) if(op_seen[oi]==0 || dop_seen[oi]==0) $fatal(1,"missing opcode");\n    $finish;')
(root/'tb_directed_internal.v').write_text(tb);print('Mapped 2313 unique FF Q states to actual emitted register declarations')
