# Check that row capacity cannot drive mapping writes in the same cycle.
if {$argc != 1} {error "Expected FPGA_BUILD_DIRECTORY"}
set build [file normalize [lindex $argv 0]]
open_checkpoint [file join $build scheduler_routed.dcp]
set sources [get_cells -hier -quiet -filter {IS_SEQUENTIAL == 1 && NAME =~ *U_PRM/U_PRM_MAPPING_COUNTER/reg_mem_reg*}]
set targets [get_cells -hier -quiet -filter {IS_SEQUENTIAL == 1 && NAME =~ *U_PRM/GEN_PRM_IST_MAP*reg_mem_reg*}]
set stage [get_cells -hier -quiet -filter {IS_SEQUENTIAL == 1 && NAME =~ *U_PRM/plan_*reg*}]
if {![llength $sources] || ![llength $targets] || ![llength $stage]} {error "PRM reservation audit endpoints missing"}
set outputs [get_pins -of_objects $sources -filter {DIRECTION == OUT}]
set overlap [filter [all_fanout -flat -endpoints_only -from $outputs] {NAME =~ *U_PRM/GEN_PRM_IST_MAP*reg_mem_reg*}]
set paths [get_timing_paths -from $sources -to $targets -max_paths 1]
set f [open [file join $build prm_reservation_audit.txt] w]
puts $f "PRM row counter registers: [llength $sources]"
puts $f "PRM mapping registers: [llength $targets]"
puts $f "PRM reservation registers: [llength $stage]"
puts $f "Counter-to-mapping timing paths: [llength $paths]"
puts $f "Counter-to-mapping combinational fanout endpoints: [llength $overlap]"
close $f
if {[llength $paths] || [llength $overlap]} {error "PRM capacity still drives mapping writes combinationally"}
puts "PRM_RESERVATION_AUDIT_PASS"
exit
