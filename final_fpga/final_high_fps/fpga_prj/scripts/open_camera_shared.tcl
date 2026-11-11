# Open this independent native project. No local synthesis or physical run.
set project [file normalize [file join [file dirname [info script]] ../al/rfcamera_fusion_r1.al]]
cd [file dirname $project]
open_project $project -noanalyze
close_project
open_project $project
file mkdir ../tmp
report_run_param syn_1 -file ../tmp/native_syn.params
puts "CAMERA_SHARED_PROJECT_OPENED"
close_project
exit 0
