# Frontier boundary and XSim fixes (2026-10-29)

Based on ORYUKDO `2918338440252904a53acdcbfea30a6e484bccbc`.
These changes preserve the public ports, parameters, LSQ selection and predictor
selection. They do not incorporate the downstream CPU's CSR implementation or
its additional interrupt-cause/retirement ports.

## Ordered side effects

After the last older instruction retires, the frontier still has to resolve its
window, branch or trap event. Previously `o_head_valid` could grant the younger
CSR or non-speculative memory operation during this interval. A pending
interrupt or redirect could then flush an operation whose external side effect
had already happened.

Head permission now requires CHECK, or DRAIN with at least one older retirement
remaining. It is withheld in the empty DRAIN cycle and throughout EVENT. Normal
window and serial-prefix processing resume head permission when CHECK resumes.
This is a functional correction, independent of the simulator.

## XSim compatibility

`o_serial_accept` now explicitly reads the slot-valid and generation arrays,
including the existing range/reset/flush guards. In XSim 2022.2, the original
continuous assignment calling `live()` could remain stale when only an array
element changed and the input token did not. The directed test fails immediately
after allocation on the original RTL and passes with the explicit expression.

The flag declarations precede this expression. `backend_reset_n` is also
declared before its first use in the scheduler, avoiding XSim's forward implicit
net/declaration conflict. The backend reset equation is unchanged.

## Reproduction and results

```sh
# Linux/WSL: existing 19 configurations plus 4 new frontier configurations
python3 gen2/src/TB/run_oryukdo.py --output gen2/build/frontier_fix
```

```powershell
# Windows; replace the Vivado installation path as needed
python gen2/src/TB/run_oryukdo_xsim.py --vivado-bin D:/Xilinx2202/Vivado/2022.2/bin
```

- Verilator 5.020: **23/23 PASS**.
- XSim 2022.2: **8/8 PASS**: four frontier cases and the integrated scheduler
  with built-in/custom LSQ crossed with static/external prediction.
- New frontier tests cover interrupt/branch/fault boundaries, stalled retirement,
  normal window and serial-prefix progress, constant-token allocation/retirement,
  reset, flush, generation reuse and out-of-range slots, at depths 4 and 3.
- Negative controls use the unmodified original frontier with the same tests.
  XSim reports `Younger ordered side effect escaped boundary mode=0` and
  `Stable token not accepted after allocation`, respectively.

The XSim runner accepts `--rtl`, `--frontier-only` and `--frontier-test 0|1` to
repeat those isolated comparisons without modifying the checkout.

[Machine-readable results and source hashes](validation/frontier_boundary_fix.json)
and [simulation logs](validation/frontier_boundary_fix/) record this revision.
Hashes in the summary normalize CRLF to LF for Git checkout portability.

The downstream RV32 CPU had already passed Linux 6.12 userspace boot with the
equivalent fixes. That is system integration evidence, not a claim that this
standalone scheduler contains a complete CPU. This upstream patch was checked
with the regressions above; FPGA synthesis/place-and-route and board execution
were not rerun. Existing 70 MHz measurements belong to their recorded older RTL.
