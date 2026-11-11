#------------------------------------------------------------------------------
# Behavioral simulation of the Anlogic uart_demo example with ModelSim.
#
# RTL-only simulation: no TD device libraries are needed. Verified working with
# ModelSim SE-64 2020.4.
#
# Usage:
#   vsim -c -do "set SRC <dir>; do sim_behavioral.do"
# or from the source directory:
#   vsim -c -do sim_behavioral.do
#
# NOTE: do NOT pass -novopt to vsim on 2020.4 - it is deprecated and makes
# `vsim` fail with "Error loading design" (vsim-12110).
#------------------------------------------------------------------------------

if { ![info exists SRC] } { set SRC "." }

puts "### compile"
if { [file exists work] } { file delete -force work }
vlib work
vmap work work

vlog -timescale 1ns/1ps \
     "$SRC/uart_tx.v" \
     "$SRC/tb_uart_tx.v"

puts "### elaborate + run"
vsim -c -work work tb_top
run -all

puts "### done"
quit -f
