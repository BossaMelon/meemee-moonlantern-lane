#!/usr/bin/env python3
"""Launch an immutable Git snapshot with no .godot cache, preserving all user files."""
import argparse
import hashlib
import io
import json
import os
import re
from pathlib import Path
import subprocess
import tarfile


def git_tree(path: Path) -> str:
    """Hash archive content using Git's tree format without writing Git objects."""
    def object_hash(kind, payload):
        return hashlib.sha1(kind+b' '+str(len(payload)).encode()+b'\0'+payload).digest()

    def directory(folder):
        entries=[]
        for file in folder.iterdir():
            name=os.fsencode(file.name)
            if file.is_symlink():
                mode=b'120000'
                digest=object_hash(b'blob',os.fsencode(os.readlink(file)))
            elif file.is_dir():
                mode=b'40000'
                digest=directory(file)
            else:
                mode=b'100755' if file.stat().st_mode & 0o111 else b'100644'
                digest=object_hash(b'blob',file.read_bytes())
            entries.append((name+(b'/' if mode==b'40000' else b''),mode+b' '+name+b'\0'+digest))
        return object_hash(b'tree',b''.join(row for _,row in sorted(entries)))
    return directory(path).hex()


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--godot', required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--candidate', default='HEAD')
    p.add_argument('--overlay', action='append', default=[], help='Apply the exact diff of a separately authorized dependency commit to the temporary snapshot')
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
    assert git_tree(snapshot)==tree, 'Exported archive does not match the candidate Git tree'
    overlays=[]
    for revision in a.overlay:
        overlay=subprocess.check_output(['git','rev-parse',revision+'^{commit}'],cwd=root,text=True).strip()
        patch=subprocess.check_output(['git','diff',overlay+'^',overlay,'--binary'],cwd=root)
        subprocess.run(['git','apply','--check','-'],input=patch,cwd=snapshot,check=True)
        subprocess.run(['git','apply','-'],input=patch,cwd=snapshot,check=True)
        paths=subprocess.check_output(['git','diff',overlay+'^',overlay,'--name-only'],cwd=root,text=True).splitlines()
        overlays.append({'commit':overlay,'paths':paths,'patch_sha256':hashlib.sha256(patch).hexdigest()})
    combined_tree=git_tree(snapshot)
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
    evidence={'candidate_commit':commit,'candidate_tree':tree,'overlays':overlays,'combined_product_tree':combined_tree,'initial_import_cache_present':False,'command':command,'probe_sha256':hashlib.sha256(probe).hexdigest(),'exit_code':proc.returncode,'log':str(out/'process.log'),'snapshot':str(snapshot)}
    report=out/'source-launch.json'
    evidence['result']=json.loads(report.read_text()) if report.exists() else None
    evidence['engine_errors']=re.findall(r'^(?:SCRIPT ERROR:|ERROR:).*$',(out/'process.log').read_text(errors='replace'),re.MULTILINE)
    evidence['passed']=proc.returncode==0 and not evidence['engine_errors'] and bool(evidence['result']) and evidence['result'].get('passed') is True
    (out/'evidence.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(evidence,ensure_ascii=False,indent=2))
    return 0 if evidence['passed'] else 1


if __name__=='__main__':
    raise SystemExit(main())
