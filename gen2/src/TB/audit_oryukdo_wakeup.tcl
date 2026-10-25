# Verify the former completion-generation to PRM-input control path is cut.
if {$argc != 1} {error "Expected FPGA_BUILD_DIRECTORY"}
set build [file normalize [lindex $argv 0]]
open_checkpoint [file join $build scheduler_routed.dcp]
set sources [get_cells -hier -quiet -filter {IS_SEQUENTIAL == 1 && NAME =~ *U_FRONTIER/*generations_reg*}]
set targets [get_cells -hier -quiet -filter {IS_SEQUENTIAL == 1 && NAME =~ *U_PRM/U_PRM_INPUT_BUFFER/*reg_mem_reg*}]
set stage [get_cells -hier -quiet -filter {IS_SEQUENTIAL == 1 && NAME =~ wake_*reg*}]
if {![llength $sources] || ![llength $targets] || ![llength $stage]} {error "Wakeup audit endpoints missing"}
set outputs [get_pins -of_objects $sources -filter {DIRECTION == OUT}]
set overlap [filter [all_fanout -flat -endpoints_only -from $outputs] {NAME =~ *U_PRM/U_PRM_INPUT_BUFFER/*reg_mem_reg*}]
set paths [get_timing_paths -from $sources -to $targets -max_paths 1]
set f [open [file join $build wakeup_audit.txt] w]
puts $f "Frontier generation registers: [llength $sources]"
puts $f "PRM input buffer sequential cells: [llength $targets]"
puts $f "Registered Ready cells: [llength $stage]"
puts $f "Generation-to-PRM-input timing paths: [llength $paths]"
puts $f "Generation-to-PRM-input combinational fanout endpoints: [llength $overlap]"
close $f
if {[llength $paths] || [llength $overlap]} {error "Completion generation still drives PRM input combinationally"}
puts "WAKEUP_AUDIT_PASS"
exit
