obj-m := ph1a_c2h.o
KDIR ?= /lib/modules/$(shell uname -r)/build
PYTHON ?= python3
.PHONY: all check-abi clean
all: check-abi
	$(MAKE) -C $(KDIR) M=$(CURDIR) W=1 modules
check-abi:
	$(PYTHON) generate_abi.py --check
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
