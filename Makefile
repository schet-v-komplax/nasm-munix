Q       := @
ARCH    := x86

LD		:= ld
CC		:= gcc
AR		:= ar
OBJCOPY	:= objcopy
MAKE	:= make -s
NASM	:= nasm -f bin -w-zeroing

image 	:= munix.img
version	:= 0.05

world 	+= tools/boot
world 	+= tools/install
world 	+= tools/mkfs

world 	+= fs/boot/munix.sys

world 	+= fs/drivers/blk.sys
world 	+= fs/drivers/con.sys
world 	+= fs/drivers/mm.sys

%: %.c			# c files -> elf
	$(Q)echo $<...
	$(Q)$(CC) -o $@ $<

%: %.asm		# nasm files -> raw
	$(Q)echo $<...
	$(Q)$(NASM) -o $@ $<
	$(Q)chmod +x $@

%.sys: %.asm	# nasm files -> sys
	$(Q)echo $<...
	$(Q)$(NASM) -o $@ $<
	$(Q)chmod +x $@

$(image): $(world)
	tools/mkfs v=$(version) s=8M c=fs d=[/drivers/mm.sys:34,/drivers/blk.sys:35,/drivers/con.sys:36] b=tools/boot > $(image)

.PHONY: clean
clean:
	$(Q)rm -f $(world)

.PHONY: install
install: $(image) $(dev)
	sudo tools/install $(image) $(dev)

.PHONY: hex
hex:
	$(Q)$(MAKE) clean
	$(Q)rm -f $(image)
	$(Q)$(MAKE) $(image)
	hexdump -C $(image)
	$(Q)$(MAKE) clean

.PHONY: run
run:
	$(Q)$(MAKE) clean
	$(Q)rm -f $(image)
	$(Q)$(MAKE) $(image)
	qemu-system-x86_64 --full-screen -hda $(image)
	$(Q)$(MAKE) clean
