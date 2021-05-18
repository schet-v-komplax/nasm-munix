Q       := @
ARCH    := x86

LD		:= ld
CC		:= gcc
AR		:= ar
OBJCOPY	:= objcopy
MAKE	:= make -s
NASM	:= nasm -f bin -w-zeroing

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

image 	:= munix.img

world 	+= tools/build
world 	+= tools/install
world 	+= tools/masterboot

world 	+= fs/bin/cat
world 	+= fs/bin/clear
world 	+= fs/bin/fsstat
world 	+= fs/bin/hexdump
world 	+= fs/bin/ls
world 	+= fs/bin/shell
world 	+= fs/bin/stat

world 	+= fs/boot/init.sys
world 	+= fs/boot/munix.sys

$(image): $(world)
	tools/build r=fs b=tools/masterboot > $(image)

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

.PHONY: test
test:
	$(Q)$(MAKE) clean
	$(Q)rm -f $(image)
	$(Q)$(MAKE) $(image)
	qemu-system-x86_64 --full-screen -hda $(image)
	$(Q)$(MAKE) clean
