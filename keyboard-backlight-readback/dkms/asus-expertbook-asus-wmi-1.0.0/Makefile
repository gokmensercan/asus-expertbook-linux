# Out-of-tree build of asus-wmi + asus-nb-wmi with the B9406CAA keyboard
# backlight read-back quirk. Source tree is chosen by kernel major.minor.
KMM := $(shell echo $(KERNELRELEASE) | cut -d. -f1,2)
ifeq ($(KMM),7.2)
SRCDIR := 7.2
else ifeq ($(KMM),6.18)
SRCDIR := 6.18
else
$(error asus-expertbook-asus-wmi: no source tree for kernel $(KERNELRELEASE))
endif
obj-m += asus-wmi.o asus-nb-wmi.o
asus-wmi-y := $(SRCDIR)/asus-wmi.o
asus-nb-wmi-y := $(SRCDIR)/asus-nb-wmi.o
ccflags-y += -I$(src)/$(SRCDIR)
