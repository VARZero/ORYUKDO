# Verify that a live AGU request no longer controls memory completion service.
if {$argc != 1} {error "Expected FPGA_BUILD_DIRECTORY"}
set build [file normalize [lindex $argv 0]]
open_checkpoint [file join $build scheduler_routed.dcp]
set inputs [get_ports i_agu_*]
set processed [get_cells -hier -quiet -filter {IS_SEQUENTIAL == 1 && NAME =~ *U_MEMORY*processed*}]
if {![llength $inputs] || ![llength $processed]} {error "Audit endpoints missing"}
set paths [get_timing_paths -from $inputs -to $processed -max_paths 1]
# Input paths have no board IO delays in this OOC build. Check combinational
# fanout as well, so an unconstrained timing path cannot produce a false pass.
set overlap [filter [all_fanout -flat -endpoints_only -from $inputs] {NAME =~ *U_MEMORY*processed*}]
set f [open [file join $build memory_completion_audit.txt] w]
puts $f "AGU input ports: [llength $inputs]"
puts $f "Memory processed registers: [llength $processed]"
puts $f "AGU-to-processed timing paths: [llength $paths]"
puts $f "AGU-to-processed combinational fanout endpoints: [llength $overlap]"
close $f
if {[llength $paths] || [llength $overlap]} {error "AGU still controls memory processed state combinationally"}
puts "MEMORY_COMPLETION_AUDIT_PASS"
exit
