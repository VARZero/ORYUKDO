#!/usr/bin/env python3
"""Run boundary, stable-token and integrated scheduler regressions in XSim.

Run with Windows Python and --vivado-bin pointing to Vivado's bin directory.
Logs and source hashes are kept under gen2/build; no project RTL is rewritten.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vivado-bin', type=Path, required=True)
    parser.add_argument('--rtl', type=Path, default=ROOT/'src/RTL')
    parser.add_argument('--output', type=Path, default=ROOT/'build/oryukdo_xsim')
    parser.add_argument('--frontier-only', action='store_true')
    parser.add_argument('--frontier-test', type=int, choices=(0, 1), help='0: boundaries; 1: stable token')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    sources = sorted(args.rtl.resolve().glob('*.sv'))
    sources += [ROOT/'src/TB/tb_oryukdo_frontier.sv', ROOT/'src/TB/tb_oryukdo_scheduler.sv']
    if args.frontier_only:
        sources = [args.rtl.resolve()/'oryukdo_frontier.sv', ROOT/'src/TB/tb_oryukdo_frontier.sv']
    hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    tests = (0, 1) if args.frontier_test is None else (args.frontier_test,)
    cases = [('tb_oryukdo_frontier', dict(TEST=t, DEPTH=d)) for d in (4, 3) for t in tests]
    if not args.frontier_only:
        cases += [('tb_oryukdo_scheduler', dict(CUSTOM_LSQ=c, EXTERNAL_PREDICTOR=p))
                  for c in (0, 1) for p in (0, 1)]
    wrappers = []
    for top, params in cases:
        name = top + '__' + '_'.join(f'{k}_{v}' for k, v in params.items())
        parameters = ','.join(f'.{k}({v})' for k, v in params.items())
        wrappers.append(f'module {name}; {top} #({parameters}) dut(); endmodule\n')
    wrapper = output/'cases.sv'
    wrapper.write_text('`timescale 1ns/1ps\n'+''.join(wrappers))
    (output/'sources.prj').write_text(''.join(f'sv work "{p.as_posix()}"\n' for p in [*sources, wrapper]))
    records = []

    def tool(name, arguments, log):
        with (output/log).open('w') as stream:
            result = subprocess.run([str(args.vivado_bin.resolve()/f'{name}.bat'), *arguments],
                                    cwd=output, stdout=stream, stderr=subprocess.STDOUT, timeout=600)
        if result.returncode:
            raise RuntimeError(f'{name} failed: {output/log}')

    tool('xvlog', ['-prj', 'sources.prj', '-log', 'compile.log'], 'compile.driver.log')
    for top, params in cases:
        name = top + '__' + '_'.join(f'{k}_{v}' for k, v in params.items())
        tool('xelab', [f'work.{name}', '-s', name, '-log', f'{name}.elaborate.log'],
             f'{name}.elaborate.driver.log')
        tool('xsim', [name, '-runall', '-log', f'{name}.run.log'], f'{name}.run.driver.log')
        passed = f'{top} PASS' in (output/f'{name}.run.log').read_text(errors='replace')
        records.append(dict(name=name, parameters=params, passed=passed))
        (output/'results.json').write_text(json.dumps(records, indent=2)+'\n')
        if not passed:
            raise RuntimeError(f'Simulation failed: {output}/{name}.run.log')
        print(f'PASS {name}', flush=True)
    if any(hashlib.sha256(p.read_bytes()).hexdigest() != hashes[str(p)] for p in sources):
        raise RuntimeError('Sources changed during regression')
    (output/'source_hashes.json').write_text(json.dumps(hashes, indent=2)+'\n')
    print(f'{len(records)}/{len(cases)} passed', flush=True)


if __name__ == '__main__':
    main()
