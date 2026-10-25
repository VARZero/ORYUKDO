#!/usr/bin/env python3
"""Run integrated ORYUKDO recovery/window/memory regressions in WSL/Linux."""
import argparse
import hashlib
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from run_prm_pipeline import ROOT, run

CASES = [
    ('tb_oryukdo_scheduler', {}),
    ('tb_oryukdo_scheduler', dict(CUSTOM_LSQ=1)),
    ('tb_oryukdo_scheduler', dict(CUSTOM_LSQ=1, EXTERNAL_PREDICTOR=1)),
    ('tb_oryukdo_scheduler', dict(EXTERNAL_PREDICTOR=1)),
    ('tb_oryukdo_scheduler', dict(DECODE=1, EX_LANES=3, ENTRIES=17, PHY=18, UPDATES=2)),
    ('tb_oryukdo_scheduler', dict(DECODE=3, EX_LANES=7, ENTRIES=32, UPDATES=3)),
    ('tb_oryukdo_scheduler', dict(DECODE=1, ENTRIES=17, PHY=18, WINDOW_SIZE=64)),
    ('tb_oryukdo_scheduler', dict(ENTRIES=128, PHY=64, ARCH=32, GEN_W=32, EPOCH_W=32, RS_DEPTH=128)),
    ('tb_oryukdo_scheduler', dict(ENTRIES=64, PHY=64, ARCH=32, GEN_W=32, EPOCH_W=32, RS_DEPTH=128)),
    ('tb_oryukdo_scheduler', dict(ENTRIES=32, PHY=64, ARCH=32, GEN_W=32, EPOCH_W=32, RS_DEPTH=128)),
    ('tb_oryukdo_completion_queue', {}),
    ('tb_oryukdo_completion_queue', dict(LANES=3, DEPTH=3)),
    ('tb_oryukdo_nel', {}),
    ('tb_oryukdo_result_selector', {}),
    ('tb_oryukdo_result_selector', dict(LANES=3)),
    ('tb_oryukdo_result_selector', dict(LANES=7)),
    ('tb_oryukdo_prm_reservation', {}),
    ('tb_oryukdo_prm_reservation', dict(DECODE=3, DEPTH=2, ROW_DEPTH=3)),
    ('tb_oryukdo_prm_reservation', dict(DECODE=1, ROW_DEPTH=2)),
]
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--first', action='store_true')
    parser.add_argument('--case', type=int, choices=range(len(CASES)))
    parser.add_argument('--output', type=Path, default=ROOT/'build/oryukdo_regression')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    sources = list((ROOT/'src/RTL').glob('*.sv')) + sorted((ROOT/'src/TB').glob('tb_oryukdo*.sv'))
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        cases = [CASES[args.case]] if args.case is not None else CASES[:1] if args.first else CASES
        records = list(pool.map(lambda c: run(c, args.output), cases))
    for p in sources:
        if hashlib.sha256(p.read_bytes()).hexdigest() != hashes[str(p.relative_to(ROOT))]:
            raise RuntimeError('Sources changed during regression')
    (args.output/'results.json').write_text(json.dumps(records, indent=2)+'\n')
    (args.output/'source_hashes.json').write_text(json.dumps(hashes, indent=2)+'\n')
    print(f'{sum(r["passed"] for r in records)}/{len(records)} passed', flush=True)
    raise SystemExit(any(not r['passed'] for r in records))
