from io import StringIO
import json
import pytest
from ..protocol import response,serve
from ..profile_store import ProfileStore


def test_worker_protocol_roundtrip_and_errors():
    handlers={'add':lambda payload:payload['a']+payload['b']}
    assert response(dict(id=1,op='add',payload=dict(a=2,b=3)),handlers)==dict(id=1,ok=True,result=5)
    assert response(dict(id=2,op='missing'),handlers)['ok'] is False
    assert response(dict(id=3,op='add',payload=[]),handlers)['ok'] is False
    assert response(dict(id=True,op='add'),handlers)['ok'] is False
    assert response(dict(id=4,op='add',payload={}),handlers)['id']==4
    out=StringIO();serve(handlers,StringIO('broken\n'+json.dumps(dict(id=5,op='add',payload=dict(a=1,b=4)))+'\n'),out)
    first,second=map(json.loads,out.getvalue().splitlines())
    assert first['ok'] is False and second==dict(id=5,ok=True,result=5)
    assert response(dict(id=6,op='bad'),{'bad':lambda _:float('nan')})['ok'] is False


def test_profile_lifecycle_names_ids_and_atomic_update(tmp_path):
    profiles=ProfileStore('test',tmp_path/'profiles')
    assert profiles.list()==[] and not profiles.directory.exists()
    saved=profiles.save(' Room ',{'strength':1});identifier=saved['id']
    assert saved['name']=='Room'
    assert profiles.list()==[dict(id=identifier,name='Room')]
    with pytest.raises(ValueError,match='already exists'):profiles.save('room',{})
    with pytest.raises(ValueError):profiles.rename(identifier,' ')
    with pytest.raises(ValueError):profiles.update(identifier,{'x':float('nan')})
    assert profiles.read(identifier)['payload']=={'strength':1}
    profiles.rename(identifier,'Hall');profiles.update(identifier,{'strength':2})
    assert profiles.read(identifier)['name']=='Hall'
    assert profiles.read(identifier)['payload']=={'strength':2}
    assert ProfileStore('test',profiles.directory).list()==[dict(id=identifier,name='Hall')]
    profiles.delete(identifier);assert profiles.list()==[]
    with pytest.raises(ValueError):profiles.delete('../../image')
    with pytest.raises(ValueError):ProfileStore('../bad',tmp_path)


def test_profiles_ignore_corrupt_files_and_isolate_namespaces(tmp_path,monkeypatch):
    monkeypatch.setenv('XDG_DATA_HOME',str(tmp_path))
    first=ProfileStore('one');second=ProfileStore('two')
    profile=first.save('Name',{})
    assert second.list()==[]
    (first.directory/'not-an-id.json').write_text('{}')
    assert first.list()==[dict(id=profile['id'],name='Name')]


@pytest.mark.parametrize('identifier',[None,True,-1,0,[],{},float('nan'),float('inf'),9007199254740992])
def test_invalid_request_ids_always_have_serializable_null_error_ids(identifier):
    result=response(dict(id=identifier,op='run'),{'run':lambda _:None})
    assert result['id'] is None and result['ok'] is False
    json.dumps(result,allow_nan=False)


def test_protocol_rejects_nonfinite_duplicate_and_unknown_fields_before_dispatch():
    called=[];handlers={'run':lambda payload:called.append(payload)}
    out=StringIO()
    lines=['{"id":1,"op":"run","payload":{"x":NaN}}',
           '{"id":2,"id":3,"op":"run"}',
           '{"id":4,"op":"run","payload":{"x":Infinity}}',
           '{"id":5,"op":"run","extra":"unexpected"}',
           '{"id":6,"op":"run","payload":{}}']
    serve(handlers,StringIO('\n'.join(lines)+'\n'),out)
    results=list(map(json.loads,out.getvalue().splitlines()))
    assert len(results)==5 and [r['ok'] for r in results]==[False,False,False,False,True]
    assert called==[{}]
    assert 'Duplicate JSON key' in results[1]['error']


def test_protocol_callback_diagnostics_use_stderr_and_payload_is_a_copy(capsys):
    request=dict(id=1,op='run',payload=dict(value=1))
    def handler(payload):
        print('callback diagnostic')
        payload['value']=2
        return payload
    result=response(request,dict(run=handler))
    captured=capsys.readouterr()
    assert captured.out=='' and captured.err=='callback diagnostic\n'
    assert result==dict(id=1,ok=True,result=dict(value=2))
    assert request['payload']==dict(value=1)
    out=StringIO();serve({'run':lambda _:set([1])},StringIO('{"id":1,"op":"run"}\n{"id":2,"op":"missing"}\n'),out)
    assert len(out.getvalue().splitlines())==2
    assert all(not json.loads(line)['ok'] for line in out.getvalue().splitlines())


@pytest.mark.parametrize('document',[[],None,{'version':True}, {'version':1,'name':'','payload':{}},
    {'version':1,'name':'Bad\nName','payload':{}}, {'version':1,'name':'Valid','payload':float('nan')}])
def test_profile_corrupt_roots_names_versions_payloads_are_skipped(tmp_path,document):
    store=ProfileStore('test',tmp_path)
    identifier='a'*32
    if isinstance(document,dict):document=dict(document,id=identifier)
    store.filename(identifier).write_text(json.dumps(document))
    with pytest.raises(ValueError):store.read(identifier)
    assert store.list()==[]


def test_profile_payload_validation_and_atomic_failure_leave_existing_data(tmp_path,monkeypatch):
    from .. import profile_store
    store=ProfileStore('test',tmp_path)
    doc=store.save('Saved',{'amount':1});identifier=doc['id'];raw=store.filename(identifier).read_bytes()
    recursive={};recursive['loop']=recursive
    for invalid in [recursive,{'keys':{1:'invalid'}}, {'value':float('inf')}]:
        with pytest.raises(ValueError):store.update(identifier,invalid)
        assert store.filename(identifier).read_bytes()==raw
    def fail(*args):raise OSError('disk failed')
    monkeypatch.setattr(profile_store,'atomic_json',fail)
    with pytest.raises(OSError,match='disk failed'):store.update(identifier,{'amount':2})
    assert store.read(identifier)['payload']=={'amount':1}
    assert not list(tmp_path.glob('.'+identifier+'*'))


def test_profile_concurrent_duplicate_saves_use_one_stable_id(tmp_path):
    import os,subprocess,sys
    from pathlib import Path
    scripts=Path(__file__).resolve().parents[2]
    program='''import json,sys
from tool_app.profile_store import ProfileStore
try:
 result=ProfileStore("test",sys.argv[1]).save("Same name",{"value":1})
 print(json.dumps({"ok":True,"id":result["id"]}))
except ValueError as error:
 print(json.dumps({"ok":False,"error":str(error)}))
'''
    environment=dict(os.environ,PYTHONPATH=str(scripts))
    processes=[subprocess.Popen([sys.executable,'-c',program,str(tmp_path)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=environment) for _ in range(4)]
    results=[]
    for process in processes:
        stdout,stderr=process.communicate(timeout=10)
        assert process.returncode==0 and stderr==''
        results.append(json.loads(stdout))
    successes=[result for result in results if result['ok']]
    assert len(successes)==1
    store=ProfileStore('test',tmp_path)
    assert store.list()==[dict(id=successes[0]['id'],name='Same name')]
    assert len(list(tmp_path.glob('*.json')))==1
