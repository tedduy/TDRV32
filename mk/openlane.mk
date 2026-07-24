# OpenLane 2 ASIC implementation environment.

OPENLANE_IMAGE ?= ghcr.io/efabless/openlane2:2.3.10
OPENLANE_PDK_VOLUME ?= tdrv32-openlane-pdk
OPENLANE_PDK ?= sky130A
OPENLANE_SCL ?= sky130_fd_sc_hd
OPENLANE_CONFIG ?= /workspace/asic/openlane/config.json
OPENLANE_ARGS ?=

.PHONY: openlane-image mount-openlane openlane

openlane-image:
	@$(DOCKER) image inspect "$(OPENLANE_IMAGE)" >/dev/null 2>&1 || \
		$(DOCKER) pull "$(OPENLANE_IMAGE)"

mount-openlane: openlane-image
	@$(DOCKER) run --rm -it \
		--entrypoint bash \
		-v "$(CURDIR):/workspace" \
		-v "$(OPENLANE_PDK_VOLUME):/pdk" \
		-e PDK_ROOT=/pdk \
		-w /workspace \
		"$(OPENLANE_IMAGE)"

openlane: openlane-image
	@$(DOCKER) run --rm \
		-v "$(CURDIR):/workspace" \
		-v "$(OPENLANE_PDK_VOLUME):/pdk" \
		-e PDK_ROOT=/pdk \
		-w /workspace \
		--entrypoint openlane \
		"$(OPENLANE_IMAGE)" \
		--pdk-root /pdk \
		--pdk "$(OPENLANE_PDK)" \
		--scl "$(OPENLANE_SCL)" \
		$(OPENLANE_ARGS) \
		"$(OPENLANE_CONFIG)"
