#!/usr/bin/env python3
"""Optimize a routed ORYUKDO checkpoint, preserving its original build."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--threads', type=int, default=8)
    args = parser.parse_args()
    if not 1 <= args.threads <= 8:
        parser.error('1..8 threads required')
    base, output = args.build.resolve(), args.output.resolve()
    manifest = json.loads((base/'manifest.json').read_text(encoding='utf-8-sig'))
    if 'ROUTED_REPORTS' not in (base/'status.txt').read_text():
        raise ValueError('Parent must have finished writing the routed checkpoint')
    for name, expected in manifest['synthesis_source_hashes'].items():
        if digest(base/'source'/name) != expected:
            raise ValueError(f'Parent snapshot changed: {name}')
    output.mkdir(exist_ok=False)
    shutil.copytree(base/'source', output/'source')
    for pattern in ['synth_*', 'opt_*', 'placed_*', 'design_config.tcl', 'connectivity.txt']:
        for path in base.glob(pattern):
            if path.is_file():
                shutil.copy2(path, output/path.name)
    manifest.pop('vivado_exit', None)
    manifest.pop('working_rtl_unchanged', None)
    manifest['post_route_optimization'] = dict(
        parent_build=str(base), parent_checkpoint='scheduler_routed.dcp',
        parent_checkpoint_sha256=digest(base/'scheduler_routed.dcp'),
        directive='AggressiveExplore', route_directive='Explore',
        clock_mhz=manifest['requested_mhz'], threads=args.threads)
    original = (base/'run.tcl').read_text()
    head = original.split('stage START\n', 1)[0]
    tail = 'stage ROUTED_REPORTS\n'+original.split('stage ROUTED_REPORTS\n', 1)[1]
    body = f'''stage START
source [file join $output design_config.tcl]
open_checkpoint {{{(base/'scheduler_routed.dcp').as_posix()}}}
set clock_site [get_property HD.CLK_SRC [get_ports clk]]
stage POST_ROUTE_OPTIMIZATION
phys_opt_design -directive AggressiveExplore
write_checkpoint -force scheduler_physopt.dcp
stage POST_ROUTE_REPAIR
route_design -directive Explore
write_checkpoint -force scheduler_routed.dcp
write_verilog -mode funcsim -force funcsim.v
'''
    (output/'run.tcl').write_text(head+body+tail)
    (output/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    command = [manifest['vivado_executable'], '-mode', 'batch', '-source', str(output/'run.tcl'),
               '-log', str(output/'vivado.log'), '-journal', str(output/'vivado.jou'),
               '-tclargs', str(output), str(manifest['requested_mhz']), str(args.threads)]
    with (output/'console.log').open('w') as log:
        result = subprocess.run(command, cwd=output, stdout=log, stderr=subprocess.STDOUT)
    manifest['vivado_exit'] = result.returncode
    manifest['working_rtl_unchanged'] = all(
        digest(ROOT/'src/RTL'/name) == expected for name, expected in manifest['original_source_hashes'].items())
    (output/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(f'Post-route Vivado exit={result.returncode}; {output}', flush=True)
    raise SystemExit(result.returncode)
