import subprocess
G='/opt/godot/Godot_v4.7.2-stable_linux.x86_64'
P='/home/claude/testse/TestSE/SE2026.02.2/procedural-dungeon'
SVC=f'{P}/scripts/run_management/run_export_service.gd'
OLD='''	var access := authorize(requester, scope)
	if access["error"] != "":
		return {"ok": false, "error": access["error"], "records": [], "skipped": 0}
	var listing := RunRecordRepository.new(records_dir).list_records()
	var records := select_records(listing["records"], access, clock.call())'''
NEW='''	_access = authorize(requester, scope)
	if _access["error"] != "":
		return {"ok": false, "error": _access["error"], "records": [], "skipped": 0}
	var listing := RunRecordRepository.new(records_dir).list_records()
	var records := select_records(listing["records"], _access, clock.call())'''
src=open(SVC,encoding='utf-8').read()
assert src.count(OLD)==1
mut=src.replace(OLD,NEW).replace('var records_dir: String\n','var records_dir: String\nvar _access := {}\n',1)
open(SVC,'w',encoding='utf-8').write(mut)
print("MUTANT C1: export_runs keeps the decision in a member variable (state shared between calls)")
try:
    for i in range(1,7):
        r=subprocess.run([G,'--headless','--path',P,'-s','res://tests/run_tests.gd'],capture_output=True,text=True,timeout=300)
        lines=r.stdout.splitlines()
        failed=[l.split('::')[1] for l in lines if l.startswith('FAIL')]
        summ=[l for l in lines if 'tests,' in l]
        print(f'run {i}: exit={r.returncode} {summ[0] if summ else "no summary"}; failing: {", ".join(failed) if failed else "NONE (mutant survived)"}')
        if failed and i==1:
            first=[l for l in lines if l.startswith("    - ")][:3]
            for l in first: print("   ", l[:170])
finally:
    open(SVC,'w',encoding='utf-8').write(src)
