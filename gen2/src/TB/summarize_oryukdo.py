#!/usr/bin/env python3
"""Record checked ORYUKDO regressions and completed FPGA stages (including fit failure)."""
import argparse
import hashlib
import json
from pathlib import Path
from summarize_lsq_fpga import ROOT, stage, summarize


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def regression(directory, baseline=False):
    directory = directory.resolve()
    records = json.loads((directory/'results.json').read_text())
    hashes = json.loads((directory/'source_hashes.json').read_text())
    for name, expected in hashes.items():
        # Baseline EULSUKDO elaborates no ORYUKDO module; those sources evolved
        # after the reference regression. Check every source it does elaborate.
        if baseline and 'oryukdo' in Path(name).name:
            continue
        if digest(ROOT/name) != expected:
            raise ValueError(f'Regression source changed: {name}')
    if not all(r['passed'] for r in records):
        raise ValueError(f'Failed regression: {directory}')
    return dict(directory=str(directory.relative_to(ROOT)), cases=records)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--regression', type=Path, default=ROOT/'build/oryukdo_prm_reservation_regression')
    parser.add_argument('--extra-regression', type=Path, action='append', default=[])
    parser.add_argument('--baseline', type=Path, default=ROOT/'build/oryukdo_baseline_regression')
    parser.add_argument('--comparison-build', type=Path)
    parser.add_argument('--comparison-gate', type=Path)
    parser.add_argument('--fpga', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT.parent/'docs/validation/oryukdo_gen2.json')
    args = parser.parse_args()
    args.fpga = args.fpga.resolve()
    record = dict(base_eulsukdo_commit='9b0e1c6b792b132f05844c3113ff8dfde712cd77',
                  integrated_regression=regression(args.regression),
                  eulsukdo_reference_regression=regression(args.baseline, baseline=True))
    record['additional_regressions'] = [regression(d) for d in args.extra_regression]
    manifest = json.loads((args.fpga/'manifest.json').read_text())
    physical = manifest.get('post_route_optimization')
    if physical:
        parent = Path(physical['parent_build'])
        if digest(parent/physical['parent_checkpoint']) != physical['parent_checkpoint_sha256']:
            raise ValueError('Post-route parent checkpoint changed')
        parent_manifest = json.loads((parent/'manifest.json').read_text())
        if parent_manifest['synthesis_source_hashes'] != manifest['synthesis_source_hashes']:
            raise ValueError('Post-route parent RTL snapshot differs')
    for name, expected in manifest['original_source_hashes'].items():
        if digest(ROOT/'src/RTL'/name) != expected:
            raise ValueError(f'FPGA source changed: {name}')
    for name, expected in manifest['synthesis_source_hashes'].items():
        if digest(args.fpga/'source'/name) != expected:
            raise ValueError(f'FPGA snapshot changed: {name}')
    status = (args.fpga/'status.txt').read_text()
    if any(line.endswith(' COMPLETE') for line in status.splitlines()) and manifest.get('vivado_exit') == 0:
        record['fpga'] = summarize(args.fpga)
        record['fpga']['stages']['opt'] = stage(args.fpga, 'opt')
        record['fpga']['route_complete'] = record['fpga']['route']['complete']
    else:
        record['fpga'] = dict(manifest=manifest, status=status, fresh_build_pass=False,
                              stages={}, route_complete=False)
        for name in ['synth', 'opt', 'placed', 'routed']:
            if (args.fpga/f'{name}_summary.txt').exists():
                record['fpga']['stages'][name] = stage(args.fpga, name)
    gate = args.fpga/'gate_sim/result.json'
    record['fpga']['functional_netlist_pass'] = False
    if gate.exists():
        result = json.loads(gate.read_text())
        if result['netlist_sha256'] != digest(args.fpga/'funcsim.v') or result['bench_sha256'] != digest(ROOT/'src/TB/tb_oryukdo_scheduler.sv'):
            raise ValueError('Gate simulation source changed')
        record['fpga']['gate_simulation'] = result
        record['fpga']['functional_netlist_pass'] = result['passed']
    if args.comparison_build or args.comparison_gate:
        if not (args.comparison_build and args.comparison_gate):
            parser.error('Both comparison paths are required')
        before = json.loads((args.comparison_gate/'result.json').read_text())
        if not before['passed'] or before['netlist_sha256'] != digest(args.comparison_build/'funcsim.v'):
            raise ValueError('Baseline simulation failed or its netlist changed')
        if before['bench_sha256'] != digest(ROOT/'src/TB/tb_oryukdo_scheduler.sv'):
            raise ValueError('Baseline benchmark source differs')
        after = record['fpga'].get('gate_simulation', {})
        if not after.get('passed'):
            raise ValueError('New simulation must pass before cycle comparison')
        before_perf = {r['mode']: r for r in before.get('performance', [])}
        after_perf = {r['mode']: r for r in after.get('performance', [])}
        if set(before_perf) != {0,1} or set(after_perf) != {0,1}:
            raise ValueError('Missing performance cases')
        comparison_manifest = json.loads((args.comparison_build/'manifest.json').read_text())
        for field in ['part','entries','phy','rs_depth','decode','issue','generation_bits']:
            if manifest[field] != comparison_manifest[field]:
                raise ValueError(f'Comparison configuration differs: {field}')
        for m in [0,1]:
            if before_perf[m]['instructions'] != after_perf[m]['instructions']:
                raise ValueError('Comparison instruction count differs')
        record['scheduler_cycle_comparison'] = dict(
            scope='32 scripted instructions, public-interface functional netlists; not full-CPU IPC',
            baseline_build=str(args.comparison_build.resolve()),
            baseline_gate_directory=str(args.comparison_gate.resolve()),
            baseline_netlist_sha256=before['netlist_sha256'],
            current_netlist_sha256=after['netlist_sha256'],
            shared_bench_sha256=before['bench_sha256'],
            cases=[dict(mode=m, workload=['independent','dependent_chain'][m],
                        instructions=before_perf[m]['instructions'],
                        before_cycles=before_perf[m]['cycles'], after_cycles=after_perf[m]['cycles'])
                   for m in [0,1]])
    record['fpga']['validated_build_pass'] = (
        record['fpga']['fresh_build_pass'] and record['fpga']['functional_netlist_pass'])
    connectivity = args.fpga/'connectivity.txt'
    if connectivity.exists():
        record['fpga']['connectivity_audit'] = connectivity.read_text().splitlines()
    pipeline_audit = args.fpga/'decode_pipeline_audit.txt'
    if pipeline_audit.exists():
        record['fpga']['decode_pipeline_audit'] = pipeline_audit.read_text().splitlines()
    memory_audit = args.fpga/'memory_completion_audit.txt'
    if memory_audit.exists():
        record['fpga']['memory_completion_audit'] = memory_audit.read_text().splitlines()
    issue_audit = args.fpga/'issue_audit.txt'
    if issue_audit.exists():
        record['fpga']['issue_audit'] = issue_audit.read_text().splitlines()
    wakeup_audit = args.fpga/'wakeup_audit.txt'
    if wakeup_audit.exists():
        record['fpga']['wakeup_audit'] = wakeup_audit.read_text().splitlines()
    prm_audit = args.fpga/'prm_reservation_audit.txt'
    if prm_audit.exists():
        record['fpga']['prm_reservation_audit'] = prm_audit.read_text().splitlines()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2)+'\n')
    print(args.output)
