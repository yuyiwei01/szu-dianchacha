"""Verify that the single EXE works in an otherwise empty directory."""
import datetime
import os
import json
import pathlib
import re
import shutil
import subprocess
import tempfile
import time
import urllib.request

root = pathlib.Path(__file__).resolve().parents[1]
build = re.search(r'BuildId = "([0-9a-f]+)"', (root / '.build/Launcher.cs').read_text(encoding='utf-8-sig'))[1]

def health(port):
    try:
        with urllib.request.urlopen(f'http://127.0.0.1:{port}/api/health', timeout=.5) as response:
            return json.load(response)
    except Exception:
        return {}

def locate():
    for port in range(18765,18775):
        if health(port).get('buildId') == build:
            return port
    return None

with tempfile.TemporaryDirectory(prefix='电量 EXE 独立测试 ') as folder:
    exe = pathlib.Path(folder) / '独立 电量.exe'
    shutil.copy2(root / 'dist/SZU电查查.exe', exe)
    assert len(list(pathlib.Path(folder).iterdir())) == 1
    assert locate() is None, 'Stop this build before running the test'
    process = subprocess.Popen([str(exe), '--no-browser'], cwd=folder)
    base = None
    try:
        for _ in range(80):
            port = locate()
            if port:
                base = f'http://127.0.0.1:{port}'
                break
            assert process.poll() is None, 'EXE exited during startup'
            time.sleep(.2)
        assert base, 'No healthy service started'
        def get(path):
            with urllib.request.urlopen(base+path,timeout=5) as response:
                return json.load(response)
        token = get('/api/config')['token']
        def post(path, data):
            request = urllib.request.Request(base+path, data=json.dumps(data).encode(),headers={'Content-Type':'application/json','X-Local-Token':token})
            with urllib.request.urlopen(request,timeout=10) as response:
                return json.load(response)
        for asset in ['app.js','chart.js','style.css','model.js','favicon.svg','index.html']:
            with urllib.request.urlopen(base+'/'+asset) as response:
                assert response.read() == (root/'web'/asset).read_bytes(), asset
        duplicate = subprocess.Popen([str(exe),'--no-browser'],cwd=folder)
        assert duplicate.wait(timeout=10) == 0
        assert locate() == port
        dorm = {key: os.environ.get('SZU_TEST_'+key.upper()) for key in ['campus','building','room']}
        if any(dorm.values()):
            assert all(dorm.values()), 'Set all three SZU_TEST_* variables for an optional school query'
            today = datetime.date.today()
            post('/api/query', {**dorm, 'begin':str(today-datetime.timedelta(days=29)), 'end':str(today)})
            for _ in range(300):
                job=get('/api/job')
                if job['state']!='running':break
                time.sleep(.2)
            assert job['state']=='done', 'Optional school query did not complete'
            assert job['data']['complete'] is True
            assert isinstance(job['data']['usage'],list)
            assert isinstance(job['data']['purchases'],list)
        assert post('/api/stop',{})['state']=='stopped'
        assert process.wait(timeout=15)==0
        assert locate() is None
        print('PASS: standalone EXE in empty Chinese/spaced path, embedded assets, duplicate startup and shutdown')
    finally:
        if process.poll() is None:
            try:
                post('/api/stop',{})
                process.wait(timeout=10)
            except Exception:
                process.kill()
