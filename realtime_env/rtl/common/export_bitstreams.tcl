# Exports one FlashPro Express job per Design Root to AES-GCM-Libero/bitstreams. Libero reruns
# only the flow steps that are out of date. flash.tcl programs a job onto the kit afterwards.
#   libero.exe SCRIPT:realtime_env/rtl/common/export_bitstreams.tcl
#   libero.exe SCRIPT:realtime_env/rtl/common/export_bitstreams.tcl "SCRIPT_ARGS:aes256_spi_wrapper"

set project [file normalize [file dirname [info script]]/../../../AES-GCM-Libero]
set out $project/bitstreams

set roots {
    aes128_spi_wrapper  aes128_uart_wrapper  aes128_uart_12m_top
    aes256_spi_wrapper  aes256_uart_wrapper  aes256_uart_12m_top
}
if {$argc > 0} { set roots $argv }

proc timing_met {project top} {
    set stream [open $project/designer/$top/${top}_has_violations]
    set report [read $stream]
    close $stream
    # Setup and hold, each with a total and a violations line
    return [expr {[regexp -all {multi_corner met} $report] == 4}]
}

proc export_root {project out top} {
    # A failed root must not leave its previous job looking current
    file delete $out/$top.job
    set_root -module ${top}::work
    run_tool -name {GENERATEPROGRAMMINGFILE}
    export_prog_job -job_file_name $top -export_dir $out \
        -bitstream_file_type {TRUSTED_FACILITY} -bitstream_file_components {FABRIC SNVM} \
        -design_bitstream_format {PPD}
    if {![file exists $out/$top.job]} { error "no job file written" }
    save_project
    # Last, because export_prog_job can rerun Place and Route
    run_tool -name {VERIFYTIMING}
    if {![timing_met $project $top]} {
        file delete $out/$top.job
        error "timing not met, see designer/$top"
    }
    save_project
}

# Fails inside the GUI, where the project is already open; set_root reports a real problem
catch {open_project -file $project/AES-GCM-Libero.prjx}
file mkdir $out

set failed {}
foreach top $roots {
    if {[catch {export_root $project $out $top} message]} {
        puts "FAILED $top: $message"
        lappend failed $top
    } else {
        puts "OK     $top -> $out/$top.job"
    }
}
if {[llength $failed] > 0} { error "not exported: $failed" }
