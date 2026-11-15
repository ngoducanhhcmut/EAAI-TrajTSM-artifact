"""Synthetic log-parser tests only; never RTL results or measured cycle data."""
import json, hashlib
from pathlib import Path
import check_rtl as checker

def main():
    root=Path(__file__).resolve().parent;fixture=root/'checker_fixture'
    fixture.mkdir(exist_ok=True)
    assert fixture.resolve().is_relative_to(root.resolve())
    checker.HERE=fixture
    mem=fixture/'rtl_shard_0.mem';mem.write_text('synthetic fixture\n')
    digest=hashlib.sha256(mem.read_bytes()).hexdigest()
    manifest=dict(total_jobs=2,shards=[dict(shard=0,file=mem.name,sha256=digest,job_count=2,sequences=[dict(source='T',jobs=[dict(kind='admission',response=dict(reason='ok')),dict(kind='service',response=dict(reason='timeout'))])])])
    (fixture/'rtl_manifest.json').write_text(json.dumps(manifest))
    (fixture/'rtl_batches.json').write_text(json.dumps(dict(batches=[dict(shard=0,batch=0,start_job=0,job_count=2,file=mem.name,sha256=digest)])))
    logfile=fixture/'w10a_shard_0.txt';done=Path(str(logfile)+'.done')
    sample='W10A_BATCH shard=0 batch=0 start=0 count=2\nJOB 0 PASS cycles=1\nJOB 1 PASS cycles=2\nassertion failures: 0, assertions never exercised: 1\nPASS top jobs=2 max_cycles=2\n'
    tests={}
    def test(name,text,marker,expected):
        if logfile.exists():logfile.unlink()
        if done.exists():done.unlink()
        if text is not None:logfile.write_text(text)
        if marker is not None:done.write_text(marker)
        actual=checker.check(fixture)['passed']
        assert actual==expected,(name,actual)
        tests[name]=True
    try:
        test('synthetic_complete',sample,'0',True)
        test('missing_log',None,'0',False)
        test('missing_marker',sample,None,False)
        test('failed_exit_marker',sample,'1',False)
        test('duplicate_job',sample.replace('JOB 1','JOB 0'),'0',False)
        test('missing_job',sample.replace('JOB 1 PASS cycles=2\n',''),'0',False)
        test('failure_diagnostic',sample+'ASSERT_FAIL 1 rsp\n','0',False)
        test('missing_completion',sample.replace('PASS top jobs=2 max_cycles=2\n',''),'0',False)
        test('wrong_batch',sample.replace('start=0','start=2'),'0',False)
        test('deadline_violation',sample.replace('cycles=2\n','cycles=1875001\n'),'0',False)
        mem.write_text('tampered\n');test('input_hash_mismatch',sample,'0',False)
    finally:
        for path in fixture.iterdir():path.unlink()
        fixture.rmdir()
    (root/'checker_selftests.json').write_text(json.dumps(dict(passed=True,scope='synthetic parser tests; not RTL measurements',tests=tests),indent=2))
    print('PASS',len(tests),'synthetic checker tests; no RTL execution')

if __name__=='__main__':main()
