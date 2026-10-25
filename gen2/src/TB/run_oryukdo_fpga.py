#!/usr/bin/env python3
"""Snapshot ORYUKDO RTL and implement the 2d5i scheduler on Zynq-7020."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
COMPAT_OLD = """    assign retained_count = PUSH_COUNT_WIDTH'($countones(retained_valid));
    assign push_occupancy = retained_count + PUSH_COUNT_WIDTH'($countones(push_valid_reg));"""
COMPAT_NEW = """    // Vivado 2020.2 compatibility: variable $countones is unsupported.
    function automatic logic [PUSH_COUNT_WIDTH-1:0] count_push_bits(
        input logic [PUSH_ORDERING_VG_LEN-1:0] bits_in
    );
        logic [PUSH_COUNT_WIDTH-1:0] count;
        count = '0;
        for (int bit_idx = 0; bit_idx < PUSH_ORDERING_VG_LEN; bit_idx = bit_idx+1)
            if (bits_in[bit_idx]) count = count + 1'b1;
        return count;
    endfunction

    assign retained_count = count_push_bits(retained_valid);
    assign push_occupancy = retained_count + count_push_bits(PUSH_ORDERING_VG_LEN'(push_valid_reg));"""

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mhz', type=float, default=70)
    parser.add_argument('--threads', type=int, default=8)
    parser.add_argument('--entries', type=int, default=128)
    parser.add_argument('--phy', type=int, default=64)
    parser.add_argument('--rs-depth', type=int, default=128)
    parser.add_argument('--synth-only', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--vivado', default='D:/Xilinx2202/Vivado/2022.2/bin/vivado.bat')
    args = parser.parse_args()
    if args.mhz <= 0 or not 1 <= args.threads <= 8:
        parser.error('positive MHz and 1..8 threads required')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    source = output / 'source'
    source.mkdir(exist_ok=False)
    hashes, synthesis_hashes = {}, {}
    for p in sorted((ROOT / 'src/RTL').glob('*.sv')):
        hashes[p.name] = hashlib.sha256(p.read_bytes()).hexdigest()
        data = p.read_text(encoding='utf-8')
        if p.name == '_element_logics.sv':
            if data.count(COMPAT_OLD) != 1:
                raise RuntimeError('Expected the known two $countones expressions')
            data = data.replace(COMPAT_OLD, COMPAT_NEW)
        (source / p.name).write_bytes(data.encode('utf-8'))
        synthesis_hashes[p.name] = hashlib.sha256((source / p.name).read_bytes()).hexdigest()
    metadata = dict(requested_mhz=args.mhz, part='xc7z020clg400-1', decode=2, issue=5,
                    top='oryukdo_scheduler', entries=args.entries, phy=args.phy, rs_depth=args.rs_depth, windows=8, window_size=16, generation_bits=32, threads=args.threads, synth_only=args.synth_only,
                    original_source_hashes=hashes, synthesis_source_hashes=synthesis_hashes,
                    compatibility='The two variable $countones uses are replaced only in the snapshot with the same helper used by the prior 75 MHz baseline.',
                    vivado_executable=args.vivado,
                    scope='OOC scheduler; no external IO delay constraints, board wrapper, bitstream or hardware test')
    script = ROOT / 'src/TB/impl_oryukdo_fpga.tcl'
    (output / 'run.tcl').write_bytes(script.read_bytes())
    (output / 'design_config.tcl').write_text(f'set design_generics {{ENTRIES={args.entries} PHY={args.phy} RS_DEPTH={args.rs_depth}}}\nset synth_only {int(args.synth_only)}\n')
    (output / 'manifest.json').write_text(json.dumps(metadata, indent=2)+'\n')
    command = [args.vivado, '-mode', 'batch', '-source', str(output / 'run.tcl'),
               '-log', str(output / 'vivado.log'), '-journal', str(output / 'vivado.jou'),
               '-tclargs', str(output), str(args.mhz), str(args.threads)]
    with (output / 'console.log').open('w') as log:
        result = subprocess.run(command, cwd=output, stdout=log, stderr=subprocess.STDOUT)
    metadata['vivado_exit'] = result.returncode
    metadata['working_rtl_unchanged'] = all(
        hashlib.sha256((ROOT / 'src/RTL' / n).read_bytes()).hexdigest() == h for n, h in hashes.items())
    (output / 'manifest.json').write_text(json.dumps(metadata, indent=2)+'\n')
    print(f'Vivado exit={result.returncode}; RTL unchanged={metadata["working_rtl_unchanged"]}; {output}', flush=True)
    raise SystemExit(result.returncode)
