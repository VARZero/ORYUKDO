# Inspect a completed checkpoint without changing its placement or routing.
if {$argc != 1} {error "Expected FPGA_BUILD_DIRECTORY"}
set build [file normalize [lindex $argv 0]]
open_checkpoint [file join $build scheduler_routed.dcp]
set pc_regs [get_cells -hier -quiet -filter {IS_SEQUENTIAL == 1 && NAME =~ *fetch_pc_reg*}]
set memory_generation [get_cells -hier -quiet -filter {IS_SEQUENTIAL == 1 && NAME =~ *U_MEMORY*generation*}]
if {![llength $pc_regs] || ![llength $memory_generation]} {error "Audit endpoints missing"}
set paths [get_timing_paths -from $pc_regs -to $memory_generation -max_paths 1]
set f [open [file join $build decode_pipeline_audit.txt] w]
puts $f "Fetch PC registers: [llength $pc_regs]"
puts $f "Memory generation registers: [llength $memory_generation]"
puts $f "Combinational timing paths between these register sets: [llength $paths]"
close $f
if {[llength $paths]} {error "Old fetch-PC to memory-generation path still exists"}
report_timing -from $pc_regs -to [all_registers] -max_paths 3 -file [file join $build decode_pipeline_pc_paths.rpt]
puts "DECODE_PIPELINE_AUDIT_PASS"
exit
