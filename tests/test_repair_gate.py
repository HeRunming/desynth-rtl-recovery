import copy,importlib.util,json,pathlib,shutil,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1];ART=ROOT/'artifacts/config_a'
spec=importlib.util.spec_from_file_location('repair',ROOT/'agent/repair_mul_word.py');repair=importlib.util.module_from_spec(spec);spec.loader.exec_module(repair)
class ProofGate(unittest.TestCase):
 def test_archived_inputs_and_deterministic_emission(self):
  repair.check_proof(ART/'mul_cec_v2',ART/'pico_big_netlist.v')
  out,_=repair.generate(repair.load(ART/'big_mech_cse.json'),repair.load(ART/'big_names.json'),repair.load(ART/'pico_big_netlist.json'),(ART/'pico_big_lift.v').read_text())
  self.assertEqual(out,(ART/'pico_big_lift_mul_repaired.v').read_text())
 def test_incomplete_timeout_and_changed_aig_rejected(self):
  for mutation in ('missing','timeout','aig'):
   with self.subTest(mutation=mutation),tempfile.TemporaryDirectory() as tmp:
    d=pathlib.Path(tmp)/'proof';shutil.copytree(ART/'mul_cec_v2',d)
    proof=repair.load(d/'accepted_proof.json')
    if mutation=='missing':proof['obligations'].pop()
    elif mutation=='timeout':proof['obligations'][0]['status']='timeout'
    else:(d/'lhs.aig').write_bytes((d/'lhs.aig').read_bytes()+b'changed')
    (d/'accepted_proof.json').write_text(json.dumps(proof))
    with self.assertRaises(ValueError):repair.check_proof(d,ART/'pico_big_netlist.v')
 def test_wrong_qid_and_already_repaired_rejected(self):
  m=repair.load(ART/'big_mech_cse.json');n=repair.load(ART/'big_names.json');nj=repair.load(ART/'pico_big_netlist.json');bad=copy.deepcopy(m);bad['net_meta']['27106']['name']='other(31)'
  with self.assertRaises(ValueError):repair.generate(bad,n,nj,(ART/'pico_big_lift.v').read_text())
  with self.assertRaises(ValueError):repair.generate(m,n,nj,(ART/'pico_big_lift_mul_repaired.v').read_text())
  badn=copy.deepcopy(n)
  for bus in badn['buses']:
   if 27140 in bus['bits']:bus['bits'].reverse()
  with self.assertRaises(ValueError):repair.generate(m,badn,nj,(ART/'pico_big_lift.v').read_text())
if __name__=='__main__':unittest.main()
