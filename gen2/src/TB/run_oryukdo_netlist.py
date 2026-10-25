#!/usr/bin/env python3
"""Run the public-interface regression against a Vivado functional netlist."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--build', type=Path, required=True)
    p.add_argument('--output', type=Path)
    p.add_argument('--vivado-bin', type=Path, default=Path('D:/Xilinx2202/Vivado/2022.2/bin'))
    args = p.parse_args()
    build = args.build.resolve()
    manifest = json.loads((build/'manifest.json').read_text())
    output = args.output.resolve() if args.output else build/'gate_sim'
    output.mkdir(exist_ok=True)
    bench = (ROOT/'src/TB/tb_oryukdo_scheduler.sv').read_text()
    bench = bench.replace('ARCH=16, PHY=32, DECODE=2, ENTRIES=32',
                          f'ARCH=32, PHY={manifest.get("phy",64)}, DECODE=2, ENTRIES={manifest["entries"]}')
    bench = bench.replace('RS_DEPTH=16', f'RS_DEPTH={manifest.get("rs_depth",128)}')
    bench = bench.replace('GEN_W=8, EPOCH_W=8', 'GEN_W=32, EPOCH_W=32')
    bench = re.sub(r'\boryukdo_scheduler #\(.*?\) dut\(\.\*\);', 'oryukdo_scheduler dut(.*);', bench, flags=re.S)
    bench = re.sub(r'if\(cycle_count>20000\).*?;', 'if(cycle_count>20000) $fatal(1,"global timeout");', bench, flags=re.S)
    bench = re.sub(r'if\(!accepted\) \$fatal\(1,"decode blocked.*?;',
                   'if(!accepted) $fatal(1,"decode blocked pc=%h fetch=%h",pc,o_fetch_pc);', bench, flags=re.S)
    bench = re.sub(r'\$fatal\(1,"retire timeout.*?;', '$fatal(1,"retire timeout pc=%h",pc);', bench, flags=re.S)
    # The bench already verifies committed mapping through subsequent public
    # execution. Remove only its redundant internal-array assertion.
    bench = re.sub(r'if\(dut\.(?:U_NEL\.)?U_RENAME\.committed\[1\]==0\).*?;', '', bench)
    assert 'dut.' not in bench
    bench = bench.replace('tick(3);@(negedge clk);reset_n=1;', 'tick(20);@(negedge clk);reset_n=1;')
    (output/'tb.sv').write_text(bench)
    commands = [
        ['xvlog.bat', '--sv', str(build/'funcsim.v'), str(output/'tb.sv')],
        ['xelab.bat', 'tb_oryukdo_scheduler', 'glbl', '-L', 'unisims_ver', '-L', 'unimacro_ver',
         '-s', 'gate', '-debug', 'off', '-mt', '4'],
        ['xsim.bat', 'gate', '-runall'],
    ]
    result = dict(netlist_sha256=hashlib.sha256((build/'funcsim.v').read_bytes()).hexdigest(),
                  bench_sha256=hashlib.sha256((ROOT/'src/TB/tb_oryukdo_scheduler.sv').read_bytes()).hexdigest(),
                  passed=False, stages=[])
    for index, command in enumerate(commands):
        command[0] = str(args.vivado_bin/command[0])
        with (output/f'{index}.log').open('w') as log:
            run = subprocess.run(command, cwd=output, stdout=log, stderr=subprocess.STDOUT)
        result['stages'].append(dict(command=command, exit=run.returncode))
        print(f'gate stage {index}: {run.returncode}', flush=True)
        if run.returncode:
            break
    else:
        result['passed'] = 'tb_oryukdo_scheduler PASS' in (output/'2.log').read_text()
    if (output/'2.log').exists():
        result['performance'] = [dict(mode=int(m), instructions=int(n), cycles=int(c))
            for m,n,c in re.findall(r'PERF mode=(\d+) instructions=(\d+) cycles=(\d+)', (output/'2.log').read_text())]
    (output/'result.json').write_text(json.dumps(result, indent=2)+'\n')
    raise SystemExit(0 if result['passed'] else 1)
