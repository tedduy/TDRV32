SHELL := /bin/bash
.DEFAULT_GOAL := help

# Keep this file as the public entry point. Implementation lives in mk/ so each
# verification flow can evolve independently without turning this into a script.
include mk/common.mk
include mk/tools.mk
include mk/docker.mk
include mk/act4-docker.mk
include mk/openlane.mk
include mk/consistency.mk
include mk/doctor.mk
include mk/lint.mk
include mk/simulation.mk
include mk/coverage.mk
include mk/formal.mk
include mk/synthesis.mk
include mk/compliance.mk
include mk/firmware.mk

.PHONY: help all ci test clean

help:
	@echo "TDRV32 open-source development flow"
	@echo
	@echo "Quick start"
	@echo "  make setup               Install the default local development environment"
	@echo "  make tools-setup         Install HDL tools, RISC-V GCC and riscv-formal"
	@echo "  make verification-setup  Create .venv and install Cocotb"
	@echo "  make doctor              Check required local tools"
	@echo "  make mount               Enter the Docker development environment"
	@echo "  make mount-act4          Enter the official ACT4 environment"
	@echo "  make mount-openlane      Enter the OpenLane 2 ASIC environment"
	@echo "  make openlane            Run the sky130 RTL-to-GDSII flow"
	@echo "  make test                Run Cocotb on Verilator"
	@echo "  make ci                  Run the complete RTL quality gate"
	@echo
	@echo "RTL quality"
	@echo "  make consistency         Repository ownership and manifest checks"
	@echo "  make lint                Verilator lint"
	@echo "  make random-regression   Constrained-random test seeds"
	@echo "  make coverage            Gate code metrics + 100% functional bins"
	@echo "  make formal              SymbiYosys protocol proofs"
	@echo "  make riscv-formal        Representative RV32I/RV32C + consistency checks"
	@echo "  make riscv-formal-all    Run every generated RV32IMC instruction check"
	@echo "  make synth-yosys         Yosys synthesis sanity check"
	@echo
	@echo "RISC-V compliance"
	@echo "  make act4-test           Generate and run only the ACT4 tests"
	@echo "  make act-generate        Generate the configured ACT4 tests"
	@echo "  make act-regression      Run all generated ACT4 tests"
	@echo "  make act-run ELF=<path>  Run one ACT4 ELF"
	@echo "  make act-<suite>         Run zca, zc-exceptions, zicsr,"
	@echo "                           zifencei, zicntr, m or sm-exceptions"
	@echo
	@echo "Firmware"
	@echo "  make firmware-build      Build the bare-metal smoke test"
	@echo "  make firmware-run        Run the smoke ELF with Cocotb + Verilator"
	@echo
	@echo "Maintenance"
	@echo "  make clean               Remove generated build artifacts"

test: cocotb-verilator

ci: consistency lint test random-regression coverage synth-yosys formal riscv-formal
all: ci

clean:
	@rm -rf build
	@rm -rf rtl/lint/reports
