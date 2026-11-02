set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root .build synth]
file mkdir $out
cd $out
file copy -force [file join $root programs program.hex] program.hex
set_param general.maxThreads 1
read_verilog [concat [glob $root/rtl/*.v] [glob $root/third_party/hardfloat/*.v]]
read_xdc [file join $root fpga clock.xdc]
synth_design -top riscv_pipe_top -part xc7a35tcpg236-1 -include_dirs [list $root/rtl $root/third_party/hardfloat]

report_utilization -hierarchical -file utilization.rpt
report_timing_summary -file timing.rpt
write_checkpoint -force synth.dcp
exit

