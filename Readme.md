# SDRAM Controller

This controller targets the IS42S16320F-7TL SDRAM used on the DE10-Lite Dev Kit.

## Strategy

The purpose of this module is educational.  The implementation is
really basic.  It does not implement optimal bank usage or burst transfers or
anything else that a proper implementation would include.

After initialisation, the module waits for an instruction from the Avalon bus.
When a read (or write) instruction is received, all 4 banks are initialised,
after which a series of the same instruction can continue.  The module
returns to idle after about 100 μs in order to meet precharge and refresh timing.

The module also returns to idle when a different command is received from the
Avalon bus.  It is therefore very inefficient to issue interleaved read and
write commands.  It is much better to issue commands of the same type in
groups of 4096 addresses (8192 bytes).
