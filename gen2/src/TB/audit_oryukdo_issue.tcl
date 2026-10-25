# Check that issue-time metadata validation no longer feeds any RS register.
if {$argc != 1} {error "Expected FPGA_BUILD_DIRECTORY"}
set build [file normalize [lindex $argv 0]]
open_checkpoint [file join $build scheduler_routed.dcp]
set sources [get_cells -hier -quiet -filter {IS_SEQUENTIAL == 1 && NAME =~ metadata_reg* && (NAME =~ *generation* || NAME =~ *issued*)}]
set targets [get_cells -hier -quiet -filter {IS_SEQUENTIAL == 1 && NAME =~ *U_RS/*}]
if {![llength $sources] || ![llength $targets]} {error "Issue audit endpoints missing"}
set outputs [get_pins -of_objects $sources -filter {DIRECTION == OUT}]
set overlap [filter [all_fanout -flat -endpoints_only -from $outputs] {NAME =~ *U_RS/*}]
set paths [get_timing_paths -from $sources -to $targets -max_paths 1]
set f [open [file join $build issue_audit.txt] w]
puts $f "Metadata generation/issued registers: [llength $sources]"
puts $f "RS sequential cells: [llength $targets]"
puts $f "Metadata-to-RS timing paths: [llength $paths]"
puts $f "Metadata-to-RS combinational fanout endpoints: [llength $overlap]"
close $f
if {[llength $paths] || [llength $overlap]} {error "Issue metadata still drives RS state combinationally"}
puts "ISSUE_AUDIT_PASS"
exit
