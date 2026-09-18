import pathlib,json,random,sys
p=pathlib.Path(sys.argv[1]).resolve() if len(sys.argv)>1 else pathlib.Path(__file__).resolve().parent

def parse(path):
 data=path.read_bytes();pos=data.index(b'\n')+1;magic,M,I,L,O,A=data[:pos].decode().split();M,I,L,O,A=map(int,(M,I,L,O,A));assert magic=='aig' and L==0 and I==66 and O==64
 outputs=[]
 for _ in range(O):
  end=data.index(b'\n',pos);outputs.append(int(data[pos:end]));pos=end+1
 tail=data[pos:]; gates=[]
 def varint():
  nonlocal pos
  v=s=0
  while True:
   x=data[pos];pos+=1;v|=(x&127)<<s
   if x<128:return v
   s+=7
 for i in range(A):
  out=2*(I+i+1);in0=out-varint();in1=in0-varint();assert in1<=in0<out;gates.append((in0,in1))
 syms=data[pos:].decode(errors='replace').splitlines();ins={};outs={}
 for line in syms:
  if line=='c':break
  if line.startswith('i'):
   k,v=line.split(' ',1);ins[int(k[1:])]=v
  elif line.startswith('o'):
   k,v=line.split(' ',1);outs[int(k[1:])]=v
 assert ins=={**{i:f'a[{i}]' for i in range(33)},**{33+i:f'b[{i}]' for i in range(33)}}
 assert outs=={i:f'result[{i}]' for i in range(64)}
 return data[:data.index(b'\n')+1],outputs,tail,gates

def ev(model,a,b):
 _,outs,_,gates=model;vals=[0]+[(a>>i)&1 for i in range(33)]+[(b>>i)&1 for i in range(33)]
 def lit(x):return vals[x>>1]^(x&1)
 for x,y in gates:vals.append(lit(x)&lit(y))
 return sum(lit(x)<<i for i,x in enumerate(outs))
models={s:parse(p/(s+'.aig')) for s in ('lhs','rhs')};rng=random.Random(170918)
cases=[(0,0),((1<<33)-1,2),(1<<32,1<<32),((1<<32)-1,(1<<32)-1)]+[(rng.getrandbits(33),rng.getrandbits(33)) for _ in range(256)]
for a,b in cases:
 sa=a-(1<<33) if a>>32 else a;sb=b-(1<<33) if b>>32 else b;want=(sa*sb)&((1<<64)-1)
 assert ev(models['lhs'],a,b)==ev(models['rhs'],a,b)==want,(a,b)
header,outs,tail,_=models['rhs']
for bit in (31,63):
 changed=outs.copy();changed[bit]^=1
 (p/f'rhs_flip{bit}.aig').write_bytes(header+b''.join(str(v).encode()+b'\n' for v in changed)+tail)
report={'seed':170918,'vectors':len(cases),'input_symbols_exact':True,'output_symbols_exact':True,'all_zero_outputs':{s:ev(m,0,0) for s,m in models.items()},'status':'passed','note':'Simulation audits serialization and reported counterexample; not formal equivalence.'}
(p/'aig_audit.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
