import subprocess, re, sys
G='/opt/godot/Godot_v4.7.2-stable_linux.x86_64'
P='/home/claude/testse/TestSE/SE2026.02.2/procedural-dungeon'
SVC='scripts/run_management/run_export_service.gd'
REPO='scripts/run_management/run_record_repository.gd'
mutants=[
 ("M1 TC-05","empty owner_id accepted in scope",SVC,'typeof(scope["owner_id"]) != TYPE_STRING or scope["owner_id"] == ""','typeof(scope["owner_id"]) != TYPE_STRING'),
 ("M2 TC-07","last_run.json listed as a record",REPO,'if not file_name.ends_with(".json") or file_name == LAST_RUN_FILE:\n\t\t\tcontinue\n\t\tvar parsed','if not file_name.ends_with(".json"):\n\t\t\tcontinue\n\t\tvar parsed'),
 ("M3 TC-09","corrupt files not counted",REPO,'\t\t\tskipped += 1','\t\t\tskipped += 0'),
 ("M4 TC-10","records without owner_id visible to players",SVC,'record.get("owner_id", "") != access["owner_id"]','record.has("owner_id") and record["owner_id"] != access["owner_id"]'),
 ("M5 TC-11","export prunes expired files",SVC,'\tvar listing := RunRecordRepository.new(records_dir).list_records()','\tvar repo := RunRecordRepository.new(records_dir)\n\trepo.prune_expired(clock.call())\n\tvar listing := repo.list_records()'),
 ("M6 TC-12","export creates the records directory",REPO,'\tvar dir := DirAccess.open(records_dir)\n\tif dir == null:\n\t\treturn {"records": records, "skipped": skipped}','\tDirAccess.make_dir_recursive_absolute(records_dir)\n\tvar dir := DirAccess.open(records_dir)\n\tif dir == null:\n\t\treturn {"records": records, "skipped": skipped}'),
 ("M7 TC-04","expiry boundary off by one (< instead of <=)",SVC,'if expires_at <= now:','if expires_at < now:'),
]
out=[]
for mid,desc,f,old,new in mutants:
    path=f'{P}/{f}'
    src=open(path,encoding='utf-8').read()
    assert src.count(old)==1,(mid,src.count(old))
    open(path,'w',encoding='utf-8').write(src.replace(old,new))
    r=subprocess.run([G,'--headless','--path',P,'-s','res://tests/run_tests.gd'],capture_output=True,text=True,timeout=180)
    open(path,'w',encoding='utf-8').write(src)
    lines=r.stdout.splitlines()
    failed=[l.split('::')[1] for l in lines if l.startswith('FAIL')]
    summ=[l for l in lines if 'tests,' in l][0]
    out.append(f'{mid}: {desc}\n  exit={r.returncode}  {summ}\n  failing: {", ".join(failed) if failed else "NONE (mutant survived)"}')
print('\n'.join(out))
