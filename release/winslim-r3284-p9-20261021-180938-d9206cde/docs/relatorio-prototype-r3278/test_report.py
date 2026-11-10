import unittest
from build_report import render
class TestReport(unittest.TestCase):
 def setUp(self):
  self.data={'verified':True,'changed':1,'unchanged':2,'items':[{'Id':'UI-001','Name':'Modo Escuro','Status':'AlreadyConfigured'},{'Id':'UI-001','Name':'Modo Escuro','Status':'AlreadyConfigured'},{'Id':'UI-010','Name':'Relógio','Status':'AppliedVerified'}], 'excluded':[{'Id':'UI-023','Name':'Não compatível','Reason':'Sem suporte'}], 'errors':[]}
 def test_groups(self):
  s=render(self.data);self.assertIn('Tweaks distintos',s);self.assertIn('>3</div>',s);self.assertIn('2 valor(es)',s)
 def test_escaping(self):
  self.data['profile']='<script>alert(1)</script>';s=render(self.data);self.assertNotIn('<script>',s)
 def test_discrepancy(self):
  self.data['changed']=9;self.assertIn('não correspondem',render(self.data))
 def test_failure(self):
  self.data['verified']=False;self.assertIn('Requer revisão',render(self.data))
 def test_excluded(self):
  self.assertIn('Sem suporte',render(self.data))
if __name__=='__main__':unittest.main()
