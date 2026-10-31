"""Small local launcher contract checks; no GPU or network required."""
import os,pathlib,socket,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Launcher(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.p=pathlib.Path(self.tmp.name)
  self.sock=socket.socket(socket.AF_UNIX);self.sock.bind(str(self.p/'pipewire-0'))
  self.bus=socket.socket(socket.AF_UNIX);self.bus.bind(str(self.p/'bus'))
  engine=self.p/'podman';engine.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$CALL_LOG"\nif [[ "$1" == inspect ]]; then echo "${MOCK_RUNNING:-false}"; fi\n');engine.chmod(0o755)
  busctl=self.p/'busctl';busctl.write_text('#!/bin/sh\nexit 1\n');busctl.chmod(0o755)
  self.env={**os.environ,'PATH':str(self.p)+':'+os.environ['PATH'],'HOME':str(self.p),'XDG_RUNTIME_DIR':str(self.p),'DISPLAY':':99','WAYLAND_DISPLAY':'','LINUX_BROADCAST_ENGINE':str(engine),'CALL_LOG':str(self.p/'calls')}
 def tearDown(self):self.sock.close();self.bus.close();self.tmp.cleanup()
 def launch(self,*args):return subprocess.run(['bash',str(ROOT/'scripts/linux-broadcast-container'),*args],env=self.env,text=True,capture_output=True)
 def test_run_exposes_only_session_and_persistent_state(self):
  r=self.launch('--background');self.assertEqual(r.returncode,0,r.stderr)
  calls=(self.p/'calls').read_text();self.assertIn('nvidia.com/gpu=all',calls);self.assertIn('pipewire-0',calls);self.assertIn('dst=/home/broadcast',calls);self.assertIn('--background',calls)
  self.assertNotIn('--privileged',calls);self.assertNotIn('--network=host',calls);self.assertNotIn('docker.sock',calls)
 def test_relaunch_activates_existing_container(self):
  self.env['MOCK_RUNNING']='true';r=self.launch();self.assertEqual(r.returncode,0,r.stderr)
  calls=(self.p/'calls').read_text();self.assertIn('exec ',calls);self.assertNotIn('run --',calls)
 def test_missing_pipewire_is_actionable(self):
  self.sock.close();(self.p/'pipewire-0').unlink();r=self.launch();self.assertNotEqual(r.returncode,0);self.assertIn('PipeWire',r.stderr)
if __name__=='__main__':unittest.main()
