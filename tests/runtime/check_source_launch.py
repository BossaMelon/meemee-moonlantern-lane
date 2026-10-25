#!/usr/bin/env python3
"""Launch an immutable Git snapshot with no .godot cache, preserving all user files."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--godot', required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--candidate', default='HEAD')
    a=p.parse_args()
    root=Path(__file__).resolve().parents[2]
    out=a.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    snapshot=out/'source'
    snapshot.mkdir()  # Never overwrite prior evidence or an existing cache.
    commit=subprocess.check_output(['git','rev-parse',a.candidate+'^{commit}'],cwd=root,text=True).strip()
    tree=subprocess.check_output(['git','rev-parse',commit+'^{tree}'],cwd=root,text=True).strip()
    archive=subprocess.check_output(['git','archive',commit],cwd=root)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(snapshot, filter='data')
    assert not (snapshot/'.godot').exists()
    # The probe is an external test harness if candidate predates P03; record it.
    probe=(root/'tests/runtime/launch_probe.gd').read_bytes()
    probe_path=snapshot/'tests/runtime/launch_probe.gd'
    probe_path.parent.mkdir(parents=True,exist_ok=True)
    probe_path.write_bytes(probe)
    command=[str(snapshot/'tools/启动月灯巷.command'),'--log-file',str(out/'engine.log'),'--script','tests/runtime/launch_probe.gd']
    env=dict(os.environ,GODOT=str(Path(a.godot).resolve()),P03_LAUNCH_OUTPUT=str(out))
    with (out/'process.log').open('w') as log:
        proc=subprocess.run(command,cwd=snapshot,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=45)
    evidence={'candidate_commit':commit,'candidate_tree':tree,'initial_import_cache_present':False,'command':command,'probe_sha256':hashlib.sha256(probe).hexdigest(),'exit_code':proc.returncode,'log':str(out/'process.log'),'snapshot':str(snapshot)}
    report=out/'source-launch.json'
    evidence['result']=json.loads(report.read_text()) if report.exists() else None
    (out/'evidence.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(evidence,ensure_ascii=False,indent=2))
    return proc.returncode if proc.returncode else (0 if evidence['result'] and evidence['result']['passed'] else 1)


if __name__=='__main__':
    raise SystemExit(main())
