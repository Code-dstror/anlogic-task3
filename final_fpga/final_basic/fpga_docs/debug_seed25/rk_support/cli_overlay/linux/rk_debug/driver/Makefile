obj-m := ph1a_c2h_debug.o
ccflags-y += -I$(src)/../../dma_c2h_candidate -I$(src)/../../../docs
PYTHON ?= python3
.PHONY: all check-source clean
all: check-source
	@test -n "$(KDIR)" || (echo "Explicit matching KDIR required"; exit 1)
	$(MAKE) -C $(KDIR) M=$(CURDIR) W=1 modules
check-source:
	$(PYTHON) derive.py --check
	$(PYTHON) ../../dma_c2h_candidate/generate_abi.py --check
clean:
	@test -n "$(KDIR)" || (echo "Explicit matching KDIR required"; exit 1)
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
