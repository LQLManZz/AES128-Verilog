# Programs one job from AES-GCM-Libero/bitstreams onto the kit. Only the job name changes between runs.
#   FPExpress.exe SCRIPT:realtime_env/rtl/common/flash.tcl "SCRIPT_ARGS:aes256_spi_wrapper" console_mode:show
# A second argument picks another action: READ_IDCODE, VERIFY_DIGEST, ERASE. The default is PROGRAM.

set bitstreams [file normalize [file dirname [info script]]/../../../AES-GCM-Libero/bitstreams]
set top [lindex $argv 0]
set action [expr {$argc > 1 ? [lindex $argv 1] : "PROGRAM"}]

file mkdir $bitstreams/fpexpress
create_job_project -job_project_location $bitstreams/fpexpress \
    -job_file $bitstreams/$top.job -overwrite 1
set_programming_action -name {MPFS095T} -action $action
run_selected_actions
save_project
close_project
